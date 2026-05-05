-- ============================================================
-- LUDO V2 - Migration vers le treasury unifie (COMPLETE)
-- ============================================================
-- A executer APRES treasury_unified.sql.
-- Idempotent : safe to re-run.
--
-- Patche les 3 fonctions critiques :
--   1. ludo_v2_start_game : debite tous les joueurs via treasury_place_bet
--      (FIX du bug : avant, mises jamais debitees -> creation d'argent)
--   2. ludo_v2_play_move : winner via apply_game_payout (93% / 7%)
--   3. ludo_v2_forfeit : idem
--
-- Resultat business : la caisse super-admin recoit 7% de chaque pot Ludo V2.
-- ============================================================

-- ============================================================
-- 1) ludo_v2_start_game - debit atomique de tous les joueurs
-- ============================================================
-- AVANT le patch :
--   Insere la game row, met la room en playing.
--   AUCUN debit ! Bug critique : winner recoit du free money a la fin.
-- APRES :
--   Insere la game row, debite CHAQUE joueur du turn_order via la caisse,
--   puis met la room en playing.
--   Si un joueur n'a pas assez (rare apres le pre-check UI), ROLLBACK auto
--   et la partie n'est pas creee.
create or replace function public.ludo_v2_start_game(p_room_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_game_id UUID;
  v_pawns JSONB := '{}'::jsonb;
  v_color_map JSONB := '{}'::jsonb;
  v_turn_order UUID[] := ARRAY[]::UUID[];
  v_first UUID;
  v_bet INT;
  v_player_uid UUID;
  r RECORD;
begin
  for r in select user_id, slot from public.ludo_v2_room_players where room_id = p_room_id order by slot
  loop
    v_pawns := v_pawns || jsonb_build_object(r.user_id::text, jsonb_build_array(0,0,0,0));
    v_color_map := v_color_map || jsonb_build_object(r.user_id::text, r.slot);
    v_turn_order := array_append(v_turn_order, r.user_id);
  end loop;

  if array_length(v_turn_order, 1) is null or array_length(v_turn_order, 1) < 2 then
    raise exception 'Pas assez de joueurs';
  end if;

  if v_pawns is null or v_pawns = '{}'::jsonb then
    raise exception 'Erreur construction pawns: %', v_pawns;
  end if;

  v_first := v_turn_order[1];

  -- Recuperer la mise de la room
  select bet_amount into v_bet from public.ludo_v2_rooms where id = p_room_id;

  -- Inserer la game (avant le debit pour avoir un game_id pour les logs)
  insert into public.ludo_v2_games (room_id, pawns, current_turn, turn_order, color_map, bet_amount)
  values (p_room_id, v_pawns, v_first, v_turn_order, v_color_map, v_bet)
  returning id into v_game_id;

  -- ===== TREASURY MIGRATION : debiter tous les joueurs =====
  -- Si l'un d'entre eux n'a pas assez de coins, ROLLBACK -> partie annulee.
  -- treasury_place_bet est atomique (lock + verif + debit + log + caisse).
  if v_bet > 0 then
    foreach v_player_uid in array v_turn_order loop
      perform public.treasury_place_bet('ludo_v2', v_game_id::text, v_player_uid, v_bet);
    end loop;
  end if;

  update public.ludo_v2_rooms set status = 'playing', game_id = v_game_id where id = p_room_id;
  return v_game_id;
end;
$function$;

grant execute on function public.ludo_v2_start_game(uuid) to authenticated;

-- ============================================================
-- 2) ludo_v2_play_move - payout via apply_game_payout
-- ============================================================
-- Quand un joueur gagne (tous pions a 58), au lieu du credit direct,
-- on appelle apply_game_payout : winner recoit 93% du pot, caisse 7%.
create or replace function public.ludo_v2_play_move(p_game_id uuid, p_pawn_index integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_game RECORD;
  v_uid UUID := auth.uid();
  v_uid_text TEXT;
  v_pawns JSONB;
  v_my_pawns JSONB;
  v_current_step INT;
  v_new_step INT;
  v_dice INT;
  v_captured BOOLEAN := false;
  v_won BOOLEAN := false;
  v_extra_turn BOOLEAN := false;
  v_next_turn UUID;
  v_my_color INT;
  v_my_offset INT;
  v_opp_key TEXT;
  v_opp_pawns JSONB;
  v_opp_color INT;
  v_opp_offset INT;
  v_my_abs INT;
  v_opp_abs INT;
  v_opp_step INT;
  v_offsets INT[] := ARRAY[0, 39, 26, 13];
  v_safe_cells INT[] := ARRAY[0, 8, 13, 21, 26, 34, 39, 47];
  v_turn_order UUID[];
  v_turn_idx INT;
  v_pot INT;
  i INT;
begin
  v_uid_text := v_uid::text;
  select * into v_game from public.ludo_v2_games where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'Partie introuvable'; end if;
  if v_game.current_turn != v_uid then raise exception 'Pas votre tour'; end if;
  if not v_game.dice_rolled then raise exception 'Lancez le de'; end if;
  if p_pawn_index < 0 or p_pawn_index > 3 then raise exception 'Pion invalide'; end if;
  if v_game.pawns is null then raise exception 'pawns est NULL'; end if;

  v_dice := v_game.dice_value;
  v_pawns := v_game.pawns;
  v_my_pawns := v_pawns -> v_uid_text;
  if v_my_pawns is null then raise exception 'Joueur absent'; end if;

  v_current_step := (v_my_pawns ->> p_pawn_index)::int;
  if v_current_step is null then raise exception 'Pion null'; end if;

  if v_current_step = 0 then
    if v_dice != 6 then raise exception '6 requis'; end if;
    v_new_step := 1;
  elsif v_current_step >= 58 then
    raise exception 'Deja arrive';
  else
    v_new_step := v_current_step + v_dice;
    if v_new_step > 58 then raise exception 'Score exact requis'; end if;
  end if;

  v_my_pawns := jsonb_set(v_my_pawns, ARRAY[p_pawn_index::text], to_jsonb(v_new_step));
  v_pawns := jsonb_set(v_pawns, ARRAY[v_uid_text], v_my_pawns);

  if v_new_step >= 1 and v_new_step <= 51 then
    v_my_color := (v_game.color_map ->> v_uid_text)::int;
    v_my_offset := v_offsets[v_my_color + 1];
    v_my_abs := ((v_new_step - 1) + v_my_offset) % 52;

    if not (v_my_abs = ANY(v_safe_cells)) then
      for v_opp_key in select jsonb_object_keys(v_pawns)
      loop
        if v_opp_key = v_uid_text then continue; end if;
        v_opp_color := (v_game.color_map ->> v_opp_key)::int;
        v_opp_offset := v_offsets[v_opp_color + 1];
        v_opp_pawns := v_pawns -> v_opp_key;
        for i in 0..3 loop
          v_opp_step := (v_opp_pawns ->> i)::int;
          if v_opp_step >= 1 and v_opp_step <= 51 then
            v_opp_abs := ((v_opp_step - 1) + v_opp_offset) % 52;
            if v_opp_abs = v_my_abs then
              v_opp_pawns := jsonb_set(v_opp_pawns, ARRAY[i::text], '0'::jsonb);
              v_captured := true;
            end if;
          end if;
        end loop;
        if v_captured then
          v_pawns := jsonb_set(v_pawns, ARRAY[v_opp_key], v_opp_pawns);
        end if;
      end loop;
    end if;
  end if;

  v_won := true;
  for i in 0..3 loop
    if (v_my_pawns ->> i)::int < 58 then v_won := false; exit; end if;
  end loop;

  v_extra_turn := (v_dice = 6) or v_captured;
  v_turn_order := v_game.turn_order;

  if v_won then
    update public.ludo_v2_games
    set pawns = v_pawns, status = 'finished', winner_id = v_uid,
        dice_rolled = false, dice_value = NULL, last_move_by = v_uid,
        turn_number = v_game.turn_number + 1, updated_at = NOW()
    where id = p_game_id;

    -- ===== TREASURY MIGRATION =====
    if v_game.bet_amount > 0 then
      v_pot := v_game.bet_amount * array_length(v_turn_order, 1);
      perform public.apply_game_payout('ludo_v2', p_game_id::text, v_uid, v_pot);
    end if;

    return jsonb_build_object('captured', v_captured, 'won', true, 'extra_turn', false);
  end if;

  if v_extra_turn then
    v_next_turn := v_uid;
  else
    v_turn_idx := 1;
    for i in 1..array_length(v_turn_order, 1) loop
      if v_turn_order[i] = v_uid then v_turn_idx := i; exit; end if;
    end loop;
    v_turn_idx := (v_turn_idx % array_length(v_turn_order, 1)) + 1;
    v_next_turn := v_turn_order[v_turn_idx];
  end if;

  update public.ludo_v2_games
  set pawns = v_pawns, current_turn = v_next_turn, dice_rolled = false, dice_value = NULL,
      last_move_by = v_uid, turn_number = v_game.turn_number + 1, updated_at = NOW()
  where id = p_game_id;

  return jsonb_build_object('captured', v_captured, 'won', false, 'extra_turn', v_extra_turn);
end;
$function$;

grant execute on function public.ludo_v2_play_move(uuid, integer) to authenticated;

-- ============================================================
-- 3) ludo_v2_forfeit - payout via apply_game_payout
-- ============================================================
-- Quand un joueur abandonne, le pot va au "premier adversaire" (winner
-- determine par turn_order). Au lieu de credit direct, apply_game_payout.
create or replace function public.ludo_v2_forfeit(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_game RECORD;
  v_uid UUID := auth.uid();
  v_winner UUID;
  v_pot INT;
  i INT;
begin
  select * into v_game from public.ludo_v2_games where id = p_game_id and status = 'playing' for update;
  if not found then return; end if;

  -- Trouver le premier adversaire comme gagnant
  for i in 1..array_length(v_game.turn_order, 1) loop
    if v_game.turn_order[i] != v_uid then
      v_winner := v_game.turn_order[i];
      exit;
    end if;
  end loop;

  update public.ludo_v2_games
  set status = 'finished', winner_id = v_winner, updated_at = NOW()
  where id = p_game_id;

  -- ===== TREASURY MIGRATION =====
  if v_game.bet_amount > 0 and v_winner is not null then
    v_pot := v_game.bet_amount * array_length(v_game.turn_order, 1);
    perform public.apply_game_payout('ludo_v2', p_game_id::text, v_winner, v_pot);
  end if;
end;
$function$;

grant execute on function public.ludo_v2_forfeit(uuid) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution recommandees :
--
-- 1. Lance une partie Ludo V2 (2 joueurs, mise 50)
-- 2. Verifie que les 2 joueurs sont debites a v_start_game (-50 chacun)
-- 3. Termine la partie (winner gagne)
-- 4. Verifie : winner recoit 93 (pot 100 - 7% caisse), perdant garde 0
-- 5. Verifie le solde caisse : +7 par partie
--    select * from public.treasury_summary;
--
-- 6. Verifie les mouvements dans treasury_movements :
--    select created_at, movement_type, amount, edge_pct, user_id
--    from public.treasury_movements
--    where game_type = 'ludo_v2'
--    order by created_at desc limit 20;
--
--    Tu dois voir pour chaque partie :
--    - 2 lignes 'loss_collect' (mises debitees) au depart
--    - 1 ligne 'payout' au winner (93% du pot)
--    - 1 ligne 'house_cut' a la caisse (7% du pot)
--
-- Total systeme conservatif :
--   Avant partie : Alice 80 + Bob 80 = 160
--   Apres partie : Alice 30 + Bob 123 + Caisse 7 = 160 (Alice perd, Bob gagne)
