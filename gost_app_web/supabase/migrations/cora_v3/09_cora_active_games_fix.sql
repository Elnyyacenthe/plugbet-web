-- ============================================================
-- CORA DICE V3.1 — Fix TOO_MANY_ACTIVE_GAMES + zombies
-- ============================================================
-- Corrige :
--   - rooms zombies bloquant la limite max_concurrent_games_per_user
--   - cleanup eager au moment du create (anti dépendance pg_cron)
--   - RPC d'abandon explicite côté user (kill switch)
--   - reprise plus claire avec cora_get_active
-- ============================================================

-- ============================================================
-- 1. Seuils plus agressifs
-- ============================================================
update public.cora_dice_config
   set room_idle_minutes       = 15,   -- au lieu de 60
       game_inactivity_minutes = 10,   -- au lieu de 30
       updated_at              = now()
 where id = 1;

-- ============================================================
-- 2. Helper interne : cleanup eager des rooms d'un user
-- ============================================================
-- Appelé AVANT le count d'active_games dans cora_create_room/cora_join_room.
-- N'agit que sur des rows assez vieilles (5 min waiting, 5 min playing sans update).
-- Le but : ne pas casser une partie active légitime, juste nettoyer les zombies.
create or replace function public._cora_cleanup_user_zombies(p_user_id uuid)
returns int
language plpgsql security definer set search_path=public
as $$
declare
  r record;
  v_other uuid;
  v_count int := 0;
begin
  -- Rooms 'waiting' > 5 min sans personne qui ready : on cancel + refund
  for r in
    select rm.id, rm.bet_amount
      from cora_rooms rm
      join cora_room_players p on p.room_id = rm.id and p.user_id = p_user_id
     where rm.status = 'waiting'
       and rm.created_at < now() - interval '5 minutes'
       and not exists (
         select 1 from cora_room_players cp
          where cp.room_id = rm.id and cp.is_ready = true
       )
    for update skip locked
  loop
    for v_other in select user_id from cora_room_players where room_id = r.id loop
      begin
        perform _ledger_post(
          v_other, r.bet_amount, 'refund',
          'cora_zombie_refund:' || r.id::text || ':' || v_other::text,
          'cora_dice', r.id::text,
          jsonb_build_object('reason','zombie_room_cleanup')
        );
      exception when others then null;
      end;
    end loop;
    update game_treasury
       set balance = balance - (r.bet_amount * (select count(*) from cora_room_players where room_id = r.id)),
           total_paid_out = total_paid_out + (r.bet_amount * (select count(*) from cora_room_players where room_id = r.id)),
           updated_at = now()
     where id = 1;
    delete from cora_room_players where room_id = r.id;
    update cora_rooms set status = 'cancelled' where id = r.id;
    v_count := v_count + 1;
  end loop;

  -- Games 'playing' > 5 min sans update : cancel + refund tous les participants
  for r in
    select g.id, g.bet_amount, g.room_id, g.game_state
      from cora_games g
      join cora_room_players p on p.room_id = g.room_id and p.user_id = p_user_id
     where g.status = 'playing'
       and g.updated_at < now() - interval '5 minutes'
    for update skip locked
  loop
    declare v_uids uuid[];
    begin
      select array_agg((k)::uuid) into v_uids
        from jsonb_object_keys(r.game_state -> 'players') as k;
      v_uids := coalesce(v_uids, array[]::uuid[]);
      if coalesce(array_length(v_uids, 1), 0) > 0 then
        perform cora_refund_participants(r.id::text, v_uids, r.bet_amount);
      end if;
    end;
    update cora_games set
      status = 'cancelled',
      game_state = jsonb_set(jsonb_set(game_state, '{is_cancelled}', 'true'),
                              '{cancel_reason}', '"zombie_cleanup"'),
      updated_at = now()
    where id = r.id;
    update cora_rooms set status = 'cancelled' where id = r.room_id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end; $$;

revoke all on function public._cora_cleanup_user_zombies(uuid) from public, anon, authenticated;

-- ============================================================
-- 3. cora_create_room v3.1 : eager cleanup + meilleur message
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
  v_active jsonb;
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

  -- 🔥 EAGER CLEANUP : avant de checker la limite, on retire les zombies du user
  perform _cora_cleanup_user_zombies(v_uid);

  -- Recompte après cleanup
  select count(*) into v_active_count
    from cora_rooms r
    join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
    where r.status in ('waiting', 'playing');

  if v_active_count >= v_cfg.max_concurrent_games_per_user then
    -- Renvoie l'info de la partie active pour que le client propose "Reprendre"
    select jsonb_build_object(
      'type', case when r.status='playing' then 'game' else 'room' end,
      'room_id', r.id,
      'game_id', (select id from cora_games where room_id = r.id and status='playing' limit 1),
      'code', r.code,
      'status', r.status,
      'bet_amount', r.bet_amount,
      'created_at', r.created_at
    ) into v_active
      from cora_rooms r
      join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
     where r.status in ('waiting','playing')
     order by r.created_at desc limit 1;
    raise exception 'TOO_MANY_ACTIVE_GAMES: max=% active=%', v_cfg.max_concurrent_games_per_user, coalesce(v_active::text, 'null')
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

  select coalesce(username, 'Joueur') into v_username
    from user_profiles where id = v_uid;

  insert into cora_rooms (code, host_id, player_count, bet_amount, is_private, host_username, status)
    values (v_code, v_uid, p_player_count, p_bet_amount, p_is_private, v_username, 'waiting')
    returning id into v_room_id;

  insert into cora_room_players (room_id, user_id, username, is_ready)
    values (v_room_id, v_uid, v_username, false);

  perform cora_place_bet(v_uid, v_room_id::text, p_bet_amount);

  return jsonb_build_object(
    'room_id', v_room_id, 'code', v_code,
    'bet_amount', p_bet_amount, 'player_count', p_player_count
  );
end; $$;

revoke all on function public.cora_create_room(int, bigint, boolean) from public, anon;
grant execute on function public.cora_create_room(int, bigint, boolean) to authenticated;

-- ============================================================
-- 4. cora_abandon_my_rooms : kill switch côté user
-- ============================================================
-- Permet à un user d'abandonner TOUTES ses parties actives en 1 appel.
-- Refund automatique des rooms 'waiting'. Forfait pour les games 'playing'.
create or replace function public.cora_abandon_my_rooms()
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  r record;
  v_count_rooms int := 0;
  v_count_games int := 0;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;

  -- Forfait pour chaque game playing du user
  for r in
    select g.id from cora_games g
      join cora_room_players p on p.room_id = g.room_id and p.user_id = v_uid
     where g.status = 'playing'
  loop
    begin
      perform cora_forfeit(r.id);
      v_count_games := v_count_games + 1;
    exception when others then null;
    end;
  end loop;

  -- Leave + refund pour chaque room waiting du user
  for r in
    select r.id from cora_rooms r
      join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
     where r.status = 'waiting'
  loop
    begin
      perform cora_leave_room(r.id);
      v_count_rooms := v_count_rooms + 1;
    exception when others then null;
    end;
  end loop;

  return jsonb_build_object(
    'rooms_left', v_count_rooms,
    'games_forfeited', v_count_games
  );
end; $$;

revoke all on function public.cora_abandon_my_rooms() from public, anon;
grant execute on function public.cora_abandon_my_rooms() to authenticated;

-- ============================================================
-- 5. Fallback cron : si pg_cron absent, l'app peut appeler directement
-- ============================================================
-- Expose un wrapper public (auth) qui combine les 2 cleanups,
-- callable depuis l'app périodiquement (ou Edge Function) si pg_cron KO.
create or replace function public.cora_run_cleanup()
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare v_rooms int; v_games int;
begin
  v_rooms := cora_cleanup_stale_rooms();
  v_games := cora_cleanup_stuck_games();
  return jsonb_build_object('cleaned_rooms', v_rooms, 'cleaned_games', v_games);
end; $$;

revoke all on function public.cora_run_cleanup() from public, anon, authenticated;
-- Volontairement pas grant à authenticated : seul service_role peut l'appeler
-- (depuis Edge Function ou cron externe). Empêche le DoS.

-- ============================================================
-- 6. Recheck pg_cron
-- ============================================================
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron OK : crons cora-cleanup-rooms / cora-cleanup-games actifs.';
  else
    raise notice 'pg_cron ABSENT : active-le via Supabase Dashboard > Database > Extensions > pg_cron, ou appelle cora_run_cleanup() depuis une Edge Function périodique.';
  end if;
end $$;
