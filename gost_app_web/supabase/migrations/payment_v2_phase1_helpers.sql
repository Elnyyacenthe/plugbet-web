-- ============================================================
-- PAYMENT V2 — PHASE 1 HELPERS (à exécuter APRÈS phase1_lockdown)
-- ============================================================
-- Petites RPCs nécessaires pour que le Flutter puisse :
--   1. Updater la reference Freemopay après le POST /payment
--   2. Annuler un retrait + refund si erreur réseau
-- ============================================================

-- update_freemopay_reference : appelé par le client après initiation Freemopay
-- Pour stocker la reference retournée par Freemopay (utile pour query status)
create or replace function public.update_freemopay_reference(
  p_external_id text,
  p_reference text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tx record;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_tx from public.freemopay_transactions where external_id = p_external_id;
  if not found then raise exception 'TX_NOT_FOUND'; end if;

  -- Sécurité : seul le user qui a créé la tx peut updater sa reference
  if v_tx.user_id != v_uid then
    raise exception 'NOT_OWNER';
  end if;

  -- Ne update que si reference encore vide ou identique (idempotent)
  if v_tx.reference is null or v_tx.reference = p_reference
     or v_tx.reference = v_tx.external_id then
    update public.freemopay_transactions
      set reference = p_reference, updated_at = now()
      where id = v_tx.id;

    perform public.log_payment_event(
      v_tx.correlation_id, 'API_RESPONSE_RECEIVED', v_tx.id, v_uid, 'info',
      'Reference Freemopay attribuée',
      jsonb_build_object('reference', p_reference),
      'mobile_app'
    );
  end if;
end;
$$;
grant execute on function public.update_freemopay_reference(text, text) to authenticated;


-- cancel_freemopay_withdraw : annule un retrait + refund le user
-- Appelé par le client si l'API Freemopay refuse OU timeout réseau.
-- Idempotent par external_id.
create or replace function public.cancel_freemopay_withdraw(
  p_external_id text,
  p_reason text default 'cancelled'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tx record;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_tx from public.freemopay_transactions
    where external_id = p_external_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'TX_NOT_FOUND'); end if;

  -- Sécurité
  if v_tx.user_id != v_uid then raise exception 'NOT_OWNER'; end if;
  if v_tx.transaction_type != 'WITHDRAW' then
    raise exception 'NOT_WITHDRAW';
  end if;

  -- Si déjà cancelled/failed, ne rien refaire (idempotence)
  if v_tx.status in ('FAILED', 'CANCELLED') then
    return jsonb_build_object('ok', true, 'idempotent', true);
  end if;
  if v_tx.status = 'SUCCESS' then
    return jsonb_build_object('ok', false, 'reason', 'ALREADY_SUCCESS');
  end if;

  -- Refund le user (idempotent par request_id)
  perform public.wallet_apply_delta(
    v_uid, v_tx.amount,
    'mobile_money_withdraw_refund',
    'freemopay_tx', v_tx.id::text,
    jsonb_build_object('reason', p_reason),
    'cancel_withdraw_' || v_tx.id::text
  );

  -- Update status
  update public.freemopay_transactions set
    status = 'FAILED',
    message = p_reason,
    updated_at = now()
  where id = v_tx.id;

  perform public.log_payment_event(
    v_tx.correlation_id, 'WALLET_REFUNDED', v_tx.id, v_uid, 'info',
    format('Retrait annulé : %s', p_reason),
    jsonb_build_object('amount', v_tx.amount, 'reason', p_reason),
    'mobile_app'
  );

  return jsonb_build_object('ok', true, 'refunded', v_tx.amount);
end;
$$;
grant execute on function public.cancel_freemopay_withdraw(text, text) to authenticated;
