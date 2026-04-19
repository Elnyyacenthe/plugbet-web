-- ============================================================
-- Apple of Fortune – Supabase Migration
-- Tables + Secure RPC Functions
-- ============================================================

-- ============================================================
-- 1. TABLE: apple_fortune_sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS apple_fortune_sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id),
  bet_amount    INT NOT NULL CHECK (bet_amount > 0),
  status        TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'lost', 'cashed_out')),
  current_row   INT NOT NULL DEFAULT 0,
  columns       INT NOT NULL DEFAULT 3,
  safe_tiles_per_row INT NOT NULL DEFAULT 2,
  total_rows    INT NOT NULL DEFAULT 8,
  current_multiplier NUMERIC(10,2) NOT NULL DEFAULT 1.0,
  current_potential_win INT NOT NULL DEFAULT 0,
  -- Server-side board: JSON array of arrays, each inner array = safe tile indices
  -- e.g. [[0,2],[1,2],[0,1],[2],[0],[1,2],[0,2],[1]]
  board_state   JSONB NOT NULL,
  revealed_rows JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_afs_user_status
  ON apple_fortune_sessions(user_id, status);

-- RLS: users can only read their own sessions
ALTER TABLE apple_fortune_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own sessions"
  ON apple_fortune_sessions FOR SELECT
  USING (auth.uid() = user_id);

-- No direct INSERT/UPDATE/DELETE from client — only via RPC
CREATE POLICY "No direct insert"
  ON apple_fortune_sessions FOR INSERT
  WITH CHECK (false);

CREATE POLICY "No direct update"
  ON apple_fortune_sessions FOR UPDATE
  USING (false);

CREATE POLICY "No direct delete"
  ON apple_fortune_sessions FOR DELETE
  USING (false);


-- ============================================================
-- 2. RPC: create_apple_fortune_session
-- Creates a new game, deducts bet, generates random board
-- ============================================================
CREATE OR REPLACE FUNCTION create_apple_fortune_session(
  p_user_id    UUID,
  p_bet_amount INT,
  p_columns    INT DEFAULT 5,
  p_safe_tiles INT DEFAULT 1,
  p_total_rows INT DEFAULT 8
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_coins      INT;
  v_board      JSONB;
  v_row_safe   INT[];
  v_session_id UUID;
  v_i          INT;
  v_j          INT;
  v_pick       INT;
  v_temp       INT;
  v_arr        INT[];
BEGIN
  -- Validate user
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Validate params
  IF p_bet_amount < 10 THEN
    RETURN jsonb_build_object('error', 'bet_too_low');
  END IF;
  IF p_safe_tiles >= p_columns OR p_safe_tiles < 1 THEN
    RETURN jsonb_build_object('error', 'invalid_config');
  END IF;

  -- Check no active session exists
  IF EXISTS (
    SELECT 1 FROM apple_fortune_sessions
    WHERE user_id = p_user_id AND status = 'active'
  ) THEN
    RETURN jsonb_build_object('error', 'session_already_active');
  END IF;

  -- Check & deduct coins atomically
  SELECT coins INTO v_coins
    FROM user_profiles
    WHERE id = p_user_id
    FOR UPDATE;

  IF v_coins IS NULL OR v_coins < p_bet_amount THEN
    RETURN jsonb_build_object('error', 'insufficient_coins');
  END IF;

  UPDATE user_profiles
    SET coins = coins - p_bet_amount
    WHERE id = p_user_id;

  -- Generate random board (server-side only)
  v_board := '[]'::jsonb;
  FOR v_i IN 0..(p_total_rows - 1) LOOP
    -- Fisher-Yates shuffle on column indices to pick safe tiles
    v_arr := ARRAY(SELECT generate_series(0, p_columns - 1));

    FOR v_j IN REVERSE (p_columns - 1)..1 LOOP
      v_pick := floor(random() * (v_j + 1))::int;
      v_temp := v_arr[v_pick + 1];
      v_arr[v_pick + 1] := v_arr[v_j + 1];
      v_arr[v_j + 1] := v_temp;
    END LOOP;

    v_row_safe := v_arr[1:p_safe_tiles];
    v_board := v_board || jsonb_build_array(to_jsonb(v_row_safe));
  END LOOP;

  -- Create session
  INSERT INTO apple_fortune_sessions (
    user_id, bet_amount, columns, safe_tiles_per_row, total_rows,
    board_state, current_potential_win
  ) VALUES (
    p_user_id, p_bet_amount, p_columns, p_safe_tiles, p_total_rows,
    v_board, p_bet_amount
  )
  RETURNING id INTO v_session_id;

  -- Return session state (WITHOUT board_state for security)
  RETURN jsonb_build_object(
    'id', v_session_id,
    'user_id', p_user_id,
    'bet_amount', p_bet_amount,
    'status', 'active',
    'current_row', 0,
    'columns', p_columns,
    'safe_tiles_per_row', p_safe_tiles,
    'total_rows', p_total_rows,
    'current_multiplier', 1.0,
    'current_potential_win', p_bet_amount,
    'revealed_rows', '[]'::jsonb,
    'created_at', now()
  );
END;
$$;


-- ============================================================
-- 3. RPC: reveal_apple_fortune_tile
-- Player picks a tile; backend validates against hidden board
-- ============================================================
CREATE OR REPLACE FUNCTION reveal_apple_fortune_tile(
  p_session_id UUID,
  p_user_id    UUID,
  p_tile_index INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session    apple_fortune_sessions%ROWTYPE;
  v_safe_tiles JSONB;
  v_safe_arr   INT[];
  v_is_win     BOOLEAN;
  v_new_mult   NUMERIC(10,2);
  v_new_win    INT;
  v_new_row    INT;
  v_revealed   JSONB;
BEGIN
  -- Validate user
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Lock session row
  SELECT * INTO v_session
    FROM apple_fortune_sessions
    WHERE id = p_session_id AND user_id = p_user_id
    FOR UPDATE;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'session_not_found');
  END IF;

  IF v_session.status != 'active' THEN
    RETURN jsonb_build_object('error', 'session_not_active');
  END IF;

  -- Validate tile index
  IF p_tile_index < 0 OR p_tile_index >= v_session.columns THEN
    RETURN jsonb_build_object('error', 'invalid_tile');
  END IF;

  -- Get safe tiles for current row from board_state
  v_safe_tiles := v_session.board_state->v_session.current_row;

  -- Convert JSONB array to INT array
  SELECT array_agg(val::int)
    INTO v_safe_arr
    FROM jsonb_array_elements_text(v_safe_tiles) AS val;

  -- Check if chosen tile is safe
  v_is_win := p_tile_index = ANY(v_safe_arr);

  -- Build revealed row entry
  v_revealed := jsonb_build_object(
    'row', v_session.current_row,
    'chosen_tile', p_tile_index,
    'is_win', v_is_win,
    'safe_tiles', v_safe_tiles
  );

  IF v_is_win THEN
    -- Calculate new multiplier from fixed table
    -- Row: 1=x1.9, 2=x3.8, 3=x7.6, 4=x15, 5=x30, 6=x60, 7=x120, 8=x500
    v_new_row := v_session.current_row + 1;
    v_new_mult := (ARRAY[1.9, 3.8, 7.6, 15.0, 30.0, 60.0, 120.0, 500.0])[v_new_row];
    v_new_win := floor(v_session.bet_amount * v_new_mult)::int;

    -- Check if reached top (auto-finish)
    IF v_new_row >= v_session.total_rows THEN
      -- Auto cash out at top
      UPDATE user_profiles
        SET coins = coins + v_new_win
        WHERE id = p_user_id;

      UPDATE apple_fortune_sessions SET
        current_row = v_new_row,
        current_multiplier = v_new_mult,
        current_potential_win = v_new_win,
        revealed_rows = v_session.revealed_rows || v_revealed,
        status = 'cashed_out',
        updated_at = now(),
        finished_at = now()
      WHERE id = p_session_id;

      RETURN jsonb_build_object(
        'is_win', true,
        'safe_tiles', v_safe_tiles,
        'current_row', v_new_row,
        'current_multiplier', v_new_mult,
        'current_potential_win', v_new_win,
        'finished', true,
        'payout', v_new_win
      );
    ELSE
      -- Advance to next row
      UPDATE apple_fortune_sessions SET
        current_row = v_new_row,
        current_multiplier = v_new_mult,
        current_potential_win = v_new_win,
        revealed_rows = v_session.revealed_rows || v_revealed,
        updated_at = now()
      WHERE id = p_session_id;

      RETURN jsonb_build_object(
        'is_win', true,
        'safe_tiles', v_safe_tiles,
        'current_row', v_new_row,
        'current_multiplier', v_new_mult,
        'current_potential_win', v_new_win,
        'finished', false
      );
    END IF;
  ELSE
    -- LOST: update session
    UPDATE apple_fortune_sessions SET
      status = 'lost',
      current_potential_win = 0,
      revealed_rows = v_session.revealed_rows || v_revealed,
      updated_at = now(),
      finished_at = now()
    WHERE id = p_session_id;

    RETURN jsonb_build_object(
      'is_win', false,
      'safe_tiles', v_safe_tiles,
      'current_row', v_session.current_row,
      'current_multiplier', v_session.current_multiplier,
      'current_potential_win', 0
    );
  END IF;
END;
$$;


-- ============================================================
-- 4. RPC: cashout_apple_fortune_session
-- Player collects current winnings
-- ============================================================
CREATE OR REPLACE FUNCTION cashout_apple_fortune_session(
  p_session_id UUID,
  p_user_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session apple_fortune_sessions%ROWTYPE;
  v_payout  INT;
BEGIN
  -- Validate user
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Lock session
  SELECT * INTO v_session
    FROM apple_fortune_sessions
    WHERE id = p_session_id AND user_id = p_user_id
    FOR UPDATE;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('error', 'session_not_found');
  END IF;

  IF v_session.status != 'active' THEN
    RETURN jsonb_build_object('error', 'session_not_active');
  END IF;

  -- Must have passed at least 1 row to cash out
  IF v_session.current_row < 1 THEN
    RETURN jsonb_build_object('error', 'must_pass_at_least_one_row');
  END IF;

  v_payout := v_session.current_potential_win;

  -- Credit coins atomically
  UPDATE user_profiles
    SET coins = coins + v_payout
    WHERE id = p_user_id;

  -- Close session
  UPDATE apple_fortune_sessions SET
    status = 'cashed_out',
    updated_at = now(),
    finished_at = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'payout', v_payout,
    'multiplier', v_session.current_multiplier
  );
END;
$$;


-- ============================================================
-- 5. RPC: get_apple_fortune_state
-- Recover active session (e.g., after app restart)
-- ============================================================
CREATE OR REPLACE FUNCTION get_apple_fortune_state(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session apple_fortune_sessions%ROWTYPE;
BEGIN
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  SELECT * INTO v_session
    FROM apple_fortune_sessions
    WHERE user_id = p_user_id AND status = 'active'
    ORDER BY created_at DESC
    LIMIT 1;

  IF v_session IS NULL THEN
    RETURN NULL;
  END IF;

  -- Return state WITHOUT board_state (security)
  RETURN jsonb_build_object(
    'id', v_session.id,
    'user_id', v_session.user_id,
    'bet_amount', v_session.bet_amount,
    'status', v_session.status,
    'current_row', v_session.current_row,
    'columns', v_session.columns,
    'safe_tiles_per_row', v_session.safe_tiles_per_row,
    'total_rows', v_session.total_rows,
    'current_multiplier', v_session.current_multiplier,
    'current_potential_win', v_session.current_potential_win,
    'revealed_rows', v_session.revealed_rows,
    'created_at', v_session.created_at
  );
END;
$$;
