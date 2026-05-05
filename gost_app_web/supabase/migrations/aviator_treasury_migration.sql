-- ============================================================
-- AVIATOR - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_payout_fix.sql.
-- Idempotent.
--
-- Bugs corriges :
--   1. aviator_place_bet : UPDATE direct user_profiles -> ne credite PAS la caisse
--      -> les mises etaient "perdues" du systeme. Maintenant : treasury_place_bet.
--   2. aviator_cashout : UPDATE direct user_profiles avec bet*mult complet
--      -> AUCUNE commission 10% prelevee. Maintenant : apply_game_payout.
--
-- Logique :
--   - Mise X : caisse += X (via treasury_place_bet)
--   - Cashout au mult M : payout brut = X*M, dont 10% caisse + 90% joueur
--   - Crash sans cashout : la mise reste a la caisse (deja la, rien a faire)
-- ============================================================

-- ============================================================
-- 1) aviator_place_bet - debit via treasury
-- ============================================================
create or replace function public.aviator_place_bet(
  p_round_num bigint,
  p_slot smallint,
  p_amount int,
  p_username text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_bet_id uuid;
  v_now_ms bigint;
  v_round_start_ms bigint;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'NOT_AUTH';
  end if;
  if p_amount <= 0 then
    raise exception 'BAD_AMOUNT';
  end if;
  if p_slot not in (1, 2) then
    raise exception 'BAD_SLOT';
  end if;

  -- Validation fenetre temporelle (-2s avant debut .. +5s apres)
  v_now_ms := (extract(epoch from now()) * 1000)::bigint;
  v_round_start_ms := p_round_num * 15000;
  if v_now_ms < v_round_start_ms - 2000 then
    raise exception 'ROUND_NOT_STARTED';
  end if;
  if v_now_ms >= v_round_start_ms + 5000 then
    raise exception 'BET_WINDOW_CLOSED';
  end if;

  -- Inserer la mise d'abord (a cause de la contrainte unique slot)
  insert into public.aviator_bets (round_num, user_id, username, slot, amount)
    values (p_round_num, v_user_id, p_username, p_slot, p_amount)
    returning id into v_bet_id;

  -- ===== TREASURY MIGRATION =====
  -- Debit via la caisse (atomique, verifie solde, log auto, leve INSUFFICIENT_COINS si pas assez)
  perform public.treasury_place_bet(
    'aviator',
    format('%s-%s', p_round_num::text, p_slot::text),
    v_user_id,
    p_amount
  );

  return v_bet_id;
exception when unique_violation then
  raise exception 'ALREADY_BET';
end;
$$;

grant execute on function public.aviator_place_bet(bigint, smallint, int, text) to authenticated;

-- ============================================================
-- 2) aviator_cashout - payout via apply_game_payout (90/10)
-- ============================================================
-- Retourne le gain NET (apres commission 10%) recu par le joueur.
create or replace function public.aviator_cashout(
  p_round_num bigint,
  p_slot smallint,
  p_mult numeric
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_bet record;
  v_gross int;
  v_net int;
  v_crash numeric;
  v_now_ms bigint;
  v_round_start_ms bigint;
  v_game_id text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'NOT_AUTH';
  end if;
  if p_mult <= 0 then
    raise exception 'BAD_MULT';
  end if;

  -- Validation fenetre temporelle
  v_now_ms := (extract(epoch from now()) * 1000)::bigint;
  v_round_start_ms := p_round_num * 15000;
  if v_now_ms < v_round_start_ms + 5000 - 500 then
    raise exception 'FLIGHT_NOT_STARTED';
  end if;
  if v_now_ms >= v_round_start_ms + 15000 + 2000 then
    raise exception 'ROUND_ENDED';
  end if;

  -- Validation anti-triche : p_mult <= crashPoint
  v_crash := public._aviator_crash_point(p_round_num);
  if p_mult > v_crash + 0.01 then
    raise exception 'MULT_EXCEEDS_CRASH';
  end if;

  -- Lock la mise
  select * into v_bet
    from public.aviator_bets
    where round_num = p_round_num
      and user_id = v_user_id
      and slot = p_slot
    for update;

  if not found then
    raise exception 'BET_NOT_FOUND';
  end if;
  if v_bet.cashed_out_at is not null then
    raise exception 'ALREADY_CASHED_OUT';
  end if;

  -- Gain BRUT (avant commission)
  v_gross := floor(v_bet.amount * p_mult)::int;

  -- ===== TREASURY MIGRATION =====
  -- apply_game_payout splitte 90% joueur, 10% caisse
  v_game_id := format('%s-%s', p_round_num::text, p_slot::text);
  if v_gross > 0 then
    v_net := public.apply_game_payout(
      'aviator', v_game_id, v_user_id, v_gross
    );
  else
    v_net := 0;
  end if;

  -- Marquer la mise cashed-out (avec le mult REEL valide serveur, et le NET recu)
  update public.aviator_bets
    set cashed_out_at = p_mult,
        win_amount = v_net  -- gain NET (apres commission)
    where id = v_bet.id;

  return v_net;
end;
$$;

grant execute on function public.aviator_cashout(bigint, smallint, numeric) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications :
--
-- Scenario 1 (mise 100, cashout @ 2.5x) :
--   - aviator_place_bet : user -100, caisse +100
--   - aviator_cashout : gross = 100*2.5 = 250
--                       apply_game_payout(250) -> user +225 (90%), caisse +25 (10%)
--   - Bilan user : -100 + 225 = +125
--   - Bilan caisse : +100 - 225 = -125 (perte cette manche, normal pour multiplicateur eleve)
--   - house_cut log : 25 (= 10%)
--
-- Scenario 2 (mise 100, crash sans cashout) :
--   - aviator_place_bet : user -100, caisse +100
--   - Pas de cashout : la mise reste dans la caisse
--   - Bilan caisse : +100 (gain pour la maison)
--
-- Scenario 3 (mise 100, cashout @ 1.1x) :
--   - aviator_place_bet : user -100, caisse +100
--   - aviator_cashout : gross = 100*1.1 = 110
--                       apply_game_payout(110) -> user +99 (90%), caisse +11 (10%)
--   - Bilan user : -100 + 99 = -1 (perte malgre cashout, a cause des 10%)
--   - Bilan caisse : +100 - 99 = +1
--
-- Note importante : avec ce fix, un cashout precoce (mult ~1.1) peut etre LEGEREMENT
-- perdant pour le joueur a cause du 10%. C'est intentionnel - meme cashout instantane
-- nest pas gratuit. Le joueur doit cashout >= 1.12x pour break-even net.
-- ============================================================
