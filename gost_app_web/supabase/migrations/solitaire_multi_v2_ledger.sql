-- ============================================================
-- SOLITAIRE MULTIJOUEUR V2 — Migration vers _ledger_post
-- ============================================================
-- Bug : le service multijoueur Solitaire utilise WalletService.deductCoins
-- qui appelle l'ancienne RPC my_wallet_apply_delta. Si elle est cassée /
-- retourne null, le user voit "fonds insuffisants" même avec les fonds.
--
-- Fix : nouvelle RPC solitaire_multi_place_bet qui passe par _ledger_post
-- (V3, idempotent, atomique). Le service Dart appellera celle-ci.
-- ============================================================

-- ============================================================
-- 1. Place une mise pour rejoindre/créer une room solitaire multi
-- ============================================================
create or replace function public.solitaire_multi_place_bet(
  p_room_id  text,    -- room_id de la solitaire_rooms (multi)
  p_amount   bigint
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;
  if p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if p_amount < 50 or p_amount > 10000 then
    raise exception 'INVALID_BET_RANGE: 50-10000' using errcode = '22023';
  end if;

  -- User bloqué ?
  if exists (select 1 from user_profiles where id = v_uid and is_blocked) then
    raise exception 'ACCOUNT_BLOCKED' using errcode = '42501';
  end if;

  -- Solde suffisant (lecture dual-source via wallet_balance V18)
  v_balance := wallet_balance(v_uid);
  if v_balance < p_amount then
    raise exception 'INSUFFICIENT_FUNDS: required=%, balance=%', p_amount, v_balance
      using errcode = 'P0001';
  end if;

  -- Débit ledger (idempotent par room_id + user)
  perform _ledger_post(
    v_uid, -p_amount, 'bet',
    'solitaire_multi_bet:' || p_room_id || ':' || v_uid::text,
    'solitaire_multi', p_room_id,
    jsonb_build_object('source', 'solitaire_multi_place_bet', 'room_id', p_room_id)
  );

  -- Crédit caisse jeu
  begin
    update game_treasury
      set balance = balance + p_amount,
          total_received = total_received + p_amount,
          updated_at = now()
      where id = 1;
  exception when undefined_table then null;
  end;

  return jsonb_build_object(
    'placed', true,
    'amount', p_amount,
    'new_balance', wallet_balance(v_uid)
  );
end; $$;
revoke all on function public.solitaire_multi_place_bet(text, bigint) from public, anon;
grant execute on function public.solitaire_multi_place_bet(text, bigint) to authenticated;

-- ============================================================
-- 2. Refund (annulation room avant lancement)
-- ============================================================
create or replace function public.solitaire_multi_refund(
  p_room_id  text,
  p_amount   bigint
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  perform _ledger_post(
    v_uid, p_amount, 'refund',
    'solitaire_multi_refund:' || p_room_id || ':' || v_uid::text,
    'solitaire_multi', p_room_id,
    jsonb_build_object('reason', 'room_cancel_or_leave_before_start')
  );

  begin
    update game_treasury
       set balance = greatest(0, balance - p_amount),
           total_paid_out = total_paid_out + p_amount,
           updated_at = now()
     where id = 1;
  exception when undefined_table then null;
  end;

  return jsonb_build_object('refunded', true, 'amount', p_amount);
end; $$;
revoke all on function public.solitaire_multi_refund(text, bigint) from public, anon;
grant execute on function public.solitaire_multi_refund(text, bigint) to authenticated;

-- ============================================================
-- 3. Payout du gagnant (idempotent par room_id)
-- ============================================================
create or replace function public.solitaire_multi_payout(
  p_room_id    text,
  p_winner_id  uuid,
  p_pot        bigint,
  p_house_cut  numeric default 0.10
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_cut bigint;
  v_net bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_pot <= 0 then return jsonb_build_object('paid', 0); end if;

  v_cut := floor(p_pot * coalesce(p_house_cut, 0.10))::bigint;
  v_net := p_pot - v_cut;

  perform _ledger_post(
    p_winner_id, v_net, 'payout',
    'solitaire_multi_payout:' || p_room_id,
    'solitaire_multi', p_room_id,
    jsonb_build_object('pot', p_pot, 'commission', v_cut)
  );

  begin
    update game_treasury
       set balance = balance - p_pot,
           total_paid_out = total_paid_out + p_pot,
           updated_at = now()
     where id = 1;
  exception when undefined_table then null;
  end;

  if v_cut > 0 then
    begin
      update admin_treasury
         set balance = balance + v_cut,
             total_earned = total_earned + v_cut,
             updated_at = now()
       where id = 1;
      if not found then
        insert into admin_treasury(id, balance, total_earned, total_withdrawn)
          values (1, v_cut, v_cut, 0);
      end if;
    exception when undefined_table then null;
    end;
  end if;

  return jsonb_build_object('paid', v_net, 'commission', v_cut);
end; $$;
revoke all on function public.solitaire_multi_payout(text, uuid, bigint, numeric)
  from public, anon, authenticated;
-- Appelé uniquement par le service côté serveur OU via RPC dédiée
-- (pas authenticated direct car le winner_id est un paramètre = vol possible).
