-- ============================================================
-- NETWORK TELEMETRY (P4)
-- ============================================================
-- But : MESURER l'impact reel des coupures reseau sur les jeux.
-- NetworkRetry logue chaque action qui a du etre reessayee :
--   - outcome='recovered' : a fini par passer apres N retries
--   - outcome='failed'    : a echoue malgre tous les retries
--
-- Permet dans le dashboard de voir :
--   - combien de joueurs subissent des coupures
--   - sur quels jeux/actions (label)
--   - si P1/P2/P3 ont reduit le probleme dans le temps
--
-- Aucun impact gameplay : insertion fire-and-forget cote client,
-- toute erreur avalee. Pas de retry sur le log lui-meme.
--
-- Idempotent (IF NOT EXISTS / CREATE OR REPLACE).
-- ============================================================

begin;

-- ============================================================
-- 1) Table
-- ============================================================
create table if not exists public.network_events (
  id         bigint generated always as identity primary key,
  user_id    uuid,
  label      text not null,        -- ex: cf_choose_side, bj_hit, cora_submit_roll
  retries    int  not null default 0,
  outcome    text not null check (outcome in ('recovered','failed')),
  err        text,
  created_at timestamptz not null default now()
);

create index if not exists idx_netev_created on public.network_events (created_at);
create index if not exists idx_netev_label   on public.network_events (label, created_at);

alter table public.network_events enable row level security;
-- Aucune policy : seule la fonction SECURITY DEFINER ecrit. Lecture
-- = dashboard via service_role (bypass RLS) ou la vue d'agregat.

-- ============================================================
-- 2) RPC d'insertion (appelee par le client, fire-and-forget)
-- ============================================================
create or replace function public.log_network_event(
  p_label   text,
  p_retries int,
  p_outcome text,
  p_err     text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then return; end if;                 -- pas de log anonyme
  if p_label is null or length(p_label) = 0 then return; end if;
  if p_outcome not in ('recovered','failed') then return; end if;

  insert into public.network_events (user_id, label, retries, outcome, err)
  values (
    v_uid,
    left(p_label, 64),
    greatest(coalesce(p_retries, 0), 0),
    p_outcome,
    case when p_err is null then null else left(p_err, 300) end
  );
end $$;
revoke all on function public.log_network_event(text, int, text, text) from public, anon;
grant execute on function public.log_network_event(text, int, text, text) to authenticated;

-- ============================================================
-- 3) Vue d'agregat pour le dashboard (par jour / label / outcome)
-- ============================================================
create or replace view public.network_events_daily_v as
select
  date_trunc('day', created_at)            as day,
  label,
  outcome,
  count(*)                                 as events,
  count(distinct user_id)                  as users,
  round(avg(retries)::numeric, 2)          as avg_retries,
  max(retries)                             as max_retries
from public.network_events
group by 1, 2, 3
order by 1 desc, events desc;

-- ============================================================
-- 4) Purge cron : on garde 30 jours d'historique
-- ============================================================
create or replace function public.network_events_purge()
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  with d as (
    delete from public.network_events
    where created_at < now() - interval '30 days'
    returning 1
  ) select count(*) into v_n from d;
  return v_n;
end $$;
revoke all on function public.network_events_purge() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('network_events_purge')
      where exists (select 1 from cron.job where jobname = 'network_events_purge');
    perform cron.schedule('network_events_purge', '15 3 * * *',
      $cron$ select public.network_events_purge(); $cron$);
  end if;
end $$;

commit;

-- ============================================================
-- VERIFICATIONS
-- ============================================================
-- 1) La RPC existe :
--    select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and proname='log_network_event';
--
-- 2) Test insert (en tant qu'utilisateur connecte) :
--    select public.log_network_event('test_label', 2, 'recovered', null);
--    select * from public.network_events order by id desc limit 1;
--
-- 3) Dashboard : select * from public.network_events_daily_v limit 20;
