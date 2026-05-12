-- ============================================================
-- WALLET V1.1 — wallet_balance() lit la source la plus à jour
-- ============================================================
-- BUG : les dépôts FreemoPay passent par addCoins legacy qui
-- update user_profiles.coins directement SANS créer d'entrée
-- wallet_ledger. Du coup wallet_balance() (qui lit le ledger)
-- voit l'ancien solde et déclenche INSUFFICIENT_FUNDS alors que
-- l'user a clairement les fonds dans user_profiles.coins.
--
-- FIX TEMPORAIRE : prend le GREATEST entre :
--   - wallet_ledger.balance_after (source V3)
--   - user_profiles.coins (legacy mais toujours vivante)
--
-- FIX DÉFINITIF (P0) : migrer FreemoPay vers _ledger_post.
-- Mais le GREATEST permet de débloquer les dépôts maintenant
-- sans casser la migration en cours.
-- ============================================================

create or replace function public.wallet_balance(p_user_id uuid default null)
returns bigint
language sql stable security definer set search_path=public
as $$
  select greatest(
    coalesce((
      select balance_after from wallet_ledger
       where user_id = coalesce(p_user_id, auth.uid())
       order by id desc limit 1
    ), 0),
    coalesce((
      select coins from user_profiles
       where id = coalesce(p_user_id, auth.uid())
    ), 0)
  );
$$;
revoke all on function public.wallet_balance(uuid) from public, anon;
grant execute on function public.wallet_balance(uuid) to authenticated;

-- ============================================================
-- Bonus : fonction de réconciliation manuelle pour ramener le
-- ledger à parité avec user_profiles.coins quand il y a un drift
-- positif côté user_profiles (= dépôt legacy non passé par ledger).
-- ============================================================
create or replace function public.reconcile_user_ledger(p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_ledger_balance bigint;
  v_profile_coins bigint;
  v_diff bigint;
  v_id bigint;
begin
  if p_user_id is null then raise exception 'USER_ID_REQUIRED'; end if;

  select coalesce(balance_after, 0) into v_ledger_balance
    from wallet_ledger where user_id = p_user_id
    order by id desc limit 1;

  select coalesce(coins, 0) into v_profile_coins
    from user_profiles where id = p_user_id;

  v_diff := v_profile_coins - coalesce(v_ledger_balance, 0);

  if v_diff = 0 then
    return jsonb_build_object('reconciled', false, 'reason', 'already_in_sync',
                              'ledger', v_ledger_balance, 'profile', v_profile_coins);
  end if;

  if v_diff > 0 then
    -- profile > ledger (cas typique : dépôt legacy non capturé)
    -- → on crée un ledger entry pour combler
    v_id := _ledger_post(
      p_user_id, v_diff, 'adjustment',
      'reconcile_legacy:' || p_user_id::text || ':' || extract(epoch from now())::text,
      'system', null,
      jsonb_build_object('reason', 'reconcile_legacy_deposit_drift',
                         'old_ledger', v_ledger_balance,
                         'profile_coins', v_profile_coins,
                         'diff', v_diff));
    return jsonb_build_object('reconciled', true, 'created_ledger_id', v_id,
                              'diff', v_diff, 'direction', 'profile_to_ledger');
  else
    -- profile < ledger (rare : trigger a foiré)
    -- → on update user_profiles
    update user_profiles set coins = v_ledger_balance where id = p_user_id;
    return jsonb_build_object('reconciled', true, 'updated_profile', true,
                              'diff', v_diff, 'direction', 'ledger_to_profile');
  end if;
end $$;
revoke all on function public.reconcile_user_ledger(uuid) from public, anon, authenticated;
-- service_role only

-- ============================================================
-- Réconcilie immédiatement TOUS les drifts détectés
-- (run via reconcile_user_ledger pour chaque user en drift)
-- ============================================================
do $$
declare r record; v_count int := 0;
begin
  for r in
    with last_balances as (
      select wl.user_id,
             wl.balance_after as ledger_balance,
             row_number() over (partition by wl.user_id order by wl.id desc) as rn
        from wallet_ledger wl
    )
    select
      lb.user_id,
      lb.ledger_balance,
      coalesce(up.coins, 0)::bigint as profile_coins
    from last_balances lb
    join user_profiles up on up.id = lb.user_id
    where lb.rn = 1
      and up.coins > lb.ledger_balance  -- seulement les drifts positifs (dépôts legacy)
  loop
    perform reconcile_user_ledger(r.user_id);
    v_count := v_count + 1;
  end loop;
  raise notice 'Reconciled % users with positive ledger drift', v_count;
end $$;
