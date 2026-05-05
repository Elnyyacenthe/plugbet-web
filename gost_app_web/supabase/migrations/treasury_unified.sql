-- ============================================================
-- TREASURY UNIFIE - Caisse super-admin + house edge par jeu
-- ============================================================
-- Run this in Supabase SQL editor.
-- Idempotent : safe to re-run.
-- Cree :
--   1. Table public.house_edge_config (pourcentage par jeu)
--   2. Table public.treasury_movements (audit log)
--   3. RPC public.apply_game_payout (paiement atomique avec house cut)
--   4. RPC public.treasury_collect_loss (debit pure, sans payout)
--   5. RPC public.treasury_get_balance (lecture solde caisse)
--   6. RPC public.treasury_settle_draw (gestion match nul)
-- ============================================================

-- ============================================================
-- 1) Configuration des house edge par jeu
-- ============================================================
create table if not exists public.house_edge_config (
  game_type text primary key,
  edge_pct numeric(5,4) not null check (edge_pct >= 0 and edge_pct <= 1),
  min_pot int not null default 0,
  max_payout int,
  on_draw text not null default 'refund_minus_edge'
    check (on_draw in ('refund', 'refund_minus_edge', 'house_keeps')),
  enabled boolean not null default true,
  description text,
  updated_at timestamptz not null default now()
);

-- House edge UNIFORME 10% sur tous les jeux (decision business : admin
-- prend toujours 10% du pot/gain final, sans exception).
insert into public.house_edge_config (game_type, edge_pct, description) values
  ('aviator',        0.1000, 'Crash multiplicateur - 10%'),
  ('apple_fortune',  0.1000, 'Solo vs maison - 10%'),
  ('mines',          0.1000, 'Solo diamants vs bombes - 10%'),
  ('solitaire',      0.1000, 'Solo Klondike - 10%'),
  ('coinflip',       0.1000, 'Duel 1v1 - 10%'),
  ('cora_dice',      0.1000, 'Multi 2-4 joueurs - 10%'),
  ('checkers',       0.1000, 'Duel echecs/dames - 10%'),
  ('blackjack',      0.1000, 'Multi vs dealer - 10%'),
  ('roulette',       0.1000, 'Multi grande table - 10%'),
  ('ludo',           0.1000, 'Ludo classique - 10%'),
  ('ludo_v2',        0.1000, 'Ludo V2 - 10%'),
  ('fantasy',        0.1000, 'Fantasy League - 10% sur entry fees')
on conflict (game_type) do update set
  edge_pct = excluded.edge_pct,
  description = excluded.description,
  updated_at = now();

alter table public.house_edge_config enable row level security;

-- Lecture publique (les clients voient le edge applique - transparence)
drop policy if exists "anyone_reads_house_edge" on public.house_edge_config;
create policy "anyone_reads_house_edge"
  on public.house_edge_config for select using (true);

-- Modification interdite cote client (admin seulement via service_role)
drop policy if exists "no_client_writes_house_edge" on public.house_edge_config;
create policy "no_client_writes_house_edge"
  on public.house_edge_config for all using (false) with check (false);

-- ============================================================
-- 2) Log de tous les mouvements treasury (audit)
-- ============================================================
create table if not exists public.treasury_movements (
  id uuid primary key default gen_random_uuid(),
  game_type text not null,
  game_id text,
  user_id uuid references auth.users(id) on delete set null,
  movement_type text not null
    check (movement_type in ('house_cut', 'payout', 'refund', 'loss_collect', 'jackpot', 'adjustment')),
  amount int not null,
  pot_total int,
  edge_pct numeric(5,4),
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_treasury_movements_game
  on public.treasury_movements(game_type, created_at desc);
create index if not exists idx_treasury_movements_user
  on public.treasury_movements(user_id, created_at desc);
create index if not exists idx_treasury_movements_type
  on public.treasury_movements(movement_type, created_at desc);

alter table public.treasury_movements enable row level security;

-- Pas de lecture client (privacy + securite). Admin seulement.
drop policy if exists "no_client_reads_treasury_movements" on public.treasury_movements;
create policy "no_client_reads_treasury_movements"
  on public.treasury_movements for select using (false);

-- ============================================================
-- 3) Solde de la caisse super-admin
-- ============================================================
-- Une simple table singleton qui stocke le solde courant.
-- Mise a jour atomique a chaque mouvement.
create table if not exists public.treasury_balance (
  id smallint primary key default 1 check (id = 1),  -- singleton
  balance bigint not null default 0,
  total_in bigint not null default 0,    -- total entrees historiques
  total_out bigint not null default 0,   -- total sorties historiques
  updated_at timestamptz not null default now()
);

insert into public.treasury_balance (id, balance) values (1, 0)
  on conflict (id) do nothing;

alter table public.treasury_balance enable row level security;

drop policy if exists "no_client_treasury_balance" on public.treasury_balance;
create policy "no_client_treasury_balance"
  on public.treasury_balance for all using (false);

-- ============================================================
-- 4) RPC : apply_game_payout (paiement atomique avec house cut)
-- ============================================================
-- Distribue un pot : (1 - edge_pct) au winner + edge_pct a la caisse.
-- Appellee par les RPCs de jeu (rlt_auto_continue, cf_auto_continue, etc).
--
-- Garanties :
--   - Atomique : tout ou rien (transaction implicite plpgsql)
--   - Trace dans treasury_movements
--   - Met a jour treasury_balance
--   - Respecte max_payout si configure
--
-- Retourne le NET paye au winner (utile pour l'affichage cote client).
create or replace function public.apply_game_payout(
  p_game_type text,
  p_game_id text,
  p_winner_id uuid,
  p_pot_total int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg record;
  v_house_cut int;
  v_net_payout int;
begin
  if p_pot_total <= 0 then
    raise exception 'INVALID_POT';
  end if;
  if p_winner_id is null then
    raise exception 'INVALID_WINNER';
  end if;

  -- Charger config edge du jeu
  select * into v_cfg from public.house_edge_config
    where game_type = p_game_type and enabled = true;
  if not found then
    raise exception 'GAME_NOT_CONFIGURED: %', p_game_type;
  end if;

  -- Calculer la coupure
  v_house_cut := floor(p_pot_total * v_cfg.edge_pct)::int;
  v_net_payout := p_pot_total - v_house_cut;

  -- Appliquer plafond (anti-fraude / anti-bug)
  if v_cfg.max_payout is not null and v_net_payout > v_cfg.max_payout then
    v_net_payout := v_cfg.max_payout;
    v_house_cut := p_pot_total - v_net_payout;
  end if;

  -- 1. Crediter le winner
  update public.user_profiles
    set coins = coins + v_net_payout,
        updated_at = now()
    where id = p_winner_id;

  -- 2. Crediter la caisse super-admin
  update public.treasury_balance
    set balance = balance + v_house_cut,
        total_in = total_in + v_house_cut,
        updated_at = now()
    where id = 1;

  -- 3. Logger les 2 mouvements
  insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, pot_total, edge_pct)
    values
      (p_game_type, p_game_id, p_winner_id, 'payout', v_net_payout, p_pot_total, v_cfg.edge_pct),
      (p_game_type, p_game_id, null, 'house_cut', v_house_cut, p_pot_total, v_cfg.edge_pct);

  return v_net_payout;
end;
$$;

grant execute on function public.apply_game_payout(text, text, uuid, int) to authenticated;

-- ============================================================
-- 5) RPC : treasury_collect_loss (debit pur, sans payout)
-- ============================================================
-- Pour les jeux solo perdus (Mines, Apple Fortune, Aviator crash sans cashout).
-- Le user a deja ete debite a la mise initiale → on log juste le mouvement
-- et on credit la caisse.
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
declare
  v_cfg record;
begin
  if p_amount <= 0 then return; end if;

  -- 100% va a la caisse pour les pertes solo
  update public.treasury_balance
    set balance = balance + p_amount,
        total_in = total_in + p_amount,
        updated_at = now()
    where id = 1;

  insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount)
    values (p_game_type, p_game_id, p_user_id, 'loss_collect', p_amount);
end;
$$;

grant execute on function public.treasury_collect_loss(text, text, uuid, int) to authenticated;

-- ============================================================
-- 6) RPC : treasury_settle_draw (match nul)
-- ============================================================
-- Quand 2+ joueurs sont a egalite, redistribue le pot selon la politique
-- du jeu (refund integral / refund moins edge / house garde tout).
create or replace function public.treasury_settle_draw(
  p_game_type text,
  p_game_id text,
  p_user_ids uuid[],
  p_amount_per_user int       -- mise initiale individuelle
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg record;
  v_pot_total int;
  v_per_user_refund int;
  v_house_cut int;
  v_user_id uuid;
begin
  v_pot_total := p_amount_per_user * array_length(p_user_ids, 1);

  select * into v_cfg from public.house_edge_config
    where game_type = p_game_type and enabled = true;
  if not found then
    raise exception 'GAME_NOT_CONFIGURED: %', p_game_type;
  end if;

  if v_cfg.on_draw = 'house_keeps' then
    -- Casino prend tout (rare, agressif)
    update public.treasury_balance
      set balance = balance + v_pot_total,
          total_in = total_in + v_pot_total,
          updated_at = now()
      where id = 1;
    insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, pot_total)
      values (p_game_type, p_game_id, null, 'house_cut', v_pot_total, v_pot_total);

  elsif v_cfg.on_draw = 'refund' then
    -- Refund integral (perte pour la maison)
    foreach v_user_id in array p_user_ids loop
      update public.user_profiles set coins = coins + p_amount_per_user, updated_at = now()
        where id = v_user_id;
      insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount)
        values (p_game_type, p_game_id, v_user_id, 'refund', p_amount_per_user);
    end loop;

  else  -- refund_minus_edge (defaut)
    v_house_cut := floor(p_amount_per_user * v_cfg.edge_pct)::int;
    v_per_user_refund := p_amount_per_user - v_house_cut;
    foreach v_user_id in array p_user_ids loop
      update public.user_profiles set coins = coins + v_per_user_refund, updated_at = now()
        where id = v_user_id;
      insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, edge_pct)
        values (p_game_type, p_game_id, v_user_id, 'refund', v_per_user_refund, v_cfg.edge_pct);
    end loop;
    update public.treasury_balance
      set balance = balance + v_house_cut * array_length(p_user_ids, 1),
          total_in = total_in + v_house_cut * array_length(p_user_ids, 1),
          updated_at = now()
      where id = 1;
    insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, edge_pct)
      values (p_game_type, p_game_id, null, 'house_cut', v_house_cut * array_length(p_user_ids, 1), v_cfg.edge_pct);
  end if;
end;
$$;

grant execute on function public.treasury_settle_draw(text, text, uuid[], int) to authenticated;

-- ============================================================
-- 7) RPC : treasury_get_balance (admin only)
-- ============================================================
-- Retourne le solde de la caisse super-admin.
-- Necessite que le caller soit admin (a verifier via une table user_roles).
create or replace function public.treasury_get_balance()
returns table(
  balance bigint,
  total_in bigint,
  total_out bigint,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  -- TODO: verification admin
  -- if not exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'admin') then
  --   raise exception 'NOT_ADMIN';
  -- end if;
  return query select t.balance, t.total_in, t.total_out, t.updated_at
    from public.treasury_balance t where t.id = 1;
end;
$$;

grant execute on function public.treasury_get_balance() to authenticated;

-- ============================================================
-- 8) Vue admin : revenus par jeu / par jour
-- ============================================================
create or replace view public.treasury_daily_revenue as
select
  date_trunc('day', created_at)::date as day,
  game_type,
  count(*) filter (where movement_type = 'house_cut') as cuts_count,
  coalesce(sum(amount) filter (where movement_type = 'house_cut'), 0) as house_revenue,
  coalesce(sum(amount) filter (where movement_type = 'loss_collect'), 0) as direct_losses,
  coalesce(sum(amount) filter (where movement_type = 'payout'), 0) as total_payouts
from public.treasury_movements
group by 1, 2
order by 1 desc, 2;

grant select on public.treasury_daily_revenue to authenticated;

-- ============================================================
-- 9) RPC : treasury_place_bet (debit joueur + credit caisse, atomique)
-- ============================================================
-- A APPELER au moment ou le joueur place sa mise, AU LIEU de juste
-- deduire les coins du joueur. Ca garantit que l'argent va dans la
-- caisse super-admin et n'est pas "perdu" du systeme.
--
-- Modele zero-creation : l'argent ne disparait jamais, il transite
-- toujours entre solde joueur ↔ caisse super-admin.
create or replace function public.treasury_place_bet(
  p_game_type text,
  p_game_id text,
  p_user_id uuid,
  p_amount int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance int;
begin
  if p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if p_user_id is null then
    raise exception 'INVALID_USER';
  end if;

  -- Lock + verifier solde
  select coins into v_balance from public.user_profiles
    where id = p_user_id for update;
  if v_balance is null then
    raise exception 'NO_PROFILE';
  end if;
  if v_balance < p_amount then
    raise exception 'INSUFFICIENT_COINS';
  end if;

  -- Debit joueur
  update public.user_profiles
    set coins = coins - p_amount, updated_at = now()
    where id = p_user_id;

  -- Credit caisse
  update public.treasury_balance
    set balance = balance + p_amount,
        total_in = total_in + p_amount,
        updated_at = now()
    where id = 1;

  -- Log
  insert into public.treasury_movements
    (game_type, game_id, user_id, movement_type, amount)
    values (p_game_type, p_game_id, p_user_id, 'loss_collect', p_amount);
end;
$$;

grant execute on function public.treasury_place_bet(text, text, uuid, int) to authenticated;

-- ============================================================
-- 10) RPC : treasury_pay_winner (credit joueur depuis caisse, atomique)
-- ============================================================
-- Pour les jeux SOLO (Mines, Apple Fortune, Aviator) ou la mise est deja
-- dans la caisse, et le winner doit recevoir bet * multiplicateur.
-- L'argent provient de la caisse super-admin (alimentee par les pertes).
--
-- Note: pour les jeux MULTI (Coinflip, Ludo, Cora, Roulette, Blackjack,
-- Fantasy), utilise apply_game_payout() a la place — il fait le split
-- (1 - edge) au winner + edge a la caisse en une seule operation.
create or replace function public.treasury_pay_winner(
  p_game_type text,
  p_game_id text,
  p_user_id uuid,
  p_amount int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg record;
begin
  if p_amount <= 0 then return; end if;
  if p_user_id is null then
    raise exception 'INVALID_USER';
  end if;

  -- Plafond max_payout (anti-fraude)
  select * into v_cfg from public.house_edge_config
    where game_type = p_game_type;
  if found and v_cfg.max_payout is not null and p_amount > v_cfg.max_payout then
    p_amount := v_cfg.max_payout;
  end if;

  -- Credit joueur
  update public.user_profiles
    set coins = coins + p_amount, updated_at = now()
    where id = p_user_id;

  -- Debit caisse (peut aller negatif temporairement, c'est normal)
  update public.treasury_balance
    set balance = balance - p_amount,
        total_out = total_out + p_amount,
        updated_at = now()
    where id = 1;

  -- Log
  insert into public.treasury_movements
    (game_type, game_id, user_id, movement_type, amount)
    values (p_game_type, p_game_id, p_user_id, 'payout', p_amount);
end;
$$;

grant execute on function public.treasury_pay_winner(text, text, uuid, int) to authenticated;

-- ============================================================
-- 11) Vue admin : revenus globaux + par jeu
-- ============================================================
create or replace view public.treasury_summary as
select
  (select balance from public.treasury_balance where id = 1) as current_balance,
  (select total_in from public.treasury_balance where id = 1) as total_collected,
  (select total_out from public.treasury_balance where id = 1) as total_paid_out,
  (select count(*) from public.treasury_movements where movement_type = 'house_cut') as house_cuts_count,
  coalesce((select sum(amount) from public.treasury_movements where movement_type = 'house_cut'), 0) as house_cuts_total,
  coalesce((select sum(amount) from public.treasury_movements where movement_type = 'loss_collect'), 0) as losses_collected,
  coalesce((select sum(amount) from public.treasury_movements where movement_type = 'payout'), 0) as payouts_total;

grant select on public.treasury_summary to authenticated;

-- Top joueurs net (gagnants/perdants reels)
create or replace view public.treasury_player_stats as
select
  user_id,
  count(*) filter (where movement_type = 'loss_collect') as bets_lost,
  count(*) filter (where movement_type = 'payout') as bets_won,
  coalesce(sum(amount) filter (where movement_type = 'loss_collect'), 0) as total_wagered,
  coalesce(sum(amount) filter (where movement_type = 'payout'), 0) as total_won,
  coalesce(sum(amount) filter (where movement_type = 'payout'), 0)
    - coalesce(sum(amount) filter (where movement_type = 'loss_collect'), 0) as net_position
from public.treasury_movements
where user_id is not null
group by user_id
order by net_position desc;

grant select on public.treasury_player_stats to authenticated;

-- ============================================================
-- 12) Backward-compat : wrapper sur les vieilles RPCs
-- ============================================================
-- Aviator et Solitaire utilisent ces noms. On les wrap pour qu'ils
-- redirigent vers les nouvelles RPCs (avec log) sans casser l'existant.
create or replace function public.game_treasury_collect_loss(
  p_amount int,
  p_game_type text,
  p_user_id uuid,
  p_description text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.treasury_collect_loss(
    p_game_type,
    p_description, -- on stocke la description en game_id (pas ideal mais retro-compat)
    p_user_id,
    p_amount
  );
end;
$$;

grant execute on function public.game_treasury_collect_loss(int, text, uuid, text) to authenticated;

create or replace function public.game_treasury_pay_win(
  p_amount int,
  p_game_type text,
  p_user_id uuid,
  p_description text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Pour les jeux qui appellent encore l'ancien API, on credite directement
  -- le winner (le edge a deja ete deduit par leur logique interne, ex: Aviator
  -- avec sa Pareto distribution).
  -- Note : si tu veux que ces jeux passent aussi par apply_game_payout,
  -- il faut modifier le code Dart qui les appelle.
  update public.user_profiles
    set coins = coins + p_amount, updated_at = now()
    where id = p_user_id;

  update public.treasury_balance
    set balance = balance - p_amount,
        total_out = total_out + p_amount,
        updated_at = now()
    where id = 1;

  insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, metadata)
    values (p_game_type, null, p_user_id, 'payout', p_amount, jsonb_build_object('legacy', true, 'description', p_description));
end;
$$;

grant execute on function public.game_treasury_pay_win(int, text, uuid, text) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- A faire ensuite : modifier chaque RPC settlement (rlt_auto_continue,
-- cf_auto_continue, finish_ludo_game, etc.) pour appeler apply_game_payout
-- au lieu de creditier le winner manuellement.
-- Voir ARCHITECTURE_PROFIT_ANALYSIS.md section 6.
