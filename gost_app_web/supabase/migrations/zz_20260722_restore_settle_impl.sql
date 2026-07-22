-- ============================================================
-- RESTAURATION : _settle_virtual_selection_impl
-- ============================================================
-- CONTEXTE (incident du 2026-07-22)
-- Aucun pari ne se reglait plus : ni les paris reels, ni les virtuels
-- (dernier reglement virtuel le 13/07). Cause : la fonction
-- `public._settle_virtual_selection_impl(text,text,int,int,int,int)`
-- avait DISPARU de la base, alors que toute la chaine en depend :
--
--   settle_real_bets_with_results ─┐
--   settle_virtual_bets           ─┤
--   _settle_virtual_selection_v2  ─┴─> _settle_virtual_selection
--                                          └─> _settle_virtual_selection_impl  (MANQUANTE)
--
-- Chaque appel echouait en 42883 "function does not exist", donc les
-- tickets restaient `pending` indefiniment et les gagnants n'etaient
-- jamais payes.
--
-- Sa definition n'existait NULLE PART dans le depot (elle n'avait jamais
-- ete versionnee) : ce fichier la reconstruit et la versionne, pour
-- qu'elle ne puisse plus se perdre.
--
-- CONTRAT (inchange, celui qu'attend le wrapper) :
--   retourne 'won' | 'lost' | 'void'
--   'void' = marche non reconnu -> le wrapper bascule alors sur
--            _settle_final_score_only (Over/Under a ligne variable).
-- ============================================================

CREATE OR REPLACE FUNCTION public._settle_virtual_selection_impl(
  p_sport       text,
  p_market_code text,
  p_home_score  integer,
  p_away_score  integer,
  p_ht_home     integer,
  p_ht_away     integer
) RETURNS text
LANGUAGE plpgsql
AS $function$
declare
  v_code  text;
  v_out   text;
  v_total int;
  v_line  numeric;
  v_ht    text;
begin
  -- Sans score final, on ne tranche pas.
  if p_market_code is null or p_home_score is null or p_away_score is null then
    return 'void';
  end if;

  v_code := lower(p_market_code);

  -- Resultat plein temps
  if    p_home_score > p_away_score then v_out := 'home';
  elsif p_away_score > p_home_score then v_out := 'away';
  else                                   v_out := 'draw';
  end if;
  v_total := p_home_score + p_away_score;

  -- ── 1X2 ──
  if v_code in ('home', 'draw', 'away') then
    return case when v_code = v_out then 'won' else 'lost' end;
  end if;

  -- ── Double chance ──
  if v_code = 'dc_1x' then
    return case when v_out in ('home', 'draw') then 'won' else 'lost' end;
  elsif v_code = 'dc_12' then
    return case when v_out in ('home', 'away') then 'won' else 'lost' end;
  elsif v_code = 'dc_x2' then
    return case when v_out in ('draw', 'away') then 'won' else 'lost' end;
  end if;

  -- ── Totals a ligne variable : over_2_5 / under_1_5 / over25 ... ──
  if v_code ~ '^(over|under)_?[0-9]+([_.][0-9]+)?$' then
    v_line := replace(
                regexp_replace(v_code, '^(over|under)_?', ''),
                '_', '.'
              )::numeric;
    -- forme compacte "over25" -> 25 doit devenir 2.5
    if v_line >= 10 and v_line = trunc(v_line) then
      v_line := v_line / 10.0;
    end if;
    if v_code like 'over%' then
      return case when v_total > v_line then 'won' else 'lost' end;
    else
      return case when v_total < v_line then 'won' else 'lost' end;
    end if;
  end if;

  -- ── Les deux equipes marquent ──
  if v_code in ('btts_yes', 'btts', 'gg') then
    return case when p_home_score > 0 and p_away_score > 0 then 'won' else 'lost' end;
  elsif v_code in ('btts_no', 'ng') then
    return case when p_home_score = 0 or p_away_score = 0 then 'won' else 'lost' end;
  end if;

  -- ── Marches mi-temps (exigent le score HT) ──
  if v_code in ('ht_home', 'ht_draw', 'ht_away') then
    if p_ht_home is null or p_ht_away is null then
      return 'void';   -- pas de score mi-temps disponible -> non tranchable
    end if;
    if    p_ht_home > p_ht_away then v_ht := 'ht_home';
    elsif p_ht_away > p_ht_home then v_ht := 'ht_away';
    else                             v_ht := 'ht_draw';
    end if;
    return case when v_code = v_ht then 'won' else 'lost' end;
  end if;

  -- Marche non reconnu : le wrapper tentera _settle_final_score_only.
  return 'void';
end;
$function$;

COMMENT ON FUNCTION public._settle_virtual_selection_impl(text,text,integer,integer,integer,integer)
IS 'Coeur du reglement d''une selection (1X2, double chance, totals, BTTS, mi-temps). Restauree le 2026-07-22 : elle avait disparu de la base, ce qui bloquait TOUS les reglements.';


-- ============================================================
-- RESTAURATION : treasury_movements.house_cut
-- ============================================================
-- Deuxieme derive de schema decouverte dans le meme incident : la colonne
-- `house_cut` manquait, alors que HUIT fonctions l'ecrivent, dont
-- settle_real_bets_with_results :
--
--   insert into treasury_movements
--     (game_type, game_id, user_id, movement_type, amount, house_cut)
--   values ('bet_real', ..., 'house_cut', v_bet.stake, v_bet.stake);
--
-- Resultat : 42703 "column house_cut does not exist" -> le reglement
-- echouait juste APRES avoir determine won/lost. Concerne aussi les jeux
-- (cora_pay_winner, solitaire_payout, apply_game_payout, treasury_settle_draw...).
--
-- Colonne nullable : certains inserts la renseignent, d'autres non.
ALTER TABLE public.treasury_movements
  ADD COLUMN IF NOT EXISTS house_cut integer;

COMMENT ON COLUMN public.treasury_movements.house_cut
IS 'Part encaissee par la maison sur ce mouvement (FCFA). Restauree le 2026-07-22.';
