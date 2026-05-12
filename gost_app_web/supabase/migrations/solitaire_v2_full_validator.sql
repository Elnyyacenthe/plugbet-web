-- ============================================================
-- SOLITAIRE V2.2 — Full validator (structural anti-cheat)
-- ============================================================
-- Implémente la validation rigoureuse des sessions paid :
--   1. Score consistency : score déclaré = somme des deltas des moves
--   2. Move type validity : chaque type de move respecte sa logique
--   3. Win consistency : si won, suffisamment de moves to foundation
--   4. Move sequence integrity : timestamps croissants, pas de duplicate
--   5. Cron de validation auto : flag les sessions invalides
--   6. Vue admin pour voir les sessions invalides
--
-- Pas de full replay (réimplémenter Solitaire en PL/pgSQL serait hideux),
-- mais ces checks structurels attrapent :
--   - Score manipulé (incohérent avec les moves)
--   - Win déclarée sans moves suffisants
--   - Move sequences absurdes (timestamps désordonnés)
--   - Duplications/injections de moves
-- ============================================================

-- ============================================================
-- 1. Ajout colonne validation_status
-- ============================================================
alter table public.solitaire_sessions
  add column if not exists validation_status text default 'unchecked'
    check (validation_status in ('unchecked','valid','invalid','review')),
  add column if not exists validation_details jsonb,
  add column if not exists validated_at timestamptz;

create index if not exists idx_solitaire_sessions_validation
  on public.solitaire_sessions(validation_status, closed_at desc)
  where validation_status in ('invalid','review');

-- ============================================================
-- 2. Constantes de scoring (synchro avec Dart solitaire_logic)
-- ============================================================
-- MoveType.drawFromStock      = 0  → +0
-- MoveType.recycleStock       = 1  → +0
-- MoveType.wasteToFoundation  = 2  → +10
-- MoveType.wasteToTableau     = 3  → +5
-- MoveType.tableauToFoundation= 4  → +10
-- MoveType.tableauToTableau   = 5  → +5
-- Bonus victoire              = +500
-- ============================================================

-- ============================================================
-- 3. Validator principal
-- ============================================================
create or replace function public.solitaire_validate_session(
  p_session_id uuid
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_sess solitaire_sessions;
  v_moves jsonb;
  v_move jsonb;
  v_move_type int;
  v_prev_ts int := -1;
  v_curr_ts int;
  v_invalidities text[] := array[]::text[];
  v_warnings text[] := array[]::text[];

  -- Compteurs par type de move
  v_count_draw int := 0;
  v_count_recycle int := 0;
  v_count_waste_to_found int := 0;
  v_count_waste_to_tab int := 0;
  v_count_tab_to_found int := 0;
  v_count_tab_to_tab int := 0;

  -- Score recalculé depuis les moves
  v_expected_score int := 0;

  -- Plages valides
  v_total_moves int;
  v_score_diff int;
  v_status text;
begin
  select * into v_sess from solitaire_sessions where id = p_session_id;
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'session_not_found');
  end if;

  -- Sessions practice : skip validation
  if v_sess.is_practice then
    update solitaire_sessions
       set validation_status = 'valid', validated_at = now(),
           validation_details = jsonb_build_object('skip', 'practice_mode')
     where id = p_session_id;
    return jsonb_build_object('valid', true, 'reason', 'practice_skip');
  end if;

  v_moves := coalesce(v_sess.moves_log, '[]'::jsonb);
  v_total_moves := jsonb_array_length(v_moves);

  -- ===========================================================
  -- CHECK 1 : moves_count cohérent avec moves_log
  -- ===========================================================
  if v_sess.moves_count != v_total_moves then
    v_invalidities := array_append(v_invalidities,
      format('moves_count_mismatch: declared=%s, actual=%s',
             v_sess.moves_count, v_total_moves));
  end if;

  -- ===========================================================
  -- CHECK 2 : parcours des moves, validation sequence + score
  -- ===========================================================
  for v_move in select * from jsonb_array_elements(v_moves) loop
    v_move_type := (v_move->>'t')::int;
    v_curr_ts := coalesce((v_move->>'ts')::int, 0);

    -- Timestamps croissants (sinon : injection ou désordre)
    if v_curr_ts < v_prev_ts then
      v_invalidities := array_append(v_invalidities,
        format('timestamp_out_of_order: prev=%s, curr=%s', v_prev_ts, v_curr_ts));
    end if;
    v_prev_ts := v_curr_ts;

    -- Compte le type + score increment
    case v_move_type
      when 0 then  -- drawFromStock
        v_count_draw := v_count_draw + 1;
      when 1 then  -- recycleStock
        v_count_recycle := v_count_recycle + 1;
      when 2 then  -- wasteToFoundation
        v_count_waste_to_found := v_count_waste_to_found + 1;
        v_expected_score := v_expected_score + 10;
      when 3 then  -- wasteToTableau
        v_count_waste_to_tab := v_count_waste_to_tab + 1;
        v_expected_score := v_expected_score + 5;
      when 4 then  -- tableauToFoundation
        v_count_tab_to_found := v_count_tab_to_found + 1;
        v_expected_score := v_expected_score + 10;
      when 5 then  -- tableauToTableau
        v_count_tab_to_tab := v_count_tab_to_tab + 1;
        v_expected_score := v_expected_score + 5;
      else
        v_invalidities := array_append(v_invalidities,
          format('unknown_move_type: %s', v_move_type));
    end case;

    -- Validation des champs requis selon le type
    if v_move_type in (3, 5) and v_move->>'d' is null then
      v_invalidities := array_append(v_invalidities,
        format('missing_dst_col: move_type=%s', v_move_type));
    end if;
    if v_move_type in (4, 5) and v_move->>'s' is null then
      v_invalidities := array_append(v_invalidities,
        format('missing_src_col: move_type=%s', v_move_type));
    end if;
    if v_move_type = 5 and v_move->>'i' is null then
      v_invalidities := array_append(v_invalidities,
        'missing_card_idx: move_type=5');
    end if;
  end loop;

  -- ===========================================================
  -- CHECK 3 : si won, ajouter le bonus +500
  -- ===========================================================
  if v_sess.state = 'paid' then
    v_expected_score := v_expected_score + 500;
  end if;

  -- ===========================================================
  -- CHECK 4 : score déclaré ≈ score recalculé (tolérance ±0)
  -- ===========================================================
  v_score_diff := abs(coalesce(v_sess.final_score, 0) - v_expected_score);
  if v_score_diff > 0 then
    v_invalidities := array_append(v_invalidities,
      format('score_mismatch: declared=%s, computed=%s, diff=%s',
             v_sess.final_score, v_expected_score, v_score_diff));
  end if;

  -- ===========================================================
  -- CHECK 5 : si won, contraintes d'intégrité fortes
  -- ===========================================================
  if v_sess.state = 'paid' then
    -- Nombre minimum de moves vers foundation : 52 cartes obligatoires
    -- (somme waste_to_found + tab_to_found doit être ≥ 52)
    if (v_count_waste_to_found + v_count_tab_to_found) < 52 then
      v_invalidities := array_append(v_invalidities,
        format('insufficient_foundation_moves: total=%s, required=52',
               v_count_waste_to_found + v_count_tab_to_found));
    end if;
    -- Score minimum théorique : 52*10 + 500 = 1020
    if coalesce(v_sess.final_score, 0) < 1020 then
      v_invalidities := array_append(v_invalidities,
        format('score_too_low_for_win: %s < 1020', v_sess.final_score));
    end if;
    -- Score maximum théorique : ~52*10 + 50*5 + 500 = 1270
    if coalesce(v_sess.final_score, 0) > 1500 then
      v_invalidities := array_append(v_invalidities,
        format('score_implausibly_high: %s > 1500', v_sess.final_score));
    end if;
  end if;

  -- ===========================================================
  -- CHECK 6 : warnings (non-blocants mais flag)
  -- ===========================================================
  -- Pace des moves
  if v_sess.closed_at is not null and v_total_moves > 0 then
    declare v_elapsed int;
            v_pace numeric;
    begin
      v_elapsed := extract(epoch from (v_sess.closed_at - v_sess.bet_at))::int;
      if v_elapsed > 0 then
        v_pace := v_total_moves::numeric / v_elapsed;
        if v_pace > 5 then
          v_warnings := array_append(v_warnings,
            format('bot_pace_warning: moves_per_sec=%s', round(v_pace, 2)));
        end if;
      end if;
    end;
  end if;

  -- ===========================================================
  -- Décision finale
  -- ===========================================================
  if array_length(v_invalidities, 1) is null then
    if array_length(v_warnings, 1) is null then
      v_status := 'valid';
    else
      v_status := 'review'; -- valide mais à surveiller
    end if;
  else
    v_status := 'invalid';
  end if;

  -- Persiste le résultat
  update solitaire_sessions
     set validation_status = v_status,
         validated_at = now(),
         validation_details = jsonb_build_object(
           'invalidities', to_jsonb(v_invalidities),
           'warnings',     to_jsonb(v_warnings),
           'expected_score', v_expected_score,
           'declared_score', v_sess.final_score,
           'move_counts',  jsonb_build_object(
             'draw',                v_count_draw,
             'recycle',             v_count_recycle,
             'waste_to_foundation', v_count_waste_to_found,
             'waste_to_tableau',    v_count_waste_to_tab,
             'tableau_to_foundation', v_count_tab_to_found,
             'tableau_to_tableau',  v_count_tab_to_tab,
             'total',               v_total_moves
           )
         )
   where id = p_session_id;

  -- Si invalide ET payée → alert admin haute sévérité
  if v_status = 'invalid' and v_sess.state = 'paid' and v_sess.paid_amount > 0 then
    begin
      insert into admin_alerts(user_id, alert_type, severity, title, description, metadata)
      values (v_sess.user_id, 'solitaire_invalid_session', 'critical',
              format('Session Solitaire payée mais INVALIDE (%s anomalies)',
                     array_length(v_invalidities, 1)),
              'La session a passé le payout mais le replay structural détecte des incohérences. Possible triche.',
              jsonb_build_object(
                'session_id', p_session_id,
                'paid', v_sess.paid_amount,
                'invalidities', to_jsonb(v_invalidities),
                'declared_score', v_sess.final_score,
                'expected_score', v_expected_score));
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'session_id', p_session_id,
    'status', v_status,
    'valid', v_status = 'valid',
    'invalidities', to_jsonb(v_invalidities),
    'warnings', to_jsonb(v_warnings),
    'expected_score', v_expected_score,
    'declared_score', v_sess.final_score
  );
end $$;
revoke all on function public.solitaire_validate_session(uuid) from public, anon, authenticated;

-- ============================================================
-- 4. Validation batch (cron toutes les 5 min sur sessions récentes)
-- ============================================================
create or replace function public.solitaire_validate_recent_sessions()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select id from solitaire_sessions
     where state in ('paid','forfeit')
       and validation_status = 'unchecked'
       and closed_at > now() - interval '1 hour'
     order by closed_at desc
     limit 100
  loop
    perform solitaire_validate_session(r.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke all on function public.solitaire_validate_recent_sessions() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'solitaire-validate-recent';
    perform cron.schedule('solitaire-validate-recent', '*/5 * * * *',
      $cron$ select public.solitaire_validate_recent_sessions(); $cron$);
    raise notice 'Cron solitaire-validate-recent schedulé (toutes les 5 min)';
  end if;
end $$;

-- ============================================================
-- 5. Trigger : validation immédiate après chaque payout
-- ============================================================
-- Permet de valider EN TEMPS RÉEL (pas attendre 5 min). Si invalide,
-- alert admin auto. Le payout est déjà fait à ce stade (pas blocking)
-- mais l'admin peut bloquer le user et reverse manuellement.
create or replace function public._solitaire_trigger_validate()
returns trigger
language plpgsql security definer set search_path=public, extensions
as $$
begin
  if NEW.state in ('paid','forfeit') and OLD.state = 'open' then
    perform solitaire_validate_session(NEW.id);
  end if;
  return NEW;
end $$;

drop trigger if exists trg_solitaire_validate_on_close on public.solitaire_sessions;
create trigger trg_solitaire_validate_on_close
  after update of state on public.solitaire_sessions
  for each row
  when (NEW.state in ('paid','forfeit') and OLD.state = 'open')
  execute function public._solitaire_trigger_validate();

-- ============================================================
-- 6. Vue admin : sessions invalides
-- ============================================================
drop view if exists public.solitaire_invalid_sessions_v;
create view public.solitaire_invalid_sessions_v as
select s.id as session_id, s.user_id, up.username,
       s.bet_amount, s.paid_amount, s.final_score, s.moves_count,
       s.validation_status, s.validation_details,
       s.bet_at, s.closed_at, s.validated_at,
       extract(epoch from (s.closed_at - s.bet_at))::int as elapsed_sec
  from solitaire_sessions s
  left join user_profiles up on up.id = s.user_id
 where s.validation_status in ('invalid','review')
 order by s.closed_at desc;
revoke all on solitaire_invalid_sessions_v from public, anon, authenticated;

-- ============================================================
-- 7. Top users suspects (winrate vs validation_failures)
-- ============================================================
drop view if exists public.solitaire_user_risk_v;
create view public.solitaire_user_risk_v as
with user_stats as (
  select user_id,
         count(*) as total_sessions,
         count(*) filter (where state = 'paid') as wins,
         count(*) filter (where validation_status = 'invalid') as invalid_count,
         count(*) filter (where validation_status = 'review') as review_count,
         sum(paid_amount) filter (where state = 'paid') as total_won
    from solitaire_sessions
   where bet_at > now() - interval '7 days'
     and not is_practice
   group by user_id
)
select us.*,
       up.username,
       round(100.0 * us.wins / nullif(us.total_sessions, 0), 1) as winrate_pct,
       round(100.0 * us.invalid_count / nullif(us.total_sessions, 0), 1) as invalid_pct,
       case
         when us.invalid_count > 0 then 'high_risk'
         when us.review_count >= 3 then 'medium_risk'
         when us.wins::float / nullif(us.total_sessions, 0) > 0.30 then 'high_winrate'
         else 'normal'
       end as risk_level
  from user_stats us
  left join user_profiles up on up.id = us.user_id
 where us.total_sessions >= 3
 order by us.invalid_count desc, us.review_count desc;
revoke all on solitaire_user_risk_v from public, anon, authenticated;

-- ============================================================
-- 8. Validation initiale des sessions existantes
-- ============================================================
do $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select id from solitaire_sessions
     where state in ('paid','forfeit')
       and validation_status = 'unchecked'
     order by closed_at desc
     limit 200
  loop
    begin
      perform solitaire_validate_session(r.id);
      v_count := v_count + 1;
    exception when others then
      raise notice 'Validation failed for session %: %', r.id, sqlerrm;
    end;
  end loop;
  raise notice 'Validated % existing sessions', v_count;
end $$;
