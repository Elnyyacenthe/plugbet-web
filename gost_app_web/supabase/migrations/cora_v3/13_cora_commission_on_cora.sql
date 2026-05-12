-- ============================================================
-- CORA V3.5 — Commission 10% appliquée AUSSI sur Cora
-- ============================================================
-- Flux validé par l'utilisateur :
--   - Pot accumulé pour la partie Cora = bets (100) + penalty loser (50) = 150
--   - Commission 10% de 150 = 15 → admin_treasury
--   - Reste pour le gagnant = 135 → wallet du winner
--   - game_treasury : transit only (delta = 0)
--   - Zero-sum côté joueurs+admin : KING +85, Player -100, admin +15
-- ============================================================

-- ============================================================
-- 1. cora_pay_winner : 10% de commission TOUJOURS (Cora ou non)
-- ============================================================
drop function if exists public.cora_pay_winner(uuid, text, bigint, numeric, uuid[]);

create or replace function public.cora_pay_winner(
  p_winner_id uuid,
  p_game_id   text,
  p_pot       bigint,
  p_house_cut numeric default null,   -- null = utilise cora_dice_config.house_cut_pct (10%)
  p_loser_ids uuid[] default null     -- non-null = Cora unique, applique penalty 1× bet par loser
) returns void
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_cut bigint;
  v_payout bigint;
  v_house_pct numeric;
  v_loser uuid;
  v_bet bigint;
  v_collected bigint := 0;
  v_loser_count int;
  v_total_pot bigint;
begin
  if p_pot <= 0 then return; end if;

  v_house_pct := coalesce(p_house_cut,
                          (select house_cut_pct from cora_dice_config where id = 1),
                          0.10);

  -- ===========================================================
  -- CAS CORA : collecte la penalty de chaque loser
  -- ===========================================================
  if p_loser_ids is not null and array_length(p_loser_ids, 1) > 0 then
    v_loser_count := array_length(p_loser_ids, 1);
    v_bet := p_pot / (v_loser_count + 1);  -- bet par joueur

    foreach v_loser in array p_loser_ids loop
      begin
        -- Loser paie 1× bet supplémentaire (Cora penalty)
        perform _ledger_post(
          v_loser, -v_bet, 'penalty',
          'cora_penalty:' || p_game_id || ':' || v_loser::text,
          'cora_dice', p_game_id,
          jsonb_build_object('reason', 'cora_loss', 'amount', v_bet)
        );
        v_collected := v_collected + v_bet;
      exception when others then
        -- Wallet insuffisant côté loser (très rare grâce au check 2× bet à l'entrée)
        raise log 'Cora penalty failed for user %: %', v_loser, sqlerrm;
      end;
    end loop;

    -- Les penalties entrent dans game_treasury (transit)
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
  end if;

  -- ===========================================================
  -- DISTRIBUTION : commission 10% + payout au gagnant
  -- ===========================================================
  v_total_pot := p_pot + v_collected;       -- pot bets + penalties
  v_cut       := floor(v_total_pot * v_house_pct)::bigint;
  v_payout    := v_total_pot - v_cut;

  -- Crédit gagnant (idempotent par request_id unique)
  perform _ledger_post(
    p_winner_id, v_payout, 'payout',
    'cora_payout:' || p_game_id,
    'cora_dice', p_game_id,
    jsonb_build_object(
      'pot_bets', p_pot,
      'cora_penalty_collected', v_collected,
      'pot_total', v_total_pot,
      'house_cut_pct', v_house_pct,
      'commission', v_cut,
      'is_cora', v_collected > 0
    )
  );

  -- game_treasury : sort le pot total (winner + commission)
  -- → le delta net de game_treasury sur cette partie = 0 (transit pur)
  begin
    update game_treasury
      set balance = balance - v_total_pot,
          total_paid_out = total_paid_out + v_total_pot,
          updated_at = now()
      where id = 1;
  exception when undefined_table then null;
  end;

  -- admin_treasury : reçoit la commission
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
-- 2. cora_submit_roll : passe NULL (= 10% défaut) au lieu de 0
-- ============================================================
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
        when v_cora_count = 1 then 'CORA ! Pot peer-funded'
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
      -- V3.5 : Cora peer-to-peer AVEC commission 10% (p_house_cut = null = défaut 10%)
      select array_agg((k)::uuid) into v_losers
        from jsonb_object_keys(v_players) as k
        where k != v_winners[1]
          and not coalesce((v_players -> k -> 'forfeited')::boolean, false);
      perform cora_pay_winner(v_winners[1]::uuid, p_game_id::text, v_pot, null, v_losers);
    else
      -- Win normal : pas de loser_ids, commission 10% défaut
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
