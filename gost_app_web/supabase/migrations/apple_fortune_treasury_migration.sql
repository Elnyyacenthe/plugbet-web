-- ============================================================
-- APPLE FORTUNE - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_payout_fix.sql.
-- Idempotent.
--
-- Avant : Apple Fortune utilisait UPDATE direct sur user_profiles.coins +
-- trigger apple_fortune_treasury_trg. Risque de double-comptage.
--
-- Apres : tout passe par treasury_place_bet + apply_game_payout.
-- Le trigger est SUPPRIME pour eviter les doubles credits.
-- ============================================================

-- ============================================================
-- 1) DROP les anciens triggers
-- ============================================================
do $$
declare r record;
begin
  for r in
    select t.tgname, c.relname
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_class c on c.oid = t.tgrelid
    where p.proname in ('apple_fortune_treasury_hook', 'apple_fortune_treasury_fn')
      and not t.tgisinternal
  loop
    execute format('drop trigger if exists %I on public.%I', r.tgname, r.relname);
  end loop;
end$$;

drop function if exists public.apple_fortune_treasury_hook() cascade;
drop function if exists public.apple_fortune_treasury_fn() cascade;

-- ============================================================
-- 2) create_apple_fortune_session - debit via treasury
-- ============================================================
create or replace function public.create_apple_fortune_session(
  p_user_id uuid,
  p_bet_amount integer,
  p_columns integer default 3,
  p_safe_tiles integer default 2,
  p_total_rows integer default 8
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_session_id uuid;
  v_board jsonb;
  v_arr int[];
  v_temp int;
  v_pick int;
  v_row_safe int[];
  v_i int; v_j int;
  v_balance int;
begin
  if p_user_id != auth.uid() then
    return jsonb_build_object('error', 'unauthorized');
  end if;
  if p_bet_amount <= 0 then
    return jsonb_build_object('error', 'invalid_bet');
  end if;

  select coins into v_balance from public.user_profiles where id = p_user_id;
  if v_balance is null or v_balance < p_bet_amount then
    return jsonb_build_object('error', 'insufficient_coins');
  end if;

  -- Generer le board (Fisher-Yates par row)
  v_board := '[]'::jsonb;
  for v_i in 0..(p_total_rows - 1) loop
    v_arr := array(select generate_series(0, p_columns - 1));
    for v_j in reverse (p_columns - 1)..1 loop
      v_pick := floor(random() * (v_j + 1))::int;
      v_temp := v_arr[v_pick + 1];
      v_arr[v_pick + 1] := v_arr[v_j + 1];
      v_arr[v_j + 1] := v_temp;
    end loop;
    v_row_safe := v_arr[1:p_safe_tiles];
    v_board := v_board || jsonb_build_array(to_jsonb(v_row_safe));
  end loop;

  insert into public.apple_fortune_sessions (
    user_id, bet_amount, columns, safe_tiles_per_row, total_rows,
    board_state, current_potential_win
  )
  values (
    p_user_id, p_bet_amount, p_columns, p_safe_tiles, p_total_rows,
    v_board, p_bet_amount
  )
  returning id into v_session_id;

  -- ===== TREASURY MIGRATION =====
  perform public.treasury_place_bet(
    'apple_fortune', v_session_id::text, p_user_id, p_bet_amount
  );

  return jsonb_build_object(
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
end;
$$;

grant execute on function public.create_apple_fortune_session(uuid, integer, integer, integer, integer) to authenticated;

-- ============================================================
-- 3) reveal_apple_fortune_tile - auto-cashout via apply_game_payout
-- ============================================================
create or replace function public.reveal_apple_fortune_tile(
  p_session_id uuid,
  p_user_id uuid,
  p_tile_index integer
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_session apple_fortune_sessions%rowtype;
  v_safe_tiles jsonb;
  v_safe_arr int[];
  v_is_win boolean;
  v_revealed jsonb;
  v_new_row int;
  v_new_mult numeric;
  v_new_win int;
begin
  if p_user_id != auth.uid() then
    return jsonb_build_object('error', 'unauthorized');
  end if;

  select * into v_session from public.apple_fortune_sessions
    where id = p_session_id and user_id = p_user_id for update;
  if v_session is null then
    return jsonb_build_object('error', 'session_not_found');
  end if;
  if v_session.status != 'active' then
    return jsonb_build_object('error', 'session_not_active');
  end if;
  if p_tile_index < 0 or p_tile_index >= v_session.columns then
    return jsonb_build_object('error', 'invalid_tile');
  end if;

  v_safe_tiles := v_session.board_state -> v_session.current_row;
  select array_agg(val::int) into v_safe_arr
    from jsonb_array_elements_text(v_safe_tiles) as val;

  v_is_win := p_tile_index = any(v_safe_arr);

  v_revealed := jsonb_build_object(
    'row', v_session.current_row,
    'chosen_tile', p_tile_index,
    'is_win', v_is_win,
    'safe_tiles', v_safe_tiles
  );

  if v_is_win then
    v_new_row := v_session.current_row + 1;
    v_new_mult := (array[1.9, 3.8, 7.6, 15.0, 30.0, 60.0, 120.0, 500.0])[v_new_row];
    v_new_win := floor(v_session.bet_amount * v_new_mult)::int;

    if v_new_row >= v_session.total_rows then
      -- AUTO-CASHOUT au sommet
      if v_new_win > 0 then
        perform public.apply_game_payout(
          'apple_fortune', p_session_id::text, p_user_id, v_new_win
        );
      end if;

      update public.apple_fortune_sessions set
        current_row = v_new_row,
        current_multiplier = v_new_mult,
        current_potential_win = v_new_win,
        revealed_rows = v_session.revealed_rows || v_revealed,
        status = 'cashed_out',
        updated_at = now(),
        finished_at = now()
      where id = p_session_id;

      return jsonb_build_object(
        'is_win', true, 'safe_tiles', v_safe_tiles,
        'current_row', v_new_row, 'current_multiplier', v_new_mult,
        'current_potential_win', floor(v_new_win * 0.90)::int,
        'finished', true, 'payout', floor(v_new_win * 0.90)::int
      );
    else
      update public.apple_fortune_sessions set
        current_row = v_new_row,
        current_multiplier = v_new_mult,
        current_potential_win = v_new_win,
        revealed_rows = v_session.revealed_rows || v_revealed,
        updated_at = now()
      where id = p_session_id;

      return jsonb_build_object(
        'is_win', true, 'safe_tiles', v_safe_tiles,
        'current_row', v_new_row, 'current_multiplier', v_new_mult,
        'current_potential_win', v_new_win, 'finished', false
      );
    end if;
  else
    -- LOST : mise reste a la caisse
    update public.apple_fortune_sessions set
      status = 'lost',
      current_potential_win = 0,
      revealed_rows = v_session.revealed_rows || v_revealed,
      updated_at = now(),
      finished_at = now()
    where id = p_session_id;

    return jsonb_build_object(
      'is_win', false, 'safe_tiles', v_safe_tiles,
      'current_row', v_session.current_row,
      'current_multiplier', v_session.current_multiplier,
      'current_potential_win', 0
    );
  end if;
end;
$$;

grant execute on function public.reveal_apple_fortune_tile(uuid, uuid, integer) to authenticated;

-- ============================================================
-- 4) cashout_apple_fortune_session - via apply_game_payout
-- ============================================================
create or replace function public.cashout_apple_fortune_session(
  p_session_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_session apple_fortune_sessions%rowtype;
  v_payout int;
  v_net int;
begin
  if p_user_id != auth.uid() then
    return jsonb_build_object('error', 'unauthorized');
  end if;

  select * into v_session from public.apple_fortune_sessions
    where id = p_session_id and user_id = p_user_id for update;
  if v_session is null then
    return jsonb_build_object('error', 'session_not_found');
  end if;
  if v_session.status != 'active' then
    return jsonb_build_object('error', 'session_not_active');
  end if;
  if v_session.current_row < 1 then
    return jsonb_build_object('error', 'must_pass_at_least_one_row');
  end if;

  v_payout := v_session.current_potential_win;

  if v_payout > 0 then
    v_net := public.apply_game_payout(
      'apple_fortune', p_session_id::text, p_user_id, v_payout
    );
  else
    v_net := 0;
  end if;

  update public.apple_fortune_sessions set
    status = 'cashed_out',
    updated_at = now(),
    finished_at = now()
  where id = p_session_id;

  return jsonb_build_object(
    'success', true,
    'payout', v_net,
    'multiplier', v_session.current_multiplier
  );
end;
$$;

grant execute on function public.cashout_apple_fortune_session(uuid, uuid) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
