-- ============================================================
-- PAYMENT V2 — PHASE 1 : LOCKDOWN
-- ============================================================
-- Production fintech-grade hardening. A executer sur Supabase.
-- Idempotent : safe to re-run.
--
-- CONTENU :
--   A. RLS strictes sur freemopay_transactions, app_settings,
--      wallet_ledger, treasury_balance, treasury_movements
--   B. Table payment_events (append-only, source de verite)
--   C. RPC initiate_freemopay_deposit / initiate_freemopay_withdraw
--      atomiques + idempotentes (request_id obligatoire)
--   D. Trigger consistency wallet ↔ freemopay
--   E. View transaction_timeline (timeline complete par tx)
-- ============================================================


-- ╔══════════════════════════════════════════════════════════╗
-- ║ A.1) RLS STRICTES — toutes les ecritures via RPC          ║
-- ╚══════════════════════════════════════════════════════════╝

-- freemopay_transactions : INTERDIT INSERT/UPDATE/DELETE direct
alter table public.freemopay_transactions enable row level security;

drop policy if exists "Users can insert own freemopay transactions" on public.freemopay_transactions;
drop policy if exists "freemopay_no_direct_insert" on public.freemopay_transactions;
create policy "freemopay_no_direct_insert" on public.freemopay_transactions
  for insert to authenticated with check (false);

drop policy if exists "Users can update own freemopay transactions" on public.freemopay_transactions;
drop policy if exists "freemopay_no_direct_update" on public.freemopay_transactions;
create policy "freemopay_no_direct_update" on public.freemopay_transactions
  for update to authenticated using (false) with check (false);

drop policy if exists "freemopay_no_direct_delete" on public.freemopay_transactions;
create policy "freemopay_no_direct_delete" on public.freemopay_transactions
  for delete to authenticated using (false);

-- SELECT : user voit ses propres tx, super_admin voit tout
drop policy if exists "Users can view own freemopay transactions" on public.freemopay_transactions;
drop policy if exists "freemopay_select_self_or_admin" on public.freemopay_transactions;
create policy "freemopay_select_self_or_admin" on public.freemopay_transactions
  for select to authenticated using (
    user_id = auth.uid()
    or coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin'
  );

-- app_settings : super_admin only (les credentials Freemopay y sont)
alter table public.app_settings enable row level security;

drop policy if exists "Authenticated users can read app_settings" on public.app_settings;
drop policy if exists "app_settings_super_admin_only" on public.app_settings;
create policy "app_settings_super_admin_only" on public.app_settings
  for all to authenticated using (
    coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin'
  ) with check (
    coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin'
  );

-- wallet_ledger : SELECT self/admin, ZERO ecriture directe
-- (deja en place via ludo_v2_perfection.sql, on verifie)
drop policy if exists "wl_no_direct_write" on public.wallet_ledger;
create policy "wl_no_direct_write" on public.wallet_ledger
  for all to authenticated using (false) with check (false);

drop policy if exists "wl_select_self" on public.wallet_ledger;
create policy "wl_select_self" on public.wallet_ledger
  for select to authenticated using (
    user_id = auth.uid()
    or coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin'
  );

-- treasury_balance : super_admin lecture seule, AUCUNE ecriture directe
do $$ begin
  if exists (select 1 from pg_class where relname = 'treasury_balance') then
    execute 'alter table public.treasury_balance enable row level security';
    execute 'drop policy if exists "treasury_balance_super_admin_select" on public.treasury_balance';
    execute 'create policy "treasury_balance_super_admin_select" on public.treasury_balance
      for select to authenticated using (
        coalesce((select role from public.user_profiles where id = auth.uid()), '''') = ''super_admin''
      )';
    execute 'drop policy if exists "treasury_balance_no_direct_write" on public.treasury_balance';
    execute 'create policy "treasury_balance_no_direct_write" on public.treasury_balance
      for all to authenticated using (false) with check (false)';
  end if;
end $$;

-- treasury_movements : meme pattern
do $$ begin
  if exists (select 1 from pg_class where relname = 'treasury_movements') then
    execute 'alter table public.treasury_movements enable row level security';
    execute 'drop policy if exists "treasury_movements_select" on public.treasury_movements';
    execute 'create policy "treasury_movements_select" on public.treasury_movements
      for select to authenticated using (
        user_id = auth.uid()
        or coalesce((select role from public.user_profiles where id = auth.uid()), '''') = ''super_admin''
      )';
    execute 'drop policy if exists "treasury_movements_no_direct_write" on public.treasury_movements';
    execute 'create policy "treasury_movements_no_direct_write" on public.treasury_movements
      for all to authenticated using (false) with check (false)';
  end if;
end $$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ A.2) Contraintes additionnelles                           ║
-- ╚══════════════════════════════════════════════════════════╝

-- external_id UNIQUE pour empecher les duplications
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'freemopay_external_id_unique'
  ) then
    alter table public.freemopay_transactions
      add constraint freemopay_external_id_unique unique (external_id);
  end if;
end $$;

-- Index pour reconciliation rapide
create index if not exists idx_freemopay_status_created
  on public.freemopay_transactions(status, created_at);
create index if not exists idx_freemopay_user_status
  on public.freemopay_transactions(user_id, status);
create index if not exists idx_wallet_ledger_ref_v2
  on public.wallet_ledger(ref_type, ref_id) where ref_type is not null;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ B) TABLE payment_events — APPEND-ONLY                     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Source de verite immuable de toute la timeline d'un paiement.
-- Aucun UPDATE/DELETE possible. Permet replay complet d'un litige.

create table if not exists public.payment_events (
  id              bigserial primary key,
  correlation_id  uuid not null,                -- lie tous les events d'une transaction
  freemopay_tx_id uuid references public.freemopay_transactions(id) on delete set null,
  user_id         uuid,
  event_type      text not null check (event_type in (
    'INITIATED',              -- transaction creee cote backend
    'API_REQUEST_SENT',       -- POST envoye a Freemopay
    'API_RESPONSE_RECEIVED',  -- reponse de Freemopay
    'WEBHOOK_RECEIVED',       -- callback Freemopay arrive
    'HMAC_VALIDATED',         -- signature webhook OK
    'HMAC_INVALID',           -- signature webhook KO (alerte)
    'RECONCILE_STARTED',      -- cron polling Freemopay
    'WALLET_CREDITED',        -- coins ajoutes user
    'WALLET_DEBITED',         -- coins retires user (retrait)
    'WALLET_REFUNDED',        -- coins re-credites apres retrait failed
    'LEDGER_WRITTEN',         -- entree wallet_ledger creee
    'STATUS_UPDATED',         -- freemopay_transactions.status change
    'FAILED',                 -- transaction marquee echouee
    'CANCELLED',              -- annulation user
    'TICKET_CREATED',         -- ticket support auto
    'NOTIFICATION_SENT',      -- push/email envoye user
    'ALERT_TRIGGERED',        -- admin_alert raise
    'MANUAL_INTERVENTION'     -- admin a fait qqch
  )),
  level           text not null default 'info' check (level in ('debug','info','warn','error','critical')),
  message         text,
  payload         jsonb default '{}',           -- request body, response, callback data, etc.
  ip_address      text,
  user_agent      text,
  source          text default 'system',        -- 'mobile_app' | 'webhook' | 'cron' | 'admin' | 'system'
  created_at      timestamptz not null default now()
);

create index if not exists idx_payment_events_correlation
  on public.payment_events(correlation_id, created_at);
create index if not exists idx_payment_events_tx
  on public.payment_events(freemopay_tx_id, created_at);
create index if not exists idx_payment_events_user
  on public.payment_events(user_id, created_at desc);
create index if not exists idx_payment_events_type_level
  on public.payment_events(event_type, level, created_at desc);

alter table public.payment_events enable row level security;

drop policy if exists "payment_events_select_self_or_admin" on public.payment_events;
create policy "payment_events_select_self_or_admin" on public.payment_events
  for select to authenticated using (
    user_id = auth.uid()
    or coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin'
  );

drop policy if exists "payment_events_no_direct_write" on public.payment_events;
create policy "payment_events_no_direct_write" on public.payment_events
  for all to authenticated using (false) with check (false);

-- Trigger empechant l'UPDATE/DELETE meme avec service_role par erreur
create or replace function public.payment_events_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'payment_events is append-only. Use insert only.';
end;
$$;

drop trigger if exists payment_events_no_update on public.payment_events;
create trigger payment_events_no_update
  before update on public.payment_events
  for each row execute function public.payment_events_immutable();

drop trigger if exists payment_events_no_delete on public.payment_events;
create trigger payment_events_no_delete
  before delete on public.payment_events
  for each row execute function public.payment_events_immutable();

-- Helper : log event
create or replace function public.log_payment_event(
  p_correlation_id uuid,
  p_event_type text,
  p_freemopay_tx_id uuid default null,
  p_user_id uuid default null,
  p_level text default 'info',
  p_message text default null,
  p_payload jsonb default '{}',
  p_source text default 'system'
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  insert into public.payment_events
    (correlation_id, event_type, freemopay_tx_id, user_id, level, message, payload, source)
  values
    (p_correlation_id, p_event_type, p_freemopay_tx_id, p_user_id, p_level, p_message, p_payload, p_source)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.log_payment_event(uuid, text, uuid, uuid, text, text, jsonb, text) to service_role;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ C) RPCs ATOMIQUES POUR INITIER UNE TRANSACTION            ║
-- ╚══════════════════════════════════════════════════════════╝

-- Ajouter colonne correlation_id si manquante
alter table public.freemopay_transactions
  add column if not exists correlation_id uuid default gen_random_uuid();

-- Backfill correlation_id pour les transactions existantes
update public.freemopay_transactions
  set correlation_id = id
  where correlation_id is null;

-- RPC d'initiation depot. Atomique : insert tx + log event INITIATED.
-- L'appel HTTP a Freemopay reste cote client (Edge Function ou Flutter)
-- mais la creation de la ligne DB est verrouillee par cette RPC.
create or replace function public.initiate_freemopay_deposit(
  p_amount int,
  p_payer_phone text,
  p_external_id text,
  p_reference text default null,   -- nullable au depart, set apres POST Freemopay
  p_correlation_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tx_id uuid;
  v_corr uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_amount <= 0 or p_amount > 5000000 then raise exception 'INVALID_AMOUNT'; end if;
  if p_payer_phone is null or length(p_payer_phone) < 9 then raise exception 'INVALID_PHONE'; end if;

  v_corr := coalesce(p_correlation_id, gen_random_uuid());

  -- Idempotence : si meme external_id deja existant, retourne la ligne
  select id, correlation_id into v_tx_id, v_corr
    from public.freemopay_transactions where external_id = p_external_id;
  if v_tx_id is not null then
    return jsonb_build_object('idempotent', true, 'tx_id', v_tx_id, 'correlation_id', v_corr);
  end if;

  -- Rate limit : max 5 inits/min/user
  begin
    perform public.check_rate_limit_v2('init_deposit', 5, 60);
  exception when undefined_function then null;
  end;

  insert into public.freemopay_transactions
    (user_id, reference, external_id, transaction_type, amount, status,
     payer_or_receiver, correlation_id)
  values
    (v_uid, coalesce(p_reference, gen_random_uuid()::text), p_external_id, 'DEPOSIT',
     p_amount, 'PENDING', p_payer_phone, v_corr)
  returning id into v_tx_id;

  perform public.log_payment_event(
    v_corr, 'INITIATED', v_tx_id, v_uid, 'info',
    format('Deposit %s FCFA initie pour %s', p_amount, p_payer_phone),
    jsonb_build_object('amount', p_amount, 'phone', p_payer_phone, 'external_id', p_external_id),
    'mobile_app'
  );

  return jsonb_build_object(
    'tx_id', v_tx_id,
    'correlation_id', v_corr,
    'idempotent', false
  );
end;
$$;
grant execute on function public.initiate_freemopay_deposit(int, text, text, text, uuid) to authenticated;


-- RPC d'initiation retrait. ATOMIQUE :
--   1. Lock wallet, check solde
--   2. Debit user via wallet_apply_delta
--   3. Insert freemopay_transactions PENDING
--   4. Log event INITIATED + WALLET_DEBITED + LEDGER_WRITTEN
-- Si l'appel HTTP a Freemopay echoue ensuite, le client doit appeler
-- cancel_freemopay_withdraw pour declencher le refund.
create or replace function public.initiate_freemopay_withdraw(
  p_amount int,
  p_receiver_phone text,
  p_external_id text,
  p_reference text default null,
  p_correlation_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tx_id uuid;
  v_corr uuid;
  v_balance int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_amount <= 0 or p_amount > 1000000 then raise exception 'INVALID_AMOUNT'; end if;
  if p_receiver_phone is null or length(p_receiver_phone) < 9 then raise exception 'INVALID_PHONE'; end if;

  v_corr := coalesce(p_correlation_id, gen_random_uuid());

  -- Idempotence
  select id, correlation_id into v_tx_id, v_corr
    from public.freemopay_transactions where external_id = p_external_id;
  if v_tx_id is not null then
    return jsonb_build_object('idempotent', true, 'tx_id', v_tx_id, 'correlation_id', v_corr);
  end if;

  -- Rate limit
  begin
    perform public.check_rate_limit_v2('init_withdraw', 3, 60);
  exception when undefined_function then null;
  end;

  -- Anti double-retrait : un seul WITHDRAW PENDING par user
  if exists (
    select 1 from public.freemopay_transactions
    where user_id = v_uid and transaction_type = 'WITHDRAW'
      and status = 'PENDING' and created_at > now() - interval '10 minutes'
  ) then
    raise exception 'WITHDRAW_ALREADY_PENDING';
  end if;

  -- Debit atomique via wallet_ledger (raise si insuffisant)
  perform public.wallet_apply_delta(
    v_uid, -p_amount,
    'mobile_money_withdraw_init',
    'freemopay_external', p_external_id,
    jsonb_build_object('phone', p_receiver_phone, 'correlation_id', v_corr),
    'withdraw_init_' || p_external_id
  );

  insert into public.freemopay_transactions
    (user_id, reference, external_id, transaction_type, amount, status,
     payer_or_receiver, correlation_id)
  values
    (v_uid, coalesce(p_reference, gen_random_uuid()::text), p_external_id, 'WITHDRAW',
     p_amount, 'PENDING', p_receiver_phone, v_corr)
  returning id into v_tx_id;

  perform public.log_payment_event(v_corr, 'INITIATED', v_tx_id, v_uid, 'info',
    format('Withdraw %s FCFA initie vers %s', p_amount, p_receiver_phone),
    jsonb_build_object('amount', p_amount, 'phone', p_receiver_phone), 'mobile_app');
  perform public.log_payment_event(v_corr, 'WALLET_DEBITED', v_tx_id, v_uid, 'info',
    format('User debited %s coins', p_amount),
    jsonb_build_object('amount', p_amount), 'system');
  perform public.log_payment_event(v_corr, 'LEDGER_WRITTEN', v_tx_id, v_uid, 'info',
    'wallet_ledger entry created', '{}', 'system');

  select coins into v_balance from public.user_profiles where id = v_uid;

  return jsonb_build_object(
    'tx_id', v_tx_id, 'correlation_id', v_corr,
    'idempotent', false, 'new_balance', v_balance
  );
end;
$$;
grant execute on function public.initiate_freemopay_withdraw(int, text, text, text, uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ D) TRIGGER consistency wallet ↔ freemopay                 ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.check_freemopay_consistency()
returns trigger language plpgsql as $$
begin
  -- Si transaction passe a SUCCESS pour un DEPOSIT, on doit avoir
  -- une ligne wallet_ledger correspondante dans les 5 minutes
  if new.status = 'SUCCESS'
     and new.transaction_type = 'DEPOSIT'
     and (old is null or old.status != 'SUCCESS') then
    perform pg_sleep(0);  -- placeholder ; le check post-sleep est fait par le cron
    -- On log juste l'event ; le check de conformite sera fait par
    -- le cron de monitoring (Phase 4)
    perform public.log_payment_event(
      new.correlation_id, 'STATUS_UPDATED', new.id, new.user_id, 'info',
      format('Freemopay tx status: %s', new.status),
      jsonb_build_object('old_status', old.status, 'new_status', new.status),
      'system'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists freemopay_consistency_trg on public.freemopay_transactions;
create trigger freemopay_consistency_trg
  after update on public.freemopay_transactions
  for each row execute function public.check_freemopay_consistency();


-- ╔══════════════════════════════════════════════════════════╗
-- ║ E) VIEW transaction_timeline                              ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace view public.transaction_timeline_v as
select
  ft.id as tx_id,
  ft.correlation_id,
  ft.user_id,
  up.username,
  ft.transaction_type,
  ft.amount,
  ft.status as current_status,
  ft.reference,
  ft.external_id,
  ft.payer_or_receiver as phone,
  ft.created_at as initiated_at,
  ft.updated_at as last_update,
  -- Timeline complete
  (
    select jsonb_agg(jsonb_build_object(
      'event', e.event_type,
      'level', e.level,
      'message', e.message,
      'source', e.source,
      'at', e.created_at,
      'payload', e.payload
    ) order by e.created_at)
    from public.payment_events e
    where e.correlation_id = ft.correlation_id
  ) as timeline,
  -- Summary
  (
    select count(*) from public.payment_events e
    where e.correlation_id = ft.correlation_id and e.level in ('error','critical')
  ) as error_count,
  (
    select count(*) from public.payment_events e
    where e.correlation_id = ft.correlation_id and e.event_type = 'WALLET_CREDITED'
  ) as wallet_credit_count,
  -- Extract de wallet_ledger
  (
    select coalesce(sum(wl.delta), 0)
    from public.wallet_ledger wl
    where wl.ref_type = 'freemopay_tx' and wl.ref_id = ft.id::text
  ) as wallet_impact
from public.freemopay_transactions ft
left join public.user_profiles up on up.id = ft.user_id;

grant select on public.transaction_timeline_v to authenticated;

-- RPC pour le dashboard (avec RLS implicite via super_admin check)
create or replace function public.get_transaction_timeline(p_tx_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_tx_user uuid;
  v_result jsonb;
begin
  v_role := coalesce((select role from public.user_profiles where id = v_uid), '');
  select user_id into v_tx_user from public.freemopay_transactions where id = p_tx_id;

  if v_tx_user is null then return null; end if;
  if v_tx_user != v_uid and v_role != 'super_admin' then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select to_jsonb(t) into v_result
    from public.transaction_timeline_v t
    where t.tx_id = p_tx_id;

  return v_result;
end;
$$;
grant execute on function public.get_transaction_timeline(uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ FIN PHASE 1                                                ║
-- ╚══════════════════════════════════════════════════════════╝
-- Verifications post-execution :
--
-- 1. Tester RLS : INSERT direct sur freemopay_transactions par
--    un user authentifie -> doit echouer
--    INSERT INTO freemopay_transactions(...) -> ERROR
--
-- 2. Tester INSERT sur wallet_ledger -> ERROR
--
-- 3. Tester app_settings SELECT par user normal -> ERROR
--
-- 4. Initier un depot via initiate_freemopay_deposit() -> OK,
--    voir la ligne dans payment_events avec event_type=INITIATED
--
-- 5. Lancer get_transaction_timeline(<tx_id>) -> retourne JSON
--    avec timeline complete
-- ============================================================
