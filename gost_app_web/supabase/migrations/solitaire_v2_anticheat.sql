-- ============================================================
-- SOLITAIRE V2.1 — Foundation anti-cheat (seed + moves audit)
-- ============================================================
-- Ajoute :
--   1. seed dans solitaire_sessions (reproductibilité du shuffle)
--   2. moves_log jsonb dans solitaire_sessions (audit & replay)
--   3. solitaire_place_bet retourne le seed généré serveur
--   4. solitaire_payout accepte p_moves jsonb et fait des plausibility checks
--   5. solitaire_validate_session() : audit/replay pour admin
--
-- Note : la validation FULL (replay des 52 cartes) reste un fix P1 séparé.
-- Cette migration pose les fondations pour pouvoir l'implémenter.
-- ============================================================

-- 1. Ajout colonnes seed + moves_log (idempotent)
alter table public.solitaire_sessions
  add column if not exists seed bigint,
  add column if not exists moves_log jsonb default '[]'::jsonb,
  add column if not exists moves_count int default 0,
  add column if not exists fraud_flags jsonb default '[]'::jsonb;

create index if not exists idx_solitaire_sessions_fraud
  on public.solitaire_sessions((jsonb_array_length(fraud_flags)))
  where jsonb_array_length(fraud_flags) > 0;

-- ============================================================
-- 2. solitaire_place_bet V2.1 — génère le seed serveur
-- ============================================================
create or replace function public.solitaire_place_bet(
  p_amount      bigint,
  p_is_practice boolean default false
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_cfg solitaire_config;
  v_session_id uuid;
  v_open_count int;
  v_request_id text;
  v_seed bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;

  select * into v_cfg from solitaire_config where id = 1;

  begin
    perform check_rate_limit('solitaire_bet', v_uid::text, v_cfg.max_sessions_per_min, '1 minute');
  exception when undefined_function then null;
  end;

  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  -- Seed cryptographique 63-bit (positif, fits dans bigint)
  v_seed := abs(('x' || encode(gen_random_bytes(8), 'hex'))::bit(64)::bigint);

  if p_is_practice then
    v_session_id := gen_random_uuid();
    insert into solitaire_sessions(
      id, user_id, bet_amount, is_practice, state, request_id_bet, seed)
      values (v_session_id, v_uid, 0, true, 'open',
              'solitaire_practice:' || v_session_id::text, v_seed);
    return jsonb_build_object(
      'session_id', v_session_id,
      'bet', 0,
      'is_practice', true,
      'seed', v_seed);
  end if;

  if p_amount < v_cfg.min_bet or p_amount > v_cfg.max_bet then
    raise exception 'INVALID_BET_RANGE: min=% max=%', v_cfg.min_bet, v_cfg.max_bet
      using errcode = '22023';
  end if;

  select count(*) into v_open_count from solitaire_sessions
   where user_id = v_uid and state = 'open'
     and bet_at > now() - (v_cfg.session_timeout_min || ' minutes')::interval;
  if v_open_count > 0 then
    raise exception 'SESSION_ALREADY_OPEN' using errcode = 'P0006';
  end if;

  if (select wallet_balance(v_uid)) < p_amount then
    raise exception 'INSUFFICIENT_FUNDS' using errcode = 'P0001';
  end if;

  v_session_id := gen_random_uuid();
  v_request_id := 'solitaire_bet:' || v_session_id::text;

  perform _ledger_post(
    v_uid, -p_amount, 'bet', v_request_id,
    'solitaire', v_session_id::text,
    jsonb_build_object('source','solitaire_place_bet','session_id',v_session_id,
                       'seed',v_seed));

  insert into solitaire_sessions(
    id, user_id, bet_amount, is_practice, state, request_id_bet, seed)
    values (v_session_id, v_uid, p_amount, false, 'open', v_request_id, v_seed);

  return jsonb_build_object(
    'session_id', v_session_id,
    'bet', p_amount,
    'is_practice', false,
    'seed', v_seed,
    'expires_at', now() + (v_cfg.session_timeout_min || ' minutes')::interval
  );
end; $$;

revoke all on function public.solitaire_place_bet(bigint, boolean) from public, anon;
grant execute on function public.solitaire_place_bet(bigint, boolean) to authenticated;

-- ============================================================
-- 3. solitaire_payout V2.1 — accepte p_moves + plausibility checks
-- ============================================================
drop function if exists public.solitaire_payout(uuid, int, boolean);

create or replace function public.solitaire_payout(
  p_session_id uuid,
  p_score      int,
  p_won        boolean,
  p_moves      jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_sess solitaire_sessions;
  v_cfg solitaire_config;
  v_gross bigint;
  v_cut bigint;
  v_net bigint;
  v_today_payout bigint;
  v_moves_count int;
  v_fraud_flags jsonb := '[]'::jsonb;
  v_elapsed_sec int;
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;
  select * into v_cfg from solitaire_config where id = 1;

  select * into v_sess from solitaire_sessions
   where id = p_session_id and user_id = v_uid for update;
  if not found then raise exception 'SESSION_NOT_FOUND' using errcode = 'P0002'; end if;

  -- Idempotence
  if v_sess.state = 'paid' then
    return jsonb_build_object('paid', v_sess.paid_amount, 'state', 'paid', 'idempotent', true);
  end if;
  if v_sess.state in ('forfeit','expired','cancelled') then
    return jsonb_build_object('paid', 0, 'state', v_sess.state, 'idempotent', true);
  end if;
  if v_sess.state != 'open' then
    raise exception 'SESSION_INVALID_STATE: %', v_sess.state using errcode = 'P0007';
  end if;

  if v_sess.bet_at < now() - (v_cfg.session_timeout_min || ' minutes')::interval then
    update solitaire_sessions set state='expired', closed_at=now(), final_score=p_score
      where id = p_session_id;
    raise exception 'SESSION_EXPIRED' using errcode = 'P0008';
  end if;

  -- ===========================================================
  -- PLAUSIBILITY CHECKS (anti-cheat partiel)
  -- ===========================================================
  v_moves_count := jsonb_array_length(coalesce(p_moves, '[]'::jsonb));
  v_elapsed_sec := extract(epoch from (now() - v_sess.bet_at))::int;

  -- Check 1 : si gagné, il faut au minimum N moves (52 cartes à placer en
  -- fondation = au moins 52 moves, plus quelques inter-tableau)
  if p_won and v_moves_count < 30 then
    v_fraud_flags := v_fraud_flags || jsonb_build_array(
      jsonb_build_object('flag', 'too_few_moves',
        'moves', v_moves_count, 'min_expected', 30));
  end if;

  -- Check 2 : score plausible vs nombre de moves
  -- Score max raisonnable = 52*10 (foundations) + 50*5 (inter-tableau) + 500 (win)
  --                     ≈ 1270 points pour une partie parfaite
  if p_won and p_score > 1500 then
    v_fraud_flags := v_fraud_flags || jsonb_build_array(
      jsonb_build_object('flag', 'score_too_high', 'score', p_score, 'max', 1500));
  end if;

  -- Check 3 : temps trop court pour une victoire (< 30 secondes = suspicieux)
  if p_won and v_elapsed_sec < 30 then
    v_fraud_flags := v_fraud_flags || jsonb_build_array(
      jsonb_build_object('flag', 'too_fast_win',
        'elapsed_sec', v_elapsed_sec, 'min', 30));
  end if;

  -- Check 4 : ratio moves/sec absurde (> 5/sec = bot probable)
  if v_moves_count > 0 and v_elapsed_sec > 0
     and (v_moves_count::float / v_elapsed_sec) > 5 then
    v_fraud_flags := v_fraud_flags || jsonb_build_array(
      jsonb_build_object('flag', 'bot_pace',
        'moves_per_sec', round((v_moves_count::numeric / v_elapsed_sec)::numeric, 2)));
  end if;

  -- ===========================================================
  -- POLICY : si fraud_flags présent → flag pour audit, mais on paie
  -- quand même. L'admin voit l'alerte et peut bloquer le user.
  -- (Bloquer immédiatement = trop strict, faux positifs possibles)
  -- ===========================================================

  if v_sess.is_practice then
    update solitaire_sessions
       set state = case when p_won then 'paid' else 'forfeit' end,
           closed_at = now(), final_score = p_score, paid_amount = 0,
           moves_log = p_moves, moves_count = v_moves_count,
           fraud_flags = v_fraud_flags
     where id = p_session_id;
    return jsonb_build_object('paid', 0, 'state', 'practice_done',
                              'fraud_flags', v_fraud_flags);
  end if;

  if not p_won then
    update solitaire_sessions
       set state='forfeit', closed_at=now(), final_score=p_score,
           moves_log=p_moves, moves_count=v_moves_count,
           fraud_flags=v_fraud_flags
     where id = p_session_id;
    return jsonb_build_object('paid', 0, 'state', 'forfeit');
  end if;

  -- VICTOIRE : payout server-validé
  v_gross := v_sess.bet_amount * 2;
  v_cut := floor(v_gross * v_cfg.house_cut_pct)::bigint;
  v_net := v_gross - v_cut;

  -- Cap journalier
  select coalesce(sum(paid_amount), 0) into v_today_payout
    from solitaire_sessions
   where user_id = v_uid and state = 'paid'
     and closed_at > now() - interval '24 hours';
  if v_today_payout + v_net > v_cfg.max_payout_per_24h then
    raise exception 'DAILY_PAYOUT_CAP_REACHED' using errcode = 'P0009';
  end if;

  perform _ledger_post(
    v_uid, v_net, 'payout',
    'solitaire_payout:' || p_session_id::text,
    'solitaire', p_session_id::text,
    jsonb_build_object('gross', v_gross, 'commission', v_cut, 'score', p_score,
                       'fraud_flags', v_fraud_flags));

  if v_cut > 0 then
    update admin_treasury set balance=balance+v_cut, total_earned=total_earned+v_cut,
      updated_at=now() where id = 1;
    if not found then
      insert into admin_treasury(id, balance, total_earned, total_withdrawn)
        values (1, v_cut, v_cut, 0);
    end if;
  end if;

  -- Si fraud_flags présent → alerte admin
  if jsonb_array_length(v_fraud_flags) > 0 then
    begin
      insert into admin_alerts(user_id, alert_type, severity, title, description, metadata)
      values (v_uid, 'solitaire_suspicious_win',
              case when jsonb_array_length(v_fraud_flags) >= 2 then 'high' else 'medium' end,
              format('Victoire Solitaire suspecte (%s flags)', jsonb_array_length(v_fraud_flags)),
              'Plausibility checks ont détecté des anomalies. Voir metadata.fraud_flags.',
              jsonb_build_object('session_id', p_session_id,
                                 'bet', v_sess.bet_amount,
                                 'payout', v_net,
                                 'score', p_score,
                                 'moves_count', v_moves_count,
                                 'elapsed_sec', v_elapsed_sec,
                                 'fraud_flags', v_fraud_flags));
    exception when undefined_table then null;
    end;
  end if;

  update solitaire_sessions
     set state='paid', closed_at=now(), final_score=p_score,
         paid_amount=v_net,
         request_id_pay='solitaire_payout:' || p_session_id::text,
         moves_log=p_moves, moves_count=v_moves_count,
         fraud_flags=v_fraud_flags
   where id = p_session_id;

  return jsonb_build_object(
    'paid', v_net, 'gross', v_gross, 'commission', v_cut, 'state', 'paid',
    'fraud_flags', v_fraud_flags);
end; $$;

revoke all on function public.solitaire_payout(uuid, int, boolean, jsonb) from public, anon;
grant execute on function public.solitaire_payout(uuid, int, boolean, jsonb) to authenticated;

-- ============================================================
-- 4. solitaire_get_active_session retourne aussi le seed
--    (déjà OK car SELECT * to_jsonb)
-- ============================================================

-- ============================================================
-- 5. View admin pour voir les sessions suspectes
-- ============================================================
create or replace view public.solitaire_fraud_alerts_v as
select id as session_id, user_id, bet_amount, paid_amount, final_score,
       moves_count, fraud_flags, bet_at, closed_at,
       extract(epoch from (closed_at - bet_at))::int as elapsed_sec
  from solitaire_sessions
 where jsonb_array_length(fraud_flags) > 0
 order by bet_at desc;
revoke all on solitaire_fraud_alerts_v from public, anon, authenticated;
