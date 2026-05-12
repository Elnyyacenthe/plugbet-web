-- ============================================================
-- FREEMOPAY WITHDRAWAL — Debit via wallet_ledger (V2)
-- ============================================================
-- L'ancien chemin (deductCoins -> my_wallet_apply_delta) ecrit dans
-- wallet_transactions, PAS dans wallet_ledger. Du coup le retrait
-- semble passer mais peut etre annule par wallet-drift-repair-daily.
--
-- Cette RPC fait le debit V2 (ledger) atomiquement :
--   1. Verifie le solde via wallet_balance (lit wallet_ledger)
--   2. Debit via wallet_apply_delta (V2, 7-params)
--   3. Renvoie le nouveau solde ou erreur
--
-- A appeler depuis le client AVANT d'appeler l'API Freemopay.
-- Si Freemopay echoue ensuite, refund via freemopay_refund_withdrawal.
-- ============================================================

create or replace function public.freemopay_debit_for_withdrawal(
  p_amount int,
  p_external_id text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_balance bigint;
  v_new_balance int;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'NOT_AUTH');
  end if;
  if p_amount <= 0 then
    return jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT');
  end if;
  if p_external_id is null or length(p_external_id) = 0 then
    return jsonb_build_object('success', false, 'error', 'MISSING_EXTERNAL_ID');
  end if;

  -- Solde frais depuis le ledger (source de verite)
  v_balance := wallet_balance(v_uid);
  if v_balance < p_amount then
    return jsonb_build_object(
      'success', false,
      'error', 'INSUFFICIENT_FUNDS',
      'balance', v_balance,
      'required', p_amount
    );
  end if;

  -- Debit V2 atomique (wallet_ledger + user_profiles.coins en meme transaction)
  -- Idempotent via request_id : 2 appels avec meme external_id = 1 seul debit
  begin
    v_new_balance := wallet_apply_delta(
      v_uid,
      -p_amount,
      'mobile_money_withdraw',
      'freemopay_tx',
      p_external_id,
      jsonb_build_object('source', 'freemopay_init_withdrawal'),
      'mm_withdraw_debit_' || p_external_id
    );
  exception when others then
    if sqlerrm like '%WALLET_INSUFFICIENT%' then
      return jsonb_build_object(
        'success', false,
        'error', 'INSUFFICIENT_FUNDS',
        'balance', wallet_balance(v_uid)
      );
    end if;
    return jsonb_build_object('success', false, 'error', sqlerrm);
  end;

  return jsonb_build_object('success', true, 'new_balance', v_new_balance);
end;
$$;

grant execute on function public.freemopay_debit_for_withdrawal(int, text) to authenticated;

-- ============================================================
-- Refund si Freemopay echoue apres le debit
-- ============================================================
create or replace function public.freemopay_refund_withdrawal(
  p_amount int,
  p_external_id text,
  p_reason text default 'freemopay_api_failed'
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_new_balance int;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'NOT_AUTH');
  end if;
  if p_amount <= 0 then
    return jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT');
  end if;

  v_new_balance := wallet_apply_delta(
    v_uid,
    p_amount,
    'mobile_money_withdraw_refund',
    'freemopay_tx',
    p_external_id,
    jsonb_build_object('reason', p_reason, 'source', 'client_refund'),
    'mm_withdraw_refund_' || p_external_id
  );

  return jsonb_build_object('success', true, 'new_balance', v_new_balance);
end;
$$;

grant execute on function public.freemopay_refund_withdrawal(int, text, text) to authenticated;
