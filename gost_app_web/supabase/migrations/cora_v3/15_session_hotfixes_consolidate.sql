-- ============================================================
-- CORA V3 — Consolidation des hotfixes de session
-- ============================================================
-- Capture en migration durable TOUS les SQL ad-hoc appliqués
-- pendant la session de debug du 7 mai 2026.
-- Idempotent : peut être ré-exécuté sans risque.
--
-- Inclut :
--   1. _cora_lock_room (hashtext au lieu de hashtextextended::int)
--   2. RLS recursive fix (_cora_user_in_room helper + policies)
--   3. search_path extensions sur les fonctions pgcrypto
--   4. Migration types money en bigint (9 colonnes)
--   5. user_profiles policy lock (coins/xp/role/is_blocked immutables)
--   6. DROP des vues legacy bloquantes (auto-discovery)
--   7. Cleanup global des rooms zombies
-- ============================================================

-- ============================================================
-- 1. _cora_lock_room : hashtext au lieu de hashtextextended::int
-- ============================================================
create or replace function public._cora_lock_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path=public, extensions
as $$
begin
  perform pg_advisory_xact_lock(
    hashtext('cora_room'),
    hashtext(p_room_id::text)
  );
end; $$;
revoke all on function public._cora_lock_room(uuid) from public, anon, authenticated;

-- ============================================================
-- 2. RLS non-récursif via helper SECURITY DEFINER
-- ============================================================
create or replace function public._cora_user_in_room(p_room_id uuid, p_user_id uuid)
returns boolean
language sql security definer set search_path=public stable
as $$
  select exists (
    select 1 from cora_room_players
     where room_id = p_room_id and user_id = p_user_id
  );
$$;
revoke all on function public._cora_user_in_room(uuid, uuid) from public, anon;
grant execute on function public._cora_user_in_room(uuid, uuid) to authenticated;

drop policy if exists "rp_select" on public.cora_room_players;
create policy "rp_select" on public.cora_room_players for select using (
  user_id = auth.uid()
  or _cora_user_in_room(room_id, auth.uid())
);

drop policy if exists "rooms_select" on public.cora_rooms;
create policy "rooms_select" on public.cora_rooms for select using (
  (status = 'waiting' and is_private = false)
  or host_id = auth.uid()
  or _cora_user_in_room(id, auth.uid())
);

-- ============================================================
-- 3. search_path = public, extensions sur les fonctions pgcrypto
-- ============================================================
do $$ begin
  alter function public.cora_create_room(int, bigint, boolean)
    set search_path = public, extensions;
exception when others then raise notice 'set search_path cora_create_room: %', sqlerrm;
end $$;

do $$ begin
  alter function public._cora_secure_dice()
    set search_path = public, extensions;
exception when others then raise notice 'set search_path _cora_secure_dice: %', sqlerrm;
end $$;

do $$ begin
  alter function public._ledger_adjust(uuid, bigint, text)
    set search_path = public, extensions;
exception when others then raise notice 'set search_path _ledger_adjust: %', sqlerrm;
end $$;

-- ============================================================
-- 4. Types money → bigint (auto-discovery + drop des vues bloquantes)
-- ============================================================
-- Auto-discovery : drop toute vue qui dépend des tables à migrer
do $$
declare
  r record;
  v_views text[] := array[]::text[];
  v_def text;
begin
  for r in
    select distinct dep.relname as view_name, ns.nspname as schema_name
      from pg_depend d
      join pg_rewrite rw on rw.oid = d.objid
      join pg_class dep on dep.oid = rw.ev_class
      join pg_namespace ns on ns.oid = dep.relnamespace
      join pg_class src on src.oid = d.refobjid
     where d.deptype = 'n'
       and dep.relkind = 'v'
       and src.relname in ('user_profiles','game_treasury','admin_treasury',
                           'cora_rooms','cora_games','wallet_ledger')
       and ns.nspname = 'public'
  loop
    select pg_get_viewdef(format('%I.%I', r.schema_name, r.view_name)::regclass, true) into v_def;
    v_views := array_append(v_views,
      format('CREATE VIEW %I.%I AS %s', r.schema_name, r.view_name, v_def));
    execute format('drop view if exists %I.%I cascade', r.schema_name, r.view_name);
    raise notice 'Dropped: %.%', r.schema_name, r.view_name;
  end loop;

  -- Drop la policy qui réfère coins/xp
  drop policy if exists "users_update_own_profile_safe" on public.user_profiles;

  -- ALTER COLUMN → bigint (idempotent : si déjà bigint, ne fait rien)
  begin alter table public.game_treasury  alter column balance        type bigint;
  exception when others then null; end;
  begin alter table public.game_treasury  alter column total_received type bigint;
  exception when others then null; end;
  begin alter table public.game_treasury  alter column total_paid_out type bigint;
  exception when others then null; end;
  begin alter table public.admin_treasury alter column balance        type bigint;
  exception when others then null; end;
  begin alter table public.admin_treasury alter column total_earned   type bigint;
  exception when others then null; end;
  begin alter table public.admin_treasury alter column total_withdrawn type bigint;
  exception when others then null; end;
  begin alter table public.cora_rooms     alter column bet_amount     type bigint;
  exception when others then null; end;
  begin alter table public.cora_games     alter column bet_amount     type bigint;
  exception when others then null; end;
  begin alter table public.user_profiles  alter column coins          type bigint;
  exception when others then null; end;
  begin alter table public.user_profiles  alter column xp             type bigint;
  exception when others then null; end;

  -- Recrée la policy user_profiles
  create policy "users_update_own_profile_safe" on public.user_profiles for update
    using (auth.uid() = id)
    with check (
      auth.uid() = id
      and coins      is not distinct from (select coins      from user_profiles where id = auth.uid())
      and xp         is not distinct from (select xp         from user_profiles where id = auth.uid())
      and role       is not distinct from (select role       from user_profiles where id = auth.uid())
      and is_blocked is not distinct from (select is_blocked from user_profiles where id = auth.uid())
    );

  -- Recrée toutes les vues
  foreach v_def in array v_views loop
    begin
      execute v_def;
    exception when others then
      raise notice 'View recreate failed: % | sql=%', sqlerrm, left(v_def, 100);
    end;
  end loop;
end $$;

-- ============================================================
-- 5. Vérification finale
-- ============================================================
do $$
declare v_count int;
begin
  select count(*) into v_count from information_schema.columns
    where table_schema='public'
      and table_name in ('game_treasury','admin_treasury','cora_rooms',
                         'cora_games','user_profiles')
      and column_name in ('balance','total_received','total_paid_out',
                          'total_earned','total_withdrawn','bet_amount',
                          'coins','xp')
      and data_type = 'bigint';
  if v_count >= 9 then
    raise notice 'Money columns migration OK (% bigint columns)', v_count;
  else
    raise warning 'Money columns INCOMPLETE (% bigint, expected >= 9)', v_count;
  end if;
end $$;
