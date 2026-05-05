-- ============================================================
-- LUDO V1 - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql.
-- Idempotent : safe to re-run.
--
-- Ce que ca change :
--   - accept_challenge : remplace le debit direct par treasury_place_bet
--     (les coins partent dans la caisse super-admin au lieu de "disparaitre")
--   - finish_ludo_game : remplace le credit direct par apply_game_payout
--     (le winner recoit pot - 7%, la caisse garde 7%)
--   - cancel_ludo_game : remplace les refunds directs par treasury_settle_draw
--     (politique on_draw configuree dans house_edge_config)
--
-- Garanties business :
--   - L'argent ne disparait jamais du systeme (zero-creation)
--   - 7% de chaque pot Ludo ramene direct dans la caisse super-admin
--   - Toutes les operations sont logguees dans treasury_movements
--
-- TODO : il faut aussi migrer create_game_from_room (mode room/multi).
-- Partage le SQL de cette fonction et je livre le patch correspondant.
-- ============================================================

-- ============================================================
-- 1) accept_challenge - debit via treasury_place_bet
-- ============================================================
create or replace function public.accept_challenge(p_challenge_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from_user uuid;
  v_to_user uuid;
  v_bet int;
  v_game_id uuid;
begin
  -- Verifier que c'est bien le destinataire qui accepte
  select from_user, to_user, bet_amount
  into v_from_user, v_to_user, v_bet
  from public.ludo_challenges
  where id = p_challenge_id and status = 'pending';

  if not found then
    raise exception 'Defi introuvable ou deja traite';
  end if;

  if v_to_user != auth.uid() then
    raise exception 'Seul le destinataire peut accepter ce defi';
  end if;

  -- Creer la partie d'abord pour avoir un game_id (utilise dans treasury_place_bet)
  insert into public.ludo_games (
    challenge_id, player1, player2, current_turn, bet_amount,
    game_state, status
  )
  values (
    p_challenge_id, v_from_user, v_to_user, v_from_user, v_bet,
    jsonb_build_object(
      'pawns', jsonb_build_object(
        v_from_user::text, '[0,0,0,0]'::jsonb,
        v_to_user::text, '[0,0,0,0]'::jsonb
      ),
      'lastDice', 0,
      'hasRolled', false,
      'moveHistory', '[]'::jsonb
    ),
    'playing'
  )
  returning id into v_game_id;

  -- Debiter les 2 joueurs via la caisse (atomique avec verification solde)
  -- Si l'un des 2 n'a plus assez, ROLLBACK auto -> partie annulee
  perform public.treasury_place_bet('ludo', v_game_id::text, v_from_user, v_bet);
  perform public.treasury_place_bet('ludo', v_game_id::text, v_to_user, v_bet);

  -- Mettre a jour le challenge
  update public.ludo_challenges
  set status = 'accepted', game_id = v_game_id, updated_at = now()
  where id = p_challenge_id;

  return v_game_id;
end;
$$;

grant execute on function public.accept_challenge(uuid) to authenticated;

-- ============================================================
-- 2) finish_ludo_game - payout via apply_game_payout
-- ============================================================
-- Le winner recoit (pot - 7%), les 7% vont dans la caisse super-admin.
-- Pour 2 joueurs : pot = bet * 2 -> winner recoit bet * 2 * 0.93 = ~1.86x sa mise.
create or replace function public.finish_ludo_game(p_game_id uuid, p_winner_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bet int;
  v_player1 uuid;
  v_player2 uuid;
  v_status text;
  v_pot int;
  v_loser uuid;
begin
  select bet_amount, player1, player2, status
  into v_bet, v_player1, v_player2, v_status
  from public.ludo_games
  where id = p_game_id;

  if not found then
    raise exception 'Partie introuvable';
  end if;

  if v_status != 'playing' then
    raise exception 'Cette partie est deja terminee';
  end if;

  if p_winner_id != v_player1 and p_winner_id != v_player2 then
    raise exception 'Le gagnant doit etre un des joueurs';
  end if;

  -- Identifier le perdant
  v_loser := case when p_winner_id = v_player1 then v_player2 else v_player1 end;

  -- Pot total (mises deja dans la caisse via treasury_place_bet)
  v_pot := v_bet * 2;

  -- Distribuer : winner recoit pot - 7%, caisse garde 7%
  -- (atomique, log auto, met a jour treasury_balance)
  perform public.apply_game_payout('ludo', p_game_id::text, p_winner_id, v_pot);

  -- Stats winner
  update public.user_profiles
  set games_won = games_won + 1,
      games_played = games_played + 1,
      updated_at = now()
  where id = p_winner_id;

  -- Stats loser
  update public.user_profiles
  set games_played = games_played + 1,
      updated_at = now()
  where id = v_loser;

  -- Marquer la partie comme terminee
  update public.ludo_games
  set status = 'finished', winner_id = p_winner_id, updated_at = now()
  where id = p_game_id;
end;
$$;

grant execute on function public.finish_ludo_game(uuid, uuid) to authenticated;

-- ============================================================
-- 3) cancel_ludo_game - refund via treasury_settle_draw
-- ============================================================
-- Politique de refund definie dans house_edge_config.on_draw :
--   - 'refund' : refund integral (0% pour la maison)
--   - 'refund_minus_edge' : refund minus 7% (par defaut)
--   - 'house_keeps' : caisse garde tout (rare)
create or replace function public.cancel_ludo_game(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bet int;
  v_player1 uuid;
  v_player2 uuid;
  v_status text;
begin
  select bet_amount, player1, player2, status
  into v_bet, v_player1, v_player2, v_status
  from public.ludo_games
  where id = p_game_id;

  if not found then
    raise exception 'Partie introuvable';
  end if;

  if v_status != 'playing' then
    raise exception 'Cette partie est deja terminee';
  end if;

  -- Verifier que l'appelant est bien un des joueurs
  if auth.uid() != v_player1 and auth.uid() != v_player2 then
    raise exception 'Vous n etes pas un joueur de cette partie';
  end if;

  -- Refund via treasury (politique on_draw pour Ludo = refund_minus_edge par defaut)
  perform public.treasury_settle_draw(
    'ludo',
    p_game_id::text,
    array[v_player1, v_player2],
    v_bet
  );

  -- Marquer la partie comme annulee
  update public.ludo_games
  set status = 'cancelled', winner_id = null, updated_at = now()
  where id = p_game_id;

  -- Mettre a jour la salle associee si elle existe
  update public.ludo_rooms
  set status = 'cancelled', updated_at = now()
  where game_id = p_game_id;
end;
$$;

grant execute on function public.cancel_ludo_game(uuid) to authenticated;

-- ============================================================
-- 4) abandon_ludo_game - inchange (delegue a finish_ludo_game)
-- ============================================================
-- Cette fonction n'a pas besoin d'etre modifiee : elle appelle
-- deja finish_ludo_game qui est maintenant treasury-aware.
-- (re-creee ici pour idempotence)
create or replace function public.abandon_ludo_game(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player1 uuid;
  v_player2 uuid;
  v_winner uuid;
begin
  select player1, player2 into v_player1, v_player2
  from public.ludo_games where id = p_game_id and status = 'playing';

  if not found then
    raise exception 'Partie introuvable ou deja terminee';
  end if;

  -- Le gagnant est l'autre joueur
  if auth.uid() = v_player1 then
    v_winner := v_player2;
  elsif auth.uid() = v_player2 then
    v_winner := v_player1;
  else
    raise exception 'Vous n etes pas un joueur de cette partie';
  end if;

  perform public.finish_ludo_game(p_game_id, v_winner);
end;
$$;

grant execute on function public.abandon_ludo_game(uuid) to authenticated;

-- ============================================================
-- TODO : create_game_from_room (mode multi-room)
-- ============================================================
-- Cette fonction n'a pas ete modifiee. Pour completer la migration
-- du mode salle multi-joueurs (4 joueurs), partage le SQL actuel et
-- je livrerai le patch :
--
-- select pg_get_functiondef(oid)
-- from pg_proc where proname = 'create_game_from_room';
--
-- Le patch sera : remplacer chaque debit direct
--   update user_profiles set coins = coins - bet_amount where id IN (...)
-- par
--   for v_player in (select unnest(array[player1, player2, player3, player4]))
--     perform treasury_place_bet('ludo', game_id::text, v_player, bet_amount)
--   end loop
-- ============================================================

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution recommandees :
--   1. Lance une partie Ludo classique (challenge ou room 2 joueurs)
--   2. Verifie que les 2 joueurs sont bien debites a l'acceptation
--   3. Termine la partie -> verifie que le winner recoit ~93% du pot
--   4. Verifie le solde de la caisse :
--      select * from public.treasury_summary;
--   5. Verifie le mouvement loggue :
--      select * from public.treasury_movements
--      where game_type = 'ludo' order by created_at desc limit 10;
