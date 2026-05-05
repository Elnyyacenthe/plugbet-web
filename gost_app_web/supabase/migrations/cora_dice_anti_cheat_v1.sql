-- ============================================================
-- CORA DICE - Anti-cheat : dés générés SERVEUR
-- ============================================================
-- A executer APRES cora_dice_treasury_migration.sql.
--
-- BUG CRITIQUE :
--   Avant : le client envoyait p_dice1 et p_dice2 que le serveur acceptait
--   tels quels. Un attaquant pouvait toujours envoyer (6,6) ou n'importe quel
--   score gagnant.
--
-- FIX :
--   Le serveur genere lui-meme les des via random() et retourne le resultat
--   au client (jsonb avec dice1, dice2, score). Le client se contente
--   d'afficher.
-- ============================================================

-- DROP l'ancienne signature (parametres p_dice1, p_dice2)
drop function if exists public.submit_cora_roll(uuid, integer, integer);

-- Nouvelle version : aucun parametre dice, generation serveur, retour jsonb
create or replace function public.submit_cora_roll(p_game_id uuid)
returns jsonb
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
  v_dice1 INT;
  v_dice2 INT;
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
  v_result JSONB;
begin
  select * into v_game from public.cora_games
    where id = p_game_id and status = 'playing' for update;
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

  -- ===== ANTI-CHEAT : DES GENERES SERVEUR =====
  v_dice1 := floor(random() * 6 + 1)::int;
  v_dice2 := floor(random() * 6 + 1)::int;
  v_score := v_dice1 + v_dice2;
  v_roll := jsonb_build_object('dice1', v_dice1, 'dice2', v_dice2);

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

  -- Prochain joueur non lance (en boucle)
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

  -- Tous ont joue ?
  for v_key in select jsonb_object_keys(v_players) loop
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
      for v_key in select jsonb_object_keys(v_players) loop
        v_p := v_players -> v_key;
        v_is_cora := (v_p -> 'roll' ->> 'dice1') = (v_p -> 'roll' ->> 'dice2');
        if v_is_cora then v_cora_count := v_cora_count + 1; end if;
      end loop;

      for v_key in select jsonb_object_keys(v_players) loop
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

      -- ===== TREASURY =====
      v_pot := v_game.bet_amount * v_game.player_count;

      if v_pot > 0 then
        if array_length(v_winners, 1) = 1 then
          v_winner_uuids := v_winners::uuid[];
          perform public.apply_game_payout('cora_dice', p_game_id::text,
                                           v_winner_uuids[1], v_pot);
        else
          select array_agg(k::uuid) into v_all_participants
            from jsonb_object_keys(v_players) as k;
          perform public.treasury_refund_all('cora_dice', p_game_id::text,
                                             v_all_participants, v_game.bet_amount);
        end if;
      end if;
    end;
  else
    if v_next_turn is not null then
      v_state := jsonb_set(v_state, '{current_turn}', to_jsonb(v_next_turn));
    end if;
    update public.cora_games
      set game_state = v_state, updated_at = NOW()
      where id = p_game_id;
  end if;

  -- Retour jsonb : le client recoit les dice + score qu'il doit afficher
  v_result := jsonb_build_object(
    'dice1', v_dice1,
    'dice2', v_dice2,
    'score', v_score,
    'is_finished', v_all_rolled
  );
  return v_result;
end;
$function$;

grant execute on function public.submit_cora_roll(uuid) to authenticated;

-- ============================================================
-- Cleanup rooms abandonnees (refund createur)
-- ============================================================
create or replace function public.cora_dice_cleanup_stale_rooms()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room record;
  v_user_ids uuid[];
  v_count int := 0;
begin
  for v_room in
    select * from public.cora_rooms
    where status = 'waiting'
      and created_at < now() - interval '1 hour'
  loop
    if v_room.bet_amount > 0 then
      select array_agg(user_id) into v_user_ids
        from public.cora_room_players where room_id = v_room.id;
      v_user_ids := coalesce(v_user_ids, array[]::uuid[]);

      if array_length(v_user_ids, 1) > 0 then
        perform public.treasury_refund_all(
          'cora_dice', v_room.id::text, v_user_ids, v_room.bet_amount
        );
      end if;
    end if;

    update public.cora_rooms set status = 'cancelled' where id = v_room.id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.cora_dice_cleanup_stale_rooms() to authenticated;
