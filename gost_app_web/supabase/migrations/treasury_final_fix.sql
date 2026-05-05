-- ============================================================
-- TREASURY FINAL FIX
-- ============================================================
-- A executer en DERNIER, apres :
--   - treasury_unified.sql
--   - ludo_v1_treasury_migration.sql
--   - ludo_v2_treasury_migration.sql
--   - coinflip_treasury_migration.sql
--   - cora_dice_treasury_migration.sql
--   - treasury_dashboard_bridge.sql
--
-- Ce fichier :
--   1. SUPPRIME le trigger ludo_v2_treasury_trg qui ajoutait 15% en
--      double (notre nouveau systeme gere deja les 10%)
--   2. SUPPRIME admin_treasury_take_commission (plus utilise)
--   3. PATCHE treasury_collect_loss et les wrappers legacy pour
--      qu'ils ecrivent aussi dans admin_treasury (visible dashboard)
--   4. SYNC le solde admin_treasury depuis le solde reel actuel
--
-- Resultat final :
--   - Une seule caisse : admin_treasury (solde temps reel)
--   - 10% commission UNIFORME (configure dans house_edge_config)
--   - Mines + Apple Fortune continuent de marcher (leurs triggers OK)
--   - Ludo V2 n'a plus de double-comptage
-- ============================================================

-- ============================================================
-- 1) DROP le trigger Ludo V2 qui causait le double 15%
-- ============================================================
drop trigger if exists ludo_v2_treasury_trg on public.ludo_v2_games;
drop function if exists public.ludo_v2_treasury_hook();

-- ============================================================
-- 2) Patch treasury_collect_loss : aussi dans admin_treasury
-- ============================================================
-- Cette fonction est appelee par game_treasury_collect_loss (wrapper),
-- donc indirectement par les triggers Mines et Apple Fortune.
create or replace function public.treasury_collect_loss(
  p_game_type text,
  p_game_id text,
  p_user_id uuid,
  p_amount int
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_amount <= 0 then return; end if;

  -- Mon systeme
  update public.treasury_balance
    set balance = balance + p_amount,
        total_in = total_in + p_amount,
        updated_at = now()
    where id = 1;

  insert into public.treasury_movements
    (game_type, game_id, user_id, movement_type, amount)
    values (p_game_type, p_game_id, p_user_id, 'loss_collect', p_amount);

  -- Legacy (admin_treasury + treasury_transactions pour le dashboard)
  update public.admin_treasury
    set balance = balance + p_amount,
        total_earned = total_earned + p_amount,
        updated_at = now()
    where id = 1;

  insert into public.treasury_transactions
    (treasury_type, type, amount, game_type, source, description, user_id, metadata)
    values ('admin', 'earning', p_amount, p_game_type, 'solo_loss',
      'Mise perdue (jeu solo)', p_user_id,
      jsonb_build_object('game_id', p_game_id));
end;
$$;

grant execute on function public.treasury_collect_loss(text, text, uuid, int) to authenticated;

-- ============================================================
-- 3) Patch wrapper game_treasury_collect_loss : redirige proprement
-- ============================================================
-- Appelee par les triggers Mines et Apple Fortune.
-- Redirige vers treasury_collect_loss qui ecrit aussi dans admin_treasury.
create or replace function public.game_treasury_collect_loss(
  p_amount bigint,
  p_game_type text,
  p_user_id uuid default null,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id text;
begin
  if p_amount <= 0 then return; end if;

  -- Extraire session_id du metadata si dispo
  v_session_id := coalesce(p_metadata ->> 'session_id', p_description, 'no-id');

  perform public.treasury_collect_loss(
    p_game_type, v_session_id, p_user_id, p_amount::int
  );
end;
$$;

grant execute on function public.game_treasury_collect_loss(bigint, text, uuid, text, jsonb) to authenticated;

-- ============================================================
-- 4) Patch wrapper game_treasury_pay_win : redirige proprement
-- ============================================================
-- Appelee par les triggers Mines et Apple Fortune (cash out).
create or replace function public.game_treasury_pay_win(
  p_amount bigint,
  p_game_type text,
  p_user_id uuid default null,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id text;
begin
  if p_amount <= 0 then return; end if;

  v_session_id := coalesce(p_metadata ->> 'session_id', p_description, 'no-id');

  -- Crediter le joueur (l'argent vient de admin_treasury qui contient les pertes)
  update public.user_profiles
    set coins = coins + p_amount, updated_at = now()
    where id = p_user_id;

  -- Decrementer treasury_balance (mon systeme)
  update public.treasury_balance
    set balance = balance - p_amount,
        total_out = total_out + p_amount,
        updated_at = now()
    where id = 1;

  -- Decrementer admin_treasury (legacy/dashboard)
  update public.admin_treasury
    set balance = balance - p_amount,
        total_withdrawn = total_withdrawn + p_amount,
        updated_at = now()
    where id = 1;

  -- Log mon systeme
  insert into public.treasury_movements
    (game_type, game_id, user_id, movement_type, amount)
    values (p_game_type, v_session_id, p_user_id, 'payout', p_amount);

  -- Log legacy (dashboard)
  insert into public.treasury_transactions
    (treasury_type, type, amount, game_type, source, description, user_id, metadata)
    values ('admin', 'payout', p_amount, p_game_type, 'solo_win',
      coalesce(p_description, 'Gain solo'), p_user_id, p_metadata);
end;
$$;

grant execute on function public.game_treasury_pay_win(bigint, text, uuid, text, jsonb) to authenticated;

-- ============================================================
-- 5) DROP admin_treasury_take_commission (plus utilise)
-- ============================================================
-- Cette fonction etait appelee uniquement par ludo_v2_treasury_hook
-- (qu'on vient de drop). Et elle avait des taux hardcodes (15% vs 10%)
-- ce qui contredit notre nouvelle politique 10% UNIFORME.
drop function if exists public.admin_treasury_take_commission(bigint, text, uuid, jsonb);

-- ============================================================
-- 6) Synchronisation FINALE du dashboard
-- ============================================================
-- Important : remet admin_treasury a niveau avec mon treasury_balance.
-- Apres ca, les soldes seront identiques et garderont leur synchro
-- via les RPCs patchees.
update public.admin_treasury
set balance = (select balance from public.treasury_balance where id = 1),
    total_earned = (select total_in from public.treasury_balance where id = 1),
    total_withdrawn = (select total_out from public.treasury_balance where id = 1),
    updated_at = now()
where id = 1;

-- ============================================================
-- 7) Verifications post-execution
-- ============================================================
-- Ces requetes te confirment que tout est OK :
--
-- a) Solde dashboard = solde reel ?
--    select t.balance as my, a.balance as dashboard,
--           (t.balance = a.balance) as ok
--    from treasury_balance t, admin_treasury a
--    where t.id = 1 and a.id = 1;
--
-- b) Plus de trigger Ludo V2 ?
--    select tgname from pg_trigger where tgname = 'ludo_v2_treasury_trg';
--    -- doit retourner 0 ligne
--
-- c) admin_treasury_take_commission supprimee ?
--    select proname from pg_proc where proname = 'admin_treasury_take_commission';
--    -- doit retourner 0 ligne
--
-- d) Mines et Apple Fortune triggers toujours la (ils restent !) ?
--    select tgname from pg_trigger
--    where tgname in ('mines_treasury_trg', 'apple_fortune_treasury_trg');
--    -- doit retourner 2 lignes
--
-- TEST FINAL :
--   1. Lance une partie Ludo V2 -> commission 10% visible dashboard
--   2. Lance une partie Mines (cash out) -> mouvement visible dashboard
--   3. Lance une partie Apple Fortune (perte) -> mouvement visible
--   4. Plus de "Commission 15% sur pot" dans treasury_transactions
