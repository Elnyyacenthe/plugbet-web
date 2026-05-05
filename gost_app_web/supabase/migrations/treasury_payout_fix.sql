-- ============================================================
-- TREASURY PAYOUT FIX - Bug critique apply_game_payout
-- ============================================================
-- BUG TROUVE : apply_game_payout creditait le winner SANS debiter la caisse,
-- ce qui creait de l'argent du neant a chaque partie multijoueur.
--
-- Comportement actuel (bug) :
--   1. Credit winner +net_payout (= 90% pot)         (OK)
--   2. balance = balance + house_cut (= 10%)         (BUG - devrait soustraire net_payout)
--   3. log payout + house_cut                        (OK pour tracage, mais balance fausse)
--
-- Comportement corrige :
--   1. Credit winner +net_payout
--   2. balance = balance - net_payout (la caisse paye le winner)
--   3. total_out += net_payout
--   4. log payout + house_cut (le house_cut est implicite : c'est ce qu'il
--      reste dans la caisse apres avoir paye le winner)
--
-- Impact :
--   - Affecte TOUS les jeux qui utilisent apply_game_payout :
--     coinflip, cora_dice, ludo_v1, ludo_v2, roulette, blackjack, fantasy, checkers
--   - Les jeux solo (Mines, Apple Fortune, Aviator) utilisent treasury_pay_winner
--     qui est deja correct.
--
-- ============================================================

create or replace function public.apply_game_payout(
  p_game_type text,
  p_game_id text,
  p_winner_id uuid,
  p_pot_total int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg record;
  v_house_cut int;
  v_net_payout int;
begin
  if p_pot_total <= 0 then
    raise exception 'INVALID_POT';
  end if;
  if p_winner_id is null then
    raise exception 'INVALID_WINNER';
  end if;

  -- Charger config edge du jeu
  select * into v_cfg from public.house_edge_config
    where game_type = p_game_type and enabled = true;
  if not found then
    raise exception 'GAME_NOT_CONFIGURED: %', p_game_type;
  end if;

  -- Calculer la coupure
  v_house_cut := floor(p_pot_total * v_cfg.edge_pct)::int;
  v_net_payout := p_pot_total - v_house_cut;

  -- Plafond max_payout (anti-fraude / anti-bug)
  if v_cfg.max_payout is not null and v_net_payout > v_cfg.max_payout then
    v_net_payout := v_cfg.max_payout;
    v_house_cut := p_pot_total - v_net_payout;
  end if;

  -- 1. Crediter le winner (avec son gain net apres edge)
  update public.user_profiles
    set coins = coins + v_net_payout,
        updated_at = now()
    where id = p_winner_id;

  -- 2. DEBITER la caisse super-admin du montant verse au winner.
  -- Les mises ont deja ete creditees a la caisse via treasury_place_bet.
  -- Donc :
  --   caisse += pot      (depuis treasury_place_bet × N joueurs)
  --   caisse -= net_payout (paiement au winner)
  --   net : caisse +=  house_cut   (= la marge de la maison)
  update public.treasury_balance
    set balance = balance - v_net_payout,
        total_out = total_out + v_net_payout,
        updated_at = now()
    where id = 1;

  -- 3. Logger les 2 mouvements (audit trail)
  insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, pot_total, edge_pct)
    values
      (p_game_type, p_game_id, p_winner_id, 'payout', v_net_payout, p_pot_total, v_cfg.edge_pct),
      (p_game_type, p_game_id, null, 'house_cut', v_house_cut, p_pot_total, v_cfg.edge_pct);

  return v_net_payout;
end;
$$;

grant execute on function public.apply_game_payout(text, text, uuid, int) to authenticated;

-- ============================================================
-- RECONCILIATION : ajuster treasury_balance pour reflechir le bug passe
-- ============================================================
-- Pour chaque payout deja fait, la caisse a ete creditee de +house_cut au lieu
-- de -net_payout. Donc la caisse est EXCEDENTAIRE de (net_payout + house_cut)
-- = pot_total par paiement passe.
--
-- Calculer le delta a soustraire :
--   delta = sum(pot_total des mouvements 'payout' dans treasury_movements)
--
-- Cette section est commentee par defaut. Decommenter pour appliquer une fois.
-- ============================================================

-- Pour voir le delta de correction sans rien modifier :
--   select coalesce(sum(pot_total), 0) as overcredit
--   from treasury_movements where movement_type = 'payout';
--
-- Puis pour reconcilier (ATTENTION : a executer 1 SEULE FOIS) :
-- do $$
-- declare v_delta int;
-- begin
--   select coalesce(sum(pot_total), 0) into v_delta
--   from treasury_movements where movement_type = 'payout';
--   if v_delta > 0 then
--     update treasury_balance set
--       balance = balance - v_delta,
--       total_out = total_out + v_delta,
--       updated_at = now()
--     where id = 1;
--     -- Log la correction
--     insert into treasury_movements (game_type, movement_type, amount, metadata)
--     values ('system', 'adjustment', -v_delta,
--             jsonb_build_object('reason', 'apply_game_payout_bugfix_reconciliation'));
--   end if;
-- end$$;

-- ============================================================
-- FIN
-- ============================================================
-- Apres execution :
--   1. Tous les NOUVEAUX games ont une caisse coherente (zero creation)
--   2. Si tu veux aussi reconcilier le passe : decommenter le bloc DO ci-dessus
--      et executer UNE SEULE FOIS.
-- ============================================================
