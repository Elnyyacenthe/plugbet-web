-- ============================================================
-- Cron : settle_real_bets toutes les 10 min
-- ============================================================
-- Necessite extension pg_cron + pg_net (deja en place sur Plugbet).
-- Le cron appelle l'edge function settle_real_bets via HTTP POST.
--
-- PREREQUIS (a executer 1 fois MANUELLEMENT avant cette migration) :
-- ------------------------------------------------------------
-- Le `alter database postgres set ...` est BLOQUE sur Supabase managed
-- (permission denied). Il faut passer par le vault :
--
--   select vault.create_secret('<TON_SERVICE_ROLE_KEY>', 'service_role_for_cron');
--
-- (sans les chevrons, et NE JAMAIS commit la clef dans git)
--
-- Verification : la requete suivante doit retourner 1 ligne :
--   select name from vault.secrets where name = 'service_role_for_cron';
-- ============================================================

-- Supprime un eventuel ancien cron du meme nom
do $$ begin
  perform cron.unschedule('settle-real-bets-10min');
exception when others then null;
end $$;

-- Cron : toutes les 10 minutes. Lit la clef service_role depuis le vault.
select cron.schedule(
  'settle-real-bets-10min',
  '*/10 * * * *',
  $cron$
  select net.http_post(
    url := 'https://dqzrociaaztlezwlgzwh.supabase.co/functions/v1/settle_real_bets',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'service_role_for_cron' limit 1
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- ============================================================
-- Verification :
-- ============================================================
-- 1. Lister les crons actifs :
--    select * from cron.job;
-- 2. Voir les dernieres executions :
--    select * from cron.job_run_details order by start_time desc limit 5;
-- 3. Appeler manuellement (test) :
--    select net.http_post(
--      url := 'https://<PROJECT_REF>.supabase.co/functions/v1/settle_real_bets',
--      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer <KEY>'),
--      body := '{}'::jsonb
--    );
