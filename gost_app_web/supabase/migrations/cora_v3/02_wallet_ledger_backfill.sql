-- ============================================================
-- WALLET LEDGER — Backfill depuis user_profiles.coins
-- ============================================================
-- One-shot : crée 1 ligne ledger 'adjustment' par user existant
-- pour initialiser le ledger avec leur solde actuel.
--
-- À exécuter UNE FOIS après 01_wallet_ledger.sql.
-- Idempotent (ON CONFLICT DO NOTHING via request_id unique).
-- ============================================================

insert into wallet_ledger
  (user_id, amount, balance_before, balance_after, type,
   game_type, game_id, request_id, metadata)
select
  id, coins, 0, coins, 'adjustment',
  'system', null,
  'migration_initial:' || id::text,
  jsonb_build_object(
    'migrated_at', now(),
    'source', 'user_profiles.coins'
  )
from user_profiles
where coins is not null and coins > 0
on conflict (user_id, request_id) do nothing;

-- Vérification : combien de users initialisés ?
do $$
declare v_count int; v_total bigint;
begin
  select count(*), sum(coins) into v_count, v_total from user_profiles where coins > 0;
  raise notice 'Backfill terminé : % users, % coins total migrés', v_count, v_total;
end $$;

-- ============================================================
-- Trigger temporaire : sync user_profiles.coins ← wallet_ledger
-- ============================================================
-- Phase de transition : tant que les anciens callers utilisent
-- user_profiles.coins, on synchronise depuis le ledger pour les
-- garder cohérents. À retirer après migration complète des callers.
-- ============================================================
create or replace function public._sync_coins_from_ledger() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  update user_profiles set coins = NEW.balance_after
    where id = NEW.user_id and coins is distinct from NEW.balance_after;
  return null;
end $$;

drop trigger if exists ledger_to_coins_sync on wallet_ledger;
create trigger ledger_to_coins_sync
  after insert on wallet_ledger
  for each row execute function _sync_coins_from_ledger();

-- ============================================================
-- Lock user_profiles.coins / xp / role / is_blocked en RLS
-- ============================================================
-- Les users authentifiés ne peuvent plus modifier ces colonnes.
-- ============================================================
drop policy if exists "users_update_own_profile" on user_profiles;
drop policy if exists "Users update own profile"  on user_profiles;
drop policy if exists "update_own_profile"        on user_profiles;

create policy "users_update_own_profile_safe" on user_profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and coins      is not distinct from (select coins      from user_profiles where id = auth.uid())
    and xp         is not distinct from (select xp         from user_profiles where id = auth.uid())
    and role       is not distinct from (select role       from user_profiles where id = auth.uid())
    and is_blocked is not distinct from (select is_blocked from user_profiles where id = auth.uid())
  );

comment on policy "users_update_own_profile_safe" on user_profiles is
  'User peut modifier ses infos (username, avatar...) mais coins/xp/role/is_blocked sont immuables côté client.';
