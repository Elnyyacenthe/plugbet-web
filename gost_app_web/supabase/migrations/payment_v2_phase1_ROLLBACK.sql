-- ============================================================
-- PAYMENT V2 — PHASE 1 ROLLBACK
-- ============================================================
-- Annule les RLS strictes de payment_v2_phase1_lockdown.sql
-- pour revenir à l'état d'avant (paiements remarchent immediatement).
--
-- Ce qu'on GARDE (non bloquant) :
--   - Table payment_events (juste un journal, ne bloque rien)
--   - RPCs initiate_freemopay_deposit / withdraw (existent mais optionnelles)
--   - Helpers update_freemopay_reference / cancel_freemopay_withdraw
--   - external_id UNIQUE constraint (utile, ne casse rien)
--   - Indexes (utiles pour perf)
--
-- Ce qu'on ROLLBACK :
--   - RLS strictes sur freemopay_transactions, app_settings,
--     wallet_ledger, treasury_balance, treasury_movements
--   - On reactive INSERT/UPDATE direct
-- ============================================================


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 1) freemopay_transactions : restaurer RLS d'origine       ║
-- ╚══════════════════════════════════════════════════════════╝

drop policy if exists "freemopay_no_direct_insert" on public.freemopay_transactions;
drop policy if exists "freemopay_no_direct_update" on public.freemopay_transactions;
drop policy if exists "freemopay_no_direct_delete" on public.freemopay_transactions;
drop policy if exists "freemopay_select_self_or_admin" on public.freemopay_transactions;

-- Policies originales (de 20260419_freemopay_integration.sql)
drop policy if exists "Users can insert own freemopay transactions" on public.freemopay_transactions;
create policy "Users can insert own freemopay transactions"
  on public.freemopay_transactions for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own freemopay transactions" on public.freemopay_transactions;
create policy "Users can update own freemopay transactions"
  on public.freemopay_transactions for update
  using (auth.uid() = user_id);

drop policy if exists "Users can view own freemopay transactions" on public.freemopay_transactions;
create policy "Users can view own freemopay transactions"
  on public.freemopay_transactions for select
  using (auth.uid() = user_id);


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 2) app_settings : restaurer lecture authenticated         ║
-- ╚══════════════════════════════════════════════════════════╝

drop policy if exists "app_settings_super_admin_only" on public.app_settings;
drop policy if exists "Authenticated users can read app_settings" on public.app_settings;

create policy "Authenticated users can read app_settings"
  on public.app_settings for select to authenticated using (true);


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 3) wallet_ledger : keep restrictive (pas d'INSERT direct) ║
-- ╚══════════════════════════════════════════════════════════╝
-- Note : wallet_ledger DOIT rester verrouillee (sinon faille majeure).
-- Les ecritures legitimes passent toujours par wallet_apply_delta (SECURITY DEFINER).
-- On laisse tel quel, c'est OK.


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 4) treasury_balance / treasury_movements                  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Idem : on laisse les RLS strictes ici, c'est protege par les
-- fonctions treasury_*. Le client n'ecrit jamais directement.


-- ╔══════════════════════════════════════════════════════════╗
-- ║ FIN ROLLBACK                                               ║
-- ╚══════════════════════════════════════════════════════════╝
-- Apres ce SQL, ton app Flutter reprend le flow original :
--   - INSERT direct dans freemopay_transactions (OK)
--   - UPDATE direct via updateTransactionStatus (OK)
--   - addCoins cote client (OK)
-- ============================================================
