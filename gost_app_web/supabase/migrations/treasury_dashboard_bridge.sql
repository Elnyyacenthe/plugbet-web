-- ============================================================
-- TREASURY DASHBOARD BRIDGE
-- ============================================================
-- Fait converger MON nouveau systeme (treasury_balance, treasury_movements)
-- avec les tables LEGACY que le dashboard lit (admin_treasury,
-- treasury_transactions, game_treasury).
--
-- A executer APRES tous les autres fichiers de migration treasury.
-- Idempotent : safe to re-run.
--
-- Resultat : UNE SEULE caisse visible (admin_treasury) qui contient
-- TOUS les fonds (mises + commissions). Plus de separation game/admin.
-- ============================================================

-- ============================================================
-- 1) Synchroniser admin_treasury avec mon treasury_balance
-- ============================================================
-- Repercute le solde courant + total_in/out dans la table admin_treasury
-- que le dashboard utilise.
update public.admin_treasury
set balance = (select balance from public.treasury_balance where id = 1),
    total_earned = (select total_in from public.treasury_balance where id = 1),
    total_withdrawn = (select total_out from public.treasury_balance where id = 1),
    updated_at = now()
where id = 1;

-- ============================================================
-- 2) Patch treasury_place_bet : ecrit aussi dans admin_treasury + treasury_transactions
-- ============================================================
-- Le bet va directement dans admin_treasury (la caisse unique).
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
  if p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if p_user_id is null then raise exception 'INVALID_USER'; end if;

  select coins into v_balance from public.user_profiles where id = p_user_id for update;
  if v_balance is null then raise exception 'NO_PROFILE'; end if;
  if v_balance < p_amount then raise exception 'INSUFFICIENT_COINS'; end if;

  -- Debit joueur
  update public.user_profiles
    set coins = coins - p_amount, updated_at = now()
    where id = p_user_id;

  -- Credit caisse (mon systeme)
  update public.treasury_balance
    set balance = balance + p_amount,
        total_in = total_in + p_amount,
        updated_at = now()
    where id = 1;

  -- Credit caisse (legacy : admin_treasury que le dashboard lit)
  update public.admin_treasury
    set balance = balance + p_amount,
        total_earned = total_earned + p_amount,
        updated_at = now()
    where id = 1;

  -- Log mon systeme
  insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount)
    values (p_game_type, p_game_id, p_user_id, 'loss_collect', p_amount);

  -- Log legacy (visible sur le dashboard)
  insert into public.treasury_transactions
    (treasury_type, type, amount, game_type, source, description, user_id, metadata)
    values ('admin', 'earning', p_amount, p_game_type, 'bet_placed',
      'Mise placee', p_user_id, jsonb_build_object('game_id', p_game_id));
end;
$$;

grant execute on function public.treasury_place_bet(text, text, uuid, int) to authenticated;

-- ============================================================
-- 3) Patch apply_game_payout : ecrit aussi dans admin_treasury + treasury_transactions
-- ============================================================
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
  if p_pot_total <= 0 then raise exception 'INVALID_POT'; end if;
  if p_winner_id is null then raise exception 'INVALID_WINNER'; end if;

  select * into v_cfg from public.house_edge_config
    where game_type = p_game_type and enabled = true;
  if not found then raise exception 'GAME_NOT_CONFIGURED: %', p_game_type; end if;

  v_house_cut := floor(p_pot_total * v_cfg.edge_pct)::int;
  v_net_payout := p_pot_total - v_house_cut;

  if v_cfg.max_payout is not null and v_net_payout > v_cfg.max_payout then
    v_net_payout := v_cfg.max_payout;
    v_house_cut := p_pot_total - v_net_payout;
  end if;

  -- 1. Crediter le winner
  update public.user_profiles
    set coins = coins + v_net_payout, updated_at = now()
    where id = p_winner_id;

  -- 2. Decrementer la caisse du payout (le pot etait dans admin_treasury via place_bet)
  update public.treasury_balance
    set balance = balance - v_net_payout,
        total_out = total_out + v_net_payout,
        updated_at = now()
    where id = 1;

  update public.admin_treasury
    set balance = balance - v_net_payout,
        total_withdrawn = total_withdrawn + v_net_payout,
        updated_at = now()
    where id = 1;

  -- 3. Log mon systeme
  insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, pot_total, edge_pct)
    values
      (p_game_type, p_game_id, p_winner_id, 'payout', v_net_payout, p_pot_total, v_cfg.edge_pct),
      (p_game_type, p_game_id, null, 'house_cut', v_house_cut, p_pot_total, v_cfg.edge_pct);

  -- 4. Log legacy (visible sur le dashboard)
  insert into public.treasury_transactions
    (treasury_type, type, amount, game_type, source, description, user_id, metadata)
    values
      ('admin', 'payout', v_net_payout, p_game_type, 'multi_win',
        'Paiement gagnant (90% du pot)', p_winner_id,
        jsonb_build_object('game_id', p_game_id, 'pot', p_pot_total)),
      ('admin', 'commission', v_house_cut, p_game_type, 'house_edge',
        'Commission ' || (v_cfg.edge_pct * 100) || '% sur le pot', null,
        jsonb_build_object('game_id', p_game_id, 'pot', p_pot_total));

  return v_net_payout;
end;
$$;

grant execute on function public.apply_game_payout(text, text, uuid, int) to authenticated;

-- ============================================================
-- 4) Patch apply_game_payout_split (multi-winners avec edge)
-- ============================================================
create or replace function public.apply_game_payout_split(
  p_game_type text,
  p_game_id text,
  p_winner_ids uuid[],
  p_pot_total int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg record;
  v_house_cut int;
  v_total_payout int;
  v_per_winner int;
  v_winner uuid;
  v_n int;
  v_actual_house int;
begin
  if p_pot_total <= 0 then raise exception 'INVALID_POT'; end if;
  v_n := array_length(p_winner_ids, 1);
  if v_n is null or v_n = 0 then raise exception 'NO_WINNERS'; end if;

  select * into v_cfg from public.house_edge_config
    where game_type = p_game_type and enabled = true;
  if not found then raise exception 'GAME_NOT_CONFIGURED: %', p_game_type; end if;

  v_house_cut := floor(p_pot_total * v_cfg.edge_pct)::int;
  v_total_payout := p_pot_total - v_house_cut;
  v_per_winner := floor(v_total_payout::numeric / v_n)::int;
  v_actual_house := p_pot_total - (v_per_winner * v_n);

  foreach v_winner in array p_winner_ids loop
    update public.user_profiles
      set coins = coins + v_per_winner, updated_at = now()
      where id = v_winner;

    insert into public.treasury_movements
      (game_type, game_id, user_id, movement_type, amount, pot_total, edge_pct)
      values (p_game_type, p_game_id, v_winner, 'payout', v_per_winner, p_pot_total, v_cfg.edge_pct);

    insert into public.treasury_transactions
      (treasury_type, type, amount, game_type, source, description, user_id, metadata)
      values ('admin', 'payout', v_per_winner, p_game_type, 'multi_split_win',
        'Paiement gagnant (split)', v_winner,
        jsonb_build_object('game_id', p_game_id, 'pot', p_pot_total, 'winners_count', v_n));
  end loop;

  -- Decrementer caisse pour le total paye
  update public.treasury_balance
    set balance = balance - (v_per_winner * v_n),
        total_out = total_out + (v_per_winner * v_n),
        updated_at = now()
    where id = 1;

  update public.admin_treasury
    set balance = balance - (v_per_winner * v_n),
        total_withdrawn = total_withdrawn + (v_per_winner * v_n),
        updated_at = now()
    where id = 1;

  if v_actual_house > 0 then
    insert into public.treasury_movements
      (game_type, game_id, user_id, movement_type, amount, pot_total, edge_pct)
      values (p_game_type, p_game_id, null, 'house_cut', v_actual_house, p_pot_total, v_cfg.edge_pct);

    insert into public.treasury_transactions
      (treasury_type, type, amount, game_type, source, description, user_id, metadata)
      values ('admin', 'commission', v_actual_house, p_game_type, 'house_edge_split',
        'Commission sur split', null,
        jsonb_build_object('game_id', p_game_id, 'pot', p_pot_total, 'winners_count', v_n));
  end if;

  return v_per_winner;
end;
$$;

grant execute on function public.apply_game_payout_split(text, text, uuid[], int) to authenticated;

-- ============================================================
-- 5) Patch treasury_pay_winner : aussi dans admin_treasury + transactions
-- ============================================================
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
  if p_user_id is null then raise exception 'INVALID_USER'; end if;

  select * into v_cfg from public.house_edge_config where game_type = p_game_type;
  if found and v_cfg.max_payout is not null and p_amount > v_cfg.max_payout then
    p_amount := v_cfg.max_payout;
  end if;

  update public.user_profiles
    set coins = coins + p_amount, updated_at = now()
    where id = p_user_id;

  update public.treasury_balance
    set balance = balance - p_amount,
        total_out = total_out + p_amount,
        updated_at = now()
    where id = 1;

  update public.admin_treasury
    set balance = balance - p_amount,
        total_withdrawn = total_withdrawn + p_amount,
        updated_at = now()
    where id = 1;

  insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount)
    values (p_game_type, p_game_id, p_user_id, 'payout', p_amount);

  insert into public.treasury_transactions
    (treasury_type, type, amount, game_type, source, description, user_id, metadata)
    values ('admin', 'payout', p_amount, p_game_type, 'solo_win',
      'Paiement gagnant solo', p_user_id,
      jsonb_build_object('game_id', p_game_id));
end;
$$;

grant execute on function public.treasury_pay_winner(text, text, uuid, int) to authenticated;

-- ============================================================
-- 6) Patch treasury_refund_all : refund visible sur dashboard
-- ============================================================
create or replace function public.treasury_refund_all(
  p_game_type text,
  p_game_id text,
  p_user_ids uuid[],
  p_amount_per_user int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_total int;
begin
  if p_amount_per_user <= 0 then return; end if;

  v_total := p_amount_per_user * array_length(p_user_ids, 1);

  foreach v_user_id in array p_user_ids loop
    update public.user_profiles
      set coins = coins + p_amount_per_user, updated_at = now()
      where id = v_user_id;

    insert into public.treasury_movements
      (game_type, game_id, user_id, movement_type, amount)
      values (p_game_type, p_game_id, v_user_id, 'refund', p_amount_per_user);

    insert into public.treasury_transactions
      (treasury_type, type, amount, game_type, source, description, user_id, metadata)
      values ('admin', 'payout', p_amount_per_user, p_game_type, 'refund_draw',
        'Remboursement match nul', v_user_id,
        jsonb_build_object('game_id', p_game_id, 'reason', 'tie_no_house_cut'));
  end loop;

  update public.treasury_balance
    set balance = balance - v_total,
        total_out = total_out + v_total,
        updated_at = now()
    where id = 1;

  update public.admin_treasury
    set balance = balance - v_total,
        total_withdrawn = total_withdrawn + v_total,
        updated_at = now()
    where id = 1;
end;
$$;

grant execute on function public.treasury_refund_all(text, text, uuid[], int) to authenticated;

-- ============================================================
-- 7) Patch treasury_settle_draw : visible sur dashboard
-- ============================================================
create or replace function public.treasury_settle_draw(
  p_game_type text,
  p_game_id text,
  p_user_ids uuid[],
  p_amount_per_user int
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
  if not found then raise exception 'GAME_NOT_CONFIGURED: %', p_game_type; end if;

  if v_cfg.on_draw = 'refund' then
    -- Refund integral
    perform public.treasury_refund_all(p_game_type, p_game_id, p_user_ids, p_amount_per_user);

  elsif v_cfg.on_draw = 'house_keeps' then
    -- Caisse garde tout (rien a faire, deja dans admin_treasury via place_bet)
    insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, pot_total)
      values (p_game_type, p_game_id, null, 'house_cut', v_pot_total, v_pot_total);
    insert into public.treasury_transactions
      (treasury_type, type, amount, game_type, source, description, metadata)
      values ('admin', 'commission', v_pot_total, p_game_type, 'house_keeps_draw',
        'Caisse garde tout (politique on_draw = house_keeps)',
        jsonb_build_object('game_id', p_game_id, 'pot', v_pot_total));

  else  -- refund_minus_edge
    v_house_cut := floor(p_amount_per_user * v_cfg.edge_pct)::int;
    v_per_user_refund := p_amount_per_user - v_house_cut;
    foreach v_user_id in array p_user_ids loop
      update public.user_profiles
        set coins = coins + v_per_user_refund, updated_at = now()
        where id = v_user_id;
      insert into public.treasury_movements (game_type, game_id, user_id, movement_type, amount, edge_pct)
        values (p_game_type, p_game_id, v_user_id, 'refund', v_per_user_refund, v_cfg.edge_pct);
      insert into public.treasury_transactions
        (treasury_type, type, amount, game_type, source, description, user_id, metadata)
        values ('admin', 'payout', v_per_user_refund, p_game_type, 'refund_minus_edge',
          'Remboursement -10%', v_user_id,
          jsonb_build_object('game_id', p_game_id));
    end loop;

    update public.treasury_balance
      set balance = balance - (v_per_user_refund * array_length(p_user_ids, 1)),
          total_out = total_out + (v_per_user_refund * array_length(p_user_ids, 1)),
          updated_at = now()
      where id = 1;
    update public.admin_treasury
      set balance = balance - (v_per_user_refund * array_length(p_user_ids, 1)),
          total_withdrawn = total_withdrawn + (v_per_user_refund * array_length(p_user_ids, 1)),
          updated_at = now()
      where id = 1;
  end if;
end;
$$;

grant execute on function public.treasury_settle_draw(text, text, uuid[], int) to authenticated;

-- ============================================================
-- 8) Synchronisation FINALE : recalcule admin_treasury depuis treasury_balance
-- ============================================================
update public.admin_treasury
set balance = (select balance from public.treasury_balance where id = 1),
    total_earned = (select total_in from public.treasury_balance where id = 1),
    total_withdrawn = (select total_out from public.treasury_balance where id = 1),
    updated_at = now()
where id = 1;

-- ============================================================
-- FIN
-- ============================================================
-- Verification post-execution :
--
-- 1. Le solde admin_treasury doit matcher mon treasury_balance :
--    select t.balance, a.balance from treasury_balance t, admin_treasury a
--    where t.id = 1 and a.id = 1;
--
-- 2. Lance une partie Coinflip ou Cora Dice ou Ludo V2 :
--    Le dashboard doit voir :
--    - admin_treasury.balance qui augmente du pot (a la mise)
--    - admin_treasury.balance qui diminue du payout (au gain)
--    - Net positif de 10% du pot dans admin_treasury (commission)
--
-- 3. treasury_transactions doit contenir :
--    - 'earning' (mises debitees)
--    - 'payout' (paiement gagnant)
--    - 'commission' (10% du pot)
--    - 'refund' (en cas de match nul)
--
-- Le dashboard se rafraichit automatiquement (realtime subscription).
