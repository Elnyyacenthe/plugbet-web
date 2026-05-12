-- ============================================================
-- SECURITY DROPS + TREASURY RECONCILE
-- ============================================================
-- 1. DROP les fonctions dangereuses (au lieu de juste revoke)
-- 2. Réconcilie game_treasury à partir du wallet_ledger (source de vérité)
-- 3. Crée un job de réconciliation périodique
-- ============================================================

-- ============================================================
-- 1. DROP DÉFINITIF des fonctions dangereuses
-- ============================================================
-- treasury_refund_all : si rebind par erreur → vol massif possible.
-- On drop toutes les surcharges existantes.
do $$
declare r record;
begin
  for r in
    select n.nspname || '.' || p.proname as fn,
           '(' || pg_get_function_identity_arguments(p.oid) || ')' as args
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'treasury_refund_all'
  loop
    begin
      execute format('drop function %s%s cascade', r.fn, r.args);
      raise notice 'DROPPED dangerous function: %s%s', r.fn, r.args;
    exception when others then
      raise notice 'Drop failed for %s%s: %', r.fn, r.args, sqlerrm;
    end;
  end loop;
end $$;

-- Idem pour cora_treasury_hook (déjà fait en session, on assure)
drop function if exists public.cora_treasury_hook() cascade;
drop function if exists public.cora_vote_continue(uuid) cascade;
drop function if exists public.cora_vote_continue(uuid, boolean) cascade;
drop function if exists public.cora_vote_continue() cascade;

-- ============================================================
-- 2. RÉCONCILIATION game_treasury depuis wallet_ledger
-- ============================================================
-- Source de vérité : wallet_ledger (immutable).
-- game_treasury.balance théorique =
--    SUM(bet) − SUM(payout) − SUM(refund)  pour tous les game_type
-- (toutes les contributions des jeux passent par game_treasury).
--
-- On recalcule et on persiste l'état correct.
-- Les emergency cleanups de la session ont créé des incohérences,
-- ce job remet tout à plat.
-- ============================================================
create or replace function public.reconcile_game_treasury()
returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_old_balance bigint;
  v_old_received bigint;
  v_old_paid bigint;
  v_total_bets bigint;
  v_total_payouts bigint;
  v_total_refunds bigint;
  v_total_penalty bigint;
  v_correct_received bigint;
  v_correct_paid bigint;
  v_correct_balance bigint;
begin
  -- État actuel
  select balance, total_received, total_paid_out
    into v_old_balance, v_old_received, v_old_paid
    from game_treasury where id = 1;

  -- Calcul depuis wallet_ledger (source de vérité)
  select
    coalesce(sum(-amount) filter (where type = 'bet'), 0),
    coalesce(sum(amount)  filter (where type = 'payout'), 0),
    coalesce(sum(amount)  filter (where type = 'refund'), 0),
    coalesce(sum(-amount) filter (where type = 'penalty'), 0)
    into v_total_bets, v_total_payouts, v_total_refunds, v_total_penalty
    from wallet_ledger
   where game_type is not null;  -- Tous les jeux

  -- total_received = bets entrants + penalties Cora
  v_correct_received := v_total_bets + v_total_penalty;
  -- total_paid_out  = payouts + refunds
  v_correct_paid     := v_total_payouts + v_total_refunds;
  -- balance théorique = received - paid (ce qui reste en cagnotte)
  v_correct_balance  := v_correct_received - v_correct_paid;

  -- Persiste les valeurs correctes
  update game_treasury
     set balance        = greatest(0, v_correct_balance),
         total_received = v_correct_received,
         total_paid_out = v_correct_paid,
         updated_at     = now()
   where id = 1;

  return jsonb_build_object(
    'old_state',  jsonb_build_object(
        'balance', v_old_balance,
        'total_received', v_old_received,
        'total_paid_out', v_old_paid),
    'new_state',  jsonb_build_object(
        'balance', greatest(0, v_correct_balance),
        'total_received', v_correct_received,
        'total_paid_out', v_correct_paid),
    'breakdown',  jsonb_build_object(
        'bets',     v_total_bets,
        'penalties', v_total_penalty,
        'payouts',  v_total_payouts,
        'refunds',  v_total_refunds),
    'discrepancy_balance', v_old_balance - v_correct_balance,
    'reconciled_at', now()
  );
end; $$;
revoke all on function public.reconcile_game_treasury() from public, anon, authenticated;
-- service_role uniquement (admin via SQL editor ou Edge Function)

-- ============================================================
-- 3. Audit wallet_ledger : détecte les drifts user_profiles.coins
-- ============================================================
create or replace function public.audit_wallet_drift()
returns table (
  user_id uuid,
  ledger_balance bigint,
  profile_coins  bigint,
  drift          bigint,
  last_movement  timestamptz
)
language sql security definer set search_path=public stable
as $$
  with last_balances as (
    select wl.user_id,
           wl.balance_after as ledger_balance,
           wl.created_at as last_movement,
           row_number() over (partition by wl.user_id order by wl.id desc) as rn
      from wallet_ledger wl
  )
  select
    lb.user_id,
    lb.ledger_balance,
    coalesce(up.coins, 0)::bigint as profile_coins,
    (lb.ledger_balance - coalesce(up.coins, 0))::bigint as drift,
    lb.last_movement
  from last_balances lb
  left join user_profiles up on up.id = lb.user_id
  where lb.rn = 1
    and lb.ledger_balance != coalesce(up.coins, 0);
$$;
revoke all on function public.audit_wallet_drift() from public, anon, authenticated;
-- service_role only

-- ============================================================
-- 4. Réparation drift (force user_profiles.coins = ledger.balance_after)
-- ============================================================
create or replace function public.repair_wallet_drift()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare r record; v_count int := 0;
begin
  for r in select * from audit_wallet_drift() loop
    update user_profiles set coins = r.ledger_balance where id = r.user_id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke all on function public.repair_wallet_drift() from public, anon, authenticated;

-- ============================================================
-- 5. Cron de réconciliation hebdomadaire (lundi 4h du matin)
-- ============================================================
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname in ('treasury-reconcile-weekly','wallet-drift-repair-daily');

    perform cron.schedule('treasury-reconcile-weekly', '0 4 * * 1',
      $cron$ select public.reconcile_game_treasury(); $cron$);

    perform cron.schedule('wallet-drift-repair-daily', '0 3 * * *',
      $cron$ select public.repair_wallet_drift(); $cron$);

    raise notice 'Crons treasury-reconcile + wallet-drift-repair schedulés';
  end if;
end $$;

-- ============================================================
-- 6. Exécute la réconciliation IMMÉDIATEMENT pour fix l'état actuel
-- ============================================================
select public.reconcile_game_treasury() as initial_reconcile;
select public.repair_wallet_drift() as wallets_repaired;
