-- ============================================================
-- CORA DICE V3.3 — Suppression du système PRÊT
-- ============================================================
-- Nouvelle logique :
--   - Création : countdown 2 min
--   - Quand quelqu'un join : si la room devient FULL → game démarre instant
--   - À deadline : si pas full → cancel + refund
--   - cora_toggle_ready devient un no-op (kept pour compat ancien client)
-- ============================================================

-- ============================================================
-- 1. cora_create_room : host auto-ready au create
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

  -- V3.3 : host auto-ready
  insert into cora_room_players (room_id, user_id, username, is_ready)
    values (v_room_id, v_uid, v_username, true);

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
-- 2. cora_join_room : auto-ready + démarre si room devient full
-- ============================================================
create or replace function public.cora_join_room(p_code text)
returns jsonb
language plpgsql security definer set search_path=public, extensions
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
  v_new_deadline timestamptz;
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

  select * into v_room from cora_rooms where code = upper(p_code) for update;
  if not found then raise exception 'ROOM_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_room.status != 'waiting' then raise exception 'ROOM_NOT_OPEN' using errcode = 'P0007'; end if;

  perform _cora_lock_room(v_room.id);

  if exists (select 1 from cora_room_players where room_id = v_room.id and user_id = v_uid) then
    return jsonb_build_object('room_id', v_room.id, 'already_joined', true,
                              'start_deadline', v_room.start_deadline);
  end if;

  select count(*) into v_count from cora_room_players where room_id = v_room.id;
  if v_count >= v_room.player_count then
    raise exception 'ROOM_FULL' using errcode = 'P0008';
  end if;

  select count(*) into v_active_count
    from cora_rooms r
    join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
    where r.status in ('waiting', 'playing');
  if v_active_count >= v_cfg.max_concurrent_games_per_user then
    raise exception 'TOO_MANY_ACTIVE_GAMES' using errcode = 'P0006';
  end if;

  if (select wallet_balance(v_uid)) < v_room.bet_amount then
    raise exception 'INSUFFICIENT_FUNDS' using errcode = 'P0001';
  end if;

  select coalesce(username, 'Joueur') into v_username from user_profiles where id = v_uid;

  -- V3.3 : auto-ready au join (pas de bouton Prêt côté client)
  insert into cora_room_players (room_id, user_id, username, is_ready)
    values (v_room.id, v_uid, v_username, true);

  perform cora_place_bet(v_uid, v_room.id::text, v_room.bet_amount);

  -- Si la room devient FULL avec ce join → game démarre instant
  if (v_count + 1) >= v_room.player_count then
    v_game_id := _cora_start_game(v_room.id);
    v_started := v_game_id is not null;
  else
    -- Pas full → étend deadline pour donner du temps aux suivants
    v_new_deadline := greatest(coalesce(v_room.start_deadline, now() + interval '60 seconds'),
                               now() + interval '60 seconds');
    update cora_rooms set start_deadline = v_new_deadline where id = v_room.id;
  end if;

  return jsonb_build_object(
    'room_id', v_room.id, 'joined', true,
    'started', v_started, 'game_id', v_game_id,
    'players', v_count + 1, 'capacity', v_room.player_count,
    'start_deadline', coalesce(v_new_deadline, v_room.start_deadline)
  );
end; $$;
revoke all on function public.cora_join_room(text) from public, anon;
grant execute on function public.cora_join_room(text) to authenticated;

-- ============================================================
-- 3. cora_toggle_ready : no-op (kept pour compat, mais inutile)
-- ============================================================
create or replace function public.cora_toggle_ready(p_room_id uuid, p_ready boolean)
returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
begin
  -- V3.3 : système Ready supprimé. Tous les joueurs sont ready par défaut au join.
  return jsonb_build_object('ready', true, 'started', false, 'noop_v33', true);
end; $$;
grant execute on function public.cora_toggle_ready(uuid, boolean) to authenticated;

-- ============================================================
-- 4. cora_auto_start_pending : simplifié — cancel si pas full à deadline
-- ============================================================
create or replace function public.cora_auto_start_pending()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare
  r record;
  v_total int;
  v_count int := 0;
  v_refund record;
begin
  for r in
    select * from cora_rooms
     where status = 'waiting'
       and start_deadline is not null
       and start_deadline <= now()
    for update skip locked
  loop
    perform _cora_lock_room(r.id);

    if not exists (select 1 from cora_rooms where id = r.id and status = 'waiting') then
      continue;
    end if;

    select count(*) into v_total from cora_room_players where room_id = r.id;

    if v_total < r.player_count then
      -- Pas full à deadline → cancel + refund tous
      for v_refund in
        select user_id from cora_room_players where room_id = r.id
      loop
        begin
          perform _ledger_post(
            v_refund.user_id, r.bet_amount, 'refund',
            'cora_timeout_refund:' || r.id::text || ':' || v_refund.user_id::text,
            'cora_dice', r.id::text,
            jsonb_build_object('reason', 'deadline_room_not_full',
                               'players', v_total, 'needed', r.player_count));
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
      perform _cora_log_event(gen_random_uuid(), null, 'auto_cancel_not_full',
        jsonb_build_object('room_id', r.id, 'players', v_total, 'capacity', r.player_count));
      v_count := v_count + 1;
    else
      -- Edge case : la room est full mais le start n'a pas été déclenché → start now
      perform _cora_start_game(r.id);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end $$;
revoke all on function public.cora_auto_start_pending() from public, anon, authenticated;

-- Trigger immédiat
select public.cora_auto_start_pending() as processed_at_migration;
