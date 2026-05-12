-- ============================================================
-- CORA V3.4 — Cora financé par les pairs (pas par game_treasury)
-- ============================================================
-- Règles :
--   - Pour entrer : wallet >= 2× bet (mise + Cora penalty potentielle)
--   - Cora unique : chaque perdant paie 1× bet en plus, donné au gagnant
--   - game_treasury n'est plus la source du bonus Cora (zero-sum peer)
--   - admin_treasury : 0 commission sur Cora (inchangé)
-- ============================================================

-- ============================================================
-- 1. cora_create_room : check wallet >= 2× bet
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

  -- V3.4 : check wallet >= 2× bet (couvre la mise + Cora penalty potentielle)
  v_required := p_bet_amount * 2;
  if (select wallet_balance(v_uid)) < v_required then
    raise exception 'INSUFFICIENT_FUNDS_CORA: required=%, your_balance=%',
      v_required, (select wallet_balance(v_uid))
      using errcode = 'P0001',
            detail = format('Pour jouer Cora à %s FCFA, ton solde doit être >= %s FCFA.', p_bet_amount, v_required);
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
-- 2. cora_join_room : check wallet >= 2× bet
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
  v_required bigint;
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

  -- V3.4 : check wallet >= 2× bet
  v_required := v_room.bet_amount * 2;
  if (select wallet_balance(v_uid)) < v_required then
    raise exception 'INSUFFICIENT_FUNDS_CORA: required=%, your_balance=%',
      v_required, (select wallet_balance(v_uid))
      using errcode = 'P0001',
            detail = format('Pour rejoindre Cora à %s FCFA, ton solde doit être >= %s FCFA.', v_room.bet_amount, v_required);
  end if;

  select coalesce(username, 'Joueur') into v_username from user_profiles where id = v_uid;

  insert into cora_room_players (room_id, user_id, username, is_ready)
    values (v_room.id, v_uid, v_username, true);

  perform cora_place_bet(v_uid, v_room.id::text, v_room.bet_amount);

  if (v_count + 1) >= v_room.player_count then
    v_game_id := _cora_start_game(v_room.id);
    v_started := v_game_id is not null;
  else
    v_new_deadline := greatest(coalesce(v_room.start_deadline, now() + interval '60 seconds'),
                               now() + interval '60 seconds');
    update cora_rooms set start_deadline = v_new_deadline where id = v_room.id;
  end if;

  return jsonb_build_object(
    'room_id', v_room.id, 'joined', true,
    'started', v_started, 'game_id', v_game_id,
    'players', v_count + 1, 'capacity', v_room.player_count,
    'start_deadline', coalesce(v_new_deadline, v_room.start_deadline),
    'min_balance_required', v_required
  );
end; $$;
revoke all on function public.cora_join_room(text) from public, anon;
grant execute on function public.cora_join_room(text) to authenticated;

-- ============================================================
-- 3. cora_pay_winner : nouvelle signature avec p_loser_ids pour Cora
-- ============================================================
-- Drop l'ancienne signature (4 args) et recrée avec 5 args.
drop function if exists public.cora_pay_winner(uuid, text, bigint, numeric);

create or replace function public.cora_pay_winner(
  p_winner_id uuid,
  p_game_id   text,
  p_pot       bigint,
  p_house_cut numeric default null,
  p_loser_ids uuid[] default null  -- V3.4 : losers pour Cora peer-to-peer
) returns void
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_cut bigint := 0;
  v_payout bigint;
  v_house_pct numeric;
  v_loser uuid;
  v_bet bigint;
  v_collected bigint := 0;
  v_loser_count int;
  v_is_cora boolean := false;
begin
  if p_pot <= 0 then return; end if;

  v_house_pct := coalesce(p_house_cut, (select house_cut_pct from cora_dice_config where id = 1), 0.10);
  v_is_cora := (v_house_pct = 0 and p_loser_ids is not null and array_length(p_loser_ids, 1) > 0);

  if v_is_cora then
    -- ===========================================
    -- CAS CORA UNIQUE : peer-to-peer
    -- ===========================================
    v_loser_count := array_length(p_loser_ids, 1);
    -- Bet par joueur = pot / nombre total de joueurs
    v_bet := p_pot / (v_loser_count + 1);

    -- Chaque perdant paie 1× bet supplémentaire (Cora penalty)
    foreach v_loser in array p_loser_ids loop
      begin
        perform _ledger_post(
          v_loser, -v_bet, 'penalty',
          'cora_penalty:' || p_game_id || ':' || v_loser::text,
          'cora_dice', p_game_id,
          jsonb_build_object('reason', 'cora_loss', 'amount', v_bet)
        );
        v_collected := v_collected + v_bet;
      exception when others then
        -- Wallet insuffisant (rare grâce au check 2× bet à l'entrée)
        raise log 'Cora penalty failed for user %: %', v_loser, sqlerrm;
      end;
    end loop;

    -- Le gagnant reçoit : pot + collected penalties
    v_payout := p_pot + v_collected;

    -- game_treasury : reçoit les penalties puis paie le gagnant
    -- Net delta = -p_pot (juste le pot original sort, comme une partie normale)
    if v_collected > 0 then
      begin
        update game_treasury
          set balance = balance + v_collected,
              total_received = total_received + v_collected,
              updated_at = now()
          where id = 1;
      exception when undefined_table then null;
      end;
    end if;
  else
    -- ===========================================
    -- CAS NORMAL : commission 10%
    -- ===========================================
    v_cut := floor(p_pot * v_house_pct)::bigint;
    v_payout := p_pot - v_cut;
  end if;

  -- Crédit gagnant (idempotent)
  perform _ledger_post(
    p_winner_id, v_payout, 'payout',
    'cora_payout:' || p_game_id,
    'cora_dice', p_game_id,
    jsonb_build_object(
      'pot', p_pot, 'house_cut_pct', v_house_pct, 'cut', v_cut,
      'is_cora', v_is_cora, 'cora_bonus_collected', v_collected
    )
  );

  -- game_treasury : retire le payout
  begin
    update game_treasury
      set balance = balance - v_payout,
          total_paid_out = total_paid_out + v_payout,
          updated_at = now()
      where id = 1;
  exception when undefined_table then null;
  end;

  -- Commission admin (Cora = 0)
  if v_cut > 0 then
    begin
      update admin_treasury
        set balance = balance + v_cut,
            total_earned = total_earned + v_cut,
            updated_at = now()
        where id = 1;
      if not found then
        insert into admin_treasury(id, balance, total_earned, total_withdrawn)
          values (1, v_cut, v_cut, 0);
      end if;
    exception when undefined_table then null;
    end;
  end if;
end; $$;
revoke all on function public.cora_pay_winner(uuid, text, bigint, numeric, uuid[])
  from public, anon, authenticated;

-- ============================================================
-- 4. cora_submit_roll : passe les loser_ids au cora_pay_winner Cora
-- ============================================================
-- On modifie uniquement la branche Cora unique (search & replace)
-- Le reste de cora_submit_roll est identique à 05_cora_business_logic.sql
create or replace function public.cora_submit_roll(p_game_id uuid)
returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_game cora_games;
  v_state jsonb;
  v_players jsonb;
  v_turn_order text[];
  v_dice int[];
  v_d1 int; v_d2 int;
  v_score int;
  v_all_rolled boolean;
  v_winners text[];
  v_pot bigint;
  v_participants uuid[];
  v_losers uuid[];
  v_is_cancelled boolean := false;
  v_cancel_reason text;
  v_cora_count int := 0;
  v_cora_winner text;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED' using errcode = '42501'; end if;

  begin
    perform check_rate_limit('cora_roll', v_uid::text, 60, '1 minute');
  exception when undefined_function then null;
  end;

  select * into v_game from cora_games where id = p_game_id for update;
  if not found then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_game.status != 'playing' then raise exception 'GAME_NOT_PLAYING' using errcode = 'P0003'; end if;

  v_state := v_game.game_state;
  v_players := v_state -> 'players';

  if v_players -> v_uid::text is null then
    raise exception 'NOT_A_PLAYER' using errcode = '42501';
  end if;
  if (v_state ->> 'current_turn') != v_uid::text then
    raise exception 'NOT_YOUR_TURN' using errcode = 'P0004';
  end if;
  if (v_players -> v_uid::text -> 'roll') is not null
     and jsonb_typeof(v_players -> v_uid::text -> 'roll') != 'null' then
    raise exception 'ALREADY_ROLLED' using errcode = 'P0005';
  end if;

  v_dice := _cora_secure_dice();
  v_d1 := v_dice[1]; v_d2 := v_dice[2];
  v_score := case when v_d1 + v_d2 = 7 then -1 else v_d1 + v_d2 end;

  v_players := jsonb_set(v_players, array[v_uid::text, 'roll'],
    jsonb_build_object('dice1', v_d1, 'dice2', v_d2, 'is_cora', v_d1 = 1 and v_d2 = 1));
  v_players := jsonb_set(v_players, array[v_uid::text, 'final_score'], to_jsonb(v_score));
  v_state := jsonb_set(v_state, '{players}', v_players);

  perform _cora_log_event(p_game_id, v_uid, 'rolled',
    jsonb_build_object('dice1', v_d1, 'dice2', v_d2, 'score', v_score));

  v_turn_order := array(select jsonb_array_elements_text(v_state -> 'turn_order'));
  v_all_rolled := true;

  for i in 1..coalesce(array_length(v_turn_order, 1), 0) loop
    declare v_idx_i int := ((array_position(v_turn_order, v_uid::text) - 1 + i) % array_length(v_turn_order, 1)) + 1;
            v_next text := v_turn_order[v_idx_i];
            v_next_p jsonb := v_players -> v_next;
    begin
      if coalesce((v_next_p -> 'forfeited')::boolean, false) then continue; end if;
      if (v_next_p -> 'roll') is null or jsonb_typeof(v_next_p -> 'roll') = 'null' then
        v_state := jsonb_set(v_state, '{current_turn}', to_jsonb(v_next));
        v_state := jsonb_set(v_state, '{current_turn_idx}', to_jsonb(v_idx_i - 1));
        v_all_rolled := false;
        exit;
      end if;
    end;
  end loop;

  if v_all_rolled then
    declare
      v_max_score int := -2;
      v_uid_iter text;
      v_p jsonb;
      v_score_iter int;
      v_is_cora_iter boolean;
    begin
      v_winners := array[]::text[];

      foreach v_uid_iter in array v_turn_order loop
        v_p := v_players -> v_uid_iter;
        if coalesce((v_p -> 'forfeited')::boolean, false) then continue; end if;
        v_is_cora_iter := (v_p -> 'roll' ->> 'dice1')::int = 1
                      and (v_p -> 'roll' ->> 'dice2')::int = 1;
        if v_is_cora_iter then
          v_cora_count := v_cora_count + 1;
          v_cora_winner := v_uid_iter;
        end if;
      end loop;

      if v_cora_count >= 2 then
        v_is_cancelled := true; v_cancel_reason := 'multiple_cora';
      elsif v_cora_count = 1 then
        v_winners := array[v_cora_winner];
      else
        foreach v_uid_iter in array v_turn_order loop
          v_p := v_players -> v_uid_iter;
          if coalesce((v_p -> 'forfeited')::boolean, false) then continue; end if;
          v_score_iter := (v_p ->> 'final_score')::int;
          if v_score_iter > v_max_score then
            v_max_score := v_score_iter;
            v_winners := array[v_uid_iter];
          elsif v_score_iter = v_max_score then
            v_winners := array_append(v_winners, v_uid_iter);
          end if;
        end loop;

        if v_max_score < 0 then
          v_is_cancelled := true; v_cancel_reason := 'all_bust_seven';
          v_winners := array[]::text[];
        elsif coalesce(array_length(v_winners, 1), 0) > 1 then
          v_is_cancelled := true; v_cancel_reason := 'tie';
          v_winners := array[]::text[];
        end if;
      end if;
    end;

    v_state := jsonb_set(v_state, '{is_finished}', 'true');
    v_state := jsonb_set(v_state, '{is_cancelled}', to_jsonb(v_is_cancelled));
    v_state := jsonb_set(v_state, '{cancel_reason}',
      case when v_cancel_reason is null then 'null'::jsonb else to_jsonb(v_cancel_reason) end);
    v_state := jsonb_set(v_state, '{winners}', to_jsonb(v_winners));
    v_state := jsonb_set(v_state, '{current_turn}', 'null');
    v_state := jsonb_set(v_state, '{result}',
      to_jsonb(case
        when v_is_cancelled then 'Match annulé : ' || coalesce(v_cancel_reason, 'inconnu')
        when v_cora_count = 1 then 'CORA ! Pot doublé (peer-to-peer)'
        else 'Victoire'
      end));

    update cora_games set
      game_state = v_state,
      status = case when v_is_cancelled then 'cancelled' else 'finished' end,
      winner_ids = case when v_is_cancelled then null else v_winners::uuid[] end,
      updated_at = now()
    where id = p_game_id;

    update cora_rooms set
      status = case when v_is_cancelled then 'cancelled' else 'finished' end
      where id = v_game.room_id;

    v_pot := v_game.bet_amount * v_game.player_count;
    if v_is_cancelled then
      select array_agg((k)::uuid order by k) into v_participants
        from jsonb_object_keys(v_players) as k;
      perform cora_refund_participants(p_game_id::text, v_participants, v_game.bet_amount);
    elsif v_cora_count = 1 then
      -- V3.4 : Cora peer-to-peer. Récupère les losers (= tous sauf le gagnant non-forfeited)
      select array_agg((k)::uuid) into v_losers
        from jsonb_object_keys(v_players) as k
        where k != v_winners[1]
          and not coalesce((v_players -> k -> 'forfeited')::boolean, false);
      perform cora_pay_winner(v_winners[1]::uuid, p_game_id::text, v_pot, 0, v_losers);
    else
      perform cora_pay_winner(v_winners[1]::uuid, p_game_id::text, v_pot, null, null);
    end if;

    perform _cora_log_event(p_game_id, null, 'game_ended',
      jsonb_build_object(
        'winners', to_jsonb(v_winners),
        'cancelled', v_is_cancelled,
        'reason', coalesce(v_cancel_reason, ''),
        'pot', v_pot,
        'cora_count', v_cora_count
      ));
  else
    update cora_games set game_state = v_state, updated_at = now() where id = p_game_id;
  end if;

  return jsonb_build_object(
    'dice1', v_d1, 'dice2', v_d2, 'score', v_score,
    'is_finished', v_all_rolled,
    'is_cora', v_d1 = 1 and v_d2 = 1
  );
end; $$;
revoke all on function public.cora_submit_roll(uuid) from public, anon;
grant execute on function public.cora_submit_roll(uuid) to authenticated;
