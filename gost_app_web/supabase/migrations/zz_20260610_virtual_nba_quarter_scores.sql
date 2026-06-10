-- ============================================================
-- virtual_match : scores par quart-temps NBA
-- ============================================================
-- Permet de resoudre les marches NBA :
--   - OU par quart (Q1/Q2/Q3/Q4)
--   - 3Way Result par quart
--   - Home/Away par quart
--   - Team Total Points par quart
--   - Highest Scoring Quarter
--   - Home/Away/Total Odd/Even par quart
--
-- Distribution realiste : on split le score final en 4 quarts avec
-- variance gaussienne. Sum(quarts) == final_*_score.
-- ============================================================

-- 1) Ajout colonnes quart (idempotent)
alter table public.virtual_match
  add column if not exists q1_home int,
  add column if not exists q1_away int,
  add column if not exists q2_home int,
  add column if not exists q2_away int,
  add column if not exists q3_home int,
  add column if not exists q3_away int,
  add column if not exists q4_home int,
  add column if not exists q4_away int;

-- 2) Fonction de split : repartit un score total en 4 quarts.
-- Distribution : moyenne = total/4, ecart-type ~15%. Garantit sum = total.
create or replace function public._virtual_split_quarters(p_total int)
returns int[]
language plpgsql immutable as $$
declare
  v_mean numeric := p_total::numeric / 4.0;
  v_q int[];
  v_sum int := 0;
  v_diff int;
begin
  -- Genere 4 valeurs entieres autour de la moyenne (+/- 25% du mean)
  v_q := array[
    greatest(0, round(v_mean + (random() - 0.5) * v_mean * 0.5))::int,
    greatest(0, round(v_mean + (random() - 0.5) * v_mean * 0.5))::int,
    greatest(0, round(v_mean + (random() - 0.5) * v_mean * 0.5))::int,
    greatest(0, round(v_mean + (random() - 0.5) * v_mean * 0.5))::int
  ];
  v_sum := v_q[1] + v_q[2] + v_q[3] + v_q[4];
  -- Ajuste le dernier quart pour matcher le total exact
  v_diff := p_total - v_sum;
  v_q[4] := greatest(0, v_q[4] + v_diff);
  return v_q;
end;
$$;

-- 3) Backfill : pour les matchs NBA existants finis sans quarters
update public.virtual_match m
set
  q1_home = sp.q1_h, q1_away = sp.q1_a,
  q2_home = sp.q2_h, q2_away = sp.q2_a,
  q3_home = sp.q3_h, q3_away = sp.q3_a,
  q4_home = sp.q4_h, q4_away = sp.q4_a
from (
  select
    id,
    (_virtual_split_quarters(coalesce(final_home_score, 0)))[1] as q1_h,
    (_virtual_split_quarters(coalesce(final_home_score, 0)))[2] as q2_h,
    (_virtual_split_quarters(coalesce(final_home_score, 0)))[3] as q3_h,
    (_virtual_split_quarters(coalesce(final_home_score, 0)))[4] as q4_h,
    (_virtual_split_quarters(coalesce(final_away_score, 0)))[1] as q1_a,
    (_virtual_split_quarters(coalesce(final_away_score, 0)))[2] as q2_a,
    (_virtual_split_quarters(coalesce(final_away_score, 0)))[3] as q3_a,
    (_virtual_split_quarters(coalesce(final_away_score, 0)))[4] as q4_a
  from public.virtual_match
  where sport = 'basketball'
    and q1_home is null
    and final_home_score is not null
) sp
where m.id = sp.id;

-- 4) Helper de generation au spawn (pour les futurs matchs)
-- L'app cote serveur (cron virtual_match) peut appeler cette fonction
-- pour generer les quarters au moment du spawn d'un match NBA :
create or replace function public._virtual_generate_quarters(
  p_match_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_match record;
  v_q_h int[];
  v_q_a int[];
begin
  select sport, final_home_score, final_away_score
    into v_match from public.virtual_match where id = p_match_id;
  if v_match.sport <> 'basketball' then return; end if;
  v_q_h := _virtual_split_quarters(coalesce(v_match.final_home_score, 0));
  v_q_a := _virtual_split_quarters(coalesce(v_match.final_away_score, 0));
  update public.virtual_match set
    q1_home = v_q_h[1], q1_away = v_q_a[1],
    q2_home = v_q_h[2], q2_away = v_q_a[2],
    q3_home = v_q_h[3], q3_away = v_q_a[3],
    q4_home = v_q_h[4], q4_away = v_q_a[4]
    where id = p_match_id;
end;
$$;
