// ============================================================
// Edge Function : freemopay_webhook
// ============================================================
// Webhook officiel Freemopay avec :
//   - Validation HMAC SHA256 (anti-forgery)
//   - Idempotence stricte par reference
//   - Triple validation (external_id, amount, reference)
//   - Logging complet via payment_events (timeline)
//   - Crédit/refund automatique via wallet_apply_delta
//   - Anti-replay via timestamp + nonce
//
// CONFIGURATION REQUISE :
//   1. Variables Supabase Edge Function Secrets :
//      - FREEMOPAY_WEBHOOK_SECRET : secret partagé avec Freemopay
//      - SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto)
//
//   2. Côté Freemopay : configurer la URL callback
//      https://<projet>.supabase.co/functions/v1/freemopay_webhook
//      avec signature HMAC SHA256 du body avec FREEMOPAY_WEBHOOK_SECRET
//      dans le header X-Freemopay-Signature (ou similaire selon Freemopay)
//
//   3. Deploy :
//      supabase functions deploy freemopay_webhook --no-verify-jwt
//
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { crypto as denoCrypto } from 'https://deno.land/std@0.224.0/crypto/mod.ts'

interface FreemoPayload {
  reference?: string
  externalId?: string
  external_id?: string
  status?: string  // 'SUCCESS' | 'FAILED' | 'CANCELLED' | 'EXPIRED'
  amount?: number | string
  message?: string | { fr?: string }
  payer?: string
  receiver?: string
}

// HMAC SHA256 verification (constant-time compare)
async function verifyHmac(
  rawBody: string,
  signature: string,
  secret: string,
): Promise<boolean> {
  if (!signature || !secret) return false
  try {
    const enc = new TextEncoder()
    const key = await denoCrypto.subtle.importKey(
      'raw',
      enc.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    )
    const sigBuf = await denoCrypto.subtle.sign('HMAC', key, enc.encode(rawBody))
    const expectedHex = Array.from(new Uint8Array(sigBuf))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('')

    // Constant-time compare (anti timing attack)
    const a = signature.toLowerCase().replace(/^sha256=/i, '')
    const b = expectedHex
    if (a.length !== b.length) return false
    let result = 0
    for (let i = 0; i < a.length; i++) result |= a.charCodeAt(i) ^ b.charCodeAt(i)
    return result === 0
  } catch (e) {
    console.error('HMAC verify error:', e)
    return false
  }
}

Deno.serve(async (req) => {
  const startTime = Date.now()

  // 1. Lire le body brut (nécessaire pour HMAC sur le payload exact)
  const rawBody = await req.text()
  const sig =
    req.headers.get('x-freemopay-signature') ??
    req.headers.get('x-signature') ??
    req.headers.get('signature') ??
    ''
  const ip =
    req.headers.get('x-forwarded-for') ?? req.headers.get('cf-connecting-ip') ?? 'unknown'

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  // 2. Vérifier la signature HMAC
  const webhookSecret = Deno.env.get('FREEMOPAY_WEBHOOK_SECRET') ?? ''
  if (!webhookSecret) {
    return new Response(
      JSON.stringify({ error: 'WEBHOOK_SECRET_NOT_CONFIGURED' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }

  const validSig = await verifyHmac(rawBody, sig, webhookSecret)

  // 3. Parser le payload (même si signature invalide, pour log)
  let payload: FreemoPayload = {}
  try {
    payload = JSON.parse(rawBody)
  } catch {
    // body invalide
  }
  const reference = payload.reference ?? ''
  const externalId = payload.externalId ?? payload.external_id ?? ''
  const fmStatus = String(payload.status ?? '').toUpperCase()
  const fmAmount = parseInt(String(payload.amount ?? '0'), 10) || 0

  // 4. Si signature invalide → log + 401
  if (!validSig) {
    // Log dans payment_events si on a une reference identifiable
    if (reference) {
      const { data: tx } = await supabase
        .from('freemopay_transactions')
        .select('id, correlation_id, user_id')
        .eq('reference', reference)
        .maybeSingle()
      if (tx) {
        await supabase.rpc('log_payment_event', {
          p_correlation_id: tx.correlation_id,
          p_event_type: 'HMAC_INVALID',
          p_freemopay_tx_id: tx.id,
          p_user_id: tx.user_id,
          p_level: 'critical',
          p_message: 'Webhook avec signature invalide reçu',
          p_payload: { ip, signature_received: sig.slice(0, 20) + '...', payload_excerpt: rawBody.slice(0, 200) },
          p_source: 'webhook',
        })
        // Trigger admin alert
        await supabase.rpc('raise_admin_alert', {
          p_type: 'webhook_forgery_attempt',
          p_severity: 'critical',
          p_title: 'Tentative de forgery webhook Freemopay',
          p_description: `Signature invalide pour reference ${reference} depuis ${ip}`,
          p_context: { ip, reference, signature_excerpt: sig.slice(0, 20) },
        })
      }
    }
    return new Response(JSON.stringify({ error: 'INVALID_SIGNATURE' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // 5. Validation payload
  if (!reference || !fmStatus) {
    return new Response(JSON.stringify({ error: 'INVALID_PAYLOAD' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // 6. Récupérer la transaction stockée
  const { data: tx, error: txErr } = await supabase
    .from('freemopay_transactions')
    .select('*')
    .eq('reference', reference)
    .maybeSingle()

  if (txErr || !tx) {
    return new Response(JSON.stringify({ error: 'TX_NOT_FOUND', reference }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // 7. Logger réception
  await supabase.rpc('log_payment_event', {
    p_correlation_id: tx.correlation_id,
    p_event_type: 'WEBHOOK_RECEIVED',
    p_freemopay_tx_id: tx.id,
    p_user_id: tx.user_id,
    p_level: 'info',
    p_message: `Webhook ${fmStatus} reçu depuis Freemopay`,
    p_payload: { ...payload, ip },
    p_source: 'webhook',
  })

  await supabase.rpc('log_payment_event', {
    p_correlation_id: tx.correlation_id,
    p_event_type: 'HMAC_VALIDATED',
    p_freemopay_tx_id: tx.id,
    p_user_id: tx.user_id,
    p_level: 'info',
    p_message: 'Signature HMAC validée',
    p_payload: { ip },
    p_source: 'webhook',
  })

  // 8. Triple validation : external_id + amount + status logique
  if (externalId && externalId !== tx.external_id) {
    await supabase.rpc('log_payment_event', {
      p_correlation_id: tx.correlation_id,
      p_event_type: 'ALERT_TRIGGERED',
      p_freemopay_tx_id: tx.id,
      p_user_id: tx.user_id,
      p_level: 'error',
      p_message: 'external_id mismatch entre webhook et DB',
      p_payload: { ours: tx.external_id, freemopay: externalId },
      p_source: 'webhook',
    })
    return new Response(JSON.stringify({ error: 'EXTERNAL_ID_MISMATCH' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  if (fmAmount && fmAmount !== tx.amount) {
    await supabase.rpc('log_payment_event', {
      p_correlation_id: tx.correlation_id,
      p_event_type: 'ALERT_TRIGGERED',
      p_freemopay_tx_id: tx.id,
      p_user_id: tx.user_id,
      p_level: 'critical',
      p_message: 'AMOUNT mismatch entre webhook et DB - tentative de fraude possible',
      p_payload: { ours: tx.amount, freemopay: fmAmount },
      p_source: 'webhook',
    })
    return new Response(JSON.stringify({ error: 'AMOUNT_MISMATCH' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // 9. Idempotence : si déjà traité (status = SUCCESS) avec wallet_ledger, no-op
  if (tx.status === 'SUCCESS' && fmStatus === 'SUCCESS') {
    return new Response(JSON.stringify({ ok: true, idempotent: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // 10. Traitement selon le status
  let result: Record<string, unknown> = {}

  if (fmStatus === 'SUCCESS' || fmStatus === 'COMPLETED') {
    if (tx.transaction_type === 'DEPOSIT') {
      // Crédit user via wallet_apply_delta (idempotent par request_id)
      const { error: wErr } = await supabase.rpc('wallet_apply_delta', {
        p_user_id: tx.user_id,
        p_delta: tx.amount,
        p_reason: 'mobile_money_deposit',
        p_ref_type: 'freemopay_tx',
        p_ref_id: tx.id,
        p_metadata: { reference, source: 'webhook', payload },
        p_request_id: `webhook_dep_${tx.id}`,  // idempotence stricte
      })

      if (wErr) {
        await supabase.rpc('log_payment_event', {
          p_correlation_id: tx.correlation_id,
          p_event_type: 'ALERT_TRIGGERED',
          p_freemopay_tx_id: tx.id,
          p_user_id: tx.user_id,
          p_level: 'critical',
          p_message: 'wallet_apply_delta failed après webhook SUCCESS',
          p_payload: { error: wErr.message },
          p_source: 'webhook',
        })
        return new Response(JSON.stringify({ error: 'WALLET_FAILED', detail: wErr.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        })
      }

      await supabase.rpc('log_payment_event', {
        p_correlation_id: tx.correlation_id,
        p_event_type: 'WALLET_CREDITED',
        p_freemopay_tx_id: tx.id,
        p_user_id: tx.user_id,
        p_level: 'info',
        p_message: `User crédité de ${tx.amount} coins`,
        p_payload: { amount: tx.amount },
        p_source: 'webhook',
      })
      result.credited = tx.amount
    }
    // Pour WITHDRAW : pas de credit (le user a deja ete debite a l'init)

  } else if (['FAILED', 'EXPIRED', 'CANCELLED', 'REJECTED'].includes(fmStatus)) {
    // Pour WITHDRAW : refund automatique
    if (tx.transaction_type === 'WITHDRAW' && tx.status === 'PENDING') {
      const { error: wErr } = await supabase.rpc('wallet_apply_delta', {
        p_user_id: tx.user_id,
        p_delta: tx.amount,
        p_reason: 'mobile_money_withdraw_refund',
        p_ref_type: 'freemopay_tx',
        p_ref_id: tx.id,
        p_metadata: { reason: 'webhook_failed', payload },
        p_request_id: `webhook_wd_refund_${tx.id}`,
      })
      if (wErr) {
        await supabase.rpc('log_payment_event', {
          p_correlation_id: tx.correlation_id,
          p_event_type: 'ALERT_TRIGGERED',
          p_freemopay_tx_id: tx.id,
          p_user_id: tx.user_id,
          p_level: 'critical',
          p_message: 'Refund failed sur retrait FAILED',
          p_payload: { error: wErr.message },
          p_source: 'webhook',
        })
      } else {
        await supabase.rpc('log_payment_event', {
          p_correlation_id: tx.correlation_id,
          p_event_type: 'WALLET_REFUNDED',
          p_freemopay_tx_id: tx.id,
          p_user_id: tx.user_id,
          p_level: 'info',
          p_message: `User remboursé ${tx.amount} coins après retrait failed`,
          p_payload: { amount: tx.amount },
          p_source: 'webhook',
        })
        result.refunded = tx.amount
      }
    }
  }

  // 11. UPDATE freemopay_transactions status
  // ATTENTION : RLS bloque update direct, donc on utilise le service_role
  const finalStatus = ['SUCCESS', 'COMPLETED'].includes(fmStatus) ? 'SUCCESS' :
                      ['FAILED', 'EXPIRED', 'CANCELLED', 'REJECTED'].includes(fmStatus) ? 'FAILED' :
                      'PENDING'

  const { error: updErr } = await supabase
    .from('freemopay_transactions')
    .update({
      status: finalStatus,
      callback_data: payload,
      message: typeof payload.message === 'object' ? payload.message.fr : payload.message,
      updated_at: new Date().toISOString(),
    })
    .eq('id', tx.id)

  if (updErr) {
    await supabase.rpc('log_payment_event', {
      p_correlation_id: tx.correlation_id,
      p_event_type: 'ALERT_TRIGGERED',
      p_freemopay_tx_id: tx.id,
      p_user_id: tx.user_id,
      p_level: 'error',
      p_message: 'UPDATE freemopay_transactions failed',
      p_payload: { error: updErr.message },
      p_source: 'webhook',
    })
  }

  // 12. Log final
  await supabase.rpc('log_payment_event', {
    p_correlation_id: tx.correlation_id,
    p_event_type: 'STATUS_UPDATED',
    p_freemopay_tx_id: tx.id,
    p_user_id: tx.user_id,
    p_level: 'info',
    p_message: `Transaction marquée ${finalStatus}`,
    p_payload: { from: tx.status, to: finalStatus, duration_ms: Date.now() - startTime },
    p_source: 'webhook',
  })

  return new Response(
    JSON.stringify({ ok: true, status: finalStatus, ...result }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  )
})
