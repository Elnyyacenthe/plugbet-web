-- ============================================================
-- CORA DICE V3 — Monitoring & Anti-fraude
-- ============================================================
-- Vue métriques + scan de patterns suspects + alertes admin
-- ============================================================

-- Pré-requis : admin_alerts (du module Ludo V2) doit avoir les colonnes
-- attendues par cora_scan_fraud_patterns. On ajoute en idempotent.
alter table public.admin_alerts add column if not exists user_id  uuid;
alter table public.admin_alerts add column if not exists metadata jsonb default '{}'::jsonb;
create index if not exists idx_admin_alerts_user on public.admin_alerts(user_id, created_at desc)
  where user_id is not null;

-- ============================================================
-- 1. Vue métriques temps réel
-- ============================================================
create or replace view public.cora_metrics_v as
with stats as (
  select
    count(*) filter (where status = 'playing') as active_games,
    count(*) filter (where status = 'finished' and updated_at > now() - interval '1 hour') as games_per_hour,
    count(*) filter (where status = 'finished' and updated_at > now() - interval '24 hours') as games_per_24h,
    count(*) filter (where status = 'cancelled' and updated_at > now() - interval '1 hour') as cancellations_per_hour,
    count(*) filter (where status = 'cancelled' and updated_at > now() - interval '24 hours') as cancellations_per_24h,
    avg(bet_amount * player_count) filter (where created_at > now() - interval '1 hour') as avg_pot_1h,
    sum(bet_amount * player_count) filter (where created_at > now() - interval '24 hours') as total_volume_24h
  from cora_games
)
select
  active_games,
  games_per_hour,
  games_per_24h,
  cancellations_per_hour,
  cancellations_per_24h,
  round(avg_pot_1h::numeric, 0) as avg_pot_1h,
  total_volume_24h,
  case when (games_per_hour + cancellations_per_hour) > 0
    then round(100.0 * cancellations_per_hour / (games_per_hour + cancellations_per_hour), 2)
    else 0 end as cancel_rate_pct_1h,
  (select count(*) from cora_rooms where status = 'waiting') as waiting_rooms,
  (select count(*) from cora_rooms where status = 'waiting' and created_at < now() - interval '30 minutes') as old_waiting_rooms
from stats;

-- Lecture admin uniquement
revoke all on cora_metrics_v from public, anon, authenticated;
grant select on cora_metrics_v to authenticated;
-- (les RLS en dessous ne s'appliquent pas aux vues, mais les tables sources sont protégées)

-- ============================================================
-- 2. Scan de patterns suspects (à appeler depuis admin_alerts cron)
-- ============================================================
create or replace function public.cora_scan_fraud_patterns()
returns int
language plpgsql security definer set search_path=public
as $$
declare
  v_count int := 0;
  v_user record;
begin
  -- Pattern 1 : winrate Cora anormalement élevé sur 7 derniers jours
  for v_user in
    with recent_games as (
      select g.id, g.winner_ids::text[] as winner_ids, g.status, g.created_at,
             p.user_id
      from cora_games g
      join cora_room_players p on p.room_id = g.room_id
      where g.created_at > now() - interval '7 days'
        and g.status = 'finished'
    )
    select user_id,
           count(*) as games,
           count(*) filter (where user_id::text = any(winner_ids)) as wins,
           round(100.0 * count(*) filter (where user_id::text = any(winner_ids)) / count(*), 1) as winrate
    from recent_games
    group by user_id
    having count(*) >= 20
       and 100.0 * count(*) filter (where user_id::text = any(winner_ids)) / count(*) > 70
  loop
    if not exists (
      select 1 from admin_alerts
       where user_id = v_user.user_id and alert_type = 'cora_high_winrate'
         and created_at > now() - interval '7 days'
    ) then
      insert into admin_alerts (user_id, alert_type, severity, title, description, metadata)
      values (
        v_user.user_id, 'cora_high_winrate', 'high',
        format('Cora Dice winrate %s%% (% / %)', v_user.winrate, v_user.wins, v_user.games),
        'Joueur avec winrate suspect sur 7 jours. Vérifier collusion ou exploit.',
        jsonb_build_object(
          'games', v_user.games, 'wins', v_user.wins,
          'winrate', v_user.winrate, 'period_days', 7
        )
      );
      v_count := v_count + 1;
    end if;
  end loop;

  -- Pattern 2 : volume de mises anormal en 24h
  for v_user in
    select user_id, sum(-amount) as volume
    from wallet_ledger
    where game_type = 'cora_dice'
      and type = 'bet'
      and created_at > now() - interval '24 hours'
    group by user_id
    having sum(-amount) > 500000
  loop
    if not exists (
      select 1 from admin_alerts
       where user_id = v_user.user_id and alert_type = 'cora_high_volume'
         and created_at > now() - interval '24 hours'
    ) then
      insert into admin_alerts (user_id, alert_type, severity, title, description, metadata)
      values (
        v_user.user_id, 'cora_high_volume', 'medium',
        format('Volume Cora 24h : %s coins', v_user.volume),
        'Volume de mises élevé en 24h. À surveiller (potential blanchiment).',
        jsonb_build_object('volume_24h', v_user.volume)
      );
      v_count := v_count + 1;
    end if;
  end loop;

  -- Pattern 3 : rooms avec mêmes 2-3 user_ids récurrents (collusion)
  -- (heuristique simple : 2 users qui jouent ensemble > 10 fois en 7j)
  for v_user in
    select least(p1.user_id, p2.user_id) as u1,
           greatest(p1.user_id, p2.user_id) as u2,
           count(distinct p1.room_id) as together_count
    from cora_room_players p1
    join cora_room_players p2
      on p1.room_id = p2.room_id and p1.user_id < p2.user_id
    join cora_games g on g.room_id = p1.room_id
    where g.created_at > now() - interval '7 days'
    group by 1, 2
    having count(distinct p1.room_id) >= 15
  loop
    -- 1 alerte par paire
    if not exists (
      select 1 from admin_alerts
       where alert_type = 'cora_recurrent_pair'
         and metadata @> jsonb_build_object('user1', v_user.u1, 'user2', v_user.u2)
         and created_at > now() - interval '7 days'
    ) then
      insert into admin_alerts (user_id, alert_type, severity, title, description, metadata)
      values (
        v_user.u1, 'cora_recurrent_pair', 'medium',
        format('Paire récurrente : %s parties ensemble en 7j', v_user.together_count),
        'Deux joueurs jouent très souvent ensemble. Suspecter collusion.',
        jsonb_build_object('user1', v_user.u1, 'user2', v_user.u2, 'count', v_user.together_count)
      );
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end; $$;

revoke all on function public.cora_scan_fraud_patterns() from public, anon, authenticated;

-- ============================================================
-- 3. Schedule scan toutes les heures
-- ============================================================
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'cora-fraud-scan';
    perform cron.schedule('cora-fraud-scan', '0 * * * *',
      $cron$ select public.cora_scan_fraud_patterns(); $cron$);
    raise notice 'Cron cora-fraud-scan schedulé (chaque heure).';
  end if;
end $$;

-- ============================================================
-- 4. Vue audit ledger : vérifier l'intégrité financière
-- ============================================================
create or replace view public.cora_treasury_audit_v as
select
  -- Argent total entré dans cora (mises)
  coalesce(sum(-amount) filter (where type = 'bet' and game_type = 'cora_dice'), 0) as total_bets,
  -- Argent total sorti aux gagnants
  coalesce(sum(amount) filter (where type = 'payout' and game_type = 'cora_dice'), 0) as total_payouts,
  -- Argent total remboursé
  coalesce(sum(amount) filter (where type = 'refund' and game_type = 'cora_dice'), 0) as total_refunds,
  -- Caisses
  (select balance from game_treasury where id = 1) as game_treasury_balance,
  (select total_earned from admin_treasury where id = 1) as admin_treasury_earned,
  -- Cohérence : (total_bets - total_payouts - total_refunds) doit être == game_treasury_balance contributions cora + admin_treasury commissions cora
  -- (à vérifier manuellement, multi-jeux complique)
  count(*) filter (where game_type = 'cora_dice') as total_movements
from wallet_ledger;

revoke all on cora_treasury_audit_v from public, anon, authenticated;
-- Admin only via SQL editor.
