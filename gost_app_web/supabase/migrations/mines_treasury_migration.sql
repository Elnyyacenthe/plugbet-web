-- ============================================================
-- MINES - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_payout_fix.sql.
-- Idempotent.
--
-- Avant : Mines utilisait UPDATE direct sur user_profiles.coins +
-- un trigger mines_treasury_trg qui appelait game_treasury_collect_loss.
-- Risque de double-comptage avec le nouveau systeme.
--
-- Apres : tout passe par treasury_place_bet + apply_game_payout.
-- Le trigger est SUPPRIME pour eviter les doubles credits.
-- ============================================================

-- ============================================================
-- 1) DROP les anciens triggers (causent double-payout potentiel)
-- ============================================================
do $$
declare r record;
begin
  for r in
    select t.tgname, c.relname
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_class c on c.oid = t.tgrelid
    where p.proname in ('mines_treasury_hook', 'mines_treasury_fn')
      and not t.tgisinternal
  loop
    execute format('drop trigger if exists %I on public.%I', r.tgname, r.relname);
  end loop;
end$$;

drop function if exists public.mines_treasury_hook() cascade;
drop function if exists public.mines_treasury_fn() cascade;

-- ============================================================
-- 2) create_mines_session - debit via treasury_place_bet
-- ============================================================
create or replace function public.create_mines_session(
  p_user_id uuid,
  p_bet_amount integer,
  p_mines_count integer,
  p_grid_size integer default 25
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_session_id uuid;
  v_mine_positions jsonb;
  v_balance int;
  v_positions int[];
  v_temp int;
  v_idx int;
begin
  if p_user_id != auth.uid() then
    return jsonb_build_object('error', 'unauthorized');
  end if;

  if p_bet_amount <= 0 then
    return jsonb_build_object('error', 'invalid_bet');
  end if;

  if p_mines_count < 1 or p_mines_count >= p_grid_size then
    return jsonb_build_object('error', 'invalid_mines_count');
  end if;

  -- Verif solde (treasury_place_bet le fera aussi mais on retourne un message clair)
  select coins into v_balance from public.user_profiles where id = p_user_id;
  if v_balance is null or v_balance < p_bet_amount then
    return jsonb_build_object('error', 'insufficient_coins');
  end if;

  -- Generer Fisher-Yates shuffle pour positions des mines
  v_positions := array(select generate_series(0, p_grid_size - 1));
  for i in reverse (p_grid_size - 1)..1 loop
    v_idx := floor(random() * (i + 1))::int;
    v_temp := v_positions[i + 1];
    v_positions[i + 1] := v_positions[v_idx + 1];
    v_positions[v_idx + 1] := v_temp;
  end loop;

  -- Prendre les p_mines_count premieres positions
  v_mine_positions := to_jsonb(v_positions[1:p_mines_count]);

  -- Creer la session
  insert into public.mines_sessions(
    user_id, bet_amount, mines_count, grid_size,
    mine_positions, status, current_multiplier, current_potential_win
  )
  values(
    p_user_id, p_bet_amount, p_mines_count, p_grid_size,
    v_mine_positions, 'active', 0, 0
  )
  returning id into v_session_id;

  -- ===== TREASURY MIGRATION =====
  -- Debit via la caisse (atomique, log auto, raise INSUFFICIENT_COINS si pas assez)
  perform public.treasury_place_bet(
    'mines', v_session_id::text, p_user_id, p_bet_amount
  );

  return jsonb_build_object(
    'session_id', v_session_id,
    'grid_size', p_grid_size,
    'mines_count', p_mines_count
  );
end;
$$;

grant execute on function public.create_mines_session(uuid, integer, integer, integer) to authenticated;

-- ============================================================
-- 3) reveal_mines_tile - auto-cashout via apply_game_payout
-- ============================================================
create or replace function public.reveal_mines_tile(
  p_session_id uuid,
  p_user_id uuid,
  p_position integer
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_session mines_sessions%rowtype;
  v_mine_positions jsonb;
  v_is_mine boolean;
  v_new_count int;
  v_new_mult numeric;
  v_new_win int;
begin
  if p_user_id != auth.uid() then
    return jsonb_build_object('error', 'unauthorized');
  end if;

  select * into v_session from public.mines_sessions
    where id = p_session_id and user_id = p_user_id for update;
  if v_session is null then
    return jsonb_build_object('error', 'session_not_found');
  end if;
  if v_session.status != 'active' then
    return jsonb_build_object('error', 'session_not_active');
  end if;

  v_mine_positions := v_session.mine_positions;
  v_is_mine := exists(
    select 1 from jsonb_array_elements(v_mine_positions) m
    where (m::int) = p_position
  );

  if v_is_mine then
    -- Mine touchee : perte. Mise reste a la caisse (deja debitee).
    update public.mines_sessions set
      status = 'lost',
      revealed_positions = revealed_positions ||
        jsonb_build_array(jsonb_build_object('pos', p_position, 'is_mine', true)),
      finished_at = now(),
      updated_at = now()
    where id = p_session_id;

    return jsonb_build_object(
      'is_mine', true, 'position', p_position, 'status', 'lost',
      'mine_positions', v_mine_positions, 'finished', true
    );
  end if;

  -- Tile safe : update count + multiplier
  v_new_count := v_session.safe_revealed_count + 1;
  v_new_mult := mines_calc_multiplier(v_new_count, v_session.mines_count, v_session.grid_size);
  v_new_win := floor(v_session.bet_amount * v_new_mult)::int;

  update public.mines_sessions set
    safe_revealed_count = v_new_count,
    current_multiplier = v_new_mult,
    current_potential_win = v_new_win,
    revealed_positions = v_session.revealed_positions ||
      jsonb_build_array(jsonb_build_object('pos', p_position, 'is_mine', false)),
    updated_at = now()
  where id = p_session_id;

  -- Toutes les cases safe revelees ? -> auto-cashout
  if v_new_count >= (v_session.grid_size - v_session.mines_count) then
    -- ===== TREASURY =====
    -- apply_game_payout : 90% user, 10% caisse
    if v_new_win > 0 then
      perform public.apply_game_payout(
        'mines', p_session_id::text, p_user_id, v_new_win
      );
    end if;

    update public.mines_sessions set
      status = 'cashed_out', finished_at = now()
    where id = p_session_id;

    return jsonb_build_object(
      'is_mine', false, 'position', p_position, 'status', 'cashed_out',
      'safe_revealed_count', v_new_count, 'current_multiplier', v_new_mult,
      'current_potential_win', floor(v_new_win * 0.90)::int,
      'finished', true, 'payout', floor(v_new_win * 0.90)::int
    );
  end if;

  return jsonb_build_object(
    'is_mine', false, 'position', p_position, 'status', 'active',
    'safe_revealed_count', v_new_count, 'current_multiplier', v_new_mult,
    'current_potential_win', v_new_win, 'finished', false
  );
end;
$$;

grant execute on function public.reveal_mines_tile(uuid, uuid, integer) to authenticated;

-- ============================================================
-- 4) cashout_mines_session - via apply_game_payout
-- ============================================================
create or replace function public.cashout_mines_session(
  p_session_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_session mines_sessions%rowtype;
  v_payout int;
  v_net int;
begin
  if p_user_id != auth.uid() then
    return jsonb_build_object('error', 'unauthorized');
  end if;

  select * into v_session from public.mines_sessions
    where id = p_session_id and user_id = p_user_id for update;
  if v_session is null then
    return jsonb_build_object('error', 'session_not_found');
  end if;
  if v_session.status != 'active' then
    return jsonb_build_object('error', 'session_not_active');
  end if;
  if v_session.safe_revealed_count < 1 then
    return jsonb_build_object('error', 'must_reveal_at_least_one');
  end if;

  v_payout := v_session.current_potential_win;

  -- ===== TREASURY =====
  if v_payout > 0 then
    v_net := public.apply_game_payout(
      'mines', p_session_id::text, p_user_id, v_payout
    );
  else
    v_net := 0;
  end if;

  update public.mines_sessions set
    status = 'cashed_out',
    updated_at = now(),
    finished_at = now()
  where id = p_session_id;

  return jsonb_build_object(
    'success', true,
    'payout', v_net,  -- gain NET (apres 10% commission)
    'multiplier', v_session.current_multiplier,
    'mine_positions', v_session.mine_positions
  );
end;
$$;

grant execute on function public.cashout_mines_session(uuid, uuid) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Bilan :
--   - Bet 100 -> caisse +100 (treasury_place_bet)
--   - Joueur tape mine : caisse garde 100, joueur perd 100. Net casino : +100
--   - Joueur cashout @ x2.5 (gross 250) :
--     -> apply_game_payout(250) = user +225 (90%), caisse +25 (10%)
--     -> Bilan : caisse +100 - 225 = -125 (perte cette manche)
--     -> Joueur : -100 + 225 = +125 net
-- ============================================================
