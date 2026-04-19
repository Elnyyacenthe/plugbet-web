-- ============================================================
-- Application du rate limiting aux RPC critiques
-- A executer APRES rate_limiting.sql
-- ============================================================

-- 1. Apple Fortune : limite la creation de sessions a 1 toutes les 2s
-- (impossible de spammer la creation pour epuiser le wallet)
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
  -- Auth
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Rate limit : max 1 creation toutes les 2 secondes
  IF NOT check_rate_limit(p_user_id, 'apple_fortune_create', 2000) THEN
    RETURN jsonb_build_object('error', 'rate_limited');
  END IF;

  -- Validate
  IF p_bet_amount < 10 THEN
    RETURN jsonb_build_object('error', 'bet_too_low');
  END IF;
  IF p_safe_tiles >= p_columns OR p_safe_tiles < 1 THEN
    RETURN jsonb_build_object('error', 'invalid_config');
  END IF;
  IF EXISTS (
    SELECT 1 FROM apple_fortune_sessions
    WHERE user_id = p_user_id AND status = 'active'
  ) THEN
    RETURN jsonb_build_object('error', 'session_already_active');
  END IF;

  SELECT coins INTO v_coins
    FROM user_profiles WHERE id = p_user_id FOR UPDATE;
  IF v_coins IS NULL OR v_coins < p_bet_amount THEN
    RETURN jsonb_build_object('error', 'insufficient_coins');
  END IF;

  UPDATE user_profiles SET coins = coins - p_bet_amount WHERE id = p_user_id;

  v_board := '[]'::jsonb;
  FOR v_i IN 0..(p_total_rows - 1) LOOP
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

  INSERT INTO apple_fortune_sessions (
    user_id, bet_amount, columns, safe_tiles_per_row, total_rows,
    board_state, current_potential_win
  ) VALUES (
    p_user_id, p_bet_amount, p_columns, p_safe_tiles, p_total_rows,
    v_board, p_bet_amount
  ) RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'id', v_session_id, 'user_id', p_user_id,
    'bet_amount', p_bet_amount, 'status', 'active',
    'current_row', 0, 'columns', p_columns,
    'safe_tiles_per_row', p_safe_tiles, 'total_rows', p_total_rows,
    'current_multiplier', 1.0, 'current_potential_win', p_bet_amount,
    'revealed_rows', '[]'::jsonb, 'created_at', now()
  );
END;
$$;


-- 2. Apple Fortune : limite reveal_tile a 1 toutes les 300ms
-- (anti-tap-spam)
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
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Anti tap-spam : max 1 reveal toutes les 300ms
  IF NOT check_rate_limit(p_user_id, 'apple_fortune_reveal', 300) THEN
    RETURN jsonb_build_object('error', 'rate_limited');
  END IF;

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
  IF p_tile_index < 0 OR p_tile_index >= v_session.columns THEN
    RETURN jsonb_build_object('error', 'invalid_tile');
  END IF;

  v_safe_tiles := v_session.board_state->v_session.current_row;
  SELECT array_agg(val::int) INTO v_safe_arr
    FROM jsonb_array_elements_text(v_safe_tiles) AS val;
  v_is_win := p_tile_index = ANY(v_safe_arr);

  v_revealed := jsonb_build_object(
    'row', v_session.current_row, 'chosen_tile', p_tile_index,
    'is_win', v_is_win, 'safe_tiles', v_safe_tiles
  );

  IF v_is_win THEN
    v_new_row := v_session.current_row + 1;
    v_new_mult := (ARRAY[1.9, 3.8, 7.6, 15.0, 30.0, 60.0, 120.0, 500.0])[v_new_row];
    v_new_win := floor(v_session.bet_amount * v_new_mult)::int;

    IF v_new_row >= v_session.total_rows THEN
      UPDATE user_profiles SET coins = coins + v_new_win WHERE id = p_user_id;
      UPDATE apple_fortune_sessions SET
        current_row = v_new_row, current_multiplier = v_new_mult,
        current_potential_win = v_new_win,
        revealed_rows = v_session.revealed_rows || v_revealed,
        status = 'cashed_out', updated_at = now(), finished_at = now()
      WHERE id = p_session_id;
      RETURN jsonb_build_object(
        'is_win', true, 'safe_tiles', v_safe_tiles,
        'current_row', v_new_row, 'current_multiplier', v_new_mult,
        'current_potential_win', v_new_win, 'finished', true, 'payout', v_new_win
      );
    ELSE
      UPDATE apple_fortune_sessions SET
        current_row = v_new_row, current_multiplier = v_new_mult,
        current_potential_win = v_new_win,
        revealed_rows = v_session.revealed_rows || v_revealed, updated_at = now()
      WHERE id = p_session_id;
      RETURN jsonb_build_object(
        'is_win', true, 'safe_tiles', v_safe_tiles,
        'current_row', v_new_row, 'current_multiplier', v_new_mult,
        'current_potential_win', v_new_win, 'finished', false
      );
    END IF;
  ELSE
    UPDATE apple_fortune_sessions SET
      status = 'lost', current_potential_win = 0,
      revealed_rows = v_session.revealed_rows || v_revealed,
      updated_at = now(), finished_at = now()
    WHERE id = p_session_id;
    RETURN jsonb_build_object(
      'is_win', false, 'safe_tiles', v_safe_tiles,
      'current_row', v_session.current_row,
      'current_multiplier', v_session.current_multiplier,
      'current_potential_win', 0
    );
  END IF;
END;
$$;


-- 3. Chat combo : limite update_chat_combo a 1 toutes les 200ms par paire
-- (evite le spam de messages pour gonfler artificiellement)
-- Note : le rate_limit utilise (user_id, action) donc on inclut le conv_id dans l'action
CREATE OR REPLACE FUNCTION update_chat_combo(
  p_conversation_id UUID,
  p_from_user_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conv       conversations%ROWTYPE;
  v_today      DATE := CURRENT_DATE;
  v_yesterday  DATE := CURRENT_DATE - INTERVAL '1 day';
  v_is_user1   BOOLEAN;
  v_new_combo  INT;
  v_new_max    INT;
  v_u1_date    DATE;
  v_u2_date    DATE;
  v_incr_today BOOLEAN := false;
BEGIN
  IF p_from_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Rate limit par conversation : max 1 update toutes les 200ms
  IF NOT check_rate_limit(p_from_user_id, 'chat_combo_' || p_conversation_id::text, 200) THEN
    RETURN jsonb_build_object('error', 'rate_limited');
  END IF;

  SELECT * INTO v_conv
    FROM conversations
    WHERE id = p_conversation_id
    FOR UPDATE;

  IF v_conv IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  IF p_from_user_id != v_conv.user1_id AND p_from_user_id != v_conv.user2_id THEN
    RETURN jsonb_build_object('error', 'not_member');
  END IF;

  v_is_user1 := (p_from_user_id = v_conv.user1_id);

  IF v_is_user1 THEN
    v_u1_date := v_today;
    v_u2_date := v_conv.combo_last_user2_msg_date;
  ELSE
    v_u1_date := v_conv.combo_last_user1_msg_date;
    v_u2_date := v_today;
  END IF;

  v_new_combo := v_conv.combo_count;
  v_new_max := v_conv.combo_max;

  IF v_u1_date IS NOT NULL AND v_u2_date IS NOT NULL THEN
    IF v_u1_date >= v_yesterday AND v_u2_date >= v_yesterday THEN
      IF v_conv.combo_last_increment_date IS NULL
         OR v_conv.combo_last_increment_date < v_today THEN
        v_new_combo := v_conv.combo_count + 1;
        v_incr_today := true;
        IF v_new_combo > v_new_max THEN
          v_new_max := v_new_combo;
        END IF;
      END IF;
    ELSIF v_u1_date < v_yesterday - INTERVAL '1 day'
       OR v_u2_date < v_yesterday - INTERVAL '1 day' THEN
      v_new_combo := 0;
    END IF;
  END IF;

  UPDATE conversations SET
    combo_count = v_new_combo,
    combo_max = v_new_max,
    combo_last_user1_msg_date = v_u1_date,
    combo_last_user2_msg_date = v_u2_date,
    combo_last_increment_date = CASE
      WHEN v_incr_today THEN v_today
      ELSE combo_last_increment_date
    END
  WHERE id = p_conversation_id;

  RETURN jsonb_build_object(
    'combo_count', v_new_combo,
    'combo_max', v_new_max,
    'incremented', v_incr_today
  );
END;
$$;
