-- ============================================================
-- CORA DICE V3 — Resume Session + Events Audit + Replay
-- ============================================================
-- Crée :
--   - cora_game_events (audit log immutable)
--   - cora_get_active (reprise de session)
--   - cora_replay_game (audit, lecture)
-- ============================================================

-- Pré-requis : winner_ids doit être uuid[] (le code V3 l'exige).
-- Si 03 a sauté la migration silencieusement, on la refait ici en strict.
-- Note : Postgres interdit les subqueries dans ALTER TABLE ... USING (),
-- on passe donc par une fonction helper temporaire.
create or replace function public._cora_text_to_uuid_array(p text[])
returns uuid[] immutable language plpgsql as $$
declare
  r uuid[] := array[]::uuid[];
  e text;
begin
  if p is null then return null; end if;
  foreach e in array p loop
    if e ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      r := array_append(r, e::uuid);
    end if;
  end loop;
  return r;
end $$;

do $$
declare v_type text;
begin
  select udt_name into v_type
    from information_schema.columns
    where table_schema='public' and table_name='cora_games' and column_name='winner_ids';
  if v_type = '_text' then
    -- Drop le DEFAULT text[] avant le cast (non-castable auto en uuid[])
    alter table public.cora_games alter column winner_ids drop default;
    alter table public.cora_games
      alter column winner_ids type uuid[]
      using public._cora_text_to_uuid_array(winner_ids);
    -- Restaure le DEFAULT en uuid[]
    alter table public.cora_games alter column winner_ids set default array[]::uuid[];
    raise notice 'cora_games.winner_ids migré text[] → uuid[]';
  end if;
end $$;

drop function if exists public._cora_text_to_uuid_array(text[]);

-- ============================================================
-- 1. Table cora_game_events (immutable, append-only)
-- ============================================================
create table if not exists public.cora_game_events (
  id          bigserial primary key,
  game_id     uuid not null,
  user_id     uuid,
  event_type  text not null,
  payload     jsonb default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists idx_cora_events_game on cora_game_events(game_id, id);
create index if not exists idx_cora_events_user on cora_game_events(user_id, created_at desc) where user_id is not null;
create index if not exists idx_cora_events_type on cora_game_events(event_type, created_at desc);

alter table public.cora_game_events enable row level security;

drop policy if exists "events_select_participants" on public.cora_game_events;
create policy "events_select_participants" on public.cora_game_events for select using (
  exists (
    select 1 from cora_games g
    join cora_room_players p on p.room_id = g.room_id and p.user_id = auth.uid()
    where g.id = cora_game_events.game_id
  )
  or
  exists (
    select 1 from user_profiles where id = auth.uid()
      and role in ('admin', 'super_admin')
  )
);

-- AUCUNE policy INSERT/UPDATE/DELETE → exclusivement via _cora_log_event
-- (qui est SECURITY DEFINER et bypass RLS)

-- ============================================================
-- 2. cora_get_active : reprise de session
-- ============================================================
create or replace function public.cora_get_active()
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then return null; end if;

  -- 1. Game en cours ?
  select jsonb_build_object(
    'type', 'game',
    'game_id', g.id,
    'room_id', g.room_id,
    'status', g.status,
    'current_turn', g.game_state ->> 'current_turn',
    'is_my_turn', (g.game_state ->> 'current_turn') = v_uid::text,
    'has_rolled', (g.game_state -> 'players' -> v_uid::text -> 'roll') is not null
                  and jsonb_typeof(g.game_state -> 'players' -> v_uid::text -> 'roll') != 'null',
    'is_forfeited', coalesce((g.game_state -> 'players' -> v_uid::text -> 'forfeited')::boolean, false),
    'bet_amount', g.bet_amount,
    'player_count', g.player_count
  ) into v_result
  from cora_games g
  join cora_room_players p on p.room_id = g.room_id and p.user_id = v_uid
  where g.status = 'playing'
  order by g.created_at desc limit 1;

  if v_result is not null then return v_result; end if;

  -- 2. Room en attente ?
  select jsonb_build_object(
    'type', 'room',
    'room_id', r.id,
    'code', r.code,
    'status', r.status,
    'is_ready', p.is_ready,
    'is_host', r.host_id = v_uid,
    'bet_amount', r.bet_amount,
    'player_count', r.player_count,
    'players_count', (select count(*) from cora_room_players where room_id = r.id)
  ) into v_result
  from cora_rooms r
  join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
  where r.status = 'waiting'
  order by r.created_at desc limit 1;

  return v_result;
end; $$;

revoke all on function public.cora_get_active() from public, anon;
grant execute on function public.cora_get_active() to authenticated;

-- ============================================================
-- 3. cora_replay_game : audit/replay
-- ============================================================
create or replace function public.cora_replay_game(p_game_id uuid)
returns table (
  event_id   bigint,
  event_type text,
  user_id    uuid,
  payload    jsonb,
  created_at timestamptz
)
language sql stable security definer set search_path=public
as $$
  select id, event_type, user_id, payload, created_at
  from cora_game_events
  where game_id = p_game_id
  order by id;
$$;

revoke all on function public.cora_replay_game(uuid) from public, anon;
grant execute on function public.cora_replay_game(uuid) to authenticated;

-- ============================================================
-- 4. cora_my_history : historique de mes parties (lecture seule)
-- ============================================================
create or replace function public.cora_my_history(
  p_limit int default 20,
  p_offset int default 0
)
returns table (
  game_id      uuid,
  room_id      uuid,
  status       text,
  bet_amount   bigint,
  player_count int,
  is_winner    boolean,
  is_cancelled boolean,
  payout       bigint,
  finished_at  timestamptz
)
language sql stable security definer set search_path=public
as $$
  select
    g.id as game_id,
    g.room_id,
    g.status,
    g.bet_amount,
    g.player_count,
    -- Cast double pour tolérer winner_ids text[] (legacy) ou uuid[] (V3) :
    -- on compare en text[] pour rester agnostique du type de la colonne.
    (auth.uid()::text = any(g.winner_ids::text[])) as is_winner,
    coalesce((g.game_state ->> 'is_cancelled')::boolean, g.status = 'cancelled') as is_cancelled,
    coalesce((
      select sum(amount) from wallet_ledger
      where user_id = auth.uid()
        and game_id = g.id::text
        and type in ('payout','refund')
    ), 0)::bigint as payout,
    g.updated_at as finished_at
  from cora_games g
  join cora_room_players p on p.room_id = g.room_id and p.user_id = auth.uid()
  where g.status in ('finished','cancelled')
  order by g.updated_at desc
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset);
$$;

revoke all on function public.cora_my_history(int, int) from public, anon;
grant execute on function public.cora_my_history(int, int) to authenticated;
