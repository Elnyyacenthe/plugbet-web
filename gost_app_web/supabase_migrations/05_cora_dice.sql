-- ============================================================
-- Migration Cora Dice: Jeu de dés camerounais virtuel
-- Date: 2026-02-24
-- ============================================================

-- 1. Table des rooms Cora
CREATE TABLE IF NOT EXISTS public.cora_rooms (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  code text UNIQUE NOT NULL,
  host_id uuid REFERENCES auth.users(id) NOT NULL,
  player_count int NOT NULL DEFAULT 2,
  bet_amount int NOT NULL DEFAULT 200,
  is_private boolean DEFAULT false,
  status text DEFAULT 'waiting', -- waiting, playing, finished, cancelled
  game_id uuid,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 2. Table des parties Cora
CREATE TABLE IF NOT EXISTS public.cora_games (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id uuid REFERENCES public.cora_rooms(id) ON DELETE CASCADE,
  bet_amount int NOT NULL DEFAULT 200,
  player_count int NOT NULL,
  game_state jsonb NOT NULL,
  status text DEFAULT 'playing', -- playing, finished, cancelled
  winner_ids text[] DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 3. Table des joueurs dans une room (pour ready check)
CREATE TABLE IF NOT EXISTS public.cora_room_players (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id uuid REFERENCES public.cora_rooms(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) NOT NULL,
  username text NOT NULL,
  is_ready boolean DEFAULT false,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(room_id, user_id)
);

-- 4. Table des messages de chat
CREATE TABLE IF NOT EXISTS public.cora_messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id uuid REFERENCES public.cora_rooms(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) NOT NULL,
  username text NOT NULL,
  message text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- 5. Contraintes
ALTER TABLE cora_rooms ADD CONSTRAINT check_cora_player_count CHECK (player_count BETWEEN 2 AND 6);
ALTER TABLE cora_rooms ADD CONSTRAINT check_cora_status CHECK (status IN ('waiting', 'playing', 'finished', 'cancelled'));
ALTER TABLE cora_games ADD CONSTRAINT check_cora_game_status CHECK (status IN ('playing', 'finished', 'cancelled'));

-- 6. Index
CREATE INDEX IF NOT EXISTS idx_cora_rooms_status ON cora_rooms(status, is_private) WHERE status = 'waiting';
CREATE INDEX IF NOT EXISTS idx_cora_room_players ON cora_room_players(room_id);
CREATE INDEX IF NOT EXISTS idx_cora_messages ON cora_messages(room_id, created_at);

-- 7. RLS (Row Level Security)
ALTER TABLE cora_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE cora_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE cora_room_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE cora_messages ENABLE ROW LEVEL SECURITY;

-- Policies pour cora_rooms
DROP POLICY IF EXISTS "Users can view public rooms" ON cora_rooms;
CREATE POLICY "Users can view public rooms" ON cora_rooms
  FOR SELECT USING (
    status = 'waiting' AND is_private = false OR
    host_id = auth.uid() OR
    id IN (SELECT room_id FROM cora_room_players WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Users can update own rooms" ON cora_rooms;
CREATE POLICY "Users can update own rooms" ON cora_rooms
  FOR UPDATE USING (
    host_id = auth.uid() OR
    id IN (SELECT room_id FROM cora_room_players WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Users can delete own rooms" ON cora_rooms;
CREATE POLICY "Users can delete own rooms" ON cora_rooms
  FOR DELETE USING (host_id = auth.uid());

-- Policies pour cora_games
DROP POLICY IF EXISTS "Users can view their games" ON cora_games;
CREATE POLICY "Users can view their games" ON cora_games
  FOR SELECT USING (
    room_id IN (
      SELECT room_id FROM cora_room_players WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update their games" ON cora_games;
CREATE POLICY "Users can update their games" ON cora_games
  FOR UPDATE USING (
    room_id IN (
      SELECT room_id FROM cora_room_players WHERE user_id = auth.uid()
    )
  );

-- Policies pour cora_room_players
DROP POLICY IF EXISTS "Users can view room players" ON cora_room_players;
CREATE POLICY "Users can view room players" ON cora_room_players
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert themselves" ON cora_room_players;
CREATE POLICY "Users can insert themselves" ON cora_room_players
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update themselves" ON cora_room_players;
CREATE POLICY "Users can update themselves" ON cora_room_players
  FOR UPDATE USING (user_id = auth.uid());

-- Policies pour cora_messages
DROP POLICY IF EXISTS "Users can view messages" ON cora_messages;
CREATE POLICY "Users can view messages" ON cora_messages
  FOR SELECT USING (
    room_id IN (
      SELECT room_id FROM cora_room_players WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can insert messages" ON cora_messages;
CREATE POLICY "Users can insert messages" ON cora_messages
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- 8. Fonction: Créer une room
CREATE OR REPLACE FUNCTION create_cora_room(
  p_player_count int,
  p_bet_amount int,
  p_is_private boolean
)
RETURNS jsonb AS $$
DECLARE
  v_room_id uuid;
  v_code text;
  v_user_id uuid := auth.uid();
  v_username text;
BEGIN
  -- Générer un code unique à 6 caractères
  v_code := upper(substring(md5(random()::text) from 1 for 6));

  -- Récupérer le username
  SELECT username INTO v_username FROM user_profiles WHERE id = v_user_id;
  IF v_username IS NULL THEN
    v_username := 'Joueur';
  END IF;

  -- Créer la room
  INSERT INTO cora_rooms (host_id, code, player_count, bet_amount, is_private, status)
  VALUES (v_user_id, v_code, p_player_count, p_bet_amount, p_is_private, 'waiting')
  RETURNING id INTO v_room_id;

  -- Ajouter l'hôte comme joueur
  INSERT INTO cora_room_players (room_id, user_id, username, is_ready)
  VALUES (v_room_id, v_user_id, v_username, false);

  RETURN jsonb_build_object('room_id', v_room_id, 'code', v_code);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. Fonction: Rejoindre une room
CREATE OR REPLACE FUNCTION join_cora_room(p_code text)
RETURNS uuid AS $$
DECLARE
  v_room record;
  v_current_count int;
  v_user_id uuid := auth.uid();
  v_username text;
  v_game_id uuid;
BEGIN
  -- Récupérer la room
  SELECT * INTO v_room FROM cora_rooms WHERE code = p_code AND status = 'waiting' LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Salle introuvable ou déjà démarrée';
  END IF;

  -- Vérifier si déjà dedans
  IF EXISTS (SELECT 1 FROM cora_room_players WHERE room_id = v_room.id AND user_id = v_user_id) THEN
    RETURN v_room.id; -- Déjà dedans, retourner l'ID
  END IF;

  -- Compter les joueurs actuels
  SELECT COUNT(*) INTO v_current_count FROM cora_room_players WHERE room_id = v_room.id;

  IF v_current_count >= v_room.player_count THEN
    RAISE EXCEPTION 'Cette salle est déjà pleine';
  END IF;

  -- Récupérer le username
  SELECT username INTO v_username FROM user_profiles WHERE id = v_user_id;
  IF v_username IS NULL THEN
    v_username := 'Joueur';
  END IF;

  -- Ajouter le joueur
  INSERT INTO cora_room_players (room_id, user_id, username, is_ready)
  VALUES (v_room.id, v_user_id, v_username, false);

  -- Vérifier si la room est pleine
  v_current_count := v_current_count + 1;

  -- Si pleine ET tous prêts, démarrer la partie
  IF v_current_count = v_room.player_count THEN
    -- Vérifier si tous sont prêts
    IF (SELECT COUNT(*) FROM cora_room_players WHERE room_id = v_room.id AND is_ready = true) = v_room.player_count THEN
      SELECT create_cora_game(v_room.id) INTO v_game_id;
    END IF;
  END IF;

  RETURN v_room.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. Fonction: Toggle ready
CREATE OR REPLACE FUNCTION toggle_cora_ready(
  p_room_id uuid,
  p_is_ready boolean
)
RETURNS void AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_all_ready boolean;
  v_room record;
  v_game_id uuid;
BEGIN
  -- Mettre à jour le statut ready
  UPDATE cora_room_players
  SET is_ready = p_is_ready
  WHERE room_id = p_room_id AND user_id = v_user_id;

  -- Si ready = true, vérifier si tous sont prêts
  IF p_is_ready THEN
    SELECT * INTO v_room FROM cora_rooms WHERE id = p_room_id;

    -- Vérifier si tous les joueurs sont prêts
    SELECT (
      SELECT COUNT(*) FROM cora_room_players WHERE room_id = p_room_id AND is_ready = true
    ) = v_room.player_count INTO v_all_ready;

    -- Si tous prêts, créer la partie
    IF v_all_ready THEN
      SELECT create_cora_game(p_room_id) INTO v_game_id;
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11. Fonction: Créer une partie
CREATE OR REPLACE FUNCTION create_cora_game(p_room_id uuid)
RETURNS uuid AS $$
DECLARE
  v_game_id uuid;
  v_room record;
  v_players jsonb := '{}'::jsonb;
  v_player record;
  v_first_player uuid;
BEGIN
  -- Récupérer la room
  SELECT * INTO v_room FROM cora_rooms WHERE id = p_room_id;

  -- Construire l'état initial des joueurs
  FOR v_player IN
    SELECT user_id, username FROM cora_room_players WHERE room_id = p_room_id ORDER BY joined_at
  LOOP
    IF v_first_player IS NULL THEN
      v_first_player := v_player.user_id;
    END IF;

    v_players := v_players || jsonb_build_object(
      v_player.user_id::text,
      jsonb_build_object(
        'user_id', v_player.user_id,
        'username', v_player.username,
        'is_ready', true,
        'roll', null,
        'final_score', null
      )
    );
  END LOOP;

  -- Créer la partie
  INSERT INTO cora_games (
    room_id,
    bet_amount,
    player_count,
    game_state,
    status
  )
  VALUES (
    p_room_id,
    v_room.bet_amount,
    v_room.player_count,
    jsonb_build_object(
      'players', v_players,
      'current_turn', v_first_player,
      'winners', '[]'::jsonb,
      'is_finished', false,
      'result', null
    ),
    'playing'
  )
  RETURNING id INTO v_game_id;

  -- Mettre à jour la room
  UPDATE cora_rooms SET status = 'playing', game_id = v_game_id WHERE id = p_room_id;

  RETURN v_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 12. Fonction: Soumettre un lancer de dés
CREATE OR REPLACE FUNCTION submit_cora_roll(
  p_game_id uuid,
  p_dice1 int,
  p_dice2 int
)
RETURNS void AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game record;
  v_state jsonb;
  v_players jsonb;
  v_player jsonb;
  v_next_player uuid;
  v_all_rolled boolean := true;
  v_result jsonb;
  v_cora_count int := 0;
  v_max_score int := -1;
  v_winners text[] := '{}';
  v_winner_count int;
  v_is_cora_win boolean := false;
BEGIN
  -- Récupérer la partie
  SELECT * INTO v_game FROM cora_games WHERE id = p_game_id;
  v_state := v_game.game_state;
  v_players := v_state->'players';

  -- Vérifier que c'est le tour du joueur
  IF (v_state->>'current_turn')::uuid != v_user_id THEN
    RAISE EXCEPTION 'Ce n''est pas votre tour';
  END IF;

  -- Mettre à jour le lancer du joueur
  v_player := v_players->v_user_id::text;
  v_player := v_player || jsonb_build_object(
    'roll', jsonb_build_object(
      'dice1', p_dice1,
      'dice2', p_dice2,
      'timestamp', now()
    )
  );
  v_players := v_players || jsonb_build_object(v_user_id::text, v_player);

  -- Trouver le prochain joueur
  FOR v_player IN
    SELECT key::uuid as uid FROM jsonb_each(v_players)
    WHERE (value->>'roll') IS NULL
    ORDER BY key
  LOOP
    v_next_player := v_player.uid;
    v_all_rolled := false;
    EXIT;
  END LOOP;

  -- Mettre à jour l'état
  v_state := v_state || jsonb_build_object('players', v_players);

  IF v_all_rolled THEN
    -- Tous ont joué, calculer le résultat
    v_state := v_state || jsonb_build_object('current_turn', null);

    -- Compter les Cora
    FOR v_player IN
      SELECT value FROM jsonb_each(v_players)
      WHERE (value->'roll'->>'dice1')::int = 1 AND (value->'roll'->>'dice2')::int = 1
    LOOP
      v_cora_count := v_cora_count + 1;
    END LOOP;

    -- Cas 1: Plusieurs Cora → annulation
    IF v_cora_count > 1 THEN
      v_state := v_state || jsonb_build_object(
        'is_finished', true,
        'result', 'Plusieurs Cora ! Partie annulée, remboursement total.',
        'winners', '[]'::jsonb
      );
      UPDATE cora_games SET game_state = v_state, status = 'cancelled', updated_at = now() WHERE id = p_game_id;
      UPDATE cora_rooms SET status = 'cancelled' WHERE id = v_game.room_id;
      RETURN;
    END IF;

    -- Cas 2: Un Cora → double pot
    IF v_cora_count = 1 THEN
      FOR v_player IN
        SELECT key, value FROM jsonb_each(v_players)
        WHERE (value->'roll'->>'dice1')::int = 1 AND (value->'roll'->>'dice2')::int = 1
      LOOP
        v_winners := array_append(v_winners, v_player.key);
        v_is_cora_win := true;
        v_state := v_state || jsonb_build_object(
          'is_finished', true,
          'result', (v_player.value->>'username') || ' a fait CORA ! Double pot !',
          'winners', to_jsonb(v_winners)
        );
      END LOOP;

      UPDATE cora_games SET game_state = v_state, status = 'finished', winner_ids = v_winners, updated_at = now() WHERE id = p_game_id;
      UPDATE cora_rooms SET status = 'finished' WHERE id = v_game.room_id;
      RETURN;
    END IF;

    -- Cas 3: Pas de Cora, calculer scores
    FOR v_player IN
      SELECT key, value FROM jsonb_each(v_players)
    LOOP
      DECLARE
        v_total int;
      BEGIN
        v_total := (v_player.value->'roll'->>'dice1')::int + (v_player.value->'roll'->>'dice2')::int;
        -- 7 = score effectif -1
        IF v_total = 7 THEN
          v_total := -1;
        END IF;

        IF v_total > v_max_score THEN
          v_max_score := v_total;
          v_winners := ARRAY[v_player.key];
        ELSIF v_total = v_max_score AND v_max_score > 0 THEN
          v_winners := array_append(v_winners, v_player.key);
        END IF;
      END;
    END LOOP;

    -- Vérifier égalité
    v_winner_count := array_length(v_winners, 1);
    IF v_winner_count > 1 OR v_max_score <= 0 THEN
      v_state := v_state || jsonb_build_object(
        'is_finished', true,
        'result', 'Égalité ou tous 7 ! Partie annulée, remboursement.',
        'winners', '[]'::jsonb
      );
      UPDATE cora_games SET game_state = v_state, status = 'cancelled', updated_at = now() WHERE id = p_game_id;
      UPDATE cora_rooms SET status = 'cancelled' WHERE id = v_game.room_id;
    ELSE
      -- Un gagnant
      v_state := v_state || jsonb_build_object(
        'is_finished', true,
        'result', 'Victoire avec ' || v_max_score || ' points !',
        'winners', to_jsonb(v_winners)
      );
      UPDATE cora_games SET game_state = v_state, status = 'finished', winner_ids = v_winners, updated_at = now() WHERE id = p_game_id;
      UPDATE cora_rooms SET status = 'finished' WHERE id = v_game.room_id;
    END IF;
  ELSE
    -- Passer au joueur suivant
    v_state := v_state || jsonb_build_object('current_turn', v_next_player);
    UPDATE cora_games SET game_state = v_state, updated_at = now() WHERE id = p_game_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 13. Activer realtime
ALTER PUBLICATION supabase_realtime ADD TABLE cora_rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE cora_games;
ALTER PUBLICATION supabase_realtime ADD TABLE cora_room_players;
ALTER PUBLICATION supabase_realtime ADD TABLE cora_messages;

-- 14. Commentaires
COMMENT ON TABLE cora_rooms IS 'Salles d''attente pour Cora Dice';
COMMENT ON TABLE cora_games IS 'Parties de Cora Dice en cours';
COMMENT ON TABLE cora_room_players IS 'Joueurs dans une salle (ready check)';
COMMENT ON TABLE cora_messages IS 'Messages de chat dans les salles';
