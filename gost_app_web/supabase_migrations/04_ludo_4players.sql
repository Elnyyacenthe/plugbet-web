-- ============================================================
-- Migration Ludo: Support 4 joueurs en ligne
-- Date: 2026-02-24
-- ============================================================

-- 1. Ajouter colonnes player3, player4, player_count à ludo_games
ALTER TABLE ludo_games
ADD COLUMN IF NOT EXISTS player3 uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS player4 uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS player_count int DEFAULT 2;

-- 2. Ajouter contrainte: player_count doit être 2 ou 4
ALTER TABLE ludo_games
ADD CONSTRAINT check_player_count CHECK (player_count IN (2, 4));

-- 3. Mettre à jour RLS pour player3 et player4
DROP POLICY IF EXISTS "Users can view their own games" ON ludo_games;
CREATE POLICY "Users can view their own games" ON ludo_games
  FOR SELECT USING (
    auth.uid() = player1 OR
    auth.uid() = player2 OR
    auth.uid() = player3 OR
    auth.uid() = player4
  );

DROP POLICY IF EXISTS "Users can update their own games" ON ludo_games;
CREATE POLICY "Users can update their own games" ON ludo_games
  FOR UPDATE USING (
    auth.uid() = player1 OR
    auth.uid() = player2 OR
    auth.uid() = player3 OR
    auth.uid() = player4
  );

-- 4. Renommer guest_id en player2_id pour cohérence
ALTER TABLE ludo_rooms
RENAME COLUMN guest_id TO player2_id;

-- 5. Ajouter player_count à ludo_rooms
ALTER TABLE ludo_rooms
ADD COLUMN IF NOT EXISTS player_count int DEFAULT 2;

ALTER TABLE ludo_rooms
ADD CONSTRAINT check_room_player_count CHECK (player_count IN (2, 4));

-- 6. Mettre à jour l'index sur ludo_rooms pour inclure player_count
CREATE INDEX IF NOT EXISTS idx_ludo_rooms_available ON ludo_rooms (status, player_count)
  WHERE status = 'waiting';

-- 7. Ajouter colonnes player3_id et player4_id à ludo_rooms
ALTER TABLE ludo_rooms
ADD COLUMN IF NOT EXISTS player3_id uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS player4_id uuid REFERENCES auth.users(id);

-- 8. Mettre à jour la fonction qui crée une partie depuis une room
CREATE OR REPLACE FUNCTION create_game_from_room(room_id uuid)
RETURNS uuid AS $$
DECLARE
  game_id uuid;
  room_data record;
BEGIN
  -- Récupérer les données de la room
  SELECT * INTO room_data FROM ludo_rooms WHERE id = room_id;

  -- Créer la partie avec 2 ou 4 joueurs selon la room
  INSERT INTO ludo_games (
    player1,
    player2,
    player3,
    player4,
    player_count,
    bet_amount,
    current_turn,
    game_state
  )
  VALUES (
    room_data.host_id,
    room_data.player2_id,
    room_data.player3_id,
    room_data.player4_id,
    room_data.player_count,
    room_data.bet_amount,
    room_data.host_id,
    jsonb_build_object(
      'pawns', jsonb_build_object(
        room_data.host_id::text, ARRAY[-1, -1, -1, -1],
        room_data.player2_id::text, ARRAY[-1, -1, -1, -1],
        COALESCE(room_data.player3_id::text, 'null'), CASE WHEN room_data.player3_id IS NOT NULL THEN ARRAY[-1, -1, -1, -1] ELSE NULL END,
        COALESCE(room_data.player4_id::text, 'null'), CASE WHEN room_data.player4_id IS NOT NULL THEN ARRAY[-1, -1, -1, -1] ELSE NULL END
      ),
      'lastDice', 0,
      'hasRolled', false
    )
  )
  RETURNING id INTO game_id;

  RETURN game_id;
END;
$$ LANGUAGE plpgsql;

-- 9. Mettre à jour RLS sur ludo_rooms pour player3 et player4
DROP POLICY IF EXISTS "Users can view rooms" ON ludo_rooms;
CREATE POLICY "Users can view rooms" ON ludo_rooms
  FOR SELECT USING (
    status = 'waiting' OR
    host_id = auth.uid() OR
    player2_id = auth.uid() OR
    player3_id = auth.uid() OR
    player4_id = auth.uid()
  );

DROP POLICY IF EXISTS "Users can update rooms" ON ludo_rooms;
CREATE POLICY "Users can update rooms" ON ludo_rooms
  FOR UPDATE USING (
    host_id = auth.uid() OR
    player2_id = auth.uid() OR
    player3_id = auth.uid() OR
    player4_id = auth.uid()
  );

-- 10. Commentaires pour documentation
COMMENT ON COLUMN ludo_games.player_count IS 'Nombre de joueurs: 2 ou 4';
COMMENT ON COLUMN ludo_games.player3 IS 'Joueur 3 (optionnel, si player_count=4)';
COMMENT ON COLUMN ludo_games.player4 IS 'Joueur 4 (optionnel, si player_count=4)';
COMMENT ON COLUMN ludo_rooms.player_count IS 'Nombre de joueurs attendus: 2 ou 4';
COMMENT ON COLUMN ludo_rooms.player3_id IS 'Joueur 3 (si player_count=4)';
COMMENT ON COLUMN ludo_rooms.player4_id IS 'Joueur 4 (si player_count=4)';

-- 11. Mettre à jour la fonction create_ludo_room pour supporter player_count
CREATE OR REPLACE FUNCTION create_ludo_room(
  p_bet_amount int,
  p_is_private boolean,
  p_player_count int DEFAULT 2
)
RETURNS jsonb AS $$
DECLARE
  v_room_id uuid;
  v_code text;
  v_user_id uuid := auth.uid();
BEGIN
  -- Générer un code unique à 6 caractères
  v_code := upper(substring(md5(random()::text) from 1 for 6));

  -- Créer la salle
  INSERT INTO ludo_rooms (host_id, code, bet_amount, is_private, player_count, status)
  VALUES (v_user_id, v_code, p_bet_amount, p_is_private, p_player_count, 'waiting')
  RETURNING id INTO v_room_id;

  RETURN jsonb_build_object('room_id', v_room_id, 'code', v_code);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 12. Mettre à jour la fonction join_ludo_room pour supporter 4 joueurs
CREATE OR REPLACE FUNCTION join_ludo_room(p_code text)
RETURNS uuid AS $$
DECLARE
  v_room record;
  v_game_id uuid;
  v_user_id uuid := auth.uid();
BEGIN
  -- Récupérer la salle
  SELECT * INTO v_room FROM ludo_rooms
  WHERE code = p_code AND status = 'waiting'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Salle introuvable ou déjà démarrée';
  END IF;

  IF v_user_id = v_room.host_id THEN
    RAISE EXCEPTION 'Vous ne pouvez pas rejoindre votre propre salle';
  END IF;

  -- Déterminer quelle place prendre
  IF v_room.player_count = 2 THEN
    -- Mode 2 joueurs: remplir player2_id
    IF v_room.player2_id IS NOT NULL THEN
      RAISE EXCEPTION 'Cette salle est déjà pleine';
    END IF;

    UPDATE ludo_rooms SET player2_id = v_user_id WHERE id = v_room.id;

    -- Créer la partie immédiatement
    SELECT create_game_from_room(v_room.id) INTO v_game_id;

  ELSE
    -- Mode 4 joueurs: remplir player2_id, player3_id, ou player4_id
    IF v_room.player2_id IS NULL THEN
      UPDATE ludo_rooms SET player2_id = v_user_id WHERE id = v_room.id;
    ELSIF v_room.player3_id IS NULL THEN
      UPDATE ludo_rooms SET player3_id = v_user_id WHERE id = v_room.id;
    ELSIF v_room.player4_id IS NULL THEN
      UPDATE ludo_rooms SET player4_id = v_user_id WHERE id = v_room.id;

      -- La salle est maintenant pleine, créer la partie
      SELECT create_game_from_room(v_room.id) INTO v_game_id;
    ELSE
      RAISE EXCEPTION 'Cette salle est déjà pleine';
    END IF;
  END IF;

  RETURN v_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
