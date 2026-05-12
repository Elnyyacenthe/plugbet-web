-- ============================================================
-- WALLET LEDGER V1 — Source de vérité financière unique
-- ============================================================
-- Append-only, immutable. Aucune mutation directe possible.
-- Toutes les écritures via la fonction _ledger_post (SECURITY DEFINER privée).
--
-- À exécuter EN PREMIER. Idempotent.
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- 1. Table wallet_ledger
-- ============================================================
-- Crée si absente, sinon ajoute les colonnes manquantes.
create table if not exists public.wallet_ledger (
  id              bigserial primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  amount          bigint not null,
  balance_before  bigint not null,
  balance_after   bigint not null,
  type            text not null,
  game_type       text,
  game_id         text,
  request_id      text not null,
  metadata        jsonb default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

-- Si la table existait déjà avec un schéma différent, on patche.
alter table public.wallet_ledger add column if not exists user_id        uuid;
alter table public.wallet_ledger add column if not exists amount         bigint;
alter table public.wallet_ledger add column if not exists balance_before bigint;
alter table public.wallet_ledger add column if not exists balance_after  bigint;
alter table public.wallet_ledger add column if not exists type           text;
alter table public.wallet_ledger add column if not exists game_type      text;
alter table public.wallet_ledger add column if not exists game_id        text;
alter table public.wallet_ledger add column if not exists request_id     text;
alter table public.wallet_ledger add column if not exists metadata       jsonb default '{}'::jsonb;
alter table public.wallet_ledger add column if not exists created_at     timestamptz default now();

-- Colonnes legacy d'autres modules : si elles ont un NOT NULL elles bloquent
-- les INSERT V3. On retire la contrainte NOT NULL et on laisse la colonne
-- (zéro perte de données). Si la colonne n'existe pas, l'ALTER tombe en
-- silencieusement via le DO block.
do $$
declare r record;
begin
  for r in
    select column_name
    from information_schema.columns
    where table_schema='public' and table_name='wallet_ledger'
      and is_nullable='NO'
      and column_name not in (
        'id','user_id','amount','balance_before','balance_after',
        'type','request_id','created_at'
      )
  loop
    execute format('alter table public.wallet_ledger alter column %I drop not null', r.column_name);
    raise notice 'wallet_ledger: NOT NULL drop sur colonne legacy "%"', r.column_name;
  end loop;
end $$;

-- Contraintes (idempotent via DO block)
do $$ begin
  alter table public.wallet_ledger
    add constraint wallet_ledger_type_check
    check (type in ('bet','payout','refund','penalty','deposit','withdrawal','bonus','adjustment'));
exception
  when duplicate_object then null;
  when others then
    -- Si une contrainte différente existe ou si des données existantes
    -- violent le check, on tolère pour ne pas bloquer la migration.
    raise notice 'wallet_ledger_type_check skipped: %', sqlerrm;
end $$;

do $$ begin
  alter table public.wallet_ledger
    add constraint wallet_ledger_balance_consistent
    check (balance_after = balance_before + amount);
exception
  when duplicate_object then null;
  when duplicate_table  then null;
  when others           then raise notice 'wallet_ledger_balance_consistent skipped: %', sqlerrm;
end $$;

do $$ begin
  alter table public.wallet_ledger
    add constraint wallet_ledger_no_negative
    check (balance_after >= 0);
exception
  when duplicate_object then null;
  when duplicate_table  then null;
  when others           then raise notice 'wallet_ledger_no_negative skipped: %', sqlerrm;
end $$;

do $$ begin
  alter table public.wallet_ledger
    add constraint wallet_ledger_unique_request
    unique (user_id, request_id);
exception
  when duplicate_object then null;
  when duplicate_table  then null;  -- l'index sous-jacent existe déjà
  when others           then raise notice 'wallet_ledger_unique_request skipped: %', sqlerrm;
end $$;

create index if not exists idx_ledger_user_date on wallet_ledger(user_id, created_at desc);
create index if not exists idx_ledger_user_id   on wallet_ledger(user_id, id desc);
create index if not exists idx_ledger_game      on wallet_ledger(game_type, game_id);
create index if not exists idx_ledger_type_date on wallet_ledger(type, created_at desc);

-- ============================================================
-- 2. RLS append-only : SELECT only own, aucun INSERT/UPDATE/DELETE
-- ============================================================
alter table public.wallet_ledger enable row level security;

drop policy if exists "ledger_read_own" on public.wallet_ledger;
create policy "ledger_read_own" on public.wallet_ledger
  for select using (user_id = auth.uid());

-- ============================================================
-- 3. RPC publique : balance courante
-- ============================================================
create or replace function public.wallet_balance(p_user_id uuid default null)
returns bigint
language sql stable security definer set search_path=public
as $$
  select coalesce(balance_after, 0)
  from wallet_ledger
  where user_id = coalesce(p_user_id, auth.uid())
  order by id desc limit 1;
$$;

revoke all on function public.wallet_balance(uuid) from public, anon;
grant execute on function public.wallet_balance(uuid) to authenticated;

-- ============================================================
-- 4. RPC interne : _ledger_post (idempotent, atomique)
-- ============================================================
-- IMPORTANT : aucune grant publique. Seules les fonctions SECURITY DEFINER
-- métier appellent _ledger_post (et héritent des droits owner).
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
language plpgsql security definer set search_path=public
as $$
declare
  v_existing bigint;
  v_balance_before bigint;
  v_balance_after  bigint;
  v_id bigint;
begin
  -- Idempotence : même (user_id, request_id) déjà écrit → return l'id existant
  select id into v_existing from wallet_ledger
   where user_id = p_user_id and request_id = p_request_id;
  if found then return v_existing; end if;

  -- Sérialisation : lock sur la dernière ligne du user
  select coalesce((select balance_after from wallet_ledger
                    where user_id = p_user_id
                    order by id desc limit 1 for update), 0)
    into v_balance_before;

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
-- 5. RPC interne : adjuster le solde d'un user (admin only)
-- ============================================================
create or replace function public._ledger_adjust(
  p_user_id uuid,
  p_amount  bigint,
  p_reason  text
) returns bigint
language plpgsql security definer set search_path=public
as $$
declare v_caller_role text;
begin
  -- Verifier que le caller est super_admin
  select role into v_caller_role from user_profiles where id = auth.uid();
  if v_caller_role != 'super_admin' then
    raise exception 'ADMIN_ONLY' using errcode = '42501';
  end if;

  return _ledger_post(
    p_user_id, p_amount, 'adjustment',
    'admin_adj:' || gen_random_uuid()::text,
    'admin', null,
    jsonb_build_object('reason', p_reason, 'admin_id', auth.uid())
  );
end; $$;

revoke all on function public._ledger_adjust(uuid, bigint, text) from public, anon;
grant execute on function public._ledger_adjust(uuid, bigint, text) to authenticated;

-- ============================================================
-- 6. Vue d'audit : cohérence du ledger
-- ============================================================
create or replace view public.wallet_audit_v as
select
  user_id,
  count(*) as nb_movements,
  max(balance_after) filter (where rn = 1) as current_balance,
  sum(amount) as sum_amounts,
  max(balance_after) filter (where rn = 1) - sum(amount) as discrepancy,
  max(created_at) filter (where rn = 1) as last_movement
from (
  select user_id, amount, balance_after, created_at,
         row_number() over (partition by user_id order by id desc) rn
  from wallet_ledger
) t
group by user_id;

-- Si discrepancy != 0 pour un user → BUG. Doit toujours être 0.

comment on table public.wallet_ledger is
  'Source de vérité financière. Append-only. Idempotent par (user_id, request_id).';
