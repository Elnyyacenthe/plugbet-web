-- ============================================================
-- ROULETTE - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_final_fix.sql.
-- Idempotent : safe to re-run.
--
-- Patche :
--   1. rlt_place_bet : debit via treasury_place_bet (caisse +mise)
--   2. rlt_spin : payout via apply_game_payout (90% winner, 10% caisse)
--
-- Note : la roulette permet plusieurs paris par partie. Chaque mise
-- va a la caisse. Au spin, chaque joueur gagnant recoit 90% de son
-- gain brut (= bet * multiplicateur), 10% reste a la maison.
--
-- Resultat :
--   - Bet sur 0 : tout le monde perd, caisse garde tout (+ pas de payout)
--   - Bet sur red qui gagne : payout 200 -> 180 user + 20 caisse (10%)
--   - Bet sur number qui gagne : payout 35x -> 90% user + 10% caisse
-- ============================================================

-- ============================================================
-- 1) rlt_place_bet - debit via treasury
-- ============================================================
create or replace function public.rlt_place_bet(p_game_id uuid, p_type text, p_amount integer, p_number integer default null)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_game RECORD;
  v_uid TEXT := auth.uid()::text;
  v_state JSONB;
  v_players JSONB;
  v_player JSONB;
  v_bets JSONB;
begin
  select * into v_game from public.roulette_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'Partie introuvable'; end if;

  v_state := v_game.game_state;
  if (v_state ->> 'phase') != 'betting' then raise exception 'Paris fermes'; end if;
  if p_amount < v_game.min_bet then
    raise exception 'Mise minimum: %', v_game.min_bet;
  end if;

  -- ===== TREASURY MIGRATION =====
  -- Debit via la caisse (atomique, verifie solde, log auto)
  perform public.treasury_place_bet('roulette', p_game_id::text, v_uid::uuid, p_amount);

  -- Mettre a jour le game_state avec le nouveau pari
  v_players := v_state -> 'players';
  v_player := v_players -> v_uid;
  v_bets := coalesce(v_player -> 'bets', '[]'::jsonb);
  v_bets := v_bets || jsonb_build_object(
    'user_id', v_uid,
    'type', p_type,
    'amount', p_amount,
    'number', p_number
  );
  v_player := jsonb_set(v_player, '{bets}', v_bets);
  v_player := jsonb_set(v_player, '{total_bet}',
    to_jsonb(coalesce((v_player ->> 'total_bet')::int, 0) + p_amount));
  v_players := jsonb_set(v_players, ARRAY[v_uid], v_player);
  v_state := jsonb_set(v_state, '{players}', v_players);

  update public.roulette_games set game_state = v_state, updated_at = NOW()
    where id = p_game_id;
end;
$function$;

grant execute on function public.rlt_place_bet(uuid, text, integer, integer) to authenticated;

-- ============================================================
-- 2) rlt_spin - payout via apply_game_payout (90% / 10% caisse)
-- ============================================================
-- Pour chaque joueur ayant un gain brut > 0 :
--   apply_game_payout splitte 90% au winner, 10% caisse.
-- Pour les perdants : leur mise reste a la caisse (deja debitee a place_bet).
create or replace function public.rlt_spin(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_game RECORD;
  v_state JSONB;
  v_result INT;
  v_players JSONB;
  v_key TEXT;
  v_player JSONB;
  v_bets JSONB;
  v_total_win INT;
  v_red INT[] := ARRAY[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36];
  v_bet_type TEXT;
  v_bet_num INT;
  v_bet_amt INT;
  v_won BOOLEAN;
begin
  select * into v_game from public.roulette_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'Partie introuvable'; end if;

  v_state := v_game.game_state;
  if (v_state ->> 'phase') != 'betting' then raise exception 'Deja lance'; end if;

  v_result := floor(random() * 37)::int;
  v_state := jsonb_set(v_state, '{result}', to_jsonb(v_result));
  v_state := jsonb_set(v_state, '{phase}', '"spinning"'::jsonb);

  v_players := v_state -> 'players';

  for v_key in select jsonb_object_keys(v_players) loop
    v_player := v_players -> v_key;
    v_bets := v_player -> 'bets';
    v_total_win := 0;

    for i in 0..greatest(jsonb_array_length(v_bets) - 1, 0) loop
      if jsonb_array_length(v_bets) = 0 then exit; end if;
      v_bet_type := v_bets -> i ->> 'type';
      v_bet_amt := (v_bets -> i ->> 'amount')::int;
      v_bet_num := (v_bets -> i ->> 'number')::int;
      v_won := false;

      if v_result = 0 then
        v_won := false;
      elsif v_bet_type = 'number' and v_bet_num = v_result then
        v_won := true; v_total_win := v_total_win + v_bet_amt * 35;
      elsif v_bet_type = 'red' and v_result = ANY(v_red) then
        v_won := true; v_total_win := v_total_win + v_bet_amt * 2;
      elsif v_bet_type = 'black' and not (v_result = ANY(v_red)) then
        v_won := true; v_total_win := v_total_win + v_bet_amt * 2;
      elsif v_bet_type = 'even' and v_result % 2 = 0 then
        v_won := true; v_total_win := v_total_win + v_bet_amt * 2;
      elsif v_bet_type = 'odd' and v_result % 2 = 1 then
        v_won := true; v_total_win := v_total_win + v_bet_amt * 2;
      elsif v_bet_type = 'low' and v_result between 1 and 18 then
        v_won := true; v_total_win := v_total_win + v_bet_amt * 2;
      elsif v_bet_type = 'high' and v_result between 19 and 36 then
        v_won := true; v_total_win := v_total_win + v_bet_amt * 2;
      end if;
    end loop;

    -- Stocker le gain brut (avant cut) dans le game_state pour l'affichage
    v_player := jsonb_set(v_player, '{winnings}', to_jsonb(v_total_win));
    -- Stocker aussi le gain NET apres cut 10% (ce que le user recoit reellement)
    v_player := jsonb_set(v_player, '{net_winnings}',
      to_jsonb(floor(v_total_win * 0.90)::int));
    v_players := jsonb_set(v_players, ARRAY[v_key], v_player);

    -- ===== TREASURY MIGRATION =====
    -- Si gain brut > 0 : payout 90% au winner + 10% reste a la caisse.
    -- (apply_game_payout fait tout : credit user, debit caisse, log).
    if v_total_win > 0 then
      perform public.apply_game_payout('roulette', p_game_id::text,
                                       v_key::uuid, v_total_win);
    end if;
    -- Si v_total_win = 0 : le joueur a perdu tous ses paris.
    -- Sa mise est deja dans la caisse (via place_bet). Rien a faire.
  end loop;

  v_state := jsonb_set(v_state, '{players}', v_players);
  v_state := jsonb_set(v_state, '{is_finished}', 'true'::jsonb);
  v_state := jsonb_set(v_state, '{phase}', '"finished"'::jsonb);

  update public.roulette_games
    set game_state = v_state, status = 'finished', updated_at = NOW()
    where id = p_game_id;
end;
$function$;

grant execute on function public.rlt_spin(uuid) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution :
--
-- Scenario 1 (bet 100 sur 'red', red sort) :
--   - rlt_place_bet : user -100, caisse +100
--   - rlt_spin (red) : gain brut 200, payout 180 (90%), caisse +20 (10%)
--   - Bilan user : -100 + 180 = +80 net
--   - Bilan caisse : +100 - 180 = -80 (negatif ce round, normal)
--   - Total systeme : 0 (zero creation)
--
-- Scenario 2 (bet 100 sur 'red', noir sort) :
--   - rlt_place_bet : user -100, caisse +100
--   - rlt_spin (black) : gain brut 0, pas de payout
--   - Bilan user : -100 (perte)
--   - Bilan caisse : +100 (la mise reste)
--
-- Scenario 3 (bet 100 sur '5', 5 sort) :
--   - rlt_place_bet : user -100, caisse +100
--   - rlt_spin (5) : gain brut 100*35 = 3500, payout 3150 (90%), caisse +350
--   - Bilan caisse : +100 - 3150 = -3050 (negatif fortement, mais rare ~1/37)
--
-- Scenario 4 (resultat 0, tous les paris perdent) :
--   - Tous les bets restent dans la caisse, aucun payout.
--
-- Note : rlt_create_room, rlt_join_room, rlt_start_game ne sont PAS
-- modifiees car elles ne touchent pas a l'argent. Le debit/credit
-- se fait seulement dans place_bet et spin.
