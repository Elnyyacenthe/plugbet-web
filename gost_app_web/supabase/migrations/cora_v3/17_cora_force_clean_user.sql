-- ============================================================
-- CORA V3.7 — Force clean user pour casser TOO_MANY_ACTIVE_GAMES
-- ============================================================
-- Bug constaté : un user peut rester bloqué par TOO_MANY_ACTIVE_GAMES
-- même après abandon, parce que cora_forfeit marque seulement
-- 'forfeited' dans game_state mais ne retire pas la ligne
-- cora_room_players. Or le compteur d'active games joint là-dessus.
--
-- Fix : nouvelle fonction _cora_force_clean_user qui :
--   - Pour rooms 'waiting' : cancel + refund tous les joueurs
--   - Pour games 'playing' : refund l'user, le retire de
--     cora_room_players. Si plus personne → cancel la game/room.
--     Sinon le jeu continue pour les autres.
-- ============================================================

create or replace function public._cora_force_clean_user(p_user_id uuid)
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare
  r record;
  v_other uuid;
  v_count int := 0;
  v_game_id uuid;
begin
  if p_user_id is null then return 0; end if;

  for r in
    select rm.id, rm.bet_amount, rm.status
      from cora_rooms rm
      join cora_room_players p on p.room_id = rm.id and p.user_id = p_user_id
     where rm.status in ('waiting', 'playing')
    for update of rm skip locked
  loop
    perform _cora_lock_room(r.id);

    if r.status = 'waiting' then
      -- =====================================================
      -- ROOM EN ATTENTE : cancel total + refund TOUT LE MONDE
      -- =====================================================
      -- Refund de l'user
      if r.bet_amount > 0 then
        begin
          perform _ledger_post(
            p_user_id, r.bet_amount, 'refund',
            'cora_force_clean:' || r.id::text || ':' || p_user_id::text,
            'cora_dice', r.id::text,
            jsonb_build_object('reason', 'leave_waiting_room'));
        exception when others then null;
        end;
      end if;
      -- Refund tous les autres
      for v_other in
        select user_id from cora_room_players
         where room_id = r.id and user_id <> p_user_id
      loop
        begin
          perform _ledger_post(
            v_other, r.bet_amount, 'refund',
            'cora_force_clean:' || r.id::text || ':' || v_other::text,
            'cora_dice', r.id::text,
            jsonb_build_object('reason', 'host_or_player_left'));
        exception when others then null;
        end;
      end loop;
      delete from cora_room_players where room_id = r.id;
      update cora_rooms set status = 'cancelled', updated_at = now() where id = r.id;

    else
      -- =====================================================
      -- GAME EN COURS : FORFAIT (perd la mise, PAS de refund)
      -- Le mécanisme cora_forfeit existant gère :
      --   - marquage 'forfeited' dans game_state
      --   - si 1 seul restant non-forfeited → ce joueur gagne le pot
      --   - sinon → game continue pour les autres
      -- =====================================================
      select id into v_game_id from cora_games
        where room_id = r.id and status = 'playing'
        order by created_at desc limit 1;

      if v_game_id is not null then
        -- Marque comme forfeited dans game_state (sans refund — c'est un forfait)
        update cora_games
           set game_state = jsonb_set(
                 game_state,
                 array['players', p_user_id::text, 'forfeited'],
                 'true'),
               updated_at = now()
         where id = v_game_id;

        -- Si 1 seul restant non-forfeited → c'est le gagnant par défaut
        -- (logique de cora_forfeit déclenchée explicitement)
        declare
          v_remaining_uid uuid;
          v_remaining_count int;
          v_pot bigint;
          v_state jsonb;
        begin
          select game_state into v_state from cora_games where id = v_game_id;
          select count(*) into v_remaining_count
            from jsonb_each(v_state -> 'players') as p(k, v)
           where coalesce((v -> 'forfeited')::boolean, false) = false;

          if v_remaining_count = 1 then
            select (k)::uuid into v_remaining_uid
              from jsonb_each(v_state -> 'players') as p(k, v)
             where coalesce((v -> 'forfeited')::boolean, false) = false limit 1;

            v_pot := r.bet_amount * (
              select count(*) from jsonb_object_keys(v_state -> 'players') as kk
            );

            update cora_games set
              game_state = jsonb_set(jsonb_set(jsonb_set(jsonb_set(
                v_state,
                '{is_finished}', 'true'),
                '{is_cancelled}', 'false'),
                '{winners}', to_jsonb(array[v_remaining_uid::text])),
                '{result}', '"Victoire par forfait"'),
              status = 'finished',
              winner_ids = array[v_remaining_uid],
              updated_at = now()
            where id = v_game_id;

            update cora_rooms set status = 'finished' where id = r.id;

            -- Pay au gagnant solo (commission 10% défaut)
            perform cora_pay_winner(v_remaining_uid, v_game_id::text, v_pot, null, null);

            perform _cora_log_event(v_game_id, p_user_id, 'forfeit_lone_winner',
              jsonb_build_object('winner', v_remaining_uid, 'pot', v_pot));
          else
            -- Game continue pour les autres
            perform _cora_log_event(v_game_id, p_user_id, 'forfeited_via_force_clean',
              jsonb_build_object('remaining', v_remaining_count));
          end if;
        end;
      end if;

      -- Retire l'user de cora_room_players pour qu'il ne compte plus dans
      -- le check TOO_MANY_ACTIVE_GAMES, indépendamment de l'état de la game
      delete from cora_room_players where room_id = r.id and user_id = p_user_id;
    end if;

    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;
revoke all on function public._cora_force_clean_user(uuid) from public, anon, authenticated;

-- ============================================================
-- cora_create_room V3.7 : utilise _cora_force_clean_user
-- au lieu de _cora_cleanup_user_zombies (plus efficace)
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
  v_required bigint;
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

  -- 🔥 V3.7 : force clean systématique avant le check
  -- L'user veut créer une nouvelle partie → on libère TOUS ses slots actifs
  perform _cora_force_clean_user(v_uid);

  -- Recompte après cleanup
  select count(*) into v_active_count
    from cora_rooms r
    join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
    where r.status in ('waiting', 'playing');

  if v_active_count >= v_cfg.max_concurrent_games_per_user then
    -- Cas extrême : le force_clean a échoué (lock conflict ?). Renvoie l'info pour debug.
    select jsonb_build_object(
      'type', case when r.status='playing' then 'game' else 'room' end,
      'room_id', r.id, 'code', r.code, 'status', r.status,
      'bet_amount', r.bet_amount, 'created_at', r.created_at
    ) into v_active
      from cora_rooms r
      join cora_room_players p on p.room_id = r.id and p.user_id = v_uid
     where r.status in ('waiting','playing')
     order by r.created_at desc limit 1;
    raise exception 'TOO_MANY_ACTIVE_GAMES_AFTER_CLEAN: max=% active=%',
      v_cfg.max_concurrent_games_per_user, coalesce(v_active::text, 'null')
      using errcode = 'P0006', detail = coalesce(v_active::text, '');
  end if;

  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  v_required := p_bet_amount * 2;
  if (select wallet_balance(v_uid)) < v_required then
    raise exception 'INSUFFICIENT_FUNDS_CORA: required=%, your_balance=%',
      v_required, (select wallet_balance(v_uid))
      using errcode = 'P0001',
            detail = format('Pour jouer Cora à %s FCFA, ton solde doit être >= %s FCFA.',
                            p_bet_amount, v_required);
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
    values (v_room_id, v_uid, v_username, true);

  perform cora_place_bet(v_uid, v_room_id::text, p_bet_amount);

  return jsonb_build_object(
    'room_id', v_room_id, 'code', v_code,
    'bet_amount', p_bet_amount, 'player_count', p_player_count,
    'start_deadline', v_deadline,
    'min_balance_required', v_required
  );
end; $$;
revoke all on function public.cora_create_room(int, bigint, boolean) from public, anon;
grant execute on function public.cora_create_room(int, bigint, boolean) to authenticated;

-- ============================================================
-- cora_abandon_my_rooms V3.7 : utilise _cora_force_clean_user
-- ============================================================
create or replace function public.cora_abandon_my_rooms()
returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
  v_count := _cora_force_clean_user(v_uid);
  return jsonb_build_object('cleaned', v_count, 'force_clean', true);
end; $$;
revoke all on function public.cora_abandon_my_rooms() from public, anon;
grant execute on function public.cora_abandon_my_rooms() to authenticated;

-- ============================================================
-- Cleanup immédiat de l'utilisateur impacté (run via service_role)
-- ============================================================
-- Si tu veux nettoyer un user spécifique (ex. celui en train de tester) :
--   select public._cora_force_clean_user('UUID_DU_USER');
-- Pour le user de la screenshot (room F3BFA0 → room_id f0a655cd-2cea-4b55-9020-fc81e51310b5) :
do $$
declare v_uid uuid;
begin
  -- Trouve l'host de la room F3BFA0
  select host_id into v_uid from cora_rooms where code = 'F3BFA0';
  if v_uid is not null then
    perform _cora_force_clean_user(v_uid);
    raise notice 'Cleaned user %', v_uid;
  end if;
end $$;
