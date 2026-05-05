-- ============================================================
-- CORA DICE - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql.
-- Idempotent : safe to re-run.
--
-- Patche :
--   1. create_cora_room : debit createur via treasury_place_bet
--   2. join_cora_room : debit joiner via treasury_place_bet
--   3. submit_cora_roll :
--      - SINGLE WINNER : apply_game_payout (90% / 10% caisse)
--      - MATCH NUL (>= 2 winners ou tous bust) : REFUND COMPLET sans
--        commission. Tous les joueurs recuperent leur mise integrale.
--        La caisse ne prend RIEN. Regle business : "le benefice n'est
--        prelevé QUE quand il y a un vainqueur clair."
--
-- Principe : la caisse ne touche jamais d'argent sur un match nul.
-- ============================================================

-- ============================================================
-- 0) Helper : treasury_refund_all (refund integral apres tie)
-- ============================================================
-- Refund chaque participant de sa mise initiale, AUCUNE commission.
-- A appeler en cas de match nul (>= 2 ex-aequo, ou tous bust).
-- Contrairement a treasury_settle_draw qui peut appliquer le edge,
-- ici c'est toujours 100% refund.
create or replace function public.treasury_refund_all(
  p_game_type text,
  p_game_id text,
  p_user_ids uuid[],
  p_amount_per_user int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_total int;
begin
  if p_amount_per_user <= 0 then return; end if;

  v_total := p_amount_per_user * array_length(p_user_ids, 1);

  -- Refund chaque participant
  foreach v_user_id in array p_user_ids loop
    update public.user_profiles
      set coins = coins + p_amount_per_user, updated_at = now()
      where id = v_user_id;

    insert into public.treasury_movements
      (game_type, game_id, user_id, movement_type, amount)
      values (p_game_type, p_game_id, v_user_id, 'refund', p_amount_per_user);
  end loop;

  -- Decrement la caisse (qui contient les mises depuis place_bet)
  update public.treasury_balance
    set balance = balance - v_total,
        total_out = total_out + v_total,
        updated_at = now()
    where id = 1;
end;
$$;

grant execute on function public.treasury_refund_all(text, text, uuid[], int) to authenticated;

-- ============================================================
-- 1) create_cora_room - debit createur via treasury
-- ============================================================
create or replace function public.create_cora_room(
  p_player_count integer default 2,
  p_bet_amount integer default 200,
  p_is_private boolean default false
)
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
    exit when not exists (select 1 from public.cora_rooms where code = v_code);
  end loop;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  -- Creer la room AVANT le debit (pour avoir un room_id pour le log)
  insert into public.cora_rooms
    (code, host_id, player_count, bet_amount, is_private, host_username)
    values (v_code, v_uid, p_player_count, p_bet_amount, p_is_private, v_username)
    returning id into v_room_id;

  insert into public.cora_room_players (room_id, user_id, username, is_ready)
    values (v_room_id, v_uid, v_username, false);

  -- ===== TREASURY MIGRATION =====
  -- Debit createur via la caisse (atomique, verifie solde, log auto)
  if p_bet_amount > 0 then
    perform public.treasury_place_bet('cora_dice', v_room_id::text, v_uid, p_bet_amount);
  end if;

  return jsonb_build_object('room_id', v_room_id, 'code', v_code);
end;
$function$;

grant execute on function public.create_cora_room(integer, integer, boolean) to authenticated;

-- ============================================================
-- 2) join_cora_room - debit joiner via treasury
-- ============================================================
create or replace function public.join_cora_room(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid UUID := auth.uid();
  v_room RECORD;
  v_count INT;
  v_username TEXT;
begin
  select * into v_room from public.cora_rooms
    where code = upper(p_code) and status = 'waiting';
  if not found then raise exception 'Salle introuvable ou deja demarree'; end if;

  if exists (select 1 from public.cora_room_players
              where room_id = v_room.id and user_id = v_uid) then
    raise exception 'Deja dans cette salle';
  end if;

  select count(*) into v_count from public.cora_room_players where room_id = v_room.id;
  if v_count >= v_room.player_count then raise exception 'Cette salle est deja pleine'; end if;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  insert into public.cora_room_players (room_id, user_id, username, is_ready)
    values (v_room.id, v_uid, v_username, false);

  -- ===== TREASURY MIGRATION =====
  -- Debit joiner via la caisse
  if v_room.bet_amount > 0 then
    perform public.treasury_place_bet('cora_dice', v_room.id::text, v_uid, v_room.bet_amount);
  end if;

  return jsonb_build_object('room_id', v_room.id, 'joined', true);
end;
$function$;

grant execute on function public.join_cora_room(text) to authenticated;

-- ============================================================
-- 3) submit_cora_roll - payout via apply_game_payout / refund_all
-- ============================================================
-- - Single winner : apply_game_payout -> 90% winner, 10% caisse
-- - Match nul (tie / tous bust) : treasury_refund_all -> chaque joueur
--   recupere sa mise integrale, AUCUNE commission pour la caisse.
create or replace function public.submit_cora_roll(p_game_id uuid, p_dice1 integer, p_dice2 integer)
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
  v_score INT;
  v_roll JSONB;
  v_turn_keys TEXT[];
  v_next_turn TEXT;
  v_current_idx INT;
  v_all_rolled BOOLEAN := true;
  v_key TEXT;
  v_p JSONB;
  v_pot INT;
  v_winner_uuids UUID[];
  v_all_participants UUID[];
begin
  select * into v_game from public.cora_games where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'Partie introuvable'; end if;

  v_state := v_game.game_state;
  v_players := v_state -> 'players';
  v_player := v_players -> v_uid;

  if v_player is null then raise exception 'Joueur non trouve'; end if;
  if (v_player -> 'roll') is not null and jsonb_typeof(v_player -> 'roll') != 'null' then
    raise exception 'Deja lance';
  end if;

  if (v_state ->> 'current_turn') != v_uid then
    raise exception 'Pas votre tour';
  end if;

  v_score := p_dice1 + p_dice2;
  v_roll := jsonb_build_object('dice1', p_dice1, 'dice2', p_dice2);

  v_player := jsonb_set(v_player, '{roll}', v_roll);
  v_player := jsonb_set(v_player, '{final_score}', to_jsonb(v_score));
  v_players := jsonb_set(v_players, ARRAY[v_uid], v_player);
  v_state := jsonb_set(v_state, '{players}', v_players);

  -- Recuperer l'ordre des joueurs
  select array_agg(k) into v_turn_keys from jsonb_object_keys(v_players) as k;

  -- Trouver l'index du joueur courant
  v_next_turn := null;
  v_current_idx := 0;
  for i in 1..array_length(v_turn_keys, 1) loop
    if v_turn_keys[i] = v_uid then v_current_idx := i; end if;
  end loop;

  -- Chercher le prochain joueur non lance (en boucle)
  for i in 1..array_length(v_turn_keys, 1) loop
    declare v_idx int := ((v_current_idx - 1 + i) % array_length(v_turn_keys, 1)) + 1;
    begin
      v_p := v_players -> v_turn_keys[v_idx];
      if (v_p -> 'roll') is null or jsonb_typeof(v_p -> 'roll') = 'null' then
        v_next_turn := v_turn_keys[v_idx];
        exit;
      end if;
    end;
  end loop;

  -- Verifier si tous ont joue
  for v_key in select jsonb_object_keys(v_players)
  loop
    v_p := v_players -> v_key;
    if (v_p -> 'roll') is null or jsonb_typeof(v_p -> 'roll') = 'null' then
      v_all_rolled := false;
      exit;
    end if;
  end loop;

  if v_all_rolled then
    -- Determiner le(s) gagnant(s)
    declare
      v_max_score INT := -1;
      v_winners TEXT[] := ARRAY[]::TEXT[];
      v_cora_count INT := 0;
      v_p_score INT;
      v_is_cora BOOLEAN;
      v_has_seven BOOLEAN;
    begin
      for v_key in select jsonb_object_keys(v_players)
      loop
        v_p := v_players -> v_key;
        v_is_cora := (v_p -> 'roll' ->> 'dice1') = (v_p -> 'roll' ->> 'dice2');
        if v_is_cora then v_cora_count := v_cora_count + 1; end if;
      end loop;

      for v_key in select jsonb_object_keys(v_players)
      loop
        v_p := v_players -> v_key;
        v_p_score := (v_p ->> 'final_score')::int;
        v_has_seven := (v_p_score = 7);
        v_is_cora := (v_p -> 'roll' ->> 'dice1') = (v_p -> 'roll' ->> 'dice2');

        if v_has_seven then continue; end if;
        if v_cora_count > 1 and v_is_cora then continue; end if;

        if v_cora_count = 1 and v_is_cora then
          v_winners := ARRAY[v_key];
          v_max_score := 999;
          exit;
        end if;

        if v_p_score > v_max_score then
          v_max_score := v_p_score;
          v_winners := ARRAY[v_key];
        elsif v_p_score = v_max_score then
          v_winners := array_append(v_winners, v_key);
        end if;
      end loop;

      v_state := jsonb_set(v_state, '{is_finished}', 'true'::jsonb);
      v_state := jsonb_set(v_state, '{winners}', to_jsonb(v_winners));
      v_state := jsonb_set(v_state, '{result}', '"Partie terminee"'::jsonb);

      update public.cora_games
        set game_state = v_state, status = 'finished',
            winner_ids = v_winners::uuid[],
            updated_at = NOW()
        where id = p_game_id;

      -- ===== TREASURY MIGRATION =====
      v_pot := v_game.bet_amount * v_game.player_count;

      if v_pot > 0 then
        if array_length(v_winners, 1) = 1 then
          -- VAINQUEUR UNIQUE : 90% au winner, 10% caisse
          v_winner_uuids := v_winners::uuid[];
          perform public.apply_game_payout('cora_dice', p_game_id::text,
                                           v_winner_uuids[1], v_pot);
        else
          -- MATCH NUL (>= 2 winners OU tous bust a 7) :
          -- Refund integral a TOUS les participants. Caisse ne prend RIEN.
          -- Regle business : la caisse ne touche que sur un vrai vainqueur.
          select array_agg(k::uuid) into v_all_participants
            from jsonb_object_keys(v_players) as k;
          perform public.treasury_refund_all('cora_dice', p_game_id::text,
                                             v_all_participants, v_game.bet_amount);
        end if;
      end if;

      return;
    end;
  else
    -- Passer au joueur suivant
    if v_next_turn is not null then
      v_state := jsonb_set(v_state, '{current_turn}', to_jsonb(v_next_turn));
    end if;
  end if;

  update public.cora_games set game_state = v_state, updated_at = NOW() where id = p_game_id;
end;
$function$;

grant execute on function public.submit_cora_roll(uuid, integer, integer) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution recommandees :
--
-- Scenario 1 (single winner, 2 joueurs, mise 200) :
--   Avant : Alice 1000 + Bob 1000 = 2000
--   Debits : Alice -200, Bob -200, Caisse +400
--   Alice gagne : Alice +360 (90%), Caisse +40 (10%)
--   Apres : Alice 1160 + Bob 800 + Caisse 40 = 2000 ✓
--
-- Scenario 2 (MATCH NUL, 2 joueurs ex-aequo, mise 200) :
--   Avant : Alice 1000 + Bob 1000 = 2000
--   Debits : -200 chacun, Caisse +400
--   MATCH NUL : refund integral 200 chacun, Caisse -400
--   Apres : Alice 1000 + Bob 1000 + Caisse 0 = 2000 ✓
--   AUCUN benefice pour la maison sur un match nul.
--
-- Scenario 3 (tie 3 joueurs, 2 ex-aequo, 1 perdant, mise 100) :
--   Tous remboursés (y compris le perdant) : tous a 1000, caisse 0.
--
-- Verifier dans treasury_movements :
--   - 'loss_collect' x N (mises debitees)
--   - 'payout' + 'house_cut' SI vainqueur unique
--   - 'refund' x N (sans 'house_cut') SI match nul
