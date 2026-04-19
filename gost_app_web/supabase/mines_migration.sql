-- ============================================================
-- Mines — Jeu de type "revele les cases, evite les bombes"
-- Grille 5x5, joueur choisit le nombre de mines (1-24)
-- Multiplicateur calcule mathematiquement :
--   mult(n_safe_revealed) = ∏ (total_cases - i) / (safe_cases - i)  × edge
-- ============================================================

-- ============================================================
-- 1. TABLE : mines_sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS mines_sessions (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID NOT NULL REFERENCES auth.users(id),
  bet_amount           INT NOT NULL CHECK (bet_amount > 0),
  status               TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active','lost','cashed_out')),
  mines_count          INT NOT NULL CHECK (mines_count BETWEEN 1 AND 24),
  grid_size            INT NOT NULL DEFAULT 25, -- 5x5
  -- Positions secretes des mines (JSON array of ints, ex [3, 17, 22])
  mine_positions       JSONB NOT NULL,
  -- Positions revelees par le joueur (JSON array d'objets {pos, is_mine})
  revealed_positions   JSONB NOT NULL DEFAULT '[]'::jsonb,
  safe_revealed_count  INT NOT NULL DEFAULT 0,
  current_multiplier   NUMERIC(10,4) NOT NULL DEFAULT 1.0,
  current_potential_win INT NOT NULL DEFAULT 0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_mines_user_status
  ON mines_sessions(user_id, status);

-- RLS : users ne peuvent lire que leurs propres sessions
ALTER TABLE mines_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own mines sessions" ON mines_sessions;
CREATE POLICY "Users read own mines sessions"
  ON mines_sessions FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "No direct insert mines" ON mines_sessions;
CREATE POLICY "No direct insert mines"
  ON mines_sessions FOR INSERT
  WITH CHECK (false);

DROP POLICY IF EXISTS "No direct update mines" ON mines_sessions;
CREATE POLICY "No direct update mines"
  ON mines_sessions FOR UPDATE
  USING (false);

DROP POLICY IF EXISTS "No direct delete mines" ON mines_sessions;
CREATE POLICY "No direct delete mines"
  ON mines_sessions FOR DELETE
  USING (false);


-- ============================================================
-- 2. Helper : calcul du multiplicateur (progression lineaire)
-- mult(n) = 0.50 + n * 1.00  →  1.50, 2.50, 3.50, 4.50, ...
-- Simple et previsible : +1.00 par case sure revelee
-- ============================================================
CREATE OR REPLACE FUNCTION mines_calc_multiplier(
  p_safe_revealed INT,
  p_mines_count   INT,
  p_grid_size     INT DEFAULT 25
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_safe_revealed <= 0 THEN RETURN 1.0; END IF;
  RETURN ROUND((0.50 + p_safe_revealed * 1.00)::NUMERIC, 4);
END;
$$;


-- ============================================================
-- 3. RPC : create_mines_session
-- Deduct bet, genere positions aleatoires des mines, cree session
-- ============================================================
CREATE OR REPLACE FUNCTION create_mines_session(
  p_user_id     UUID,
  p_bet_amount  INT,
  p_mines_count INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_coins    INT;
  v_positions INT[];
  v_session_id UUID;
  v_pos       INT;
  v_idx       INT;
BEGIN
  -- Auth
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Rate limit : max 1 creation toutes les 2s
  IF NOT check_rate_limit(p_user_id, 'mines_create', 2000) THEN
    RETURN jsonb_build_object('error', 'rate_limited');
  END IF;

  -- Validate
  IF p_bet_amount < 10 THEN
    RETURN jsonb_build_object('error', 'bet_too_low');
  END IF;
  IF p_mines_count < 1 OR p_mines_count > 24 THEN
    RETURN jsonb_build_object('error', 'invalid_mines_count');
  END IF;

  -- Pas de session active
  IF EXISTS (
    SELECT 1 FROM mines_sessions
    WHERE user_id = p_user_id AND status = 'active'
  ) THEN
    RETURN jsonb_build_object('error', 'session_already_active');
  END IF;

  -- Lock + deduct coins
  SELECT coins INTO v_coins
    FROM user_profiles WHERE id = p_user_id FOR UPDATE;
  IF v_coins IS NULL OR v_coins < p_bet_amount THEN
    RETURN jsonb_build_object('error', 'insufficient_coins');
  END IF;

  UPDATE user_profiles SET coins = coins - p_bet_amount WHERE id = p_user_id;

  -- Generer N positions aleatoires uniques dans [0..24] via Fisher-Yates
  v_positions := ARRAY(SELECT generate_series(0, 24));
  FOR v_i IN REVERSE 24..1 LOOP
    v_idx := floor(random() * (v_i + 1))::int;
    v_pos := v_positions[v_idx + 1];
    v_positions[v_idx + 1] := v_positions[v_i + 1];
    v_positions[v_i + 1] := v_pos;
  END LOOP;

  -- Garder les N premieres positions comme mines
  INSERT INTO mines_sessions (
    user_id, bet_amount, mines_count,
    mine_positions, current_potential_win
  ) VALUES (
    p_user_id, p_bet_amount, p_mines_count,
    to_jsonb(v_positions[1:p_mines_count]),
    p_bet_amount
  )
  RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'id', v_session_id,
    'user_id', p_user_id,
    'bet_amount', p_bet_amount,
    'status', 'active',
    'mines_count', p_mines_count,
    'grid_size', 25,
    'safe_revealed_count', 0,
    'revealed_positions', '[]'::jsonb,
    'current_multiplier', 1.0,
    'current_potential_win', p_bet_amount,
    'created_at', now()
  );
END;
$$;


-- ============================================================
-- 4. RPC : reveal_mines_tile
-- Joueur reveal une case. Backend verifie si c'est une mine.
-- ============================================================
CREATE OR REPLACE FUNCTION reveal_mines_tile(
  p_session_id UUID,
  p_user_id    UUID,
  p_position   INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session       mines_sessions%ROWTYPE;
  v_mine_positions INT[];
  v_is_mine       BOOLEAN;
  v_new_count     INT;
  v_new_mult      NUMERIC;
  v_new_win       INT;
  v_already       BOOLEAN;
BEGIN
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Rate limit : 1 reveal toutes les 300ms (anti tap-spam)
  IF NOT check_rate_limit(p_user_id, 'mines_reveal', 300) THEN
    RETURN jsonb_build_object('error', 'rate_limited');
  END IF;

  -- Lock session
  SELECT * INTO v_session
    FROM mines_sessions
    WHERE id = p_session_id AND user_id = p_user_id
    FOR UPDATE;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'session_not_found');
  END IF;
  IF v_session.status != 'active' THEN
    RETURN jsonb_build_object('error', 'session_not_active');
  END IF;
  IF p_position < 0 OR p_position >= v_session.grid_size THEN
    RETURN jsonb_build_object('error', 'invalid_position');
  END IF;

  -- Verifier si deja revele
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_session.revealed_positions) AS elem
    WHERE (elem->>'pos')::int = p_position
  ) INTO v_already;

  IF v_already THEN
    RETURN jsonb_build_object('error', 'already_revealed');
  END IF;

  -- Recuperer positions des mines et verifier
  SELECT array_agg(val::int) INTO v_mine_positions
    FROM jsonb_array_elements_text(v_session.mine_positions) AS val;

  v_is_mine := p_position = ANY(v_mine_positions);

  IF v_is_mine THEN
    -- LOST : on met status='lost' et on revele toutes les mines
    UPDATE mines_sessions SET
      status = 'lost',
      current_potential_win = 0,
      revealed_positions = v_session.revealed_positions ||
        jsonb_build_array(jsonb_build_object('pos', p_position, 'is_mine', true)),
      updated_at = now(),
      finished_at = now()
    WHERE id = p_session_id;

    RETURN jsonb_build_object(
      'is_mine', true,
      'position', p_position,
      'status', 'lost',
      'mine_positions', v_session.mine_positions,
      'current_potential_win', 0
    );
  ELSE
    -- SAFE : incremente compteur et recalcule multiplicateur
    v_new_count := v_session.safe_revealed_count + 1;
    v_new_mult := mines_calc_multiplier(v_new_count, v_session.mines_count, v_session.grid_size);
    v_new_win := floor(v_session.bet_amount * v_new_mult)::int;

    UPDATE mines_sessions SET
      safe_revealed_count = v_new_count,
      current_multiplier = v_new_mult,
      current_potential_win = v_new_win,
      revealed_positions = v_session.revealed_positions ||
        jsonb_build_array(jsonb_build_object('pos', p_position, 'is_mine', false)),
      updated_at = now()
    WHERE id = p_session_id;

    -- Check victoire totale : toutes les cases safe revelees
    IF v_new_count >= (v_session.grid_size - v_session.mines_count) THEN
      -- Auto cash out
      UPDATE user_profiles SET coins = coins + v_new_win WHERE id = p_user_id;
      UPDATE mines_sessions SET
        status = 'cashed_out',
        finished_at = now()
      WHERE id = p_session_id;

      RETURN jsonb_build_object(
        'is_mine', false,
        'position', p_position,
        'status', 'cashed_out',
        'safe_revealed_count', v_new_count,
        'current_multiplier', v_new_mult,
        'current_potential_win', v_new_win,
        'finished', true,
        'payout', v_new_win
      );
    END IF;

    RETURN jsonb_build_object(
      'is_mine', false,
      'position', p_position,
      'status', 'active',
      'safe_revealed_count', v_new_count,
      'current_multiplier', v_new_mult,
      'current_potential_win', v_new_win,
      'finished', false
    );
  END IF;
END;
$$;


-- ============================================================
-- 5. RPC : cashout_mines_session
-- Joueur encaisse le gain courant
-- ============================================================
CREATE OR REPLACE FUNCTION cashout_mines_session(
  p_session_id UUID,
  p_user_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session mines_sessions%ROWTYPE;
  v_payout  INT;
BEGIN
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  SELECT * INTO v_session
    FROM mines_sessions
    WHERE id = p_session_id AND user_id = p_user_id
    FOR UPDATE;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'session_not_found');
  END IF;
  IF v_session.status != 'active' THEN
    RETURN jsonb_build_object('error', 'session_not_active');
  END IF;

  -- Il faut au moins 1 case safe revelee
  IF v_session.safe_revealed_count < 1 THEN
    RETURN jsonb_build_object('error', 'must_reveal_at_least_one');
  END IF;

  v_payout := v_session.current_potential_win;

  UPDATE user_profiles SET coins = coins + v_payout WHERE id = p_user_id;

  UPDATE mines_sessions SET
    status = 'cashed_out',
    updated_at = now(),
    finished_at = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'payout', v_payout,
    'multiplier', v_session.current_multiplier,
    'mine_positions', v_session.mine_positions
  );
END;
$$;


-- ============================================================
-- 6. RPC : get_mines_state (recuperation session active)
-- ============================================================
CREATE OR REPLACE FUNCTION get_mines_state(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session mines_sessions%ROWTYPE;
BEGIN
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  SELECT * INTO v_session
    FROM mines_sessions
    WHERE user_id = p_user_id AND status = 'active'
    ORDER BY created_at DESC
    LIMIT 1;

  IF v_session IS NULL THEN
    RETURN NULL;
  END IF;

  -- Retour SANS mine_positions (secret)
  RETURN jsonb_build_object(
    'id', v_session.id,
    'user_id', v_session.user_id,
    'bet_amount', v_session.bet_amount,
    'status', v_session.status,
    'mines_count', v_session.mines_count,
    'grid_size', v_session.grid_size,
    'safe_revealed_count', v_session.safe_revealed_count,
    'revealed_positions', v_session.revealed_positions,
    'current_multiplier', v_session.current_multiplier,
    'current_potential_win', v_session.current_potential_win,
    'created_at', v_session.created_at
  );
END;
$$;
