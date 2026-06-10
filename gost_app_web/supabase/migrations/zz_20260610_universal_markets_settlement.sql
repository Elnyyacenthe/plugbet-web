-- ============================================================
-- Universal Markets Settlement (virtual matches)
-- ============================================================
-- Etend _settle_virtual_selection pour resoudre les ~60 marches
-- generiques exposes par le parser StatPal :
--
--   correct_score_X:Y       -> won si score final = X-Y
--   htft_double_H/A         -> won si combinaison HT/FT match
--   odd_even_odd / _even    -> won si total buts impair/pair
--   ou_ht_over@1            -> won si total MT > line
--   ou_ht_under@1           -> won si total MT < line
--   ou_2h_*                 -> idem 2e MT
--   exact_goals_N           -> won si total buts = N
--   win_to_nil_home/away    -> won si home/away gagne sans encaisser
--   win_to_nil_home_yes/no  -> idem (variante)
--   clean_sheet_home_yes/no -> won si home n'encaisse pas
--   ...
--
-- Marches non-resolvable cote backend (Player Props, First Goal Method,
-- Anytime Scorer, etc.) -> void (refund). La maison ne tente pas de
-- decoder un buteur car les virtuels n'ont pas de roster.
-- ============================================================

create or replace function public._settle_virtual_selection(
  p_sport       text,
  p_market_code text,
  p_home_score  int,
  p_away_score  int,
  p_ht_home     int,
  p_ht_away     int
) returns text
language plpgsql immutable set search_path = public as $$
declare
  v_outcome     text;
  v_total       int;
  v_ht_outcome  text;
  v_ht_total    int;
  v_2h_total    int;
  v_2h_home     int;
  v_2h_away     int;
  v_ah_at       int;
  v_ah_side     text;
  v_ah_line     numeric;
  v_adj         numeric;
  v_score       text;
  v_n           int;
  v_at          int;
  v_line_str    text;
  v_line        numeric;
  v_ht_2h_str   text;
begin
  -- Issue match temps reglementaire
  if p_home_score > p_away_score then v_outcome := 'home';
  elsif p_away_score > p_home_score then v_outcome := 'away';
  else v_outcome := 'draw';
  end if;
  v_total := p_home_score + p_away_score;
  v_2h_home := coalesce(p_home_score - coalesce(p_ht_home, 0), 0);
  v_2h_away := coalesce(p_away_score - coalesce(p_ht_away, 0), 0);
  v_2h_total := v_2h_home + v_2h_away;

  -- ── 1X2 (les 2 sports) ──
  if p_market_code in ('home', 'draw', 'away') then
    return case when p_market_code = v_outcome then 'won' else 'lost' end;
  end if;

  -- ── Double Chance derive ──
  if p_market_code = 'dc_1X' then
    return case when v_outcome in ('home','draw') then 'won' else 'lost' end;
  elsif p_market_code = 'dc_12' then
    return case when v_outcome in ('home','away') then 'won' else 'lost' end;
  elsif p_market_code = 'dc_X2' then
    return case when v_outcome in ('draw','away') then 'won' else 'lost' end;
  end if;

  -- ── Asian Handicap (soccer + NBA) ──
  if p_market_code like 'ah\_%@%' escape '\' then
    v_ah_at  := position('@' in p_market_code);
    v_ah_side := substring(p_market_code from 1 for v_ah_at - 1);
    v_ah_line := substring(p_market_code from v_ah_at + 1)::numeric;
    if v_ah_side = 'ah_home' then
      v_adj := (p_home_score + v_ah_line) - p_away_score;
    elsif v_ah_side = 'ah_away' then
      v_adj := (p_away_score + v_ah_line) - p_home_score;
    else
      return 'void';
    end if;
    if v_adj > 0 then return 'won';
    elsif v_adj < 0 then return 'lost';
    else return 'void';
    end if;
  end if;

  -- ── Total Over/Under 2.5 (soccer uniquement, ligne fixe) ──
  if p_sport = 'soccer' then
    if p_market_code = 'over25' then
      return case when v_total > 2 then 'won' else 'lost' end;
    elsif p_market_code = 'under25' then
      return case when v_total < 3 then 'won' else 'lost' end;
    end if;

    -- ── BTTS ──
    if p_market_code = 'btts_yes' then
      return case when p_home_score >= 1 and p_away_score >= 1 then 'won' else 'lost' end;
    elsif p_market_code = 'btts_no' then
      return case when p_home_score = 0 or p_away_score = 0 then 'won' else 'lost' end;
    end if;

    -- ── Mi-temps ──
    if p_ht_home is not null and p_ht_away is not null then
      if p_ht_home > p_ht_away then v_ht_outcome := 'home';
      elsif p_ht_away > p_ht_home then v_ht_outcome := 'away';
      else v_ht_outcome := 'draw';
      end if;
      v_ht_total := p_ht_home + p_ht_away;

      if p_market_code = 'ht_home' then
        return case when v_ht_outcome = 'home' then 'won' else 'lost' end;
      elsif p_market_code = 'ht_draw' then
        return case when v_ht_outcome = 'draw' then 'won' else 'lost' end;
      elsif p_market_code = 'ht_away' then
        return case when v_ht_outcome = 'away' then 'won' else 'lost' end;
      elsif p_market_code = 'ht_over15' then
        return case when v_ht_total > 1 then 'won' else 'lost' end;
      elsif p_market_code = 'ht_under15' then
        return case when v_ht_total < 2 then 'won' else 'lost' end;
      end if;

      -- ── Correct Score (soccer) ──
      if p_market_code like 'correct\_score\_%' escape '\' then
        v_score := substring(p_market_code from 15);  -- ex: "2_0" ou "1_1"
        if v_score = (p_home_score::text || '_' || p_away_score::text) then
          return 'won';
        end if;
        return 'lost';
      end if;

      -- ── HT/FT Double (soccer) ──
      if p_market_code like 'htft\_double\_%' escape '\' then
        v_ht_2h_str := lower(substring(p_market_code from 13));
        if v_ht_2h_str = v_ht_outcome || '_' || v_outcome then
          return 'won';
        end if;
        return 'lost';
      end if;

      -- ── Odd / Even (total goals) ──
      if p_market_code = 'odd_even_odd' then
        return case when v_total % 2 = 1 then 'won' else 'lost' end;
      elsif p_market_code = 'odd_even_even' then
        return case when v_total % 2 = 0 then 'won' else 'lost' end;
      end if;

      -- ── Odd / Even mi-temps ──
      if p_market_code = 'odd_even_ht_odd' then
        return case when v_ht_total % 2 = 1 then 'won' else 'lost' end;
      elsif p_market_code = 'odd_even_ht_even' then
        return case when v_ht_total % 2 = 0 then 'won' else 'lost' end;
      end if;

      -- ── Odd / Even 2e mi-temps ──
      if p_market_code = 'odd_even_2h_odd' then
        return case when v_2h_total % 2 = 1 then 'won' else 'lost' end;
      elsif p_market_code = 'odd_even_2h_even' then
        return case when v_2h_total % 2 = 0 then 'won' else 'lost' end;
      end if;

      -- ── Clean Sheet / Win to Nil ──
      if p_market_code = 'clean_sheet_home_yes' then
        return case when p_away_score = 0 then 'won' else 'lost' end;
      elsif p_market_code = 'clean_sheet_home_no' then
        return case when p_away_score > 0 then 'won' else 'lost' end;
      elsif p_market_code = 'clean_sheet_away_yes' then
        return case when p_home_score = 0 then 'won' else 'lost' end;
      elsif p_market_code = 'clean_sheet_away_no' then
        return case when p_home_score > 0 then 'won' else 'lost' end;
      end if;
      if p_market_code = 'win_to_nil_home_yes' then
        return case when p_home_score > p_away_score and p_away_score = 0 then 'won' else 'lost' end;
      elsif p_market_code = 'win_to_nil_home_no' then
        return case when not (p_home_score > p_away_score and p_away_score = 0) then 'won' else 'lost' end;
      elsif p_market_code = 'win_to_nil_away_yes' then
        return case when p_away_score > p_home_score and p_home_score = 0 then 'won' else 'lost' end;
      elsif p_market_code = 'win_to_nil_away_no' then
        return case when not (p_away_score > p_home_score and p_home_score = 0) then 'won' else 'lost' end;
      end if;

      -- ── Win Both Halves ──
      if p_market_code = 'win_both_halves_home_yes' then
        return case when p_ht_home > p_ht_away and v_2h_home > v_2h_away then 'won' else 'lost' end;
      elsif p_market_code = 'win_both_halves_away_yes' then
        return case when p_ht_away > p_ht_home and v_2h_away > v_2h_home then 'won' else 'lost' end;
      end if;

      -- ── Highest Scoring Half ──
      if p_market_code = 'highest_half_1st' then
        return case when v_ht_total > v_2h_total then 'won' else 'lost' end;
      elsif p_market_code = 'highest_half_2nd' then
        return case when v_2h_total > v_ht_total then 'won' else 'lost' end;
      elsif p_market_code = 'highest_half_equal' then
        return case when v_ht_total = v_2h_total then 'won' else 'lost' end;
      end if;

      -- ── Exact Goals Number (soccer) ──
      if p_market_code like 'exact\_goals\_%' escape '\' then
        v_score := substring(p_market_code from 13);
        if v_score = 'no_goal' then
          return case when v_total = 0 then 'won' else 'lost' end;
        end if;
        if v_score ~ '^[0-9]+$' then
          v_n := v_score::int;
          return case when v_total = v_n then 'won' else 'lost' end;
        end if;
      end if;

      -- ── 1X2 2e mi-temps ──
      if p_market_code = '1x2_2h_home' then
        return case when v_2h_home > v_2h_away then 'won' else 'lost' end;
      elsif p_market_code = '1x2_2h_draw' then
        return case when v_2h_home = v_2h_away then 'won' else 'lost' end;
      elsif p_market_code = '1x2_2h_away' then
        return case when v_2h_away > v_2h_home then 'won' else 'lost' end;
      end if;

      -- ── OU mi-temps / 2e mi-temps (lignes variables) ──
      if p_market_code like 'ou\_ht\_%@%' escape '\' then
        v_at := position('@' in p_market_code);
        v_line_str := substring(p_market_code from v_at + 1);
        v_line := v_line_str::numeric;
        if p_market_code like 'ou\_ht\_over@%' escape '\' then
          return case when v_ht_total > v_line then 'won' else 'lost' end;
        elsif p_market_code like 'ou\_ht\_under@%' escape '\' then
          return case when v_ht_total < v_line then 'won' else 'lost' end;
        end if;
      end if;
      if p_market_code like 'ou\_2h\_%@%' escape '\' then
        v_at := position('@' in p_market_code);
        v_line := substring(p_market_code from v_at + 1)::numeric;
        if p_market_code like 'ou\_2h\_over@%' escape '\' then
          return case when v_2h_total > v_line then 'won' else 'lost' end;
        elsif p_market_code like 'ou\_2h\_under@%' escape '\' then
          return case when v_2h_total < v_line then 'won' else 'lost' end;
        end if;
      end if;

      -- ── Scoring Draw ──
      if p_market_code = 'scoring_draw_yes' then
        return case when p_home_score = p_away_score and p_home_score > 0 then 'won' else 'lost' end;
      elsif p_market_code = 'scoring_draw_no' then
        return case when not (p_home_score = p_away_score and p_home_score > 0) then 'won' else 'lost' end;
      end if;

      -- ── BTTS variantes mi-temps ──
      if p_market_code = 'btts_ht_yes' then
        return case when p_ht_home >= 1 and p_ht_away >= 1 then 'won' else 'lost' end;
      elsif p_market_code = 'btts_ht_no' then
        return case when p_ht_home = 0 or p_ht_away = 0 then 'won' else 'lost' end;
      elsif p_market_code = 'btts_2h_yes' then
        return case when v_2h_home >= 1 and v_2h_away >= 1 then 'won' else 'lost' end;
      elsif p_market_code = 'btts_2h_no' then
        return case when v_2h_home = 0 or v_2h_away = 0 then 'won' else 'lost' end;
      end if;

      -- ── BTTS dans les 2 mi-temps ──
      if p_market_code = 'btts_both_halves_yes' then
        return case when p_ht_home >= 1 and p_ht_away >= 1
                     and v_2h_home >= 1 and v_2h_away >= 1 then 'won' else 'lost' end;
      elsif p_market_code = 'btts_both_halves_no' then
        return case when not (p_ht_home >= 1 and p_ht_away >= 1
                              and v_2h_home >= 1 and v_2h_away >= 1) then 'won' else 'lost' end;
      end if;

      -- ── Marque dans les 2 mi-temps par equipe ──
      if p_market_code = 'home_score_both_yes' then
        return case when p_ht_home >= 1 and v_2h_home >= 1 then 'won' else 'lost' end;
      elsif p_market_code = 'away_score_both_yes' then
        return case when p_ht_away >= 1 and v_2h_away >= 1 then 'won' else 'lost' end;
      end if;

      -- ── Equipe marque (Yes/No) ──
      if p_market_code = 'home_score_yes' then
        return case when p_home_score >= 1 then 'won' else 'lost' end;
      elsif p_market_code = 'home_score_no' then
        return case when p_home_score = 0 then 'won' else 'lost' end;
      elsif p_market_code = 'away_score_yes' then
        return case when p_away_score >= 1 then 'won' else 'lost' end;
      elsif p_market_code = 'away_score_no' then
        return case when p_away_score = 0 then 'won' else 'lost' end;
      end if;

      -- ── Winning Margin (soccer) ──
      if p_market_code like 'winning\_margin\_%' escape '\' then
        v_score := substring(p_market_code from 16);
        v_n := abs(p_home_score - p_away_score);
        if v_score = 'draw' and v_outcome = 'draw' then return 'won'; end if;
        if v_score ~ '^home_[0-9]+' and v_outcome = 'home' then
          v_n := p_home_score - p_away_score;
          return case when v_n::text = substring(v_score from 6) then 'won' else 'lost' end;
        end if;
        if v_score ~ '^away_[0-9]+' and v_outcome = 'away' then
          v_n := p_away_score - p_home_score;
          return case when v_n::text = substring(v_score from 6) then 'won' else 'lost' end;
        end if;
        return 'lost';
      end if;
    end if;
  end if;

  -- ── NBA Race To X Points (estimable depuis final score) ──
  -- Approximation : whoever has more final points "arrives first" — un peu
  -- naif mais OK pour les virtuels qui n'ont pas de log par minute.
  if p_sport = 'basketball' and p_market_code like 'race\_%\_%' escape '\' then
    v_score := substring(p_market_code from 6);  -- ex: "30_home" ou "40_away"
    v_at := position('_' in v_score);
    v_n := substring(v_score from 1 for v_at - 1)::int;
    v_ah_side := substring(v_score from v_at + 1);
    if p_home_score >= v_n and (v_ah_side = 'home' or v_ah_side = '1') then return 'won'; end if;
    if p_away_score >= v_n and (v_ah_side = 'away' or v_ah_side = '2') then return 'won'; end if;
    if p_home_score < v_n and p_away_score < v_n and v_ah_side = 'neither' then return 'won'; end if;
    return 'lost';
  end if;

  -- ── Overtime (toujours non en virtuel — simulation finit a 48 min) ──
  if p_market_code = 'overtime_yes' then return 'lost'; end if;
  if p_market_code = 'overtime_no' then return 'won'; end if;

  -- ── Odd / Even total (NBA) ──
  if p_sport = 'basketball' then
    if p_market_code = 'odd_even_odd' then
      return case when v_total % 2 = 1 then 'won' else 'lost' end;
    elsif p_market_code = 'odd_even_even' then
      return case when v_total % 2 = 0 then 'won' else 'lost' end;
    end if;
  end if;

  -- Marches non resolvables (Player Props, First Goal Scorer, etc.) -> void
  return 'void';
end;
$$;

-- ============================================================
-- Tests :
-- ============================================================
-- select _settle_virtual_selection('soccer','correct_score_2_1',2,1,1,0); -- won
-- select _settle_virtual_selection('soccer','htft_double_home_home',2,1,1,0); -- won
-- select _settle_virtual_selection('soccer','odd_even_odd',2,1,1,0); -- won (3 buts)
-- select _settle_virtual_selection('soccer','clean_sheet_home_yes',1,0,1,0); -- won
-- select _settle_virtual_selection('soccer','win_to_nil_home_yes',2,0,1,0); -- won
-- select _settle_virtual_selection('soccer','exact_goals_3',2,1,1,0); -- won
-- select _settle_virtual_selection('soccer','ou_ht_over@0.5',2,1,1,0); -- won (1 but MT)
-- select _settle_virtual_selection('basketball','race_30_home',105,98,null,null); -- won
