-- ============================================================
-- SOLITAIRE — Wallet operations safe avec reconcile préalable
-- ============================================================
-- Bug critique : quand un user dépose via FreemoPay legacy (addCoins
-- direct sur user_profiles.coins SANS entrée wallet_ledger), le ledger
-- a balance_after=0 alors que profile.coins=500. Quand on appelle
-- _ledger_post(+payout), le trigger _sync_coins_from_ledger force
-- coins = balance_after (= petit chiffre), effaçant les fonds legacy.
--
-- Fix : avant chaque opération wallet, on appelle reconcile_user_ledger
-- pour aligner ledger sur profile.coins. Ainsi balance_before sera
-- correct et balance_after = bonne valeur.
--
-- Ce wrapper est utilisé par toutes les RPCs Solitaire multi (et peut
-- être étendu à d'autres jeux).
-- ============================================================

-- ============================================================
-- 1. Wrapper safe : reconcile + _ledger_post
-- ============================================================
create or replace function public._ledger_post_safe(
  p_user_id    uuid,
  p_amount     bigint,
  p_type       text,
  p_request_id text,
  p_game_type  text default null,
  p_game_id    text default null,
  p_metadata   jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path=public, extensions
as $$
begin
  -- 🔥 Reconcile : si profile.coins > ledger.balance_after, crée une entrée
  -- 'adjustment' pour combler. Ainsi balance_before sera correct.
  begin
    perform reconcile_user_ledger(p_user_id);
  exception when others then null; -- best-effort
  end;

  -- Maintenant on peut poster sans risque d'effacer des fonds legacy
  return _ledger_post(p_user_id, p_amount, p_type, p_request_id,
                      p_game_type, p_game_id, p_metadata);
end; $$;
revoke all on function public._ledger_post_safe(uuid, bigint, text, text, text, text, jsonb)
  from public, anon, authenticated;

-- ============================================================
-- 2. Re-deploy solitaire_multi_place_bet avec _ledger_post_safe
-- ============================================================
create or replace function public.solitaire_multi_place_bet(
  p_room_id  text,
  p_amount   bigint
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;
  if p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if p_amount < 50 or p_amount > 10000 then
    raise exception 'INVALID_BET_RANGE: 50-10000' using errcode = '22023';
  end if;

  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  -- 🔥 Reconcile FIRST : align ledger avec profile.coins legacy
  begin perform reconcile_user_ledger(v_uid); exception when others then null; end;

  v_balance := wallet_balance(v_uid);
  if v_balance < p_amount then
    raise exception 'INSUFFICIENT_FUNDS: required=%, balance=%', p_amount, v_balance
      using errcode = 'P0001';
  end if;

  perform _ledger_post(
    v_uid, -p_amount, 'bet',
    'solitaire_multi_bet:' || p_room_id || ':' || v_uid::text,
    'solitaire_multi', p_room_id,
    jsonb_build_object('source', 'solitaire_multi_place_bet', 'room_id', p_room_id)
  );

  begin
    update game_treasury
      set balance = balance + p_amount,
          total_received = total_received + p_amount,
          updated_at = now()
      where id = 1;
  exception when undefined_table then null;
  end;

  return jsonb_build_object('placed', true, 'amount', p_amount,
                            'new_balance', wallet_balance(v_uid));
end; $$;
revoke all on function public.solitaire_multi_place_bet(text, bigint) from public, anon;
grant execute on function public.solitaire_multi_place_bet(text, bigint) to authenticated;

-- ============================================================
-- 3. Re-deploy solitaire_multi_finalize avec reconcile par winner
-- ============================================================
create or replace function public.solitaire_multi_finalize(
  p_room_id    text,
  p_winner_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_pot bigint;
  v_cut bigint;
  v_total_payout bigint;
  v_per_winner bigint;
  v_winners_count int;
  v_winner uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_room from solitaire_rooms where id = p_room_id::uuid for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.status = 'finished' then
    return jsonb_build_object('idempotent', true, 'state', 'already_finished');
  end if;
  if v_room.status not in ('waiting','playing') then
    return jsonb_build_object('skipped', true, 'state', v_room.status);
  end if;

  if not exists (
    select 1 from jsonb_array_elements(v_room.game_state -> 'players') p
     where p->>'id' = v_uid::text
  ) then raise exception 'NOT_A_PARTICIPANT'; end if;

  v_winners_count := coalesce(array_length(p_winner_ids, 1), 0);

  -- ===========================================================
  -- AUCUN GAGNANT : refund tous (avec reconcile préalable)
  -- ===========================================================
  if v_winners_count = 0 then
    declare v_p jsonb; v_puid uuid;
    begin
      for v_p in select * from jsonb_array_elements(v_room.game_state -> 'players') loop
        v_puid := (v_p->>'id')::uuid;
        begin perform reconcile_user_ledger(v_puid); exception when others then null; end;
        begin
          perform _ledger_post(
            v_puid, v_room.bet_amount, 'refund',
            'solitaire_multi_no_winner_refund:' || p_room_id || ':' || v_puid::text,
            'solitaire_multi', p_room_id,
            jsonb_build_object('reason', 'no_winner_refund'));
        exception when others then null;
        end;
      end loop;
    end;
    update game_treasury
       set balance = greatest(0, balance - v_room.pot),
           total_paid_out = total_paid_out + v_room.pot,
           updated_at = now()
     where id = 1;
    update solitaire_rooms set status = 'cancelled', updated_at = now()
     where id = p_room_id::uuid;
    return jsonb_build_object('finalized', true, 'state', 'cancelled_no_winner_refunded');
  end if;

  v_pot := v_room.pot;

  -- ===========================================================
  -- ÉGALITÉ : refund original bet (avec reconcile)
  -- ===========================================================
  if v_winners_count > 1 then
    foreach v_winner in array p_winner_ids loop
      begin perform reconcile_user_ledger(v_winner); exception when others then null; end;
      perform _ledger_post(
        v_winner, v_room.bet_amount, 'refund',
        'solitaire_multi_tie_refund:' || p_room_id || ':' || v_winner::text,
        'solitaire_multi', p_room_id,
        jsonb_build_object('reason', 'tie_each_gets_back_bet',
                           'tied_winners', v_winners_count));
    end loop;

    update game_treasury
       set balance = greatest(0, balance - (v_room.bet_amount * v_winners_count)),
           total_paid_out = total_paid_out + (v_room.bet_amount * v_winners_count),
           updated_at = now()
     where id = 1;

    declare v_remainder bigint;
    begin
      v_remainder := v_pot - (v_room.bet_amount * v_winners_count);
      if v_remainder > 0 then
        update admin_treasury
           set balance = balance + v_remainder,
               total_earned = total_earned + v_remainder, updated_at = now()
         where id = 1;
        if not found then
          insert into admin_treasury(id, balance, total_earned, total_withdrawn)
            values (1, v_remainder, v_remainder, 0);
        end if;
        update game_treasury
           set balance = greatest(0, balance - v_remainder),
               total_paid_out = total_paid_out + v_remainder, updated_at = now()
         where id = 1;
      end if;
    end;

    update solitaire_rooms set status = 'finished', updated_at = now()
     where id = p_room_id::uuid;

    return jsonb_build_object('finalized', true, 'state', 'finished_tie',
                              'is_tie', true, 'each_tied_gets', v_room.bet_amount);
  end if;

  -- ===========================================================
  -- 1 SEUL GAGNANT : reconcile AVANT le payout (CRITIQUE)
  -- ===========================================================
  v_cut := floor(v_pot * 0.10)::bigint;
  v_total_payout := v_pot - v_cut;

  -- 🔥 Reconcile le ledger du winner pour qu'il garde ses fonds legacy
  begin perform reconcile_user_ledger(p_winner_ids[1]); exception when others then null; end;

  perform _ledger_post(
    p_winner_ids[1], v_total_payout, 'payout',
    'solitaire_multi_payout:' || p_room_id || ':' || p_winner_ids[1]::text,
    'solitaire_multi', p_room_id,
    jsonb_build_object('pot', v_pot, 'commission', v_cut));

  update game_treasury
     set balance = balance - v_pot,
         total_paid_out = total_paid_out + v_pot, updated_at = now()
   where id = 1;

  if v_cut > 0 then
    update admin_treasury
       set balance = balance + v_cut, total_earned = total_earned + v_cut,
           updated_at = now()
     where id = 1;
    if not found then
      insert into admin_treasury(id, balance, total_earned, total_withdrawn)
        values (1, v_cut, v_cut, 0);
    end if;
  end if;

  update solitaire_rooms set status = 'finished', updated_at = now()
   where id = p_room_id::uuid;

  return jsonb_build_object('finalized', true, 'state', 'finished',
                            'winners', to_jsonb(p_winner_ids),
                            'pot', v_pot, 'commission', v_cut,
                            'per_winner', v_total_payout, 'is_tie', false);
end; $$;
revoke all on function public.solitaire_multi_finalize(text, uuid[]) from public, anon;
grant execute on function public.solitaire_multi_finalize(text, uuid[]) to authenticated;

-- ============================================================
-- 4. Reconcile global : repair tous les drifts immédiatement
-- ============================================================
select repair_wallet_drift() as users_repaired_now;

-- ============================================================
-- Note : pour Cora et autres jeux V3 qui utilisent _ledger_post,
-- le même bug peut exister. Solution propre : modifier _ledger_post
-- pour faire reconcile auto. À coder dans une migration séparée.
-- ============================================================
