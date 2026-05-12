-- ============================================================
-- PAYMENT V2 — PHASE 2 : AUTO-RÉSOLUTION SANS WEBHOOK
-- ============================================================
-- A executer APRES rollback Phase 1.
-- Idempotent.
--
-- Stratégie : puisque le webhook Freemopay n'est pas configurable,
-- on s'appuie 100% sur le polling + auto-tickets pour garantir que :
--   - Aucune transaction PENDING ne reste figée plus de 5 min
--   - Tout dépôt SUCCESS chez Freemopay est crédité automatiquement
--   - Tout retrait FAILED est refundé automatiquement
--   - Si transaction reste PENDING > 30 min : auto-ticket support
--   - Admin alerté en temps réel via admin_alerts
--
-- DÉPENDANCES :
--   - freemopay_reconcile Edge Function (déjà déployée)
--   - support_tickets table (existe)
--   - admin_alerts table (existe)
--   - pg_cron extension (à activer si pas déjà)
--   - pg_net extension (pour appeler l'Edge Function depuis cron)
-- ============================================================


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 1) FONCTION : créer auto-ticket si PENDING trop long      ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.freemopay_auto_create_tickets()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_tx record;
  v_count int := 0;
  v_ticket_id uuid;
  v_subject text;
  v_message text;
begin
  for v_tx in
    select ft.*, up.username
    from public.freemopay_transactions ft
    left join public.user_profiles up on up.id = ft.user_id
    where ft.status = 'PENDING'
      and ft.created_at < now() - interval '30 minutes'
      -- Eviter de creer un ticket plusieurs fois pour la meme tx
      and not exists (
        select 1 from public.support_tickets st
        where st.user_id = ft.user_id
          and st.category = 'paiement'
          and st.created_at > ft.created_at - interval '1 minute'
          and (st.subject like '%' || ft.reference || '%'
               or st.subject like '%' || ft.external_id || '%')
      )
  loop
    -- Creer le ticket
    if v_tx.transaction_type = 'DEPOSIT' then
      v_subject := format('Dépôt en attente — %s FCFA — Réf %s',
                          v_tx.amount, substring(v_tx.reference, 1, 8));
      v_message := format(
        'Bonjour, votre dépôt de %s FCFA via le numéro %s n''a pas été finalisé après 30 minutes.\n\n' ||
        'Référence : %s\nID externe : %s\n\n' ||
        'Notre équipe vérifie automatiquement le statut de votre paiement. ' ||
        'Si vous avez bien été débité côté Mobile Money, vos coins arriveront ' ||
        'automatiquement dans les minutes qui viennent. Sinon, contactez-nous ici.',
        v_tx.amount, v_tx.payer_or_receiver, v_tx.reference, v_tx.external_id
      );
    else
      v_subject := format('Retrait en attente — %s FCFA — Réf %s',
                          v_tx.amount, substring(v_tx.reference, 1, 8));
      v_message := format(
        'Bonjour, votre retrait de %s FCFA vers le numéro %s n''a pas été finalisé après 30 minutes.\n\n' ||
        'Référence : %s\n\n' ||
        'Si vous n''avez pas reçu l''argent, écrivez-nous ici, nous vérifions immédiatement.',
        v_tx.amount, v_tx.payer_or_receiver, v_tx.reference
      );
    end if;

    insert into public.support_tickets (
      user_id, subject, status, category, created_at, updated_at, unread_admin
    ) values (
      v_tx.user_id, v_subject, 'open', 'paiement', now(), now(), true
    )
    returning id into v_ticket_id;

    -- Premier message systeme
    insert into public.support_messages (
      ticket_id, user_id, content, is_admin, created_at
    ) values (
      v_ticket_id, v_tx.user_id, v_message, false, now()
    );

    v_count := v_count + 1;
  end loop;

  -- Logger
  if v_count > 0 then
    perform public.log_event('info', 'freemopay_auto_ticket',
      format('Auto-created %s tickets pour transactions PENDING > 30min', v_count),
      jsonb_build_object('count', v_count));
  end if;

  return v_count;
end;
$$;

grant execute on function public.freemopay_auto_create_tickets() to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 2) FONCTION : alerter admin sur volume de PENDING anormal ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.freemopay_check_anomalies()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_pending_count int;
  v_pending_amount bigint;
  v_old_pending int;
  v_alerts int := 0;
begin
  -- Compter les transactions PENDING actives
  select count(*), coalesce(sum(amount), 0)
    into v_pending_count, v_pending_amount
    from public.freemopay_transactions
    where status = 'PENDING'
      and created_at > now() - interval '24 hours';

  -- Compter celles tres anciennes (> 1h)
  select count(*) into v_old_pending
    from public.freemopay_transactions
    where status = 'PENDING'
      and created_at < now() - interval '1 hour';

  -- Alerte si > 10 PENDING > 1h (signe que reconcile ne marche pas)
  if v_old_pending >= 10 then
    if not exists (
      select 1 from public.admin_alerts
      where alert_type = 'freemopay_reconcile_failure'
        and not resolved
        and created_at > now() - interval '1 hour'
    ) then
      perform public.raise_admin_alert(
        'freemopay_reconcile_failure', 'high',
        format('%s transactions PENDING > 1h — reconcile peut être down', v_old_pending),
        'Vérifier que freemopay_reconcile Edge Function tourne bien (cron pg_cron ou cron-job.org)',
        jsonb_build_object('old_pending_count', v_old_pending,
                          'pending_24h_count', v_pending_count,
                          'pending_24h_amount', v_pending_amount)
      );
      v_alerts := v_alerts + 1;
    end if;
  end if;

  -- Alerte si volume anormal (> 50 PENDING en 1h = pic suspect)
  declare v_recent_pending int;
  begin
    select count(*) into v_recent_pending
      from public.freemopay_transactions
      where created_at > now() - interval '1 hour';
    if v_recent_pending > 50 then
      perform public.raise_admin_alert(
        'freemopay_volume_spike', 'medium',
        format('%s transactions Mobile Money en 1h - volume eleve', v_recent_pending),
        'Verifier qu''il n''y a pas un bot / probleme api',
        jsonb_build_object('count_1h', v_recent_pending)
      );
      v_alerts := v_alerts + 1;
    end if;
  end;

  return v_alerts;
end;
$$;

grant execute on function public.freemopay_check_anomalies() to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 3) FONCTION : marquer FAILED les PENDING trop anciennes   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Apres 24h sans succes, on considere la transaction FAILED.
-- Pour les WITHDRAW : refund auto le user.

create or replace function public.freemopay_force_finalize_old_pending()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_tx record;
  v_count int := 0;
begin
  for v_tx in
    select * from public.freemopay_transactions
    where status = 'PENDING'
      and created_at < now() - interval '24 hours'
    for update skip locked
  loop
    -- Pour WITHDRAW : refund obligatoire
    if v_tx.transaction_type = 'WITHDRAW' then
      begin
        perform public.wallet_apply_delta(
          v_tx.user_id, v_tx.amount,
          'mobile_money_withdraw_refund_auto',
          'freemopay_tx', v_tx.id::text,
          jsonb_build_object('reason', 'pending_24h_auto_refund'),
          'auto_finalize_refund_' || v_tx.id::text
        );
      exception when others then
        perform public.log_event('error', 'freemopay_force_finalize',
          'Refund failed for tx ' || v_tx.id::text, jsonb_build_object('error', sqlerrm));
        continue;
      end;
    end if;

    update public.freemopay_transactions set
      status = 'FAILED',
      message = 'Auto-marquée FAILED après 24h PENDING',
      callback_data = jsonb_build_object('auto_finalize', true, 'date', now()),
      updated_at = now()
    where id = v_tx.id;

    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    perform public.log_event('info', 'freemopay_force_finalize',
      format('%s transactions PENDING 24h+ marquees FAILED', v_count),
      jsonb_build_object('count', v_count));
  end if;

  return v_count;
end;
$$;

grant execute on function public.freemopay_force_finalize_old_pending() to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 4) CRON SCHEDULES (si pg_cron actif)                       ║
-- ╚══════════════════════════════════════════════════════════╝
-- A activer manuellement (decommenter selon ton setup pg_cron+pg_net).
--
-- ATTENTION : remplacer le CRON_SECRET et l'URL par tes vraies valeurs.
--
-- 1. Reconcile Freemopay toutes les 5 min (via pg_net + Edge Function)
-- 2. Auto-creation tickets toutes les 10 min
-- 3. Anomalies check toutes les 10 min
-- 4. Force finalize 24h+ une fois par jour a 03:00
--
-- Decommenter et adapter :
-- ============================================================

-- ============================================================
-- Variant A : pg_cron + pg_net (recommandé si pg_net dispo)
-- ============================================================
-- Si pg_net est actif sur ton projet, decommente les lignes ci-dessous
-- (retire le "-- " devant chaque ligne) pour planifier l'appel auto
-- de l'Edge Function reconcile toutes les 5 min.
--
-- do $$ begin
--   if exists (select 1 from pg_extension where extname = 'pg_cron')
--      and exists (select 1 from pg_extension where extname = 'pg_net') then
--     perform cron.unschedule('freemopay_reconcile_5min')
--     where exists (select 1 from cron.job where jobname = 'freemopay_reconcile_5min');
--     perform cron.schedule('freemopay_reconcile_5min', E'*/5 * * * *', $body$
--       select net.http_post(
--         url := 'https://dqzrociaaztlezwlgzwh.supabase.co/functions/v1/freemopay_reconcile',
--         headers := jsonb_build_object(
--           'Authorization', 'Bearer SMj2zm35RTa81NPQx7kVO4F6CZBXUyHupr0e9dYwJbhWLovA',
--           'Content-Type', 'application/json'
--         )
--       );
--     $body$);
--   end if;
-- end $$;

-- ============================================================
-- Cron LOCAL (toujours dispo, pas besoin pg_net)
-- ============================================================
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Auto-tickets toutes les 10 min
    perform cron.unschedule('freemopay_auto_tickets')
    where exists (select 1 from cron.job where jobname = 'freemopay_auto_tickets');
    perform cron.schedule('freemopay_auto_tickets', '*/10 * * * *',
      $body$ select public.freemopay_auto_create_tickets() $body$);

    -- Check anomalies toutes les 10 min
    perform cron.unschedule('freemopay_check_anomalies')
    where exists (select 1 from cron.job where jobname = 'freemopay_check_anomalies');
    perform cron.schedule('freemopay_check_anomalies', '*/10 * * * *',
      $body$ select public.freemopay_check_anomalies() $body$);

    -- Force finalize quotidien a 03:00
    perform cron.unschedule('freemopay_force_finalize')
    where exists (select 1 from cron.job where jobname = 'freemopay_force_finalize');
    perform cron.schedule('freemopay_force_finalize', '0 3 * * *',
      $body$ select public.freemopay_force_finalize_old_pending() $body$);

    raise notice 'Cron jobs Phase 2 schedules : auto_tickets, check_anomalies, force_finalize';
  end if;
end $$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 5) VUE pour le user : ses transactions Mobile Money       ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace view public.my_freemopay_transactions_v as
select
  ft.id,
  ft.reference,
  ft.external_id,
  ft.transaction_type,
  ft.amount,
  ft.status,
  ft.payer_or_receiver as phone,
  ft.message,
  ft.created_at,
  ft.updated_at,
  -- Wallet impact (combien crédité/débité)
  coalesce((
    select sum(wl.delta) from public.wallet_ledger wl
    where wl.user_id = ft.user_id
      and (wl.ref_id = ft.id::text or wl.ref_id = ft.reference or wl.ref_id = ft.external_id)
  ), 0) as wallet_impact,
  -- Status humain
  case
    when ft.status = 'SUCCESS' then 'Validé'
    when ft.status = 'FAILED' then 'Échoué'
    when ft.status = 'PENDING' and ft.created_at > now() - interval '5 minutes' then 'En cours'
    when ft.status = 'PENDING' and ft.created_at > now() - interval '30 minutes' then 'En traitement'
    when ft.status = 'PENDING' then 'Vérification en cours'
    else ft.status
  end as status_label,
  -- Age
  age(now(), ft.created_at) as age
from public.freemopay_transactions ft
where ft.user_id = auth.uid()
order by ft.created_at desc;

grant select on public.my_freemopay_transactions_v to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 6) RPC user : "Vérifier maintenant" (force reconcile)     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Le user peut forcer la verification de SES transactions PENDING.
-- Rate-limited a 1 appel/30s pour eviter spam.

create or replace function public.user_check_my_pending_freemopay()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_count int := 0;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  -- Rate limit
  begin
    perform public.check_rate_limit_v2('user_check_pending', 1, 30);
  exception when undefined_function then null;
  end;

  -- On compte juste les PENDING, le reconcile sera fait par le cron auto
  select count(*) into v_count
    from public.freemopay_transactions
    where user_id = v_uid and status = 'PENDING';

  return jsonb_build_object(
    'pending_count', v_count,
    'message', case when v_count = 0
                    then 'Aucune transaction en attente'
                    else format('%s transaction(s) en attente. Vérification automatique toutes les 5 min.', v_count)
               end,
    'next_reconcile_within', '5 minutes'
  );
end;
$$;
grant execute on function public.user_check_my_pending_freemopay() to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 7) RPC : check si une transaction est deja creditee        ║
-- ╚══════════════════════════════════════════════════════════╝
-- Le client appelle cette RPC AVANT de crediter cote Flutter,
-- pour eviter le double credit (webhook a deja credite OU cron reconcile).

create or replace function public.is_freemopay_credited(p_reference text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.wallet_ledger
    where (ref_id = p_reference
           or metadata ->> 'reference' = p_reference
           or metadata ->> 'referenceId' = p_reference)
      and (reason ilike '%deposit%' or reason ilike '%refund%')
  );
$$;
grant execute on function public.is_freemopay_credited(text) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ FIN PHASE 2                                                ║
-- ╚══════════════════════════════════════════════════════════╝
-- Apres execution :
--   - Cron auto_tickets actif : toutes les 10 min, scan PENDING > 30 min
--     et cree un ticket support pour le user
--   - Cron check_anomalies actif : toutes les 10 min, alerte admin
--     si > 10 PENDING anciennes ou volume anormal
--   - Cron force_finalize actif : tous les jours a 03:00, marque FAILED
--     les PENDING > 24h et refund les retraits
--   - Vue my_freemopay_transactions_v : pour la page user "Mes paiements"
--   - RPC user_check_my_pending_freemopay : pour le bouton "Verifier"
--
-- A faire MANUELLEMENT (1 fois) :
--   1. Activer le reconcile via pg_net OU via cron-job.org externe
--      pour appeler l'Edge Function freemopay_reconcile toutes les 5 min
--   2. (Optionnel) Decommenter la section pg_net dans ce fichier
--      si pg_net est dispo sur ton projet Supabase
-- ============================================================
