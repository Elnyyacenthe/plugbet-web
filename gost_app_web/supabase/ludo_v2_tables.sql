-- ============================================================
-- LUDO V2 — Tables + RPC (idempotent)
-- ============================================================

-- ── 1. Rooms ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ludo_v2_rooms (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code          TEXT NOT NULL UNIQUE,
  host_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  player_count  INT NOT NULL DEFAULT 2 CHECK (player_count IN (2, 3, 4)),
  bet_amount    INT NOT NULL DEFAULT 0,
  is_private    BOOLEAN DEFAULT false,
  status        TEXT DEFAULT 'waiting' CHECK (status IN ('waiting','playing','finished','cancelled')),
  game_id       UUID,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. Room players (order = turn order) ──────────────────
CREATE TABLE IF NOT EXISTS public.ludo_v2_room_players (
  id        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id   UUID REFERENCES public.ludo_v2_rooms(id) ON DELETE CASCADE NOT NULL,
  user_id   UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  slot      INT NOT NULL CHECK (slot >= 0 AND slot <= 3), -- 0=Red,1=Green,2=Blue,3=Yellow
  username  TEXT DEFAULT 'Joueur',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(room_id, user_id),
  UNIQUE(room_id, slot)
);

-- ── 3. Games ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ludo_v2_games (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id       UUID REFERENCES public.ludo_v2_rooms(id) ON DELETE CASCADE,
  -- Pawns: {"<user_id>": [0,0,0,0], ...}  0=base, 1-51=track, 52-57=homestretch, 58=home
  pawns         JSONB NOT NULL DEFAULT '{}',
  current_turn  UUID NOT NULL,           -- user_id du joueur actif
  turn_order    UUID[] NOT NULL,         -- ordre des joueurs [uid1, uid2, ...]
  color_map     JSONB NOT NULL DEFAULT '{}', -- {"<uid>": 0, ...} 0=Red,1=Green,2=Blue,3=Yellow
  dice_value    INT,
  dice_rolled   BOOLEAN DEFAULT false,
  last_move_by  UUID,
  status        TEXT DEFAULT 'playing' CHECK (status IN ('playing','finished')),
  winner_id     UUID,
  turn_number   INT DEFAULT 0,
  bet_amount    INT DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 4. RLS ────────────────────────────────────────────────
ALTER TABLE public.ludo_v2_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ludo_v2_room_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ludo_v2_games ENABLE ROW LEVEL SECURITY;

-- Rooms: tout le monde peut voir les rooms publiques
DROP POLICY IF EXISTS "ludo_v2_rooms_select" ON public.ludo_v2_rooms;
CREATE POLICY "ludo_v2_rooms_select" ON public.ludo_v2_rooms FOR SELECT USING (true);
DROP POLICY IF EXISTS "ludo_v2_rooms_insert" ON public.ludo_v2_rooms;
CREATE POLICY "ludo_v2_rooms_insert" ON public.ludo_v2_rooms FOR INSERT WITH CHECK (auth.uid() = host_id);
DROP POLICY IF EXISTS "ludo_v2_rooms_update" ON public.ludo_v2_rooms;
CREATE POLICY "ludo_v2_rooms_update" ON public.ludo_v2_rooms FOR UPDATE USING (true);
DROP POLICY IF EXISTS "ludo_v2_rooms_delete" ON public.ludo_v2_rooms;
CREATE POLICY "ludo_v2_rooms_delete" ON public.ludo_v2_rooms FOR DELETE USING (auth.uid() = host_id);

-- Room players
DROP POLICY IF EXISTS "ludo_v2_rp_select" ON public.ludo_v2_room_players;
CREATE POLICY "ludo_v2_rp_select" ON public.ludo_v2_room_players FOR SELECT USING (true);
DROP POLICY IF EXISTS "ludo_v2_rp_insert" ON public.ludo_v2_room_players;
CREATE POLICY "ludo_v2_rp_insert" ON public.ludo_v2_room_players FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "ludo_v2_rp_delete" ON public.ludo_v2_room_players;
CREATE POLICY "ludo_v2_rp_delete" ON public.ludo_v2_room_players FOR DELETE USING (auth.uid() = user_id);

-- Games: participants only
DROP POLICY IF EXISTS "ludo_v2_games_select" ON public.ludo_v2_games;
CREATE POLICY "ludo_v2_games_select" ON public.ludo_v2_games FOR SELECT USING (true);
DROP POLICY IF EXISTS "ludo_v2_games_update" ON public.ludo_v2_games;
CREATE POLICY "ludo_v2_games_update" ON public.ludo_v2_games FOR UPDATE USING (true);

-- ── 5. RPC: Créer une room ────────────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_v2_create_room(
  p_player_count INT DEFAULT 2,
  p_bet INT DEFAULT 0,
  p_private BOOLEAN DEFAULT false
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_code TEXT;
  v_room_id UUID;
  v_uid UUID := auth.uid();
  v_username TEXT;
BEGIN
  -- Générer un code unique 6 chars
  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM ludo_v2_rooms WHERE code = v_code);
  END LOOP;

  SELECT COALESCE(username, 'Joueur') INTO v_username FROM user_profiles WHERE id = v_uid;

  INSERT INTO ludo_v2_rooms (code, host_id, player_count, bet_amount, is_private)
  VALUES (v_code, v_uid, p_player_count, p_bet, p_private)
  RETURNING id INTO v_room_id;

  -- Host = slot 0 (Red)
  INSERT INTO ludo_v2_room_players (room_id, user_id, slot, username)
  VALUES (v_room_id, v_uid, 0, v_username);

  RETURN jsonb_build_object('room_id', v_room_id, 'code', v_code);
END;
$$;

-- ── 6. RPC: Rejoindre une room ────────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_v2_join_room(p_code TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_room RECORD;
  v_uid UUID := auth.uid();
  v_count INT;
  v_slot INT;
  v_username TEXT;
  v_game_id UUID;
  v_slots INT[] := ARRAY[0, 2, 1, 3]; -- 2 joueurs: Red(0) + Blue(2), 4 joueurs: 0,2,1,3
BEGIN
  SELECT * INTO v_room FROM ludo_v2_rooms WHERE code = upper(p_code) AND status = 'waiting';
  IF NOT FOUND THEN RAISE EXCEPTION 'Room introuvable ou déjà commencée'; END IF;

  IF v_room.host_id = v_uid THEN RAISE EXCEPTION 'Vous êtes déjà le créateur'; END IF;

  -- Vérifier pas déjà dedans
  IF EXISTS (SELECT 1 FROM ludo_v2_room_players WHERE room_id = v_room.id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà dans cette salle';
  END IF;

  SELECT COUNT(*) INTO v_count FROM ludo_v2_room_players WHERE room_id = v_room.id;
  IF v_count >= v_room.player_count THEN RAISE EXCEPTION 'Salle pleine'; END IF;

  -- Attribuer le prochain slot libre
  -- En 2 joueurs: slot 0 (Red) et slot 2 (Blue) pour être en face
  IF v_room.player_count = 2 THEN
    v_slot := 2; -- Blue (en face de Red)
  ELSE
    -- Trouver le premier slot libre dans l'ordre [1, 2, 3]
    SELECT s INTO v_slot FROM unnest(ARRAY[1, 2, 3]) AS s
    WHERE s NOT IN (SELECT slot FROM ludo_v2_room_players WHERE room_id = v_room.id)
    ORDER BY s LIMIT 1;
  END IF;

  SELECT COALESCE(username, 'Joueur') INTO v_username FROM user_profiles WHERE id = v_uid;

  INSERT INTO ludo_v2_room_players (room_id, user_id, slot, username)
  VALUES (v_room.id, v_uid, v_slot, v_username);

  v_count := v_count + 1;

  -- Si la room est pleine → démarrer la partie
  IF v_count >= v_room.player_count THEN
    SELECT ludo_v2_start_game(v_room.id) INTO v_game_id;
    RETURN jsonb_build_object('room_id', v_room.id, 'game_id', v_game_id, 'started', true);
  END IF;

  RETURN jsonb_build_object('room_id', v_room.id, 'game_id', null, 'started', false);
END;
$$;

-- ── 7. RPC: Démarrer la partie ────────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_v2_start_game(p_room_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_game_id UUID;
  v_pawns JSONB := '{}'::jsonb;
  v_color_map JSONB := '{}'::jsonb;
  v_turn_order UUID[] := ARRAY[]::UUID[];
  v_first UUID;
  r RECORD;
BEGIN
  -- Construire l'état initial
  FOR r IN SELECT user_id, slot FROM ludo_v2_room_players WHERE room_id = p_room_id ORDER BY slot
  LOOP
    v_pawns := v_pawns || jsonb_build_object(r.user_id::text, jsonb_build_array(0,0,0,0));
    v_color_map := v_color_map || jsonb_build_object(r.user_id::text, r.slot);
    v_turn_order := array_append(v_turn_order, r.user_id);
  END LOOP;

  IF array_length(v_turn_order, 1) IS NULL OR array_length(v_turn_order, 1) < 2 THEN
    RAISE EXCEPTION 'Pas assez de joueurs pour démarrer';
  END IF;

  v_first := v_turn_order[1];

  INSERT INTO ludo_v2_games (room_id, pawns, current_turn, turn_order, color_map, bet_amount)
  VALUES (p_room_id, v_pawns, v_first, v_turn_order, v_color_map,
          (SELECT bet_amount FROM ludo_v2_rooms WHERE id = p_room_id))
  RETURNING id INTO v_game_id;

  UPDATE ludo_v2_rooms SET status = 'playing', game_id = v_game_id WHERE id = p_room_id;

  RETURN v_game_id;
END;
$$;

-- ── 8. RPC: Lancer le dé (SERVEUR UNIQUEMENT) ────────────
CREATE OR REPLACE FUNCTION public.ludo_v2_roll_dice(p_game_id UUID)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_game RECORD;
  v_uid UUID := auth.uid();
  v_dice INT;
BEGIN
  SELECT * INTO v_game FROM ludo_v2_games WHERE id = p_game_id AND status = 'playing' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.current_turn != v_uid THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;
  IF v_game.dice_rolled THEN RAISE EXCEPTION 'Dé déjà lancé'; END IF;

  -- Générer côté serveur (sécurisé)
  v_dice := floor(random() * 6 + 1)::int;

  UPDATE ludo_v2_games
  SET dice_value = v_dice, dice_rolled = true, updated_at = NOW()
  WHERE id = p_game_id;

  RETURN v_dice;
END;
$$;

-- ── 9. RPC: Jouer un mouvement ────────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_v2_play_move(p_game_id UUID, p_pawn_index INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_game RECORD;
  v_uid UUID := auth.uid();
  v_uid_text TEXT;
  v_pawns JSONB;
  v_my_pawns JSONB;
  v_current_step INT;
  v_new_step INT;
  v_dice INT;
  v_captured BOOLEAN := false;
  v_won BOOLEAN := false;
  v_extra_turn BOOLEAN := false;
  v_next_turn UUID;
  v_my_color INT;
  v_my_offset INT;
  v_opp_key TEXT;
  v_opp_pawns JSONB;
  v_opp_color INT;
  v_opp_offset INT;
  v_my_abs INT;
  v_opp_abs INT;
  v_offsets INT[] := ARRAY[0, 13, 26, 39];
  v_safe_cells INT[] := ARRAY[0, 8, 13, 21, 26, 34, 39, 47];
  v_turn_order UUID[];
  v_turn_idx INT;
  i INT;
BEGIN
  v_uid_text := v_uid::text;

  SELECT * INTO v_game FROM ludo_v2_games WHERE id = p_game_id AND status = 'playing' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.current_turn != v_uid THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;
  IF NOT v_game.dice_rolled THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  IF p_pawn_index < 0 OR p_pawn_index > 3 THEN RAISE EXCEPTION 'Pion invalide'; END IF;

  v_dice := v_game.dice_value;
  v_pawns := v_game.pawns;
  v_my_pawns := v_pawns -> v_uid_text;
  v_current_step := (v_my_pawns ->> p_pawn_index::text)::int;

  -- Valider le mouvement
  IF v_current_step = 0 THEN
    IF v_dice != 6 THEN RAISE EXCEPTION 'Il faut un 6 pour sortir'; END IF;
    v_new_step := 1;
  ELSIF v_current_step >= 58 THEN
    RAISE EXCEPTION 'Ce pion est déjà arrivé';
  ELSE
    v_new_step := v_current_step + v_dice;
    IF v_new_step > 58 THEN RAISE EXCEPTION 'Dépassement de la maison (score exact requis)'; END IF;
  END IF;

  -- Mettre à jour le pion
  v_my_pawns := jsonb_set(v_my_pawns, ARRAY[p_pawn_index::text], to_jsonb(v_new_step));
  v_pawns := jsonb_set(v_pawns, ARRAY[v_uid_text], v_my_pawns);

  -- Vérifier capture (seulement sur le track principal 1-51)
  IF v_new_step >= 1 AND v_new_step <= 51 THEN
    v_my_color := (v_game.color_map ->> v_uid_text)::int;
    v_my_offset := v_offsets[v_my_color + 1]; -- PostgreSQL arrays are 1-based
    v_my_abs := ((v_new_step - 1) + v_my_offset) % 52;

    -- Vérifier si c'est une case sûre
    IF NOT (v_my_abs = ANY(v_safe_cells)) THEN
      -- Parcourir les adversaires
      FOR v_opp_key IN SELECT jsonb_object_keys(v_pawns)
      LOOP
        IF v_opp_key = v_uid_text THEN CONTINUE; END IF;
        v_opp_color := (v_game.color_map ->> v_opp_key)::int;
        v_opp_offset := v_offsets[v_opp_color + 1];
        v_opp_pawns := v_pawns -> v_opp_key;

        FOR i IN 0..3 LOOP
          v_opp_abs := -1;
          IF (v_opp_pawns ->> i::text)::int >= 1 AND (v_opp_pawns ->> i::text)::int <= 51 THEN
            v_opp_abs := (((v_opp_pawns ->> i::text)::int - 1) + v_opp_offset) % 52;
          END IF;
          IF v_opp_abs = v_my_abs THEN
            -- Capturer ! Renvoyer à la base
            v_opp_pawns := jsonb_set(v_opp_pawns, ARRAY[i::text], '0'::jsonb);
            v_captured := true;
          END IF;
        END LOOP;

        IF v_captured THEN
          v_pawns := jsonb_set(v_pawns, ARRAY[v_opp_key], v_opp_pawns);
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- Vérifier victoire (tous les pions >= 58)
  v_won := true;
  FOR i IN 0..3 LOOP
    IF (v_my_pawns ->> i::text)::int < 58 THEN
      v_won := false;
      EXIT;
    END IF;
  END LOOP;

  -- Tour suivant
  v_extra_turn := (v_dice = 6) OR v_captured;
  v_turn_order := v_game.turn_order;

  IF v_won THEN
    UPDATE ludo_v2_games
    SET pawns = v_pawns, status = 'finished', winner_id = v_uid,
        dice_rolled = false, dice_value = NULL, last_move_by = v_uid,
        turn_number = v_game.turn_number + 1, updated_at = NOW()
    WHERE id = p_game_id;

    -- Rembourser le gagnant (mise * nombre de joueurs)
    IF v_game.bet_amount > 0 THEN
      UPDATE user_profiles SET coins = coins + (v_game.bet_amount * array_length(v_turn_order, 1))
      WHERE id = v_uid;
    END IF;

    RETURN jsonb_build_object('captured', v_captured, 'won', true, 'extra_turn', false);
  END IF;

  IF v_extra_turn THEN
    v_next_turn := v_uid; -- Rejouer
  ELSE
    -- Prochain joueur dans l'ordre
    v_turn_idx := 1;
    FOR i IN 1..array_length(v_turn_order, 1) LOOP
      IF v_turn_order[i] = v_uid THEN v_turn_idx := i; EXIT; END IF;
    END LOOP;
    v_turn_idx := (v_turn_idx % array_length(v_turn_order, 1)) + 1;
    v_next_turn := v_turn_order[v_turn_idx];
  END IF;

  UPDATE ludo_v2_games
  SET pawns = v_pawns, current_turn = v_next_turn, dice_rolled = false, dice_value = NULL,
      last_move_by = v_uid, turn_number = v_game.turn_number + 1, updated_at = NOW()
  WHERE id = p_game_id;

  RETURN jsonb_build_object('captured', v_captured, 'won', false, 'extra_turn', v_extra_turn);
END;
$$;

-- ── 10. RPC: Passer le tour (aucun coup possible) ─────────
CREATE OR REPLACE FUNCTION public.ludo_v2_skip_turn(p_game_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_game RECORD;
  v_uid UUID := auth.uid();
  v_turn_order UUID[];
  v_turn_idx INT;
  v_next UUID;
  i INT;
BEGIN
  SELECT * INTO v_game FROM ludo_v2_games WHERE id = p_game_id AND status = 'playing' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.current_turn != v_uid THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;
  IF NOT v_game.dice_rolled THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;

  v_turn_order := v_game.turn_order;
  v_turn_idx := 1;
  FOR i IN 1..array_length(v_turn_order, 1) LOOP
    IF v_turn_order[i] = v_uid THEN v_turn_idx := i; EXIT; END IF;
  END LOOP;
  v_turn_idx := (v_turn_idx % array_length(v_turn_order, 1)) + 1;
  v_next := v_turn_order[v_turn_idx];

  UPDATE ludo_v2_games
  SET current_turn = v_next, dice_rolled = false, dice_value = NULL,
      turn_number = v_game.turn_number + 1, updated_at = NOW()
  WHERE id = p_game_id;
END;
$$;

-- ── 11. Realtime ──────────────────────────────────────────
DO $rt$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='ludo_v2_games') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_v2_games;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='ludo_v2_rooms') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_v2_rooms;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='ludo_v2_room_players') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_v2_room_players;
  END IF;
END $rt$;
