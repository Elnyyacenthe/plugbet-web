-- ============================================================
-- LEDGER V1.2 — _ledger_post avec auto-reconcile inline
-- ============================================================
-- Problème : si user_profiles.coins est augmenté en dehors du ledger
-- (FreemoPay addCoins legacy, admin manual update, etc.), le prochain
-- appel à _ledger_post calcule balance_before depuis le ledger (stale)
-- et le trigger _sync_coins_from_ledger force coins=balance_after,
-- effaçant les fonds legacy.
--
-- Fix : avant le calcul de balance_before, on vérifie le drift
-- (profile.coins - ledger.balance_after). Si drift > 0, on insert une
-- entrée 'adjustment' INLINE pour combler. Pas de recursion (on insert
-- directement, on n'appelle pas reconcile_user_ledger).
--
-- Bénéfice : TOUS les jeux V3 qui utilisent _ledger_post (Cora,
-- Solitaire, Ludo V2, futurs jeux) sont automatiquement protégés.
-- ============================================================

create or replace function public._ledger_post(
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
declare
  v_existing       bigint;
  v_balance_before bigint;
  v_balance_after  bigint;
  v_id             bigint;
  v_profile_coins  bigint;
  v_drift          bigint;
  v_reconcile_id   bigint;
begin
  -- ===========================================================
  -- Idempotence : même (user_id, request_id) → return l'id existant
  -- ===========================================================
  select id into v_existing from wallet_ledger
   where user_id = p_user_id and request_id = p_request_id;
  if found then return v_existing; end if;

  -- ===========================================================
  -- Sérialisation : lock sur la dernière ligne du user
  -- ===========================================================
  select coalesce((select balance_after from wallet_ledger
                    where user_id = p_user_id
                    order by id desc limit 1 for update), 0)
    into v_balance_before;

  -- ===========================================================
  -- AUTO-RECONCILE INLINE
  -- Si profile.coins > ledger.balance_after, le drift représente des
  -- fonds legacy non capturés (dépôt FreemoPay, etc.). On insert une
  -- entrée 'adjustment' AVANT l'opération demandée pour aligner.
  -- ===========================================================
  select coalesce(coins, 0)::bigint into v_profile_coins
    from user_profiles where id = p_user_id;

  v_drift := coalesce(v_profile_coins, 0) - coalesce(v_balance_before, 0);

  if v_drift > 0 then
    -- Insert direct (PAS d'appel récursif à _ledger_post pour éviter loop)
    insert into wallet_ledger
      (user_id, amount, balance_before, balance_after, type,
       game_type, game_id, request_id, metadata)
    values
      (p_user_id, v_drift, v_balance_before, v_balance_before + v_drift,
       'adjustment',
       'system', null,
       'autoreconcile:' || p_user_id::text || ':' || extract(epoch from now())::text || ':' || v_drift::text,
       jsonb_build_object(
         'reason', 'inline_reconcile_pre_ledger_post',
         'drift', v_drift,
         'profile_coins', v_profile_coins,
         'old_ledger_balance', v_balance_before,
         'triggered_by_request_id', p_request_id
       ))
    returning id into v_reconcile_id;

    -- Update balance_before pour le post principal
    v_balance_before := v_balance_before + v_drift;
  end if;

  -- ===========================================================
  -- Opération demandée (post principal)
  -- ===========================================================
  v_balance_after := v_balance_before + p_amount;

  if v_balance_after < 0 then
    raise exception 'INSUFFICIENT_FUNDS: user=% balance=% requested=%',
      p_user_id, v_balance_before, p_amount
      using errcode = 'P0001';
  end if;

  insert into wallet_ledger
    (user_id, amount, balance_before, balance_after, type,
     game_type, game_id, request_id, metadata)
  values
    (p_user_id, p_amount, v_balance_before, v_balance_after, p_type,
     p_game_type, p_game_id, p_request_id, p_metadata)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public._ledger_post(uuid, bigint, text, text, text, text, jsonb)
  from public, anon, authenticated;

-- ============================================================
-- Test : repair drift global pour tous les users actuels
-- ============================================================
-- Plus nécessaire après cette migration car _ledger_post auto-reconcile,
-- mais on lance une fois pour clean l'état initial.
select repair_wallet_drift() as initial_repair;
