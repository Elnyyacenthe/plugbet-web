-- ============================================================
-- FREEMOPAY TX WATCHER — Trigger event-driven
-- ============================================================
-- A l'INSERT d'une transaction PENDING DEPOSIT, declenche immediatement
-- l'Edge Function freemopay_tx_watcher qui fait un backoff 15s/30s/60s
-- pour cette tx specifiquement.
--
-- Independant du cron 1 min : c'est un mecanisme parallele.
-- Si le watcher echoue ou expire, le cron prend le relai.
-- ============================================================

-- 1. Stocker la cle service_role dans app_settings (one-time)
-- ⚠️ Avant d'executer ce script, set ta cle :
--    update app_settings set value = jsonb_build_object('key', 'TON_SERVICE_ROLE_KEY')
--    where key = 'internal_service_key';
do $$ begin
  insert into public.app_settings (key, value)
  values ('internal_service_key', jsonb_build_object('key', 'TODO_REPLACE_ME'))
  on conflict (key) do nothing;
end $$;

-- 2. Trigger function
create or replace function public._trigger_freemopay_tx_watcher()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_key text;
  v_url text := 'https://dqzrociaaztlezwlgzwh.supabase.co/functions/v1/freemopay_tx_watcher';
begin
  -- Seulement DEPOSIT en PENDING (les WITHDRAW sont rares et finalisent par webhook serveur)
  if NEW.transaction_type != 'DEPOSIT' or NEW.status != 'PENDING' then
    return NEW;
  end if;

  -- Recupere la cle service_role
  select value->>'key' into v_key
  from app_settings where key = 'internal_service_key';

  if v_key is null or v_key = 'TODO_REPLACE_ME' then
    -- Pas de cle configuree : on log un alert et on laisse le cron faire
    insert into admin_alerts(alert_type, severity, title, description, metadata)
    values ('freemopay_watcher_no_key', 'warning',
            'Watcher non declenche : cle absente',
            'Configure internal_service_key dans app_settings pour activer le watcher',
            jsonb_build_object('tx_id', NEW.id));
    return NEW;
  end if;

  -- Fire-and-forget vers Edge Function
  -- timeout court car le watcher tourne ~2 min, on n'attend pas
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object('tx_id', NEW.id::text),
      timeout_milliseconds := 5000
    );
  exception when others then
    -- Si pg_net plante, on alert mais on ne bloque PAS l'INSERT
    insert into admin_alerts(alert_type, severity, title, description, metadata)
    values ('freemopay_watcher_trigger_error', 'warning',
            'Echec trigger watcher',
            sqlerrm,
            jsonb_build_object('tx_id', NEW.id, 'err', sqlerrm));
  end;

  return NEW;
end;
$$;

-- 3. Attach trigger
drop trigger if exists trg_freemopay_tx_watcher on public.freemopay_transactions;
create trigger trg_freemopay_tx_watcher
  after insert on public.freemopay_transactions
  for each row execute function public._trigger_freemopay_tx_watcher();

-- 4. Realtime sur freemopay_transactions (push instantane vers Flutter)
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'freemopay_transactions'
  ) then
    alter publication supabase_realtime add table public.freemopay_transactions;
    raise notice 'freemopay_transactions ajoute a realtime';
  end if;
end $$;

-- 5. Realtime sur admin_alerts (pour notif dashboard temps reel)
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'admin_alerts'
  ) then
    alter publication supabase_realtime add table public.admin_alerts;
    raise notice 'admin_alerts ajoute a realtime';
  end if;
end $$;
