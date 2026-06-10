-- ============================================================
-- Asian Handicap — Settlement helper (virtual matches)
-- ============================================================
-- Etend _settle_virtual_selection pour resoudre les selections AH dont
-- le market_code suit le format "ah_home@-1.5" / "ah_away@+0.5" (line
-- entiere ou demi). Quart-lines (-0.25, -0.75) sont rejetees au parser
-- cote Flutter, donc ne devraient jamais arriver ici.
--
-- Regles:
--   ah_home@L : (home_score + L) > away_score          -> won
--               (home_score + L) < away_score          -> lost
--               (home_score + L) = away_score          -> void (push)
--   ah_away@L : line stockee = -line_home, donc :
--               (away_score + L) > home_score          -> won
--               ... idem
--
-- Demi-lines (-1.5, -0.5, +0.5, +1.5) -> push impossible (won|lost net).
-- Lines entieres (0, ±1, ±2) -> push si egalite apres ajustement.
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
  v_outcome    text;
  v_total      int;
  v_ht_outcome text;
  v_ht_total   int;
  v_ah_at      int;
  v_ah_side    text;
  v_ah_line    numeric;
  v_adj        numeric;
begin
  -- Issue match temps reglementaire
  if p_home_score > p_away_score then v_outcome := 'home';
  elsif p_away_score > p_home_score then v_outcome := 'away';
  else v_outcome := 'draw';
  end if;
  v_total := p_home_score + p_away_score;

  -- ── 1X2 (les 2 sports) ──
  if p_market_code in ('home', 'draw', 'away') then
    return case when p_market_code = v_outcome then 'won' else 'lost' end;
  end if;

  -- ── Double Chance (soccer principalement) ──
  if p_market_code = 'dc_1X' then
    return case when v_outcome in ('home','draw') then 'won' else 'lost' end;
  elsif p_market_code = 'dc_12' then
    return case when v_outcome in ('home','away') then 'won' else 'lost' end;
  elsif p_market_code = 'dc_X2' then
    return case when v_outcome in ('draw','away') then 'won' else 'lost' end;
  end if;

  -- ── Asian Handicap (soccer uniquement) ──
  --    market_code "ah_home@-1.5" / "ah_away@+0.5"
  if p_sport = 'soccer' and p_market_code like 'ah\_%@%' escape '\' then
    v_ah_at  := position('@' in p_market_code);
    v_ah_side := substring(p_market_code from 1 for v_ah_at - 1);  -- "ah_home" | "ah_away"
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
    else return 'void';  -- push : line entiere + egalite ajustee
    end if;
  end if;

  -- ── Total Over/Under 2.5 (soccer uniquement, ligne fixe) ──
  if p_sport = 'soccer' then
    if p_market_code = 'over25' then
      return case when v_total > 2 then 'won' else 'lost' end;
    elsif p_market_code = 'under25' then
      return case when v_total < 3 then 'won' else 'lost' end;
    end if;

    -- ── BTTS (soccer uniquement) ──
    if p_market_code = 'btts_yes' then
      return case when p_home_score >= 1 and p_away_score >= 1 then 'won' else 'lost' end;
    elsif p_market_code = 'btts_no' then
      return case when p_home_score = 0 or p_away_score = 0 then 'won' else 'lost' end;
    end if;

    -- ── Mi-temps (soccer uniquement, necessite ht scores) ──
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
    end if;
  end if;

  -- Marches non resolvables -> void
  return 'void';
end;
$$;

-- ============================================================
-- Tests unitaires (a executer dans le SQL editor) :
-- ============================================================
-- AH home -1.5 sur 2-0  -> won  (2-1.5=0.5 > 0)
--   select _settle_virtual_selection('soccer','ah_home@-1.5',2,0,null,null);
-- AH home -1.5 sur 2-1  -> lost (2-1.5=0.5 < 1)
--   select _settle_virtual_selection('soccer','ah_home@-1.5',2,1,null,null);
-- AH home -1 sur 2-1    -> void (2-1=1 = 1, push)
--   select _settle_virtual_selection('soccer','ah_home@-1',2,1,null,null);
-- AH away +1.5 sur 0-1  -> won  (1+1.5=2.5 > 0)
--   select _settle_virtual_selection('soccer','ah_away@+1.5',0,1,null,null);
-- AH away +0 sur 1-1    -> void (1+0=1 = 1, push)
--   select _settle_virtual_selection('soccer','ah_away@+0',1,1,null,null);
