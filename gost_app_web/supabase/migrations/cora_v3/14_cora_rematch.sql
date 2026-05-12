-- ============================================================
-- CORA V3.6 — Système de revanche (rematch)
-- ============================================================
-- Logique :
--   - À la fin d'une game, chaque joueur peut cliquer "Rejouer"
--   - Le 1er clic initialise un vote (status=pending, 30s timeout)
--   - Les autres voient "Joueur X propose revanche → Accepter/Refuser"
--   - Quand TOUS acceptent → création atomique d'une nouvelle room
--     avec les mêmes paramètres, tous auto-joints, game démarre instant
--   - Si un refuse → rematch cancelled
--   - Si timeout 30s → expired
-- ============================================================

create or replace function public.cora_request_rematch(
  p_game_id uuid,
  p_accept  boolean default true
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_game cora_games;
  v_room cora_rooms;
  v_rematch jsonb;
  v_accepted text[];
  v_refused text[];
  v_required_uids text[];
  v_all_accepted boolean;
  v_any_refused boolean;
  v_new_room_id uuid;
  v_new_game_id uuid;
  v_code text;
  v_host_username text;
  v_uid_iter text;
  v_player_username text;
  v_required_balance bigint;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED' using errcode = '42501'; end if;

  -- Lock le row de la game originale
  select * into v_game from cora_games where id = p_game_id for update;
  if not found then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_game.status != 'finished' then
    raise exception 'REMATCH_ONLY_AFTER_FINISH' using errcode = 'P0010';
  end if;

  -- Check participation
  if v_game.game_state -> 'players' -> v_uid::text is null then
    raise exception 'NOT_A_PARTICIPANT' using errcode = '42501';
  end if;

  -- Charge la room originale (pour récupérer bet_amount, is_private)
  select * into v_room from cora_rooms where id = v_game.room_id;
  if not found then raise exception 'ROOM_NOT_FOUND' using errcode = 'P0002'; end if;

  -- Liste des participants non-forfeited (= ceux qui doivent voter)
  select array_agg(k) into v_required_uids
    from jsonb_object_keys(v_game.game_state -> 'players') as k
    where not coalesce((v_game.game_state -> 'players' -> k -> 'forfeited')::boolean, false);

  if coalesce(array_length(v_required_uids, 1), 0) < 2 then
    raise exception 'NOT_ENOUGH_PARTICIPANTS' using errcode = 'P0011';
  end if;

  -- État rematch actuel ou init
  v_rematch := v_game.game_state -> 'rematch';
  if v_rematch is null or jsonb_typeof(v_rematch) = 'null' then
    v_rematch := jsonb_build_object(
      'status', 'pending',
      'accepted_ids', '[]'::jsonb,
      'refused_ids', '[]'::jsonb,
      'expires_at', to_jsonb((now() + interval '30 seconds')::text),
      'new_room_id', null,
      'new_game_id', null,
      'proposer_id', v_uid::text
    );
  end if;

  -- Check expiration
  if (v_rematch ->> 'expires_at')::timestamptz < now()
     and v_rematch ->> 'status' = 'pending' then
    v_rematch := jsonb_set(v_rematch, '{status}', '"expired"');
  end if;

  -- Si déjà finalisé : retourne l'état (idempotent)
  if v_rematch ->> 'status' in ('accepted', 'refused', 'expired') then
    update cora_games set game_state = jsonb_set(game_state, '{rematch}', v_rematch),
                          updated_at = now()
      where id = p_game_id;
    return jsonb_build_object(
      'status', v_rematch ->> 'status',
      'new_room_id', v_rematch -> 'new_room_id',
      'new_game_id', v_rematch -> 'new_game_id',
      'accepted_count', jsonb_array_length(v_rematch -> 'accepted_ids'),
      'total_needed', array_length(v_required_uids, 1),
      'proposer_id', v_rematch -> 'proposer_id'
    );
  end if;

  -- Update accepted/refused
  v_accepted := array(select jsonb_array_elements_text(v_rematch -> 'accepted_ids'));
  v_refused  := array(select jsonb_array_elements_text(v_rematch -> 'refused_ids'));

  if p_accept then
    if not (v_uid::text = any(v_accepted)) then
      v_accepted := array_append(v_accepted, v_uid::text);
    end if;
    -- Si l'user était dans refused (changement d'avis), on retire
    v_refused := array_remove(v_refused, v_uid::text);
  else
    if not (v_uid::text = any(v_refused)) then
      v_refused := array_append(v_refused, v_uid::text);
    end if;
    v_accepted := array_remove(v_accepted, v_uid::text);
  end if;

  v_rematch := jsonb_set(v_rematch, '{accepted_ids}', to_jsonb(v_accepted));
  v_rematch := jsonb_set(v_rematch, '{refused_ids}',  to_jsonb(v_refused));

  v_any_refused := coalesce(array_length(v_refused, 1), 0) > 0;
  v_all_accepted := coalesce(array_length(v_accepted, 1), 0) = array_length(v_required_uids, 1)
                    and v_required_uids <@ v_accepted
                    and v_accepted <@ v_required_uids;

  if v_any_refused then
    v_rematch := jsonb_set(v_rematch, '{status}', '"refused"');
  elsif v_all_accepted then
    -- =====================================================
    -- TOUS ONT ACCEPTÉ : créer la nouvelle room atomiquement
    -- =====================================================

    -- Pré-check : tous les participants ont >= 2× bet ?
    v_required_balance := v_room.bet_amount * 2;
    foreach v_uid_iter in array v_required_uids loop
      if (select wallet_balance(v_uid_iter::uuid)) < v_required_balance then
        v_rematch := jsonb_set(v_rematch, '{status}', '"refused"');
        v_rematch := jsonb_set(v_rematch, '{insufficient_funds_user}',
                                to_jsonb(v_uid_iter));
        update cora_games set game_state = jsonb_set(game_state, '{rematch}', v_rematch),
                              updated_at = now() where id = p_game_id;
        return jsonb_build_object(
          'status', 'refused',
          'reason', 'insufficient_funds',
          'user_id', v_uid_iter
        );
      end if;
    end loop;

    -- 1. Génère un code unique
    for attempt in 1..10 loop
      v_code := upper(substr(md5(gen_random_bytes(8)::text), 1, 6));
      exit when not exists (select 1 from cora_rooms where code = v_code);
    end loop;

    -- 2. Username de l'host original
    select coalesce(username, 'Joueur') into v_host_username
      from user_profiles where id = v_room.host_id;

    -- 3. Crée la nouvelle room (waiting → sera FULL juste après les inserts)
    insert into cora_rooms (code, host_id, player_count, bet_amount, is_private,
                            host_username, status, start_deadline)
      values (v_code, v_room.host_id, array_length(v_required_uids, 1),
              v_room.bet_amount, v_room.is_private, v_host_username, 'waiting',
              now() + interval '30 seconds')
      returning id into v_new_room_id;

    -- 4. Insert tous les participants comme ready + débit bet
    foreach v_uid_iter in array v_required_uids loop
      select coalesce(username, 'Joueur') into v_player_username
        from user_profiles where id = v_uid_iter::uuid;
      insert into cora_room_players (room_id, user_id, username, is_ready)
        values (v_new_room_id, v_uid_iter::uuid, v_player_username, true);
      perform cora_place_bet(v_uid_iter::uuid, v_new_room_id::text, v_room.bet_amount);
    end loop;

    -- 5. Démarre la game tout de suite (room full)
    v_new_game_id := _cora_start_game(v_new_room_id);

    if v_new_game_id is null then
      raise exception 'REMATCH_START_FAILED';
    end if;

    v_rematch := jsonb_set(v_rematch, '{status}', '"accepted"');
    v_rematch := jsonb_set(v_rematch, '{new_room_id}', to_jsonb(v_new_room_id::text));
    v_rematch := jsonb_set(v_rematch, '{new_game_id}', to_jsonb(v_new_game_id::text));

    perform _cora_log_event(v_new_game_id, null, 'rematch_started',
      jsonb_build_object('original_game_id', p_game_id::text,
                         'players', to_jsonb(v_required_uids)));
  end if;

  -- Persiste l'état rematch dans la game originale
  update cora_games set game_state = jsonb_set(game_state, '{rematch}', v_rematch),
                        updated_at = now()
    where id = p_game_id;

  return jsonb_build_object(
    'status', v_rematch ->> 'status',
    'new_room_id', v_rematch -> 'new_room_id',
    'new_game_id', v_rematch -> 'new_game_id',
    'accepted_count', jsonb_array_length(v_rematch -> 'accepted_ids'),
    'total_needed', array_length(v_required_uids, 1),
    'proposer_id', v_rematch -> 'proposer_id',
    'expires_at', v_rematch -> 'expires_at'
  );
end; $$;

revoke all on function public.cora_request_rematch(uuid, boolean) from public, anon;
grant execute on function public.cora_request_rematch(uuid, boolean) to authenticated;

-- ============================================================
-- Helper : nettoyage des rematch expirés (à appeler par cron)
-- ============================================================
create or replace function public.cora_cleanup_expired_rematches()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare v_count int := 0; r record;
begin
  for r in
    select id, game_state from cora_games
     where status = 'finished'
       and game_state -> 'rematch' ->> 'status' = 'pending'
       and (game_state -> 'rematch' ->> 'expires_at')::timestamptz < now()
  loop
    update cora_games
       set game_state = jsonb_set(game_state, '{rematch,status}', '"expired"'),
           updated_at = now()
     where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke all on function public.cora_cleanup_expired_rematches() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'cora-rematch-cleanup';
    perform cron.schedule('cora-rematch-cleanup', '* * * * *',
      $cron$ select public.cora_cleanup_expired_rematches(); $cron$);
    raise notice 'Cron cora-rematch-cleanup schedulé';
  end if;
end $$;
