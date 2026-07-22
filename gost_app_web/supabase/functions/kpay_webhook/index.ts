// ============================================================
// Edge Function : kpay_webhook
// ============================================================
// Webhook K-Pay -> credit/refund INSTANTANE cote serveur, meme app
// fermee (restaure le flux instantane type FreemoPay).
//
// K-Pay NE GENERE PAS de webhook secret -> on ne peut pas verifier
// une signature HMAC fiable. Strategie "trigger + verify" :
//   1. Le webhook sert de PING instantane (faible latence)
//   2. On NE FAIT PAS confiance au body : on retrouve la tx en DB
//      puis on RAPPELLE l'API K-Pay (GET status) avec NOS cles API
//      pour confirmer le vrai statut (source de verite authentifiee)
//   3. Credit/refund idempotent selon le statut confirme par l'API
//
// => Securise sans secret : un faux webhook ne peut rien crediter
//    car le statut est revalide aupres de K-Pay.
// Defense en profondeur : si KPAY_WEBHOOK_SECRET (ou
// kpay_config.webhookSecret) est defini ET que la signature est
// presente mais invalide -> 401. Sinon on continue (verify via API).
//
// IDEMPOTENCE (meme cle que client/watcher/cron) :
//   depot  : wallet_apply_delta request_id 'kpay_dep_<tx_id>'
//   refund : 'kpay_wd_refund_<external_id>'
//
// CONFIG : Dashboard K-Pay callback URL =
//   https://<projet>.supabase.co/functions/v1/kpay_webhook
//   verify_jwt = false (config.toml)
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const KPAY_DEFAULT_BASE = 'https://admin.kpay.site'

interface KpayWebhook {
  event?: string
  paymentId?: string
  id?: string
  status?: string
  amount?: number | string
  externalId?: string
  external_id?: string
  failureReason?: string
  message?: string
}

async function hmacHex(secret: string, data: string): Promise<string> {
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(data))
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('')
}

function safeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let r = 0
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return r === 0
}

function j(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  })
}

// Notification push fire-and-forget vers l'utilisateur (via kpay_notify)
async function notifyUser(userId: string, title: string, msg: string): Promise<void> {
  try {
    const base = Deno.env.get('SUPABASE_URL') ?? ''
    const secret = Deno.env.get('CRON_SECRET') ?? ''
    if (!base || !secret) return
    await fetch(`${base}/functions/v1/kpay_notify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-internal-secret': secret },
      body: JSON.stringify({ user_id: userId, title, body: msg }),
      signal: AbortSignal.timeout(8000),
    })
  } catch { /* notif best-effort, jamais bloquant */ }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return j({ error: 'METHOD_NOT_ALLOWED' }, 405)

  const rawBody = await req.text()
  const sigHeader = (
    req.headers.get('x-kpay-signature') ??
    req.headers.get('x-signature') ??
    req.headers.get('signature') ?? ''
  ).toLowerCase().replace(/^sha256=/i, '')
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown'

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  let payload: KpayWebhook = {}
  try { payload = JSON.parse(rawBody) } catch { /* invalid */ }

  const paymentId = String(payload.paymentId ?? payload.id ?? '')
  const externalId = String(payload.externalId ?? payload.external_id ?? '')
  if (!paymentId && !externalId) return j({ error: 'INVALID_PAYLOAD' }, 400)

  // Config K-Pay (cles API pour la re-verification + secret optionnel)
  const { data: cfgRow } = await supabase
    .from('app_settings').select('value').eq('key', 'kpay_config').maybeSingle()
  const cfg = (cfgRow?.value as Record<string, unknown>) ?? {}
  const apiKey = cfg.apiKey as string | undefined
  const secretKey = cfg.secretKey as string | undefined
  const baseUrl = (cfg.baseUrl as string | undefined) || KPAY_DEFAULT_BASE
  const webhookSecret = (Deno.env.get('KPAY_WEBHOOK_SECRET') ?? '') ||
    ((cfg.webhookSecret as string) ?? '')

  // Defense en profondeur : si un secret EST configure et qu'une signature
  // est fournie mais invalide -> rejet. Sinon on continue (verify via API).
  if (webhookSecret && sigHeader) {
    let ok = false
    try {
      ok = safeEq(sigHeader, await hmacHex(webhookSecret, rawBody))
      if (!ok && Object.keys(payload).length) {
        ok = safeEq(sigHeader, await hmacHex(webhookSecret, JSON.stringify(payload)))
      }
    } catch { /* ignore */ }
    if (!ok) {
      await supabase.from('admin_alerts').insert({
        alert_type: 'kpay_webhook_bad_signature', severity: 'critical',
        title: 'Signature webhook K-Pay invalide',
        description: `paymentId=${paymentId} externalId=${externalId} ip=${ip}`,
        metadata: { ip, paymentId, externalId },
      })
      return j({ error: 'INVALID_SIGNATURE' }, 401)
    }
  }

  if (!apiKey || !secretKey) return j({ error: 'KPAY_CONFIG_INCOMPLETE' }, 500)

  // Retrouver la tx (reference = paymentId, fallback external_id)
  const { data: tx, error: txErr } = await (paymentId
    ? supabase.from('kpay_transactions').select('*').eq('reference', paymentId).maybeSingle()
    : supabase.from('kpay_transactions').select('*').eq('external_id', externalId).maybeSingle())

  if (txErr || !tx) {
    // Race (webhook avant commit INSERT) -> 404 : K-Pay re-essaie,
    // et le cron reconcile reste le filet de securite.
    return j({ error: 'TX_NOT_FOUND', paymentId, externalId }, 404)
  }

  // Idempotence rapide
  if (tx.status === 'SUCCESS') return j({ received: true, idempotent: true }, 200)

  // ====== SOURCE DE VERITE : re-interroger l'API K-Pay ======
  if (tx.reference && tx.reference !== tx.external_id) {
    const statusPath = tx.transaction_type === 'WITHDRAW'
      ? `/api/v1/payments/withdraw/${tx.reference}`
      : `/api/v1/payments/${tx.reference}`
    let data: Record<string, unknown> = {}
    try {
      const resp = await fetch(`${baseUrl}${statusPath}`, {
        method: 'GET',
        headers: { 'Content-Type': 'application/json', 'X-API-Key': apiKey, 'X-Secret-Key': secretKey },
        signal: AbortSignal.timeout(15000),
      })
      if (!resp.ok) return j({ received: true, note: `kpay_http_${resp.status}` }, 200)
      const body = await resp.json() as Record<string, unknown>
      data = (body.data ?? body) as Record<string, unknown>
    } catch (e) {
      return j({ received: true, note: `kpay_unreachable: ${String(e).slice(0, 80)}` }, 200)
    }

    const realStatus = String(data.status ?? '').toUpperCase()
    const realAmount = parseInt(String(data.amount ?? '0'), 10) || 0
    const realExtId = String(data.externalId ?? data.external_id ?? '')

    // Validation contre NOS donnees (anti-fraude multi-app)
    if (realExtId && realExtId !== tx.external_id) {
      await supabase.from('admin_alerts').insert({
        user_id: tx.user_id, alert_type: 'kpay_webhook_external_id_mismatch',
        severity: 'error', title: 'external_id mismatch (webhook verify)',
        description: `ours=${tx.external_id} kpay=${realExtId}`,
        metadata: { tx_id: tx.id },
      })
      return j({ error: 'EXTERNAL_ID_MISMATCH' }, 400)
    }
    if (realAmount && realAmount !== tx.amount) {
      await supabase.from('admin_alerts').insert({
        user_id: tx.user_id, alert_type: 'kpay_webhook_amount_mismatch',
        severity: 'critical', title: 'AMOUNT mismatch (webhook verify)',
        description: `ours=${tx.amount} kpay=${realAmount} tx=${tx.id}`,
        metadata: { tx_id: tx.id },
      })
      return j({ error: 'AMOUNT_MISMATCH' }, 400)
    }

    const result: Record<string, unknown> = {}

    if (realStatus === 'COMPLETED' || realStatus === 'SUCCESS') {
      if (tx.transaction_type === 'DEPOSIT') {
        const { error: wErr } = await supabase.rpc('wallet_apply_delta', {
          p_user_id: tx.user_id, p_delta: tx.amount,
          p_reason: 'mobile_money_deposit',
          p_ref_type: 'kpay_tx', p_ref_id: tx.id,
          p_metadata: { source: 'webhook', reference: tx.reference, external_id: tx.external_id, kpay_data: data },
          p_request_id: `kpay_dep_${tx.id}`,
        })
        if (wErr) {
          await supabase.from('admin_alerts').insert({
            user_id: tx.user_id, alert_type: 'kpay_webhook_credit_failed',
            severity: 'critical', title: 'Echec credit wallet depuis webhook K-Pay',
            description: `tx=${tx.id} err=${wErr.message}`,
            metadata: { tx_id: tx.id, error: wErr.message },
          })
          return j({ error: 'WALLET_FAILED', detail: wErr.message }, 500)
        }
        result.credited = tx.amount
      }
    } else if (['FAILED', 'EXPIRED', 'CANCELLED', 'REJECTED'].includes(realStatus)) {
      if (tx.transaction_type === 'WITHDRAW' && tx.status === 'PENDING') {
        const { error: wErr } = await supabase.rpc('wallet_apply_delta', {
          p_user_id: tx.user_id, p_delta: tx.amount,
          p_reason: 'mobile_money_withdraw_refund',
          p_ref_type: 'kpay_tx', p_ref_id: tx.external_id,
          p_metadata: { source: 'webhook', reason: 'verified_failed', reference: tx.external_id, kpay_data: data },
          p_request_id: `kpay_wd_refund_${tx.external_id}`,
        })
        if (!wErr) result.refunded = tx.amount
      }
    } else {
      // Toujours PENDING cote K-Pay : on ne fait rien (le ping etait premature)
      return j({ received: true, status: 'PENDING' }, 200)
    }

    const finalStatus = ['COMPLETED', 'SUCCESS'].includes(realStatus) ? 'SUCCESS' : 'FAILED'
    await supabase.from('kpay_transactions').update({
      status: finalStatus,
      callback_data: { source: 'webhook', kpay_data: data, webhook_payload: payload, date: new Date().toISOString() },
      message: (data.failureReason as string) ?? tx.message,
      updated_at: new Date().toISOString(),
    }).eq('id', tx.id)

    // Notification push (background, sans ecran d'attente)
    if (result.credited) {
      await notifyUser(tx.user_id, 'Dépôt réussi ✅',
        `${tx.amount} FCFA ont été crédités sur ton compte.`)
    } else if (result.refunded) {
      await notifyUser(tx.user_id, 'Retrait échoué',
        `Ton retrait n'a pas abouti. ${tx.amount} FCFA ont été remboursés sur ton compte.`)
    } else if (finalStatus === 'SUCCESS' && tx.transaction_type === 'WITHDRAW') {
      await notifyUser(tx.user_id, 'Retrait effectué ✅',
        `${tx.amount} FCFA ont été envoyés vers ton Mobile Money.`)
    } else if (finalStatus === 'FAILED' && tx.transaction_type === 'DEPOSIT') {
      const reason = (data.failureReason as string) || 'Le paiement n\'a pas abouti.'
      await notifyUser(tx.user_id, 'Dépôt échoué ❌',
        `Ton dépôt de ${tx.amount} FCFA n'a pas abouti. ${reason}`)
    }

    return j({ received: true, status: finalStatus, ...result }, 200)
  }

  // Reference encore placeholder (pas d'id K-Pay) -> rien a verifier
  return j({ received: true, note: 'no_kpay_id_yet' }, 200)
})
