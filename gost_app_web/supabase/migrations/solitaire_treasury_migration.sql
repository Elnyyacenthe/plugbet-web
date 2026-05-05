-- ============================================================
-- SOLITAIRE - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_payout_fix.sql.
--
-- Bug fixe :
--   - Avant : placeBet faisait (a) deductCoins direct + (b) treasury_collect_loss
--             payWin   faisait (a) addCoins direct  + (b) game_treasury_pay_win
--             -> Le payWin creait DOUBLE PAYOUT (le joueur recevait 2x).
--   - Apres : RPC unique solitaire_place_bet + solitaire_payout
--             qui passent par treasury_place_bet et apply_game_payout.
--
-- Note anti-cheat : Solitaire est solo, logique 100% client. On peut pas
-- valider la victoire serveur sans reecrire tout le moteur. La V1 du fix
-- corrige juste le double-payout et applique 10% commission. La V2 devra
-- ajouter une validation cote serveur (heavy).
-- ============================================================

create or replace function public.solitaire_place_bet(
  p_amount int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_session_id text;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;

  -- Generer un id de session (sera reutilise dans payout pour le log)
  v_session_id := gen_random_uuid()::text;

  perform public.treasury_place_bet(
    'solitaire', v_session_id, v_uid, p_amount
  );
end;
$$;

grant execute on function public.solitaire_place_bet(int) to authenticated;

-- ============================================================
-- solitaire_payout - apply_game_payout (90/10) au winner
-- ============================================================
-- p_gross : gain brut (= bet * 2 generalement). apply_game_payout
-- prelevera automatiquement 10% pour la caisse.
create or replace function public.solitaire_payout(
  p_gross int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_session_id text;
  v_net int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_gross <= 0 then return 0; end if;

  v_session_id := gen_random_uuid()::text;
  v_net := public.apply_game_payout(
    'solitaire', v_session_id, v_uid, p_gross
  );

  return v_net; -- retourne le NET reel paye au joueur (90% de p_gross)
end;
$$;

grant execute on function public.solitaire_payout(int) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Cote Flutter, le service doit appeler :
--   await _client.rpc('solitaire_place_bet', params:{'p_amount': amount});
--   final net = await _client.rpc('solitaire_payout', params:{'p_gross': bet*2});
-- au lieu de _wallet.deductCoins/addCoins + game_treasury_*.
-- ============================================================
