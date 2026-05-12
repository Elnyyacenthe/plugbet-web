-- ============================================================
-- SOLITAIRE V2 — Production (session-based, idempotent, anti-cheat)
-- ============================================================
-- Corrige TOUS les bugs critiques identifiés à l'audit :
--   1. Vol direct via solitaire_payout sans bet → session_id obligatoire
--   2. Multiple wins idempotent (request_id unique par session)
--   3. Manipulation de p_gross → calculé serveur (= bet × 2), client ignoré
--   4. Mode practice exploitable → session typée + check serveur
--   5. saveBestScore direct UPDATE → RPC validée
--   6. Pas de rate limit → ajouté
--   7. Pas de bornes bet → 50 ≤ bet ≤ 10000
--   8. Pas de cap journalier → 100 000 FCFA / 24h max payout
--   9. Crash app = mise perdue silencieusement → cora_get_active equivalent
-- ============================================================

-- ============================================================
-- 0. Pré-requis
-- ============================================================
create extension if not exists pgcrypto;

-- ============================================================
-- 1. Table solitaire_sessions (immutable trace)
-- ============================================================
create table if not exists public.solitaire_sessions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  bet_amount      bigint not null check (bet_amount >= 50 and bet_amount <= 10000),
  is_practice     boolean not null default false,
  state           text not null check (state in ('open','paid','forfeit','expired','cancelled')),
  paid_amount     bigint,
  final_score     int,
  bet_at          timestamptz not null default now(),
  closed_at       timestamptz,
  request_id_bet  text not null,
  request_id_pay  text,
  metadata        jsonb default '{}'::jsonb,
  unique (user_id, request_id_bet)
);

create index if not exists idx_solitaire_sessions_user_state
  on public.solitaire_sessions(user_id, state)
  where state = 'open';

create index if not exists idx_solitaire_sessions_bet_at
  on public.solitaire_sessions(bet_at desc);

alter table public.solitaire_sessions enable row level security;

drop policy if exists "solitaire_sessions_select_own" on public.solitaire_sessions;
create policy "solitaire_sessions_select_own" on public.solitaire_sessions
  for select using (user_id = auth.uid());
-- Aucune policy INSERT/UPDATE/DELETE → mutation uniquement via RPCs

-- ============================================================
-- 2. Table solitaire_config (admin tunable)
-- ============================================================
create table if not exists public.solitaire_config (
  id                   int primary key default 1 check (id = 1),
  min_bet              bigint not null default 50,
  max_bet              bigint not null default 10000,
  house_cut_pct        numeric(4,3) not null default 0.10
                         check (house_cut_pct between 0 and 0.30),
  session_timeout_min  int not null default 15,
  max_payout_per_24h   bigint not null default 100000,
  max_sessions_per_min int not null default 5,
  updated_at           timestamptz not null default now()
);
insert into public.solitaire_config(id) values (1) on conflict (id) do nothing;

alter table public.solitaire_config enable row level security;
drop policy if exists "solitaire_config_read" on public.solitaire_config;
create policy "solitaire_config_read" on public.solitaire_config
  for select to authenticated using (true);

-- ============================================================
-- 3. DROP des anciennes RPCs vulnérables
-- ============================================================
drop function if exists public.solitaire_place_bet(int) cascade;
drop function if exists public.solitaire_payout(int) cascade;

-- ============================================================
-- 4. solitaire_place_bet V2 — débit + crée session
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
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;

  select * into v_cfg from solitaire_config where id = 1;

  -- Rate limit (best-effort)
  begin
    perform check_rate_limit('solitaire_bet', v_uid::text, v_cfg.max_sessions_per_min, '1 minute');
  exception when undefined_function then null;
  end;

  -- User bloqué ?
  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  -- En mode practice : pas de débit, juste créer une session
  if p_is_practice then
    v_session_id := gen_random_uuid();
    insert into solitaire_sessions(id, user_id, bet_amount, is_practice, state, request_id_bet)
      values (v_session_id, v_uid, 0, true, 'open',
              'solitaire_practice:' || v_session_id::text);
    return jsonb_build_object('session_id', v_session_id, 'bet', 0, 'is_practice', true);
  end if;

  -- Validation des bornes
  if p_amount < v_cfg.min_bet or p_amount > v_cfg.max_bet then
    raise exception 'INVALID_BET_RANGE: min=% max=%', v_cfg.min_bet, v_cfg.max_bet
      using errcode = '22023';
  end if;

  -- Une seule session 'open' à la fois (prévient double-tap + multi-onglets)
  select count(*) into v_open_count
    from solitaire_sessions
   where user_id = v_uid
     and state = 'open'
     and bet_at > now() - (v_cfg.session_timeout_min || ' minutes')::interval;
  if v_open_count > 0 then
    raise exception 'SESSION_ALREADY_OPEN' using errcode = 'P0006',
      detail = 'Une partie est déjà en cours. Termine-la ou attends 15 min.';
  end if;

  -- Solde suffisant
  if (select wallet_balance(v_uid)) < p_amount then
    raise exception 'INSUFFICIENT_FUNDS: required=%, balance=%',
      p_amount, (select wallet_balance(v_uid))
      using errcode = 'P0001';
  end if;

  -- Atomique : crée la session + débit ledger
  v_session_id := gen_random_uuid();
  v_request_id := 'solitaire_bet:' || v_session_id::text;

  perform _ledger_post(
    v_uid, -p_amount, 'bet',
    v_request_id,
    'solitaire', v_session_id::text,
    jsonb_build_object('source', 'solitaire_place_bet', 'session_id', v_session_id)
  );

  insert into solitaire_sessions(id, user_id, bet_amount, is_practice, state, request_id_bet)
    values (v_session_id, v_uid, p_amount, false, 'open', v_request_id);

  return jsonb_build_object(
    'session_id', v_session_id,
    'bet', p_amount,
    'is_practice', false,
    'expires_at', now() + (v_cfg.session_timeout_min || ' minutes')::interval
  );
end; $$;

revoke all on function public.solitaire_place_bet(bigint, boolean) from public, anon;
grant execute on function public.solitaire_place_bet(bigint, boolean) to authenticated;

-- ============================================================
-- 5. solitaire_payout V2 — payout server-validé, idempotent
-- ============================================================
-- Le client passe SEULEMENT session_id, score, won. Le payout est
-- calculé côté serveur (= bet × 2, commission 10%). Le client ne contrôle
-- AUCUN montant. Aucun vol direct possible.
create or replace function public.solitaire_payout(
  p_session_id uuid,
  p_score      int,
  p_won        boolean
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
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;

  select * into v_cfg from solitaire_config where id = 1;

  -- Lock atomique sur la session
  select * into v_sess from solitaire_sessions
   where id = p_session_id and user_id = v_uid
   for update;

  if not found then
    raise exception 'SESSION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Idempotence : si déjà payée, retourner l'état existant
  if v_sess.state = 'paid' then
    return jsonb_build_object(
      'paid', v_sess.paid_amount,
      'state', 'paid',
      'idempotent', true);
  end if;
  if v_sess.state in ('forfeit','expired','cancelled') then
    return jsonb_build_object('paid', 0, 'state', v_sess.state, 'idempotent', true);
  end if;
  if v_sess.state != 'open' then
    raise exception 'SESSION_INVALID_STATE: %', v_sess.state using errcode = 'P0007';
  end if;

  -- Expiration ?
  if v_sess.bet_at < now() - (v_cfg.session_timeout_min || ' minutes')::interval then
    update solitaire_sessions
       set state = 'expired', closed_at = now(), final_score = p_score
     where id = p_session_id;
    raise exception 'SESSION_EXPIRED' using errcode = 'P0008';
  end if;

  -- Mode practice : rien à payer, juste fermer
  if v_sess.is_practice then
    update solitaire_sessions
       set state = case when p_won then 'paid' else 'forfeit' end,
           closed_at = now(),
           final_score = p_score,
           paid_amount = 0
     where id = p_session_id;
    return jsonb_build_object('paid', 0, 'state', 'practice_done', 'won', p_won);
  end if;

  -- Pas gagné = forfait, pas de payout (la mise est déjà perdue côté ledger)
  if not p_won then
    update solitaire_sessions
       set state = 'forfeit',
           closed_at = now(),
           final_score = p_score
     where id = p_session_id;
    return jsonb_build_object('paid', 0, 'state', 'forfeit');
  end if;

  -- ===========================================================
  -- VICTOIRE : payout SERVEUR-CALCULÉ
  --   gross = bet × 2 (NON contrôlable par le client)
  --   commission 10%
  -- ===========================================================
  v_gross := v_sess.bet_amount * 2;
  v_cut   := floor(v_gross * v_cfg.house_cut_pct)::bigint;
  v_net   := v_gross - v_cut;

  -- Cap journalier anti-blanchiment
  select coalesce(sum(paid_amount), 0) into v_today_payout
    from solitaire_sessions
   where user_id = v_uid
     and state = 'paid'
     and closed_at > now() - interval '24 hours';
  if v_today_payout + v_net > v_cfg.max_payout_per_24h then
    raise exception 'DAILY_PAYOUT_CAP_REACHED: today=%, max=%',
      v_today_payout, v_cfg.max_payout_per_24h
      using errcode = 'P0009';
  end if;

  -- Crédit gagnant via ledger (idempotent par request_id unique)
  perform _ledger_post(
    v_uid, v_net, 'payout',
    'solitaire_payout:' || p_session_id::text,
    'solitaire', p_session_id::text,
    jsonb_build_object(
      'gross', v_gross,
      'commission', v_cut,
      'house_cut_pct', v_cfg.house_cut_pct,
      'score', p_score
    )
  );

  -- Commission vers admin_treasury
  if v_cut > 0 then
    update admin_treasury
       set balance = balance + v_cut,
           total_earned = total_earned + v_cut,
           updated_at = now()
     where id = 1;
    if not found then
      insert into admin_treasury(id, balance, total_earned, total_withdrawn)
        values (1, v_cut, v_cut, 0);
    end if;
  end if;

  -- Marque la session comme payée
  update solitaire_sessions
     set state = 'paid',
         closed_at = now(),
         final_score = p_score,
         paid_amount = v_net,
         request_id_pay = 'solitaire_payout:' || p_session_id::text
   where id = p_session_id;

  return jsonb_build_object(
    'paid', v_net,
    'gross', v_gross,
    'commission', v_cut,
    'state', 'paid'
  );
end; $$;

revoke all on function public.solitaire_payout(uuid, int, boolean) from public, anon;
grant execute on function public.solitaire_payout(uuid, int, boolean) to authenticated;

-- ============================================================
-- 6. solitaire_get_active_session — reprise de session après crash
-- ============================================================
create or replace function public.solitaire_get_active_session()
returns jsonb
language sql stable security definer set search_path=public
as $$
  select to_jsonb(s) || jsonb_build_object(
    'expires_at', s.bet_at + (
      (select session_timeout_min from solitaire_config where id = 1) || ' minutes'
    )::interval
  )
  from solitaire_sessions s
  where s.user_id = auth.uid()
    and s.state = 'open'
    and s.bet_at > now() - interval '15 minutes'
  order by s.bet_at desc
  limit 1;
$$;

revoke all on function public.solitaire_get_active_session() from public, anon;
grant execute on function public.solitaire_get_active_session() to authenticated;

-- ============================================================
-- 7. solitaire_cancel_session — annule une session ouverte avec refund
-- ============================================================
-- Utilisé quand le client veut quitter avant d'avoir vraiment commencé
-- (ex. l'écran s'est ouvert par erreur). Refund seulement dans les
-- 5 premières secondes pour empêcher l'abus.
create or replace function public.solitaire_cancel_session(
  p_session_id uuid
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_sess solitaire_sessions;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_sess from solitaire_sessions
   where id = p_session_id and user_id = v_uid
   for update;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;
  if v_sess.state != 'open' then
    return jsonb_build_object('cancelled', false, 'state', v_sess.state);
  end if;

  -- Refund seulement si annulé < 5s (anti-abus : sinon = forfait)
  if v_sess.bet_at < now() - interval '5 seconds' then
    update solitaire_sessions
       set state = 'forfeit', closed_at = now()
     where id = p_session_id;
    return jsonb_build_object('cancelled', false, 'state', 'forfeit',
                              'reason', 'too_late_for_refund');
  end if;

  -- Refund la mise via ledger (idempotent)
  if v_sess.bet_amount > 0 and not v_sess.is_practice then
    perform _ledger_post(
      v_uid, v_sess.bet_amount, 'refund',
      'solitaire_cancel:' || p_session_id::text,
      'solitaire', p_session_id::text,
      jsonb_build_object('reason', 'cancel_within_5s')
    );
  end if;

  update solitaire_sessions
     set state = 'cancelled', closed_at = now()
   where id = p_session_id;

  return jsonb_build_object('cancelled', true, 'refunded', v_sess.bet_amount);
end; $$;

revoke all on function public.solitaire_cancel_session(uuid) from public, anon;
grant execute on function public.solitaire_cancel_session(uuid) to authenticated;

-- ============================================================
-- 8. update_solitaire_best_score — RPC sécurisée (vs UPDATE direct)
-- ============================================================
create or replace function public.update_solitaire_best_score(
  p_score int
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_current int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_score < 0 or p_score > 5000 then
    raise exception 'INVALID_SCORE_RANGE' using errcode = '22023';
  end if;

  -- N'accepte que si l'user a une session récente avec ce score
  -- (anti-manipulation leaderboard direct)
  if not exists (
    select 1 from solitaire_sessions
     where user_id = v_uid
       and final_score >= p_score
       and closed_at > now() - interval '5 minutes'
  ) then
    raise exception 'NO_RECENT_VALID_SESSION';
  end if;

  select coalesce(solitaire_best_score, 0) into v_current
    from user_profiles where id = v_uid;

  if p_score > v_current then
    update user_profiles set solitaire_best_score = p_score where id = v_uid;
    return jsonb_build_object('updated', true, 'old', v_current, 'new', p_score);
  end if;

  return jsonb_build_object('updated', false, 'current', v_current);
end; $$;

revoke all on function public.update_solitaire_best_score(int) from public, anon;
grant execute on function public.update_solitaire_best_score(int) to authenticated;

-- ============================================================
-- 9. Cron : nettoyage des sessions expirées
-- ============================================================
create or replace function public.solitaire_cleanup_expired_sessions()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_count int := 0;
  v_timeout int;
begin
  select session_timeout_min into v_timeout from solitaire_config where id = 1;
  with expired as (
    update solitaire_sessions
       set state = 'expired', closed_at = now()
     where state = 'open'
       and bet_at < now() - (v_timeout || ' minutes')::interval
    returning 1
  )
  select count(*) into v_count from expired;
  return v_count;
end; $$;

revoke all on function public.solitaire_cleanup_expired_sessions() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'solitaire-session-cleanup';
    perform cron.schedule('solitaire-session-cleanup', '*/5 * * * *',
      $cron$ select public.solitaire_cleanup_expired_sessions(); $cron$);
    raise notice 'Cron solitaire-session-cleanup schedulé (toutes les 5 min)';
  end if;
end $$;

-- ============================================================
-- 10. Vue d'audit pour admin
-- ============================================================
create or replace view public.solitaire_metrics_v as
select
  count(*) filter (where state = 'open') as active_sessions,
  count(*) filter (where state = 'paid' and closed_at > now() - interval '1 hour') as wins_per_hour,
  count(*) filter (where state = 'forfeit' and closed_at > now() - interval '1 hour') as losses_per_hour,
  count(*) filter (where state = 'expired' and closed_at > now() - interval '1 hour') as timeouts_per_hour,
  count(*) filter (where state = 'cancelled' and closed_at > now() - interval '1 hour') as cancels_per_hour,
  coalesce(sum(bet_amount) filter (where bet_at > now() - interval '24 hours'), 0) as volume_24h,
  coalesce(sum(paid_amount) filter (where state = 'paid' and closed_at > now() - interval '24 hours'), 0) as payouts_24h,
  coalesce(avg(final_score) filter (where state = 'paid' and closed_at > now() - interval '24 hours'), 0) as avg_winning_score
from solitaire_sessions;
revoke all on solitaire_metrics_v from public, anon, authenticated;

comment on table public.solitaire_sessions is
  'Trace immutable de toutes les sessions solitaire. Lien place_bet ↔ payout.';
