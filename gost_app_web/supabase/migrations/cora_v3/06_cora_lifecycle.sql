-- ============================================================
-- CORA DICE V3 — Lifecycle (rooms + cleanup)
-- ============================================================
-- Crée :
--   - cora_create_room, cora_join_room, cora_leave_room
--   - cora_toggle_ready
--   - cora_send_message
--   - cleanup crons : stale rooms / stuck games
-- ============================================================

-- Pré-requis : colonnes user_profiles attendues par les RPCs (idempotent).
alter table public.user_profiles add column if not exists is_blocked boolean not null default false;
alter table public.user_profiles add column if not exists username text;

-- ============================================================
-- 1. cora_create_room
-- ============================================================
create or replace function public.cora_create_room(
  p_player_count int default 2,
  p_bet_amount   bigint default 200,
  p_is_private   boolean default false
) returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_room_id uuid;
  v_username text;
  v_cfg cora_dice_config;
  v_active_count int;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED' using errcode = '42501'; end if;

  begin
    perform check_rate_limit('cora_create', v_uid::text, 5, '1 minute');
  exception when undefined_function then null;
  end;

  select * into v_cfg from cora_dice_config where id = 1;

  -- Validation paramètres
  if p_player_count < 2 or p_player_count > 6 then
    raise exception 'INVALID_PLAYER_COUNT' using errcode = '22023';
  end if;
  if p_bet_amount < v_cfg.min_bet or p_bet_amount > v_cfg.max_bet then
    raise exception 'INVALID_BET_RANGE: min=% max=%', v_cfg.min_bet, v_cfg.max_bet
      using errcode = '22023';
  end if;

  -- Limite : nombre max de rooms actives par user
  select count(*) into v_active_count
    from cora_rooms r
    join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
    where r.status in ('waiting', 'playing');
  if v_active_count >= v_cfg.max_concurrent_games_per_user then
    raise exception 'TOO_MANY_ACTIVE_GAMES: max=%', v_cfg.max_concurrent_games_per_user
      using errcode = 'P0006';
  end if;

  -- Vérifier user non-bloqué
  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  -- Vérifier solde suffisant (early check, _ledger_post re-vérifie atomiquement)
  if (select wallet_balance(v_uid)) < p_bet_amount then
    raise exception 'INSUFFICIENT_FUNDS' using errcode = 'P0001';
  end if;

  -- Générer code unique (avec retry)
  for attempt in 1..10 loop
    v_code := upper(substr(md5(gen_random_bytes(8)::text), 1, 6));
    exit when not exists (select 1 from cora_rooms where code = v_code);
    if attempt = 10 then
      raise exception 'CODE_GENERATION_FAILED';
    end if;
  end loop;

  select coalesce(username, 'Joueur') into v_username
    from user_profiles where id = v_uid;

  -- Créer la room
  insert into cora_rooms (code, host_id, player_count, bet_amount, is_private, host_username, status)
    values (v_code, v_uid, p_player_count, p_bet_amount, p_is_private, v_username, 'waiting')
    returning id into v_room_id;

  insert into cora_room_players (room_id, user_id, username, is_ready)
    values (v_room_id, v_uid, v_username, false);

  -- Débit via ledger (idempotent)
  perform cora_place_bet(v_uid, v_room_id::text, p_bet_amount);

  return jsonb_build_object(
    'room_id', v_room_id,
    'code', v_code,
    'bet_amount', p_bet_amount,
    'player_count', p_player_count
  );
end; $$;

revoke all on function public.cora_create_room(int, bigint, boolean) from public, anon;
grant execute on function public.cora_create_room(int, bigint, boolean) to authenticated;

-- ============================================================
-- 2. cora_join_room
-- ============================================================
create or replace function public.cora_join_room(p_code text)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_room cora_rooms;
  v_count int;
  v_username text;
  v_started boolean := false;
  v_game_id uuid;
  v_cfg cora_dice_config;
  v_active_count int;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED' using errcode = '42501'; end if;

  begin
    perform check_rate_limit('cora_join', v_uid::text, 10, '1 minute');
  exception when undefined_function then null;
  end;

  select * into v_cfg from cora_dice_config where id = 1;

  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  -- Lock the room
  select * into v_room from cora_rooms where code = upper(p_code) for update;
  if not found then raise exception 'ROOM_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_room.status != 'waiting' then raise exception 'ROOM_NOT_OPEN' using errcode = 'P0007'; end if;

  perform _cora_lock_room(v_room.id);

  -- Idempotence
  if exists (select 1 from cora_room_players where room_id = v_room.id and user_id = v_uid) then
    return jsonb_build_object('room_id', v_room.id, 'already_joined', true);
  end if;

  -- Capacité
  select count(*) into v_count from cora_room_players where room_id = v_room.id;
  if v_count >= v_room.player_count then
    raise exception 'ROOM_FULL' using errcode = 'P0008';
  end if;

  -- Limite multi-games
  select count(*) into v_active_count
    from cora_rooms r
    join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
    where r.status in ('waiting', 'playing');
  if v_active_count >= v_cfg.max_concurrent_games_per_user then
    raise exception 'TOO_MANY_ACTIVE_GAMES' using errcode = 'P0006';
  end if;

  -- Solde suffisant
  if (select wallet_balance(v_uid)) < v_room.bet_amount then
    raise exception 'INSUFFICIENT_FUNDS' using errcode = 'P0001';
  end if;

  select coalesce(username, 'Joueur') into v_username
    from user_profiles where id = v_uid;

  insert into cora_room_players (room_id, user_id, username, is_ready)
    values (v_room.id, v_uid, v_username, false);

  perform cora_place_bet(v_uid, v_room.id::text, v_room.bet_amount);

  -- Si la room devient pleine, on attend que tous soient ready (cora_toggle_ready déclenchera)
  return jsonb_build_object(
    'room_id', v_room.id,
    'joined', true,
    'started', v_started,
    'game_id', v_game_id,
    'players', v_count + 1,
    'capacity', v_room.player_count
  );
end; $$;

revoke all on function public.cora_join_room(text) from public, anon;
grant execute on function public.cora_join_room(text) to authenticated;

-- ============================================================
-- 3. cora_toggle_ready
-- ============================================================
create or replace function public.cora_toggle_ready(p_room_id uuid, p_ready boolean)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_room cora_rooms;
  v_all_ready boolean;
  v_count int;
  v_game_id uuid;
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

  -- Vérifie que le user est dans la room
  if not exists (select 1 from cora_room_players where room_id = p_room_id and user_id = v_uid) then
    raise exception 'NOT_A_PLAYER' using errcode = '42501';
  end if;

  update cora_room_players set is_ready = p_ready
    where room_id = p_room_id and user_id = v_uid;

  if p_ready then
    select count(*), bool_and(is_ready) into v_count, v_all_ready
      from cora_room_players where room_id = p_room_id;
    if v_count = v_room.player_count and v_all_ready then
      v_game_id := _cora_start_game(p_room_id);
    end if;
  end if;

  return jsonb_build_object(
    'ready', p_ready,
    'started', v_game_id is not null,
    'game_id', v_game_id
  );
end; $$;

revoke all on function public.cora_toggle_ready(uuid, boolean) from public, anon;
grant execute on function public.cora_toggle_ready(uuid, boolean) to authenticated;

-- ============================================================
-- 4. cora_leave_room (avant que la game ne démarre)
-- ============================================================
create or replace function public.cora_leave_room(p_room_id uuid)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_room cora_rooms;
  v_was_host boolean;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;

  perform _cora_lock_room(p_room_id);

  select * into v_room from cora_rooms where id = p_room_id for update;
  if not found then return jsonb_build_object('skipped', true); end if;

  -- En 'playing', il faut faire forfeit, pas leave
  if v_room.status = 'playing' then
    raise exception 'GAME_IN_PROGRESS_USE_FORFEIT' using errcode = 'P0009';
  end if;

  if v_room.status != 'waiting' then return jsonb_build_object('skipped', true); end if;

  v_was_host := (v_room.host_id = v_uid);

  -- Refund de la mise
  if v_room.bet_amount > 0 then
    perform _ledger_post(
      v_uid, v_room.bet_amount, 'refund',
      'cora_leave:' || p_room_id::text || ':' || v_uid::text,
      'cora_dice', p_room_id::text,
      jsonb_build_object('reason', 'voluntary_leave')
    );
    update game_treasury
      set balance = balance - v_room.bet_amount,
          total_paid_out = total_paid_out + v_room.bet_amount,
          updated_at = now()
      where id = 1;
  end if;

  delete from cora_room_players where room_id = p_room_id and user_id = v_uid;

  -- Si plus personne ou si le host quitte → cancel la room
  if v_was_host or not exists (select 1 from cora_room_players where room_id = p_room_id) then
    -- Refund pour les autres joueurs restants
    declare v_uid_other uuid;
    begin
      for v_uid_other in select user_id from cora_room_players where room_id = p_room_id loop
        perform _ledger_post(
          v_uid_other, v_room.bet_amount, 'refund',
          'cora_host_left:' || p_room_id::text || ':' || v_uid_other::text,
          'cora_dice', p_room_id::text,
          jsonb_build_object('reason', 'host_left')
        );
        update game_treasury
          set balance = balance - v_room.bet_amount,
              total_paid_out = total_paid_out + v_room.bet_amount,
              updated_at = now()
          where id = 1;
      end loop;
    end;
    delete from cora_room_players where room_id = p_room_id;
    update cora_rooms set status = 'cancelled' where id = p_room_id;
  end if;

  return jsonb_build_object('left', true, 'cancelled_room', v_was_host);
end; $$;

revoke all on function public.cora_leave_room(uuid) from public, anon;
grant execute on function public.cora_leave_room(uuid) to authenticated;

-- ============================================================
-- 5. cora_send_message (chat)
-- ============================================================
create or replace function public.cora_send_message(p_room_id uuid, p_message text)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_username text;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;

  begin
    perform check_rate_limit('cora_msg', v_uid::text, 30, '1 minute');
  exception when undefined_function then null;
  end;

  if length(p_message) > 500 then
    raise exception 'MESSAGE_TOO_LONG';
  end if;
  if length(trim(p_message)) = 0 then return; end if;

  if not exists (select 1 from cora_room_players where room_id = p_room_id and user_id = v_uid) then
    raise exception 'NOT_A_PLAYER';
  end if;

  select coalesce(username, 'Joueur') into v_username from user_profiles where id = v_uid;

  insert into cora_messages(room_id, user_id, username, message)
    values (p_room_id, v_uid, v_username, p_message);
end; $$;

revoke all on function public.cora_send_message(uuid, text) from public, anon;
grant execute on function public.cora_send_message(uuid, text) to authenticated;

-- ============================================================
-- 6. Cleanup automatique : rooms idle (waiting > N minutes)
-- ============================================================
create or replace function public.cora_cleanup_stale_rooms()
returns int
language plpgsql security definer set search_path=public
as $$
declare
  v_room cora_rooms;
  v_uids uuid[];
  v_count int := 0;
  v_idle_min int;
begin
  select room_idle_minutes into v_idle_min from cora_dice_config where id = 1;

  for v_room in
    select * from cora_rooms
    where status = 'waiting'
      and created_at < now() - (v_idle_min || ' minutes')::interval
    for update skip locked
  loop
    if v_room.bet_amount > 0 then
      select array_agg(user_id) into v_uids
        from cora_room_players where room_id = v_room.id;
      v_uids := coalesce(v_uids, array[]::uuid[]);
      if coalesce(array_length(v_uids, 1), 0) > 0 then
        perform cora_refund_participants(v_room.id::text, v_uids, v_room.bet_amount);
      end if;
    end if;
    delete from cora_room_players where room_id = v_room.id;
    update cora_rooms set status = 'cancelled' where id = v_room.id;
    perform _cora_log_event(coalesce(v_room.game_id, gen_random_uuid()), null, 'auto_cancelled_room',
      jsonb_build_object('room_id', v_room.id, 'reason', 'idle'));
    v_count := v_count + 1;
  end loop;
  return v_count;
end; $$;

revoke all on function public.cora_cleanup_stale_rooms() from public, anon, authenticated;
-- Appelée uniquement par cron (postgres role).

-- ============================================================
-- 7. Cleanup games stuck (playing > N minutes sans update)
-- ============================================================
create or replace function public.cora_cleanup_stuck_games()
returns int
language plpgsql security definer set search_path=public
as $$
declare
  v_game cora_games;
  v_uids uuid[];
  v_count int := 0;
  v_stuck_min int;
begin
  select game_inactivity_minutes into v_stuck_min from cora_dice_config where id = 1;

  for v_game in
    select * from cora_games
    where status = 'playing'
      and updated_at < now() - (v_stuck_min || ' minutes')::interval
    for update skip locked
  loop
    select array_agg((k)::uuid) into v_uids
      from jsonb_object_keys(v_game.game_state -> 'players') as k;
    v_uids := coalesce(v_uids, array[]::uuid[]);

    update cora_games set
      status = 'cancelled',
      game_state = jsonb_set(jsonb_set(game_state, '{is_cancelled}', 'true'),
                              '{cancel_reason}', '"timeout"'),
      updated_at = now()
    where id = v_game.id;
    update cora_rooms set status = 'cancelled' where id = v_game.room_id;

    if coalesce(array_length(v_uids, 1), 0) > 0 then
      perform cora_refund_participants(v_game.id::text, v_uids, v_game.bet_amount);
    end if;
    perform _cora_log_event(v_game.id, null, 'auto_cancelled_game',
      jsonb_build_object('reason', 'inactivity'));
    v_count := v_count + 1;
  end loop;
  return v_count;
end; $$;

revoke all on function public.cora_cleanup_stuck_games() from public, anon, authenticated;

-- ============================================================
-- 8. Schedule via pg_cron
-- ============================================================
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Supprimer les anciens jobs si présents
    perform cron.unschedule(jobid)
      from cron.job where jobname in ('cora-cleanup-rooms', 'cora-cleanup-games');

    perform cron.schedule('cora-cleanup-rooms', '*/5 * * * *',
      $cron$ select public.cora_cleanup_stale_rooms(); $cron$);
    perform cron.schedule('cora-cleanup-games', '*/2 * * * *',
      $cron$ select public.cora_cleanup_stuck_games(); $cron$);
    raise notice 'Crons Cora Dice schedulés (5min/2min).';
  else
    raise notice 'pg_cron non installé : appeler manuellement cora_cleanup_stale_rooms() et cora_cleanup_stuck_games() via app cron externe.';
  end if;
end $$;
