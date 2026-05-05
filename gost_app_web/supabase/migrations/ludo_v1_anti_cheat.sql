-- ============================================================
-- LUDO V1 - Anti-cheat : valider le gagnant cote serveur
-- ============================================================
-- A executer apres ludo_v1_treasury_migration.sql.
--
-- BUG :
--   finish_ludo_game(p_winner_id) acceptait n'importe quel joueur de la
--   partie comme gagnant, sans verifier que ses 4 pions etaient
--   effectivement a la maison (position >= 58). Un joueur malveillant
--   pouvait appeler la RPC immediatement avec p_winner_id=self.
--
-- FIX :
--   On lit game_state.pawns, on extrait les pions du p_winner_id, on verifie
--   qu'ils sont tous >= 58. Sinon, raise.
-- ============================================================

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
  v_state jsonb;
  v_pawns jsonb;
  v_winner_pawns jsonb;
  v_pos int;
  v_all_home boolean := true;
begin
  select bet_amount, player1, player2, status, game_state
  into v_bet, v_player1, v_player2, v_status, v_state
  from public.ludo_games
  where id = p_game_id
  for update;  -- Lock pour eviter race conditions

  if not found then
    raise exception 'Partie introuvable';
  end if;

  if v_status != 'playing' then
    raise exception 'Cette partie est deja terminee';
  end if;

  if p_winner_id != v_player1 and p_winner_id != v_player2 then
    raise exception 'Le gagnant doit etre un des joueurs';
  end if;

  -- ===== ANTI-CHEAT : valider que le winner a effectivement gagne =====
  -- Lire les pions du winner depuis game_state.pawns
  v_pawns := v_state -> 'pawns';
  v_winner_pawns := v_pawns -> p_winner_id::text;

  if v_winner_pawns is null or jsonb_typeof(v_winner_pawns) != 'array' then
    raise exception 'WINNER_PAWNS_NOT_FOUND';
  end if;

  -- Verifier que les 4 pions sont a la maison (>= 58)
  for i in 0..3 loop
    v_pos := (v_winner_pawns ->> i)::int;
    if v_pos < 58 then
      v_all_home := false;
      exit;
    end if;
  end loop;

  if not v_all_home then
    raise exception 'WINNER_NOT_VALIDATED: not all pawns at home';
  end if;
  -- ====================================================================

  v_loser := case when p_winner_id = v_player1 then v_player2 else v_player1 end;
  v_pot := v_bet * 2;

  perform public.apply_game_payout('ludo', p_game_id::text, p_winner_id, v_pot);

  update public.user_profiles
  set games_won = games_won + 1,
      games_played = games_played + 1,
      updated_at = now()
  where id = p_winner_id;

  update public.user_profiles
  set games_played = games_played + 1,
      updated_at = now()
  where id = v_loser;

  update public.ludo_games
  set status = 'finished', winner_id = p_winner_id, updated_at = now()
  where id = p_game_id;
end;
$$;

grant execute on function public.finish_ludo_game(uuid, uuid) to authenticated;

-- ============================================================
-- LIMITATION (V1)
-- ============================================================
-- Le des reste cote client (ludo_models.dart). Un joueur peut donc forger
-- n'importe quel etat de pions et l'envoyer via update_game_state. Une fois
-- les 4 pions "a la maison" en jsonb (forge), il appelle finish_ludo_game
-- et la validation passe.
--
-- Pour fermer cette derniere faille, il faudrait :
--   1. RPC ludo_play_move(p_game_id) qui genere le des serveur + valide
--      les deplacements
--   2. RLS strict sur ludo_games.game_state (UPDATE interdit cote client)
--
-- Tradeoff : reecriture lourde de toute la logique Ludo en SQL. A faire en V2
-- (note : Ludo V2 - jeu different - a deja cette architecture).
-- ============================================================
