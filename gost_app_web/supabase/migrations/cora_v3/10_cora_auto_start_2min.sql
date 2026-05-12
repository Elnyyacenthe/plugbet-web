-- ============================================================
-- CORA DICE V3.2 — Auto-start 2 minutes
-- ============================================================
-- Logique :
--   - À la création, chaque room a un deadline = created_at + 2 min
--   - Si tous les joueurs prévus cliquent PRÊT avant deadline → start instant
--   - À deadline :
--       * si ≥ 2 joueurs ready → refund les non-ready + start avec les ready
--       * sinon → cancel + refund tout le monde (room détruite)
--   - Cron tourne chaque minute pour gérer les deadlines
--   - Les rooms restent toujours visibles jusqu'au deadline
-- ============================================================

-- ============================================================
-- 1. Ajout de la colonne start_deadline
-- ============================================================
alter table public.cora_rooms
  add column if not exists start_deadline timestamptz;

-- Backfill : les rooms waiting existantes ont maintenant 30s pour être ready
-- (sinon elles vont être cancelled par le cron au prochain run).
update public.cora_rooms
   set start_deadline = now() + interval '30 seconds'
 where status = 'waiting' and start_deadline is null;

create index if not exists idx_cora_rooms_deadline
  on public.cora_rooms(start_deadline)
  where status = 'waiting';

-- ============================================================
-- 2. cora_create_room v3.2 : ajoute start_deadline
-- ============================================================
create or replace function public.cora_create_room(
  p_player_count int default 2,
  p_bet_amount   bigint default 200,
  p_is_private   boolean default false
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_room_id uuid;
  v_username text;
  v_cfg cora_dice_config;
  v_active_count int;
  v_active jsonb;
  v_deadline timestamptz;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED' using errcode = '42501'; end if;

  begin
    perform check_rate_limit('cora_create', v_uid::text, 5, '1 minute');
  exception when undefined_function then null;
  end;

  select * into v_cfg from cora_dice_config where id = 1;

  if p_player_count < 2 or p_player_count > 6 then
    raise exception 'INVALID_PLAYER_COUNT' using errcode = '22023';
  end if;
  if p_bet_amount < v_cfg.min_bet or p_bet_amount > v_cfg.max_bet then
    raise exception 'INVALID_BET_RANGE: min=% max=%', v_cfg.min_bet, v_cfg.max_bet
      using errcode = '22023';
  end if;

  perform _cora_cleanup_user_zombies(v_uid);

  select count(*) into v_active_count
    from cora_rooms r
    join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
    where r.status in ('waiting', 'playing');

  if v_active_count >= v_cfg.max_concurrent_games_per_user then
    select jsonb_build_object(
      'type', case when r.status='playing' then 'game' else 'room' end,
      'room_id', r.id,
      'game_id', (select id from cora_games where room_id = r.id and status='playing' limit 1),
      'code', r.code, 'status', r.status, 'bet_amount', r.bet_amount,
      'created_at', r.created_at
    ) into v_active
      from cora_rooms r
      join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
     where r.status in ('waiting','playing')
     order by r.created_at desc limit 1;
    raise exception 'TOO_MANY_ACTIVE_GAMES: max=% active=%',
      v_cfg.max_concurrent_games_per_user, coalesce(v_active::text, 'null')
      using errcode = 'P0006', detail = coalesce(v_active::text, '');
  end if;

  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  if (select wallet_balance(v_uid)) < p_bet_amount then
    raise exception 'INSUFFICIENT_FUNDS' using errcode = 'P0001';
  end if;

  for attempt in 1..10 loop
    v_code := upper(substr(md5(gen_random_bytes(8)::text), 1, 6));
    exit when not exists (select 1 from cora_rooms where code = v_code);
    if attempt = 10 then raise exception 'CODE_GENERATION_FAILED'; end if;
  end loop;

  select coalesce(username, 'Joueur') into v_username from user_profiles where id = v_uid;

  v_deadline := now() + interval '2 minutes';

  insert into cora_rooms (code, host_id, player_count, bet_amount, is_private,
                          host_username, status, start_deadline)
    values (v_code, v_uid, p_player_count, p_bet_amount, p_is_private,
            v_username, 'waiting', v_deadline)
    returning id into v_room_id;

  insert into cora_room_players (room_id, user_id, username, is_ready)
    values (v_room_id, v_uid, v_username, false);

  perform cora_place_bet(v_uid, v_room_id::text, p_bet_amount);

  return jsonb_build_object(
    'room_id', v_room_id, 'code', v_code,
    'bet_amount', p_bet_amount, 'player_count', p_player_count,
    'start_deadline', v_deadline
  );
end; $$;
revoke all on function public.cora_create_room(int, bigint, boolean) from public, anon;
grant execute on function public.cora_create_room(int, bigint, boolean) to authenticated;

-- ============================================================
-- 3. cora_auto_start_pending : cron qui gère les deadlines
-- ============================================================
create or replace function public.cora_auto_start_pending()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare
  r record;
  v_ready_count int;
  v_total int;
  v_count int := 0;
  v_refund record;
  v_game_id uuid;
begin
  for r in
    select * from cora_rooms
     where status = 'waiting'
       and start_deadline is not null
       and start_deadline <= now()
    for update skip locked
  loop
    -- Lock advisory pour ne pas concurrencer un toggle_ready en cours
    perform _cora_lock_room(r.id);

    -- Recheck après lock (un toggle_ready a pu tout changer entre temps)
    if not exists (select 1 from cora_rooms where id = r.id and status = 'waiting') then
      continue;
    end if;

    select
      count(*) filter (where is_ready = true),
      count(*)
      into v_ready_count, v_total
      from cora_room_players where room_id = r.id;

    if v_ready_count >= 2 then
      -- ≥ 2 ready → refund non-ready + démarre avec les ready
      for v_refund in
        select user_id from cora_room_players
         where room_id = r.id and is_ready = false
      loop
        begin
          perform _ledger_post(
            v_refund.user_id, r.bet_amount, 'refund',
            'cora_not_ready_refund:' || r.id::text || ':' || v_refund.user_id::text,
            'cora_dice', r.id::text,
            jsonb_build_object('reason', 'not_ready_at_deadline'));
        exception when others then null;
        end;
      end loop;

      if v_total > v_ready_count then
        update game_treasury
           set balance = greatest(0, balance - r.bet_amount * (v_total - v_ready_count)),
               total_paid_out = total_paid_out + r.bet_amount * (v_total - v_ready_count),
               updated_at = now()
         where id = 1;
      end if;

      delete from cora_room_players where room_id = r.id and is_ready = false;

      -- Aligne player_count sur le nombre réel de joueurs qui démarrent
      update cora_rooms set player_count = v_ready_count where id = r.id;

      perform _cora_log_event(gen_random_uuid(), null, 'auto_start_deadline',
        jsonb_build_object('room_id', r.id, 'ready_players', v_ready_count, 'kicked', v_total - v_ready_count));

      v_game_id := _cora_start_game(r.id);
      v_count := v_count + 1;

    else
      -- < 2 ready → cancel + refund tous + supprime room
      for v_refund in
        select user_id from cora_room_players where room_id = r.id
      loop
        begin
          perform _ledger_post(
            v_refund.user_id, r.bet_amount, 'refund',
            'cora_timeout_refund:' || r.id::text || ':' || v_refund.user_id::text,
            'cora_dice', r.id::text,
            jsonb_build_object('reason', 'deadline_insufficient_ready', 'ready_count', v_ready_count));
        exception when others then null;
        end;
      end loop;

      if v_total > 0 then
        update game_treasury
           set balance = greatest(0, balance - r.bet_amount * v_total),
               total_paid_out = total_paid_out + r.bet_amount * v_total,
               updated_at = now()
         where id = 1;
      end if;

      delete from cora_room_players where room_id = r.id;
      update cora_rooms set status = 'cancelled', updated_at = now() where id = r.id;

      perform _cora_log_event(gen_random_uuid(), null, 'auto_cancel_deadline',
        jsonb_build_object('room_id', r.id, 'ready_count', v_ready_count, 'total', v_total));
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end $$;

revoke all on function public.cora_auto_start_pending() from public, anon, authenticated;

-- ============================================================
-- 4. Cron : tourne chaque minute (granularité minimale pg_cron)
-- ============================================================
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'cora-auto-start';
    perform cron.schedule('cora-auto-start', '* * * * *',
      $cron$ select public.cora_auto_start_pending(); $cron$);
    raise notice 'Cron cora-auto-start schedulé (chaque minute)';
  end if;
end $$;

-- ============================================================
-- 5. cora_toggle_ready : ajoute le résultat de auto-start si déclenché
-- ============================================================
-- (Pas de changement majeur - garde l'instant-start si tous ready)
-- Mais ajoute un fallback : si deadline passé ET >= 2 ready → start instant
create or replace function public.cora_toggle_ready(p_room_id uuid, p_ready boolean)
returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_room cora_rooms;
  v_all_ready boolean;
  v_count int;
  v_ready_count int;
  v_game_id uuid;
  v_refund record;
  v_total int;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;

  begin
    perform check_rate_limit('cora_ready', v_uid::text, 30, '1 minute');
  exception when undefined_function then null;
  end;

  perform _cora_lock_room(p_room_id);

  select * into v_room from cora_rooms where id = p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.status != 'waiting' then raise exception 'ROOM_NOT_OPEN'; end if;

  if not exists (select 1 from cora_room_players where room_id = p_room_id and user_id = v_uid) then
    raise exception 'NOT_A_PLAYER' using errcode = '42501';
  end if;

  update cora_room_players set is_ready = p_ready
    where room_id = p_room_id and user_id = v_uid;

  if p_ready then
    select count(*), count(*) filter (where is_ready), bool_and(is_ready)
      into v_total, v_ready_count, v_all_ready
      from cora_room_players where room_id = p_room_id;

    -- Cas 1 : tous les slots remplis ET tous ready → start instant
    if v_total = v_room.player_count and v_all_ready then
      v_game_id := _cora_start_game(p_room_id);
    -- Cas 2 : deadline déjà dépassé ET ≥ 2 ready → start instant avec refund non-ready
    elsif v_room.start_deadline is not null
          and v_room.start_deadline <= now()
          and v_ready_count >= 2 then
      for v_refund in
        select user_id from cora_room_players
         where room_id = p_room_id and is_ready = false
      loop
        begin
          perform _ledger_post(
            v_refund.user_id, v_room.bet_amount, 'refund',
            'cora_not_ready_refund:' || p_room_id::text || ':' || v_refund.user_id::text,
            'cora_dice', p_room_id::text,
            jsonb_build_object('reason','not_ready_late_join'));
        exception when others then null;
        end;
      end loop;
      if v_total > v_ready_count then
        update game_treasury
           set balance = greatest(0, balance - v_room.bet_amount * (v_total - v_ready_count)),
               total_paid_out = total_paid_out + v_room.bet_amount * (v_total - v_ready_count),
               updated_at = now()
         where id = 1;
      end if;
      delete from cora_room_players where room_id = p_room_id and is_ready = false;
      update cora_rooms set player_count = v_ready_count where id = p_room_id;
      v_game_id := _cora_start_game(p_room_id);
    end if;
  end if;

  return jsonb_build_object(
    'ready', p_ready,
    'started', v_game_id is not null,
    'game_id', v_game_id,
    'deadline', v_room.start_deadline
  );
end; $$;
revoke all on function public.cora_toggle_ready(uuid, boolean) from public, anon;
grant execute on function public.cora_toggle_ready(uuid, boolean) to authenticated;

-- ============================================================
-- 6. cora_get_active : ajoute le deadline pour le client
-- ============================================================
create or replace function public.cora_get_active()
returns jsonb
language plpgsql stable security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then return null; end if;

  select jsonb_build_object(
    'type', 'game',
    'game_id', g.id, 'room_id', g.room_id, 'status', g.status,
    'current_turn', g.game_state ->> 'current_turn',
    'is_my_turn', (g.game_state ->> 'current_turn') = v_uid::text,
    'has_rolled', (g.game_state -> 'players' -> v_uid::text -> 'roll') is not null
                  and jsonb_typeof(g.game_state -> 'players' -> v_uid::text -> 'roll') != 'null',
    'is_forfeited', coalesce((g.game_state -> 'players' -> v_uid::text -> 'forfeited')::boolean, false),
    'bet_amount', g.bet_amount, 'player_count', g.player_count
  ) into v_result
  from cora_games g
  join cora_room_players p on p.room_id = g.room_id and p.user_id = v_uid
  where g.status = 'playing'
  order by g.created_at desc limit 1;

  if v_result is not null then return v_result; end if;

  select jsonb_build_object(
    'type', 'room',
    'room_id', r.id, 'code', r.code, 'status', r.status,
    'is_ready', p.is_ready, 'is_host', r.host_id = v_uid,
    'bet_amount', r.bet_amount, 'player_count', r.player_count,
    'start_deadline', r.start_deadline,
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
-- Trigger immédiat pour les rooms existantes (>2 ready déjà)
-- ============================================================
select public.cora_auto_start_pending() as processed_at_migration;
