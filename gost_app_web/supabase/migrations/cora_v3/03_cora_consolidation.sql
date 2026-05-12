-- ============================================================
-- CORA DICE V3 — Consolidation : suppression anciennes RPCs
-- ============================================================
-- Supprime toutes les versions concurrentes de submit_cora_roll,
-- create_cora_room, join_cora_room, toggle_cora_ready, create_cora_game,
-- treasury_refund_all (exposée publique = vol direct).
--
-- Crée les contraintes manquantes : uniq_active_game_per_room,
-- bornes bet_amount, host_username column.
-- ============================================================

-- ============================================================
-- 1. DROP des anciennes fonctions (toutes signatures)
-- ============================================================
drop function if exists public.submit_cora_roll(uuid)                    cascade;
drop function if exists public.submit_cora_roll(uuid, integer, integer)  cascade;
drop function if exists public.create_cora_room(integer, integer, boolean) cascade;
drop function if exists public.create_cora_room(int, int, boolean)         cascade;
drop function if exists public.join_cora_room(text)                        cascade;
drop function if exists public.toggle_cora_ready(uuid, boolean)            cascade;
drop function if exists public.create_cora_game(uuid)                      cascade;
drop function if exists public.start_cora_game(uuid)                       cascade;
drop function if exists public.cora_auto_continue(uuid)                    cascade;
drop function if exists public.cora_dice_cleanup_stale_rooms()             cascade;

-- ============================================================
-- 2. RÉVOQUER treasury_refund_all (vol direct possible)
-- ============================================================
-- Tolérant : si la fonction n'existe pas (ou a une autre signature),
-- on parcourt toutes les surcharges et on révoque chacune.
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
      execute format('revoke execute on function %s%s from public, anon, authenticated', r.fn, r.args);
      raise notice 'Revoked %s%s', r.fn, r.args;
    exception when others then
      raise notice 'Revoke skipped on %s%s: %', r.fn, r.args, sqlerrm;
    end;
  end loop;
end $$;

-- ============================================================
-- 3. Configuration globale
-- ============================================================
create table if not exists public.cora_dice_config (
  id            int primary key default 1 check (id = 1),
  min_bet                       bigint  not null default 100,
  max_bet                       bigint  not null default 1000000,
  max_rooms_per_user            int     not null default 3,
  max_concurrent_games_per_user int     not null default 2,
  turn_timeout_seconds          int     not null default 25,
  max_consecutive_timeouts      int     not null default 3,
  house_cut_pct                 numeric(4,3) not null default 0.10
    check (house_cut_pct between 0 and 0.30),
  game_inactivity_minutes       int     not null default 30,
  room_idle_minutes             int     not null default 60,
  updated_at                    timestamptz not null default now()
);
insert into public.cora_dice_config(id) values (1) on conflict (id) do nothing;

alter table public.cora_dice_config enable row level security;
drop policy if exists "config_read_authenticated" on public.cora_dice_config;
create policy "config_read_authenticated" on public.cora_dice_config
  for select to authenticated using (true);
-- UPDATE via RPC admin uniquement.

-- ============================================================
-- 4. Colonne host_username manquante (si schema legacy)
-- ============================================================
alter table public.cora_rooms add column if not exists host_username text;

-- Backfill si manquante
update cora_rooms r set host_username =
  coalesce((select username from user_profiles where id = r.host_id), 'Joueur')
  where host_username is null;

-- ============================================================
-- 5. Contraintes critiques
-- ============================================================
-- Si des doublons "playing" existent déjà (legacy), on les neutralise
-- avant d'imposer la contrainte exclude.
update cora_games g
   set status = 'cancelled'
 where status = 'playing'
   and exists (
     select 1 from cora_games g2
      where g2.room_id = g.room_id
        and g2.status = 'playing'
        and g2.id <> g.id
        and g2.created_at > g.created_at
   );

-- Une seule game 'playing' par room (idempotence côté création)
do $$ begin
  alter table public.cora_games drop constraint if exists uniq_active_game_per_room;
  alter table public.cora_games add constraint uniq_active_game_per_room
    exclude using btree (room_id with =) where (status = 'playing');
exception
  when duplicate_object then null;
  when duplicate_table  then null;
  when others           then raise notice 'uniq_active_game_per_room skipped: %', sqlerrm;
end $$;

-- bet_amount > 0 — NOT VALID pour ne pas faillir sur les rangs legacy.
-- Les rangées existantes avec bet_amount <= 0 sont tolérées, mais aucun
-- INSERT/UPDATE futur ne pourra créer un bet_amount <= 0.
do $$ begin
  alter table public.cora_rooms drop constraint if exists cora_bet_positive;
  alter table public.cora_rooms
    add constraint cora_bet_positive check (bet_amount > 0) not valid;
exception
  when duplicate_object then null;
  when duplicate_table  then null;
  when others           then raise notice 'cora_bet_positive skipped: %', sqlerrm;
end $$;

-- player_count borné — NOT VALID idem
do $$ begin
  alter table public.cora_rooms drop constraint if exists check_cora_player_count;
  alter table public.cora_rooms
    add constraint check_cora_player_count check (player_count between 2 and 6) not valid;
exception
  when duplicate_object then null;
  when duplicate_table  then null;
  when others           then raise notice 'check_cora_player_count skipped: %', sqlerrm;
end $$;

-- Note : pour valider rétroactivement après cleanup des données legacy :
--   alter table cora_rooms validate constraint cora_bet_positive;
--   alter table cora_rooms validate constraint check_cora_player_count;

-- ============================================================
-- 5b. Migration colonne winner_ids text[] → uuid[]
-- ============================================================
-- Le schéma legacy a winner_ids text[]. Le code V3 utilise uuid[]
-- (cast direct, opérateurs uuid). On migre la colonne pour aligner.
do $$
declare v_type text;
begin
  select udt_name into v_type
    from information_schema.columns
    where table_schema='public' and table_name='cora_games' and column_name='winner_ids';
  if v_type = '_text' then
    -- Cast tolérant : les valeurs invalides deviennent NULL
    alter table public.cora_games
      alter column winner_ids type uuid[]
      using (
        case
          when winner_ids is null then null::uuid[]
          else (
            select array_agg(elem::uuid)
              from unnest(winner_ids) as elem
             where elem ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          )
        end
      );
    raise notice 'cora_games.winner_ids migré text[] → uuid[]';
  end if;
exception when others then
  raise notice 'winner_ids migration skipped: %', sqlerrm;
end $$;

-- ============================================================
-- 6. Champs additionnels game_state (pour V3)
-- ============================================================
-- On utilise déjà la colonne game_state JSONB. On y stockera désormais :
--   - turn_order: text[]
--   - is_cancelled: boolean
--   - cancel_reason: text
--   - players[uid].forfeited: boolean
-- Pas besoin de changer le schéma SQL, ça reste du JSONB.

-- ============================================================
-- 7. Index pour les patterns de query V3
-- ============================================================
create index if not exists idx_cora_games_status_updated
  on cora_games(status, updated_at desc);

create index if not exists idx_cora_rooms_waiting_created
  on cora_rooms(created_at desc) where status = 'waiting';

create index if not exists idx_cora_room_players_user
  on cora_room_players(user_id);
