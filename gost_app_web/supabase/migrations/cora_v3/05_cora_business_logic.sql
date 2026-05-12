-- ============================================================
-- CORA DICE V3 — Business Logic (financière + jeu)
-- ============================================================
-- Implémente :
--   - cora_place_bet, cora_pay_winner, cora_refund_participants (via ledger)
--   - _cora_secure_dice (RNG cryptographique)
--   - _cora_lock_room, _cora_log_event
--   - _cora_start_game (interne, idempotent)
--   - cora_submit_roll, cora_forfeit (RPCs publiques)
-- ============================================================

-- ============================================================
-- 1. Helpers
-- ============================================================

-- Lock advisory par room
create or replace function public._cora_lock_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  perform pg_advisory_xact_lock(
    hashtext('cora_room'),
    hashtextextended(p_room_id::text, 0)::int
  );
end; $$;

revoke all on function public._cora_lock_room(uuid) from public, anon, authenticated;

-- RNG cryptographique
create or replace function public._cora_secure_dice()
returns int[]
language plpgsql security definer set search_path=public
as $$
declare
  v_bytes bytea;
  v_d1 int;
  v_d2 int;
begin
  v_bytes := gen_random_bytes(2);
  -- Rejection sampling pour éliminer le biais % 6
  -- Si byte ≥ 252 (= 6*42), on retire un nouveau byte. Probabilité d'attente: 4/256 par tirage.
  loop
    if get_byte(v_bytes, 0) < 252 then exit; end if;
    v_bytes := set_byte(v_bytes, 0, get_byte(gen_random_bytes(1), 0));
  end loop;
  loop
    if get_byte(v_bytes, 1) < 252 then exit; end if;
    v_bytes := set_byte(v_bytes, 1, get_byte(gen_random_bytes(1), 0));
  end loop;
  v_d1 := (get_byte(v_bytes, 0) % 6) + 1;
  v_d2 := (get_byte(v_bytes, 1) % 6) + 1;
  return array[v_d1, v_d2];
end; $$;

revoke all on function public._cora_secure_dice() from public, anon, authenticated;

-- Event logger (table créée dans 07_session_events.sql, fonction défensive)
create or replace function public._cora_log_event(
  p_game_id uuid, p_user_id uuid, p_type text, p_payload jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path=public
as $$
begin
  begin
    insert into cora_game_events(game_id, user_id, event_type, payload)
    values (p_game_id, p_user_id, p_type, p_payload);
  exception when undefined_table then
    -- Table pas encore créée (07 pas appliqué) : log via raise
    raise log 'CORA_EVENT[%] game=% user=% payload=%', p_type, p_game_id, p_user_id, p_payload;
  end;
end; $$;

revoke all on function public._cora_log_event(uuid, uuid, text, jsonb) from public, anon, authenticated;

-- ============================================================
-- 2. Financial wrappers (utilisent wallet_ledger + game_treasury)
-- ============================================================

create or replace function public.cora_place_bet(
  p_user_id uuid,
  p_game_id text,
  p_amount  bigint
) returns void
language plpgsql security definer set search_path=public
as $$
begin
  if p_amount <= 0 then return; end if;

  -- Débit user via ledger (idempotent par game_id+user)
  perform _ledger_post(
    p_user_id, -p_amount, 'bet',
    'cora_bet:' || p_game_id || ':' || p_user_id::text,
    'cora_dice', p_game_id,
    jsonb_build_object('source','place_bet')
  );

  -- Crédit caisse jeu (table existante du système treasury)
  begin
    update game_treasury
      set balance = balance + p_amount,
          total_received = total_received + p_amount,
          updated_at = now()
      where id = 1;
    if not found then
      insert into game_treasury(id, balance, total_received, total_paid_out)
        values (1, p_amount, p_amount, 0);
    end if;
  exception when undefined_table then
    raise log 'CORA: game_treasury table absente, skip cumul';
  end;
end; $$;

revoke all on function public.cora_place_bet(uuid, text, bigint) from public, anon, authenticated;

create or replace function public.cora_pay_winner(
  p_winner_id uuid,
  p_game_id   text,
  p_pot       bigint,
  p_house_cut numeric default null  -- null = lit la config
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_cut bigint;
  v_payout bigint;
  v_house_pct numeric;
begin
  if p_pot <= 0 then return; end if;

  v_house_pct := coalesce(p_house_cut, (select house_cut_pct from cora_dice_config where id = 1), 0.10);
  v_cut := floor(p_pot * v_house_pct)::bigint;
  v_payout := p_pot - v_cut;

  -- Crédit gagnant (idempotent)
  perform _ledger_post(
    p_winner_id, v_payout, 'payout',
    'cora_payout:' || p_game_id,
    'cora_dice', p_game_id,
    jsonb_build_object('pot', p_pot, 'house_cut_pct', v_house_pct, 'cut', v_cut)
  );

  -- Débit caisse jeu (le pot est sortie de la caisse vers le gagnant)
  begin
    update game_treasury
      set balance = balance - p_pot,
          total_paid_out = total_paid_out + p_pot,
          updated_at = now()
      where id = 1;
  exception when undefined_table then null;
  end;

  -- Commission vers admin (caisse projet)
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

revoke all on function public.cora_pay_winner(uuid, text, bigint, numeric) from public, anon, authenticated;

create or replace function public.cora_refund_participants(
  p_game_id     text,
  p_user_ids    uuid[],
  p_amount_each bigint
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid;
  v_n int := coalesce(array_length(p_user_ids, 1), 0);
  v_total bigint := p_amount_each * v_n;
begin
  if v_total = 0 or v_n = 0 then return; end if;

  foreach v_uid in array p_user_ids loop
    perform _ledger_post(
      v_uid, p_amount_each, 'refund',
      'cora_refund:' || p_game_id || ':' || v_uid::text,
      'cora_dice', p_game_id,
      jsonb_build_object('reason','tie_or_cancel')
    );
  end loop;

  begin
    update game_treasury
      set balance = balance - v_total,
          total_paid_out = total_paid_out + v_total,
          updated_at = now()
      where id = 1;
  exception when undefined_table then null;
  end;
end; $$;

revoke all on function public.cora_refund_participants(text, uuid[], bigint) from public, anon, authenticated;

-- ============================================================
-- 3. _cora_start_game (interne, idempotent)
-- ============================================================
create or replace function public._cora_start_game(p_room_id uuid)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_room cora_rooms;
  v_game_id uuid;
  v_players jsonb := '{}'::jsonb;
  v_turn_order text[] := array[]::text[];
  v_p record;
begin
  perform _cora_lock_room(p_room_id);

  select * into v_room from cora_rooms where id = p_room_id for update;
  if not found or v_room.status != 'waiting' then
    return null;
  end if;

  -- Vérifie qu'aucune game active n'existe (idempotence par contrainte)
  if exists (select 1 from cora_games where room_id = p_room_id and status = 'playing') then
    return null;
  end if;

  -- Construit l'ordre déterministe (par joined_at, tie-break user_id)
  for v_p in
    select user_id, username
      from cora_room_players where room_id = p_room_id
      order by joined_at, user_id
  loop
    v_turn_order := array_append(v_turn_order, v_p.user_id::text);
    v_players := v_players || jsonb_build_object(
      v_p.user_id::text,
      jsonb_build_object(
        'username', v_p.username,
        'roll', null,
        'final_score', null,
        'forfeited', false
      )
    );
  end loop;

  if coalesce(array_length(v_turn_order, 1), 0) < 2 then
    return null;
  end if;

  insert into cora_games (room_id, bet_amount, player_count, game_state, status)
  values (
    p_room_id, v_room.bet_amount, v_room.player_count,
    jsonb_build_object(
      'players', v_players,
      'turn_order', to_jsonb(v_turn_order),
      'current_turn_idx', 0,
      'current_turn', v_turn_order[1],
      'winners', '[]'::jsonb,
      'is_finished', false,
      'is_cancelled', false,
      'cancel_reason', null,
      'result', null,
      'created_at', extract(epoch from now())
    ),
    'playing'
  ) returning id into v_game_id;

  update cora_rooms set status = 'playing', game_id = v_game_id, updated_at = now()
    where id = p_room_id;

  perform _cora_log_event(v_game_id, null, 'game_started',
    jsonb_build_object(
      'player_count', v_room.player_count,
      'bet', v_room.bet_amount,
      'turn_order', to_jsonb(v_turn_order)
    ));

  return v_game_id;
end; $$;

revoke all on function public._cora_start_game(uuid) from public, anon, authenticated;

-- ============================================================
-- 4. cora_submit_roll (RPC publique)
-- ============================================================
create or replace function public.cora_submit_roll(p_game_id uuid)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_game cora_games;
  v_state jsonb;
  v_players jsonb;
  v_turn_order text[];
  v_idx int;
  v_dice int[];
  v_d1 int; v_d2 int;
  v_score int;
  v_all_rolled boolean;
  v_winners text[];
  v_pot bigint;
  v_participants uuid[];
  v_is_cancelled boolean := false;
  v_cancel_reason text;
  v_cora_count int := 0;
  v_cora_winner text;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED' using errcode = '42501'; end if;

  -- Rate limit
  begin
    perform check_rate_limit('cora_roll', v_uid::text, 60, '1 minute');
  exception when undefined_function then null;
  end;

  -- Lock atomique
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

  -- Génération sécurisée
  v_dice := _cora_secure_dice();
  v_d1 := v_dice[1]; v_d2 := v_dice[2];
  v_score := case when v_d1 + v_d2 = 7 then -1 else v_d1 + v_d2 end;

  -- État joueur
  v_players := jsonb_set(v_players, array[v_uid::text, 'roll'],
    jsonb_build_object('dice1', v_d1, 'dice2', v_d2, 'is_cora', v_d1 = 1 and v_d2 = 1));
  v_players := jsonb_set(v_players, array[v_uid::text, 'final_score'], to_jsonb(v_score));
  v_state := jsonb_set(v_state, '{players}', v_players);

  perform _cora_log_event(p_game_id, v_uid, 'rolled',
    jsonb_build_object('dice1', v_d1, 'dice2', v_d2, 'score', v_score));

  -- Trouver le prochain joueur (skip forfeited et déjà roll)
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
    -- Calcul du résultat
    declare
      v_max_score int := -2;
      v_uid_iter text;
      v_p jsonb;
      v_score_iter int;
      v_is_cora_iter boolean;
    begin
      v_winners := array[]::text[];

      -- Compter les Cora (1+1 strict)
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
        -- Pas de Cora : score le plus élevé
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

    -- Finalisation state
    v_state := jsonb_set(v_state, '{is_finished}', 'true');
    v_state := jsonb_set(v_state, '{is_cancelled}', to_jsonb(v_is_cancelled));
    v_state := jsonb_set(v_state, '{cancel_reason}',
      case when v_cancel_reason is null then 'null'::jsonb else to_jsonb(v_cancel_reason) end);
    v_state := jsonb_set(v_state, '{winners}', to_jsonb(v_winners));
    v_state := jsonb_set(v_state, '{current_turn}', 'null');
    v_state := jsonb_set(v_state, '{result}',
      to_jsonb(case
        when v_is_cancelled then 'Match annulé : ' || coalesce(v_cancel_reason, 'inconnu')
        when v_cora_count = 1 then 'CORA ! Pot doublé'
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

    -- Treasury / payout
    v_pot := v_game.bet_amount * v_game.player_count;
    if v_is_cancelled then
      select array_agg((k)::uuid order by k) into v_participants
        from jsonb_object_keys(v_players) as k;
      perform cora_refund_participants(p_game_id::text, v_participants, v_game.bet_amount);
    elsif v_cora_count = 1 then
      -- Cora double pot, pas de commission
      perform cora_pay_winner(v_winners[1]::uuid, p_game_id::text, v_pot * 2, 0);
    else
      -- Pot normal -10% commission
      perform cora_pay_winner(v_winners[1]::uuid, p_game_id::text, v_pot, null);
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

-- ============================================================
-- 5. cora_forfeit (RPC publique)
-- ============================================================
create or replace function public.cora_forfeit(p_game_id uuid)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_game cora_games;
  v_state jsonb;
  v_players jsonb;
  v_remaining int;
  v_remaining_uid uuid;
  v_pot bigint;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_game from cora_games where id = p_game_id for update;
  if not found or v_game.status != 'playing' then
    return jsonb_build_object('skipped', true);
  end if;

  perform _cora_lock_room(v_game.room_id);

  v_state := v_game.game_state;
  v_players := v_state -> 'players';
  if v_players -> v_uid::text is null then
    return jsonb_build_object('skipped', true);
  end if;
  if coalesce((v_players -> v_uid::text -> 'forfeited')::boolean, false) then
    return jsonb_build_object('already_forfeited', true);
  end if;

  -- Marquer comme forfeited
  v_players := jsonb_set(v_players, array[v_uid::text, 'forfeited'], 'true');
  v_state := jsonb_set(v_state, '{players}', v_players);

  perform _cora_log_event(p_game_id, v_uid, 'forfeited', '{}');

  -- Compter les non-forfeited
  v_remaining := (
    select count(*) from jsonb_each(v_players) as p(k, v)
     where coalesce((v -> 'forfeited')::boolean, false) = false
  );

  if v_remaining = 1 then
    -- Un seul restant : il gagne le pot
    select (k)::uuid into v_remaining_uid from jsonb_each(v_players) as p(k, v)
      where coalesce((v -> 'forfeited')::boolean, false) = false limit 1;

    v_pot := v_game.bet_amount * v_game.player_count;
    v_state := jsonb_set(v_state, '{is_finished}', 'true');
    v_state := jsonb_set(v_state, '{is_cancelled}', 'false');
    v_state := jsonb_set(v_state, '{winners}', to_jsonb(array[v_remaining_uid::text]));
    v_state := jsonb_set(v_state, '{cancel_reason}', '"forfeit_lone_winner"');
    v_state := jsonb_set(v_state, '{result}', '"Victoire par forfait"');

    update cora_games set
      game_state = v_state, status = 'finished',
      winner_ids = array[v_remaining_uid], updated_at = now()
    where id = p_game_id;
    update cora_rooms set status = 'finished' where id = v_game.room_id;

    perform cora_pay_winner(v_remaining_uid, p_game_id::text, v_pot, null);
    perform _cora_log_event(p_game_id, null, 'game_ended',
      jsonb_build_object('winners', array[v_remaining_uid::text], 'reason', 'forfeit_lone_winner', 'pot', v_pot));

    return jsonb_build_object('finished', true, 'winner', v_remaining_uid);
  else
    -- La partie continue : si c'était son tour, passer au suivant non-forfeited non-roll
    if (v_state ->> 'current_turn') = v_uid::text then
      declare
        v_to_array text[] := array(select jsonb_array_elements_text(v_state -> 'turn_order'));
        v_pos int := array_position(v_to_array, v_uid::text);
        v_next text;
        v_next_p jsonb;
      begin
        for i in 1..array_length(v_to_array, 1) loop
          v_next := v_to_array[((v_pos - 1 + i) % array_length(v_to_array, 1)) + 1];
          v_next_p := v_players -> v_next;
          if not coalesce((v_next_p -> 'forfeited')::boolean, false)
             and ((v_next_p -> 'roll') is null or jsonb_typeof(v_next_p -> 'roll') = 'null') then
            v_state := jsonb_set(v_state, '{current_turn}', to_jsonb(v_next));
            exit;
          end if;
        end loop;
      end;
    end if;

    update cora_games set game_state = v_state, updated_at = now() where id = p_game_id;
    return jsonb_build_object('forfeited', true, 'remaining', v_remaining);
  end if;
end; $$;

revoke all on function public.cora_forfeit(uuid) from public, anon;
grant execute on function public.cora_forfeit(uuid) to authenticated;
