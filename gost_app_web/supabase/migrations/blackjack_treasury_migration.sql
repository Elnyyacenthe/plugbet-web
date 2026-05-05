-- ============================================================
-- BLACKJACK - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_final_fix.sql.
-- Idempotent : safe to re-run.
--
-- Patche :
--   1. bj_create_room : debit hote via treasury_place_bet
--   2. bj_join_room   : debit joiner via treasury_place_bet
--   3. _bj_dealer_play : payouts via apply_game_payout (won) +
--                        treasury_refund_all (push). Lost = rien.
--   4. _bj_next_turn  : signature etendue avec p_game_id
--   5. bj_hit / bj_stand : pass p_game_id a _bj_next_turn
--
-- Logique payout (10% commission UNIFORME) :
--   - won  (joueur > dealer)  : gain brut = bet * 2
--                                -> 90% au joueur (= bet * 1.8)
--                                -> 10% caisse  (= bet * 0.2)
--                                Net joueur = -bet (mise) + 1.8*bet = +0.8*bet
--   - push (joueur = dealer)  : refund integral bet (PAS de commission)
--                                Net joueur = 0
--   - lost (joueur < dealer)  : mise reste a la caisse (deja debitee)
--                                Net joueur = -bet
-- ============================================================

-- ============================================================
-- 1) bj_create_room - debit hote via treasury
-- ============================================================
create or replace function public.bj_create_room(
  p_player_count integer,
  p_bet_amount integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_room_id uuid;
  v_username text;
begin
  -- Generer code unique
  loop
    v_code := upper(substr(md5(random()::text), 1, 6));
    exit when not exists (select 1 from public.blackjack_rooms where code = v_code);
  end loop;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  -- Inserer la room d'abord (besoin du room_id pour le log treasury)
  insert into public.blackjack_rooms
    (code, host_id, player_count, bet_amount, host_username)
    values (v_code, v_uid, p_player_count, p_bet_amount, v_username)
    returning id into v_room_id;

  -- ===== TREASURY MIGRATION =====
  -- Debit via la caisse (atomique, verifie solde, log auto)
  if p_bet_amount > 0 then
    perform public.treasury_place_bet(
      'blackjack', v_room_id::text, v_uid, p_bet_amount
    );
  end if;

  insert into public.blackjack_room_players(room_id, user_id, username)
    values (v_room_id, v_uid, v_username);

  return jsonb_build_object('room_id', v_room_id, 'code', v_code);
end;
$function$;

grant execute on function public.bj_create_room(integer, integer) to authenticated;

-- ============================================================
-- 2) bj_join_room - debit joiner via treasury
-- ============================================================
create or replace function public.bj_join_room(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_count int;
  v_username text;
begin
  select * into v_room from public.blackjack_rooms
    where code = upper(p_code) and status = 'waiting';
  if not found then raise exception 'Salle introuvable'; end if;

  if exists (select 1 from public.blackjack_room_players
             where room_id = v_room.id and user_id = v_uid) then
    raise exception 'Deja dans la salle';
  end if;

  select count(*) into v_count from public.blackjack_room_players
    where room_id = v_room.id;
  if v_count >= v_room.player_count then
    raise exception 'Salle pleine';
  end if;

  -- ===== TREASURY MIGRATION =====
  if v_room.bet_amount > 0 then
    perform public.treasury_place_bet(
      'blackjack', v_room.id::text, v_uid, v_room.bet_amount
    );
  end if;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  insert into public.blackjack_room_players(room_id, user_id, username)
    values (v_room.id, v_uid, v_username);

  return jsonb_build_object('room_id', v_room.id, 'joined', true);
end;
$function$;

grant execute on function public.bj_join_room(text) to authenticated;

-- ============================================================
-- 3) _bj_dealer_play - payouts via treasury (signature etendue)
-- ============================================================
-- IMPORTANT : on change la signature pour ajouter p_game_id (necessaire
-- pour les logs treasury_movements). On DROP l'ancienne version d'abord.
drop function if exists public._bj_dealer_play(jsonb);

create or replace function public._bj_dealer_play(
  p_state jsonb,
  p_game_id uuid
) returns jsonb
language plpgsql
as $function$
declare
  v_state jsonb := p_state;
  v_deck jsonb;
  v_dealer jsonb;
  v_cards jsonb;
  v_card jsonb;
  v_total int;
  v_aces int;
  v_key text;
  v_p jsonb;
  v_p_score int;
  v_results jsonb := '{}'::jsonb;
  v_d_status text;
  v_bet int;
begin
  v_state := jsonb_set(v_state, '{phase}', '"dealer_turn"'::jsonb);
  v_deck := v_state -> 'deck';
  v_dealer := v_state -> 'dealer';
  v_cards := v_dealer -> 'cards';

  -- Dealer tire jusqu'a 17+
  loop
    v_total := 0; v_aces := 0;
    for i in 0..jsonb_array_length(v_cards) - 1 loop
      declare v_r text := v_cards -> i ->> 'rank';
      begin
        if v_r = 'A' then v_total := v_total + 11; v_aces := v_aces + 1;
        elsif v_r in ('K','Q','J') then v_total := v_total + 10;
        else v_total := v_total + (v_r::int); end if;
      end;
    end loop;
    while v_total > 21 and v_aces > 0 loop
      v_total := v_total - 10; v_aces := v_aces - 1;
    end loop;

    exit when v_total >= 17;

    v_card := v_deck -> 0;
    if v_card is null then exit; end if;
    v_cards := v_cards || v_card;
    v_deck := (
      select coalesce(jsonb_agg(val), '[]'::jsonb)
      from (select val, row_number() over() as rn
            from jsonb_array_elements(v_deck) as val) t
      where rn > 1
    );
  end loop;

  v_d_status := case when v_total > 21 then 'bust' else 'stand' end;
  v_dealer := jsonb_build_object('cards', v_cards, 'status', v_d_status);
  v_state := jsonb_set(v_state, '{dealer}', v_dealer);
  v_state := jsonb_set(v_state, '{deck}', v_deck);

  -- Resoudre chaque joueur
  for v_key in select jsonb_object_keys(v_state -> 'players') loop
    v_p := v_state -> 'players' -> v_key;
    if (v_p -> 'hand' ->> 'status') = 'bust' then
      v_results := v_results || jsonb_build_object(v_key, 'lost');
      continue;
    end if;

    -- Calculer score joueur
    v_p_score := 0; v_aces := 0;
    for i in 0..jsonb_array_length(v_p -> 'hand' -> 'cards') - 1 loop
      declare v_r text := v_p -> 'hand' -> 'cards' -> i ->> 'rank';
      begin
        if v_r = 'A' then v_p_score := v_p_score + 11; v_aces := v_aces + 1;
        elsif v_r in ('K','Q','J') then v_p_score := v_p_score + 10;
        else v_p_score := v_p_score + (v_r::int); end if;
      end;
    end loop;
    while v_p_score > 21 and v_aces > 0 loop
      v_p_score := v_p_score - 10; v_aces := v_aces - 1;
    end loop;

    if v_total > 21 then
      v_results := v_results || jsonb_build_object(v_key, 'won');
    elsif v_p_score > v_total then
      v_results := v_results || jsonb_build_object(v_key, 'won');
    elsif v_p_score = v_total then
      v_results := v_results || jsonb_build_object(v_key, 'push');
    else
      v_results := v_results || jsonb_build_object(v_key, 'lost');
    end if;
  end loop;

  v_state := jsonb_set(v_state, '{results}', v_results);
  v_state := jsonb_set(v_state, '{phase}', '"finished"'::jsonb);
  v_state := jsonb_set(v_state, '{is_finished}', 'true'::jsonb);

  -- ===== TREASURY MIGRATION =====
  -- Distribuer les gains via la caisse :
  --   won  -> apply_game_payout(bet*2)  : 90% joueur, 10% caisse
  --   push -> treasury_refund_all([uid], bet) : refund 100% sans commission
  --   lost -> rien (mise reste a la caisse)
  for v_key in select jsonb_object_keys(v_results) loop
    v_bet := (v_state -> 'players' -> v_key ->> 'bet')::int;
    if v_bet <= 0 then continue; end if;

    if (v_results ->> v_key) = 'won' then
      perform public.apply_game_payout(
        'blackjack', p_game_id::text, v_key::uuid, v_bet * 2
      );
    elsif (v_results ->> v_key) = 'push' then
      perform public.treasury_refund_all(
        'blackjack', p_game_id::text, array[v_key::uuid], v_bet
      );
    end if;
    -- 'lost' : rien a faire, la mise reste a la caisse
  end loop;

  return v_state;
end;
$function$;

-- ============================================================
-- 4) _bj_next_turn - signature etendue avec p_game_id
-- ============================================================
drop function if exists public._bj_next_turn(jsonb);

create or replace function public._bj_next_turn(
  p_state jsonb,
  p_game_id uuid
) returns jsonb
language plpgsql
as $function$
declare
  v_state jsonb := p_state;
  v_turn_order jsonb;
  v_current text;
  v_next text;
  v_idx int;
  v_key text;
  v_p jsonb;
begin
  v_turn_order := v_state -> 'turn_order';
  v_current := v_state ->> 'current_turn';

  -- Trouver index courant
  v_idx := 0;
  for i in 0..jsonb_array_length(v_turn_order) - 1 loop
    if (v_turn_order ->> i) = v_current then v_idx := i; exit; end if;
  end loop;

  -- Chercher le prochain joueur encore en 'playing'
  v_next := null;
  for i in 1..jsonb_array_length(v_turn_order) loop
    declare v_ni int := ((v_idx + i) % jsonb_array_length(v_turn_order));
    begin
      v_key := v_turn_order ->> v_ni;
      v_p := v_state -> 'players' -> v_key;
      if (v_p -> 'hand' ->> 'status') = 'playing' then
        v_next := v_key; exit;
      end if;
    end;
  end loop;

  if v_next is not null then
    v_state := jsonb_set(v_state, '{current_turn}', to_jsonb(v_next));
    return v_state;
  end if;

  -- Tous les joueurs ont fini -> tour du dealer (avec payouts treasury)
  v_state := public._bj_dealer_play(v_state, p_game_id);
  return v_state;
end;
$function$;

-- ============================================================
-- 5) bj_hit - pass game_id a _bj_next_turn
-- ============================================================
create or replace function public.bj_hit(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_game record;
  v_uid text := auth.uid()::text;
  v_state jsonb;
  v_deck jsonb;
  v_players jsonb;
  v_player jsonb;
  v_hand jsonb;
  v_cards jsonb;
  v_card jsonb;
  v_total int;
  v_aces int;
begin
  select * into v_game from public.blackjack_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'Partie introuvable'; end if;

  v_state := v_game.game_state;
  if (v_state ->> 'current_turn') != v_uid then raise exception 'Pas votre tour'; end if;
  if (v_state ->> 'phase') != 'playing' then raise exception 'Phase incorrecte'; end if;

  v_deck := v_state -> 'deck';
  v_players := v_state -> 'players';
  v_player := v_players -> v_uid;
  v_hand := v_player -> 'hand';
  v_cards := v_hand -> 'cards';

  -- Tirer la premiere carte du deck
  v_card := v_deck -> 0;
  v_cards := v_cards || v_card;
  v_deck := (
    select coalesce(jsonb_agg(val), '[]'::jsonb)
    from (select val, row_number() over() as rn
          from jsonb_array_elements(v_deck) as val) t
    where rn > 1
  );

  -- Calculer le score
  v_total := 0; v_aces := 0;
  for i in 0..jsonb_array_length(v_cards) - 1 loop
    declare v_r text := v_cards -> i ->> 'rank';
    begin
      if v_r = 'A' then v_total := v_total + 11; v_aces := v_aces + 1;
      elsif v_r in ('K','Q','J') then v_total := v_total + 10;
      else v_total := v_total + (v_r::int); end if;
    end;
  end loop;
  while v_total > 21 and v_aces > 0 loop
    v_total := v_total - 10; v_aces := v_aces - 1;
  end loop;

  if v_total > 21 then
    v_hand := jsonb_build_object('cards', v_cards, 'status', 'bust');
  elsif v_total = 21 then
    v_hand := jsonb_build_object('cards', v_cards, 'status', 'stand');
  else
    v_hand := jsonb_build_object('cards', v_cards, 'status', 'playing');
  end if;

  v_player := jsonb_set(v_player, '{hand}', v_hand);
  v_players := jsonb_set(v_players, array[v_uid], v_player);
  v_state := jsonb_set(v_state, '{players}', v_players);
  v_state := jsonb_set(v_state, '{deck}', v_deck);

  if v_total >= 21 then
    v_state := public._bj_next_turn(v_state, p_game_id);
  end if;

  update public.blackjack_games
    set game_state = v_state, updated_at = now()
    where id = p_game_id;
end;
$function$;

grant execute on function public.bj_hit(uuid) to authenticated;

-- ============================================================
-- 6) bj_stand - pass game_id a _bj_next_turn
-- ============================================================
create or replace function public.bj_stand(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_game record;
  v_uid text := auth.uid()::text;
  v_state jsonb;
  v_players jsonb;
  v_player jsonb;
  v_hand jsonb;
begin
  select * into v_game from public.blackjack_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'Partie introuvable'; end if;

  v_state := v_game.game_state;
  if (v_state ->> 'current_turn') != v_uid then raise exception 'Pas votre tour'; end if;

  v_players := v_state -> 'players';
  v_player := v_players -> v_uid;
  v_hand := v_player -> 'hand';
  v_hand := jsonb_set(v_hand, '{status}', '"stand"'::jsonb);
  v_player := jsonb_set(v_player, '{hand}', v_hand);
  v_players := jsonb_set(v_players, array[v_uid], v_player);
  v_state := jsonb_set(v_state, '{players}', v_players);

  v_state := public._bj_next_turn(v_state, p_game_id);

  update public.blackjack_games
    set game_state = v_state, updated_at = now()
    where id = p_game_id;
end;
$function$;

grant execute on function public.bj_stand(uuid) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution :
--
-- Scenario 1 (bet 100, joueur 18, dealer 17 -> WON) :
--   - bj_create_room  : user1 -100, caisse +100
--   - bj_join_room    : user2 -100, caisse +100  (caisse = +200)
--   - _bj_dealer_play : apply_game_payout(bet*2 = 200) sur user gagnant
--                       -> 180 user (90%), 20 caisse (10%)
--   - Bilan caisse round = +200 - 180 = +20 (= 10% des gains payes)
--   - Bilan gagnant     = -100 + 180 = +80 net
--   - Bilan perdant     = -100
--   - Total systeme = 0 (zero creation)
--
-- Scenario 2 (bet 100, push joueur = dealer) :
--   - bj_create_room  : user1 -100, caisse +100
--   - bj_join_room    : user2 -100, caisse +200
--   - _bj_dealer_play : treasury_refund_all([user1, user2], 100) chacun
--                       -> 100 user1, 100 user2, caisse -200
--   - Bilan caisse = 0
--   - Bilan joueurs = 0 chacun (push neutre, AUCUNE commission)
--
-- Scenario 3 (bet 100, joueur bust) :
--   - bj_create_room/join : caisse +200
--   - _bj_dealer_play : 'lost' -> rien, mise reste a la caisse
--   - Bilan caisse = +100 par joueur perdant
--
-- Note : bj_start_game NON modifie (pas de mouvement money).
-- Les debits se font a create_room et join_room.
