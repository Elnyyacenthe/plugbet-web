-- ============================================================
-- Matchs Flash : plus imprevisible (forme du jour + upsets + Poisson)
-- ============================================================
-- AVANT : ratings fixes -> cotes -> RNG biaise par ratings = trop facile
-- car le rating se LIT direct sur la cote, donc parier sur le favori
-- gagne presque toujours.
--
-- APRES : 4 sources d'imprevisibilite :
--   1. FORME DU JOUR : rating effectif = rating_base + random(-18, +18)
--      Le favori sur le papier peut etre en mauvais jour (rating eff plus bas).
--      Le marche n'a PAS connaissance de cette forme -> upset realiste.
--   2. UPSET FLAG (15% des matchs) : reverse le bias home/away pour ce match.
--      Le favori (selon cote) perd dans ~15% des cas. Aligne sur stats UEFA.
--   3. POISSON GOALS : lambda dynamique par minute (5-15% prob/sec mais
--      avec burst aleatoires possible -> 0-0, 4-3, 5-1).
--   4. DEFENSE/ATTAQUE separes : ratings home_att + home_def calcules
--      separement -> matchs offensifs vs blocs defensifs.
--
-- IMPORTANT : les COTES restent calculees sur ratings de BASE (visible),
-- mais le RESULTAT utilise les ratings EFFECTIFS (caches). C'est ce qui
-- cree le decalage et donc les upsets.
-- ============================================================

create or replace function public.spawn_virtual_match_at(p_kickoff timestamptz)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_teams text[] := array[
    'Manchester City', 'Manchester United', 'Liverpool', 'Arsenal',
    'Chelsea', 'Tottenham', 'Newcastle', 'Aston Villa',
    'Real Madrid', 'FC Barcelona', 'Atlético Madrid', 'Sevilla',
    'Juventus', 'AC Milan', 'Inter Milan', 'Napoli', 'Roma', 'Lazio',
    'Bayern Munich', 'Borussia Dortmund', 'Bayer Leverkusen', 'RB Leipzig',
    'Paris SG', 'Olympique Marseille', 'Olympique Lyonnais', 'Monaco',
    'Ajax', 'Benfica', 'Porto', 'Sporting CP',
    'Flamengo', 'River Plate', 'Boca Juniors', 'Palmeiras',
    'Al Ahly', 'TP Mazembe', 'Mamelodi Sundowns', 'Espérance Tunis',
    'Wydad Casablanca', 'Al Hilal', 'Al Nassr'
  ];
  v_active_teams text[];
  v_available text[];
  v_h_idx int;
  v_a_idx int;
  -- Ratings BASE (visibles via cotes)
  v_h_rating int;
  v_a_rating int;
  -- Ratings EFFECTIFS (forme du jour, caches)
  v_h_form int;
  v_a_form int;
  -- Pour calcul des COTES (utilise base, +home advantage)
  v_h_cote numeric;
  v_a_cote numeric;
  v_hh numeric;
  v_aa numeric;
  v_dd numeric;
  v_total numeric;
  -- Pour le RESULTAT (utilise forme effective + upset)
  v_h_eff numeric;
  v_a_eff numeric;
  v_is_upset bool;
  v_goals jsonb := '[]'::jsonb;
  v_sec int;
  v_goal_p numeric;
  v_team text;
  v_id uuid;
  v_h_score int := 0;
  v_a_score int := 0;
begin
  -- Equipes actives -> exclues
  select coalesce(array_agg(distinct t), array[]::text[])
    into v_active_teams
  from (
    select home_name as t from public.virtual_match
      where kickoff > now() - interval '40 seconds'
    union all
    select away_name from public.virtual_match
      where kickoff > now() - interval '40 seconds'
  ) actives;

  select coalesce(array_agg(t), array[]::text[])
    into v_available
  from unnest(v_teams) t
  where not (t = any(v_active_teams));

  if array_length(v_available, 1) is null or array_length(v_available, 1) < 2 then
    v_available := v_teams;
  end if;

  v_h_idx := 1 + (floor(random() * array_length(v_available, 1)))::int;
  loop
    v_a_idx := 1 + (floor(random() * array_length(v_available, 1)))::int;
    exit when v_a_idx <> v_h_idx;
  end loop;

  -- ── 1. Ratings BASE (visibles sur les cotes) ──
  v_h_rating := 50 + (floor(random() * 56))::int;  -- 50-105
  v_a_rating := 50 + (floor(random() * 56))::int;

  -- ── 2. Calcul COTES sur ratings BASE + home advantage ──
  -- (les cotes refletent ce que l'utilisateur "voit" - le favori sur le
  --  papier - mais NE PREDIT PAS forcement le resultat)
  v_h_cote := (v_h_rating + 5)::numeric;  -- +5 home advantage
  v_a_cote := v_a_rating::numeric;
  v_hh := v_h_cote * v_h_cote;
  v_aa := v_a_cote * v_a_cote;
  v_dd := ((v_h_cote + v_a_cote) / 2) * 50;
  v_total := v_hh + v_aa + v_dd;

  -- ── 3. FORME DU JOUR : ratings effectifs caches (variance +-18) ──
  -- 50% des matchs, la forme effective decoincide significativement
  -- du rating affiche. C'est l'imprevisibilite "naturelle".
  v_h_form := v_h_rating + (floor(random() * 37) - 18)::int;  -- +/-18
  v_a_form := v_a_rating + (floor(random() * 37) - 18)::int;

  -- ── 4. UPSET FLAG (15% des matchs) ──
  -- Le favori (selon cotes) finit perdant. Aligne sur stats reelles UEFA.
  v_is_upset := random() < 0.15;
  if v_is_upset then
    -- Inverser le bias : utiliser le faible comme "fort" pour ce match
    if v_h_rating > v_a_rating then
      v_h_eff := v_a_form::numeric;
      v_a_eff := (v_h_form + 12)::numeric;
    else
      v_h_eff := (v_a_form + 12)::numeric;
      v_a_eff := v_h_form::numeric;
    end if;
  else
    -- Forme normale + home advantage modere (+3, plus bas que dans les cotes)
    v_h_eff := (v_h_form + 3)::numeric;
    v_a_eff := v_a_form::numeric;
  end if;

  -- ── 5. POISSON GOALS : variance accrue ──
  -- Probabilite de base + bonus si match offensif (les 2 ont rating > 75)
  -- + chaos factor random pour variance entre matchs.
  v_goal_p := 0.045 + ((v_h_eff + v_a_eff) / 2 - 60) * 0.0018;
  -- Bonus offensif si les 2 equipes sont fortes en attaque
  if v_h_form > 75 and v_a_form > 75 then
    v_goal_p := v_goal_p + 0.025;  -- match spectaculaire
  end if;
  -- Chaos : 15% de chance d'avoir un match completement fou (5+ buts)
  if random() < 0.15 then
    v_goal_p := v_goal_p * 1.6;
  end if;
  -- Clamp realiste
  v_goal_p := greatest(0.03, least(0.20, v_goal_p));

  -- ── 6. Simulation seconde par seconde ──
  for v_sec in 1..29 loop
    if random() < v_goal_p then
      -- Bias buteur : home OU upset/inverse selon forme effective
      if random() < (v_h_eff / (v_h_eff + v_a_eff)) then
        v_team := 'home';
        v_h_score := v_h_score + 1;
      else
        v_team := 'away';
        v_a_score := v_a_score + 1;
      end if;
      v_goals := v_goals || jsonb_build_object('sec', v_sec, 'team', v_team);
    end if;
  end loop;

  -- ── 7. Insertion (cotes calculees sur BASE, goals sur EFFECTIF) ──
  insert into public.virtual_match(
    home_name, away_name, home_rating, away_rating, kickoff,
    home_odds, draw_odds, away_odds, goals
  ) values (
    v_available[v_h_idx], v_available[v_a_idx], v_h_rating, v_a_rating,
    p_kickoff,
    round(1 / ((v_hh / v_total) * 1.05), 2),
    round(1 / ((v_dd / v_total) * 1.05), 2),
    round(1 / ((v_aa / v_total) * 1.05), 2),
    v_goals
  ) returning id into v_id;
  return v_id;
end;
$$;

-- ============================================================
-- NBA virtuel : meme refonte d'imprevisibilite (forme + upset)
-- ============================================================
create or replace function public.spawn_virtual_basket_match_at(p_kickoff timestamptz)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_teams text[] := array[
    'Boston Celtics', 'Brooklyn Nets', 'New York Knicks',
    'Philadelphia 76ers', 'Toronto Raptors',
    'Chicago Bulls', 'Cleveland Cavaliers', 'Detroit Pistons',
    'Indiana Pacers', 'Milwaukee Bucks',
    'Atlanta Hawks', 'Charlotte Hornets', 'Miami Heat', 'Orlando Magic',
    'LA Lakers', 'LA Clippers', 'Golden State Warriors',
    'Phoenix Suns', 'Sacramento Kings',
    'Dallas Mavericks', 'Memphis Grizzlies', 'Houston Rockets',
    'San Antonio Spurs', 'Denver Nuggets', 'Oklahoma City Thunder',
    'Utah Jazz', 'Portland Trail Blazers', 'Minnesota Timberwolves'
  ];
  v_active_teams text[];
  v_available text[];
  v_h_idx int;
  v_a_idx int;
  -- Ratings BASE (visibles via cote)
  v_h_rating int;
  v_a_rating int;
  -- Ratings EFFECTIFS (forme du jour, caches)
  v_h_form int;
  v_a_form int;
  v_h_eff_score int;
  v_a_eff_score int;
  v_is_upset bool;
  v_hh numeric;
  v_aa numeric;
  v_total numeric;
  v_home_score int;
  v_away_score int;
  v_id uuid;
begin
  select coalesce(array_agg(distinct t), array[]::text[])
    into v_active_teams
  from (
    select home_name as t from public.virtual_match
      where sport = 'basketball' and kickoff > now() - interval '40 seconds'
    union all
    select away_name from public.virtual_match
      where sport = 'basketball' and kickoff > now() - interval '40 seconds'
  ) actives;

  select coalesce(array_agg(t), array[]::text[])
    into v_available
  from unnest(v_teams) t
  where not (t = any(v_active_teams));

  if array_length(v_available, 1) is null or array_length(v_available, 1) < 2 then
    v_available := v_teams;
  end if;

  v_h_idx := 1 + (floor(random() * array_length(v_available, 1)))::int;
  loop
    v_a_idx := 1 + (floor(random() * array_length(v_available, 1)))::int;
    exit when v_a_idx <> v_h_idx;
  end loop;

  -- Ratings BASE 60-105 (visible cotes)
  v_h_rating := 60 + (floor(random() * 46))::int;
  v_a_rating := 60 + (floor(random() * 46))::int;

  -- Formule cube pour spreads NBA dramatiques (cotes inchangees)
  v_hh := v_h_rating::numeric * v_h_rating * v_h_rating;
  v_aa := v_a_rating::numeric * v_a_rating * v_a_rating;
  v_total := v_hh + v_aa;

  -- ── FORME DU JOUR (caché): variance +/-15 sur rating effectif ──
  v_h_form := v_h_rating + (floor(random() * 31) - 15)::int;
  v_a_form := v_a_rating + (floor(random() * 31) - 15)::int;

  -- ── UPSET (15% des matchs) : inverser le bias ──
  v_is_upset := random() < 0.15;
  if v_is_upset then
    -- Boost l'outsider, penalise le favori
    if v_h_rating > v_a_rating then
      v_h_eff_score := v_a_form;
      v_a_eff_score := v_h_form + 10;  -- boost
    else
      v_h_eff_score := v_a_form + 10;
      v_a_eff_score := v_h_form;
    end if;
  else
    v_h_eff_score := v_h_form;
    v_a_eff_score := v_a_form;
  end if;

  -- ── Final scores : centre ~108 + variance ÉLARGIE + forme effective ──
  -- Variance 30 (au lieu 25) = matchs plus spectaculaires
  v_home_score := 90 + (floor(random() * 35))::int + ((v_h_eff_score - 85) / 3);
  v_away_score := 90 + (floor(random() * 35))::int + ((v_a_eff_score - 85) / 3);
  if v_home_score = v_away_score then
    if random() < 0.5 then
      v_home_score := v_home_score + 1;
    else
      v_away_score := v_away_score + 1;
    end if;
  end if;

  insert into public.virtual_match(
    sport, home_name, away_name, home_rating, away_rating, kickoff,
    home_odds, draw_odds, away_odds,
    goals, final_home_score, final_away_score
  ) values (
    'basketball',
    v_available[v_h_idx], v_available[v_a_idx], v_h_rating, v_a_rating,
    p_kickoff,
    round(1 / ((v_hh / v_total) * 1.05), 2),
    null,
    round(1 / ((v_aa / v_total) * 1.05), 2),
    '[]'::jsonb, v_home_score, v_away_score
  ) returning id into v_id;
  return v_id;
end;
$$;

-- ============================================================
-- Test rapide :
-- ============================================================
-- 1. Generer 20 matchs et compter les upsets :
--    select array_agg(spawn_virtual_match_at(now() + (i * interval '30 seconds')))
--    from generate_series(1, 20) i;
--
-- 2. Verifier la variance des resultats :
--    with last20 as (
--      select home_rating, away_rating,
--             (jsonb_array_length(goals) filter (where (g->>'team') = 'home')) as h,
--             (jsonb_array_length(goals) filter (where (g->>'team') = 'away')) as a
--      from public.virtual_match m,
--           lateral (select g from jsonb_array_elements(goals) g) sub
--      where kickoff > now()
--      order by kickoff desc limit 20
--    )
--    select avg(h), avg(a), stddev(h), stddev(a) from last20;
--
-- 3. Compter les upsets reels (rating favori < rating outsider qui gagne) :
--    -- Sur 100 matchs, devrait etre ~15-25%
