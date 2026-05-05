-- ============================================================
-- COINFLIP - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql.
-- Idempotent : safe to re-run.
--
-- Patche les 3 fonctions critiques :
--   1. cf_create_room : debit du createur via treasury_place_bet
--      (avant : coins -= bet -> argent disparait du systeme)
--   2. cf_join_room : debit du joiner via treasury_place_bet
--   3. cf_choose_side : payout du winner via apply_game_payout (90% / 10%)
--
-- Resultat business : 10% de chaque pot Coinflip ramene dans la caisse.
-- ============================================================

-- ============================================================
-- 1) cf_create_room - debit createur via treasury
-- ============================================================
create or replace function public.cf_create_room(p_bet_amount integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid UUID := auth.uid();
  v_code TEXT;
  v_room_id UUID;
  v_username TEXT;
begin
  -- Generer code unique
  loop
    v_code := upper(substr(md5(random()::text), 1, 6));
    exit when not exists (select 1 from public.coinflip_rooms where code = v_code);
  end loop;

  -- Recuperer username
  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  -- Creer la room (avant le debit pour avoir un room_id pour le log)
  insert into public.coinflip_rooms (code, host_id, bet_amount)
    values (v_code, v_uid, p_bet_amount)
    returning id into v_room_id;

  insert into public.coinflip_room_players (room_id, user_id, username)
    values (v_room_id, v_uid, v_username);

  -- ===== TREASURY MIGRATION =====
  -- Debit createur : argent va dans la caisse super-admin (atomique)
  -- Si solde insuffisant : ROLLBACK auto -> room non creee
  if p_bet_amount > 0 then
    perform public.treasury_place_bet('coinflip', v_room_id::text, v_uid, p_bet_amount);
  end if;

  return jsonb_build_object('room_id', v_room_id, 'code', v_code);
end;
$function$;

grant execute on function public.cf_create_room(integer) to authenticated;

-- ============================================================
-- 2) cf_join_room - debit joiner via treasury + auto-start
-- ============================================================
create or replace function public.cf_join_room(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid UUID := auth.uid();
  v_room RECORD;
  v_username TEXT;
  v_game_id UUID;
  v_players JSONB := '{}'::jsonb;
  v_first TEXT;
  r RECORD;
begin
  select * into v_room from public.coinflip_rooms
    where code = upper(p_code) and status = 'waiting' for update;
  if not found then raise exception 'Salle introuvable'; end if;

  if exists (select 1 from public.coinflip_room_players
              where room_id = v_room.id and user_id = v_uid) then
    raise exception 'Deja dans la salle';
  end if;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  insert into public.coinflip_room_players (room_id, user_id, username)
    values (v_room.id, v_uid, v_username);

  -- Auto-start (duel : 2 joueurs)
  for r in select user_id, username from public.coinflip_room_players
            where room_id = v_room.id order by user_id
  loop
    v_players := v_players || jsonb_build_object(r.user_id::text, jsonb_build_object(
      'username', coalesce(r.username, 'Joueur'),
      'choice', null,
      'has_chosen', false));
    if v_first is null then v_first := r.user_id::text; end if;
  end loop;

  insert into public.coinflip_games (room_id, bet_amount, game_state, status)
  values (v_room.id, v_room.bet_amount,
    jsonb_build_object('players', v_players, 'result', null, 'winner_id', null,
      'phase', 'choosing', 'is_finished', false),
    'playing') returning id into v_game_id;

  update public.coinflip_rooms set status = 'playing', game_id = v_game_id
    where id = v_room.id;

  -- ===== TREASURY MIGRATION =====
  -- Debit joiner via la caisse (createur deja debite a cf_create_room)
  if v_room.bet_amount > 0 then
    perform public.treasury_place_bet('coinflip', v_game_id::text, v_uid, v_room.bet_amount);
  end if;

  return jsonb_build_object('room_id', v_room.id, 'game_id', v_game_id, 'started', true);
end;
$function$;

grant execute on function public.cf_join_room(text) to authenticated;

-- ============================================================
-- 3) cf_choose_side - payout via apply_game_payout
-- ============================================================
-- Quand les 2 joueurs ont choisi pile/face, on flip la piece.
-- Le winner est celui qui avait choisi le bon cote.
-- Au lieu de credit direct, apply_game_payout : 90% winner, 10% caisse.
create or replace function public.cf_choose_side(p_game_id uuid, p_choice text)
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
  v_key TEXT;
  v_all_chosen BOOLEAN := true;
  v_result TEXT;
  v_winner TEXT;
  v_pot INT;
begin
  if p_choice not in ('pile', 'face') then raise exception 'Choix invalide'; end if;

  select * into v_game from public.coinflip_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'Partie introuvable'; end if;

  v_state := v_game.game_state;
  if (v_state ->> 'phase') != 'choosing' then raise exception 'Phase incorrecte'; end if;

  v_players := v_state -> 'players';
  v_player := v_players -> v_uid;
  if (v_player ->> 'has_chosen')::boolean then raise exception 'Deja choisi'; end if;

  v_player := jsonb_set(v_player, '{choice}', to_jsonb(p_choice));
  v_player := jsonb_set(v_player, '{has_chosen}', 'true'::jsonb);
  v_players := jsonb_set(v_players, ARRAY[v_uid], v_player);
  v_state := jsonb_set(v_state, '{players}', v_players);

  -- Tous ont choisi ?
  for v_key in select jsonb_object_keys(v_players) loop
    if not ((v_players -> v_key ->> 'has_chosen')::boolean) then
      v_all_chosen := false;
      exit;
    end if;
  end loop;

  if v_all_chosen then
    -- Lancer la piece
    v_result := case when random() < 0.5 then 'pile' else 'face' end;
    v_state := jsonb_set(v_state, '{result}', to_jsonb(v_result));
    v_state := jsonb_set(v_state, '{phase}', '"flipping"'::jsonb);

    -- Trouver le gagnant
    for v_key in select jsonb_object_keys(v_players) loop
      if (v_players -> v_key ->> 'choice') = v_result then
        v_winner := v_key;
        exit;
      end if;
    end loop;

    v_state := jsonb_set(v_state, '{winner_id}', coalesce(to_jsonb(v_winner), 'null'::jsonb));
    v_state := jsonb_set(v_state, '{is_finished}', 'true'::jsonb);

    v_pot := v_game.bet_amount * 2;

    update public.coinflip_games
      set game_state = v_state, status = 'finished', updated_at = NOW()
      where id = p_game_id;

    -- ===== TREASURY MIGRATION =====
    -- Au lieu de credit direct, apply_game_payout : winner 90%, caisse 10%
    if v_winner is not null and v_pot > 0 then
      perform public.apply_game_payout('coinflip', p_game_id::text, v_winner::uuid, v_pot);
    end if;

  else
    update public.coinflip_games
      set game_state = v_state, updated_at = NOW()
      where id = p_game_id;
  end if;
end;
$function$;

grant execute on function public.cf_choose_side(uuid, text) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution recommandees :
--
-- 1. Lance une partie Coinflip (Alice cree room mise 50, Bob join, choix, flip)
-- 2. Apres cf_create_room : Alice debitee de 50, caisse +50
-- 3. Apres cf_join_room : Bob debite de 50, caisse +50 = 100
-- 4. Apres cf_choose_side (winner) : winner recoit 90, caisse +10 = 110-90=20 net
--
--    Wait : Initial caisse 0. Apres game complet :
--      caisse +50 (Alice) +50 (Bob) -90 (payout winner) = 10 = 10% du pot 100 ✓
--
-- 5. Verifie :
--    select * from public.treasury_summary;
--    select * from public.treasury_movements where game_type = 'coinflip'
--      order by created_at desc limit 10;
--
--    Tu dois voir pour chaque partie :
--    - 1 ligne 'loss_collect' (mise creator) avec game_id = room_id
--    - 1 ligne 'loss_collect' (mise joiner) avec game_id = v_game_id
--    - 1 ligne 'payout' au winner (90% du pot)
--    - 1 ligne 'house_cut' a la caisse (10% du pot)
--
-- Total systeme conservatif :
--   Avant : Alice 100 + Bob 100 + Caisse 0 = 200
--   Apres (Alice gagne) : Alice 50+90=140, Bob 50, Caisse 10 = 200 ✓
--
-- TODO : il existe peut-etre une fonction cf_auto_continue qui permet aux
-- 2 joueurs de relancer une partie. A migrer si elle gere les debits/credits.
-- Partage le SQL si tu veux la migrer aussi :
--   select pg_get_functiondef(oid) from pg_proc where proname = 'cf_auto_continue';
