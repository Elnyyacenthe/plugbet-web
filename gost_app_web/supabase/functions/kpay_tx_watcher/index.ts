// ============================================================
// Edge Function : kpay_tx_watcher
// ============================================================
// Watcher dedie a UNE transaction. Declenche par trigger DB sur
// INSERT kpay_transactions (DEPOSIT PENDING).
//
// Backoff : 15s, +30s, +60s (~105s). A chaque check :
//   1. Re-lit l'etat (peut etre resolu par polling client / cron)
//   2. Si encore PENDING : GET statut K-Pay
//   3. COMPLETED -> credit + SUCCESS ; FAILED -> FAILED (+ refund WITHDRAW)
//
// Idempotent via request_id 'kpay_dep_<tx_id>'.
//
// ENV : CRON_SECRET, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const KPAY_DEFAULT_BASE = 'https://admin.kpay.site'
const INTERVALS_SEC = [15, 30, 60]

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
  } catch { /* best-effort */ }
}

Deno.serve(async (req) => {
  const auth = req.headers.get('Authorization') ?? ''
  const expected = Deno.env.get('CRON_SECRET') ?? ''
  if (!expected || !auth.includes(expected)) {
    return new Response('Unauthorized', { status: 401 })
  }

  const body = await req.json().catch(() => ({})) as { tx_id?: string }
  const txId = body.tx_id
  if (!txId) return new Response(JSON.stringify({ error: 'MISSING_TX_ID' }), { status: 400 })

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  const { data: cfgData, error: cfgErr } = await supabase
    .from('app_settings').select('value').eq('key', 'kpay_config').maybeSingle()
  if (cfgErr || !cfgData) return new Response(JSON.stringify({ error: 'CONFIG_NOT_FOUND' }), { status: 500 })
  const cfg = cfgData.value as Record<string, unknown>
  const apiKey = cfg.apiKey as string | undefined
  const secretKey = cfg.secretKey as string | undefined
  const baseUrl = (cfg.baseUrl as string | undefined) || KPAY_DEFAULT_BASE
  if (!apiKey || !secretKey) return new Response(JSON.stringify({ error: 'CONFIG_INCOMPLETE' }), { status: 500 })
  const kpayHeaders = {
    'Content-Type': 'application/json',
    'X-API-Key': apiKey,
    'X-Secret-Key': secretKey,
  }

  const { data: txInit, error: txErr } = await supabase
    .from('kpay_transactions').select('*').eq('id', txId).maybeSingle()
  if (txErr || !txInit) return new Response(JSON.stringify({ error: 'TX_NOT_FOUND' }), { status: 404 })
  if (txInit.status !== 'PENDING') {
    return new Response(JSON.stringify({ resolved: 'already', status: txInit.status }))
  }

  const tx = txInit
  let checks = 0
  const log: Array<Record<string, unknown>> = []

  const statusUrl = () => tx.transaction_type === 'WITHDRAW'
    ? `${baseUrl}/api/v1/payments/withdraw/${tx.reference}`
    : `${baseUrl}/api/v1/payments/${tx.reference}`

  for (const delay of INTERVALS_SEC) {
    await new Promise(r => setTimeout(r, delay * 1000))
    checks++

    const { data: txNow } = await supabase
      .from('kpay_transactions').select('status, reference').eq('id', txId).maybeSingle()
    if (!txNow || txNow.status !== 'PENDING') {
      return new Response(JSON.stringify({ resolved: 'external', checks, log }))
    }
    // reference toujours placeholder => pas d'id K-Pay a interroger
    if (!txNow.reference || txNow.reference === tx.external_id) {
      log.push({ check: checks, action: 'placeholder_no_kpay_id' })
      continue
    }
    tx.reference = txNow.reference

    let kStatus = '', kExternalId = '', kAmount = 0
    let data: Record<string, unknown> = {}
    try {
      const resp = await fetch(statusUrl(), { method: 'GET', headers: kpayHeaders })
      if (!resp.ok) { log.push({ check: checks, http: resp.status, action: 'skip' }); continue }
      const json = await resp.json() as Record<string, unknown>
      data = (json.data ?? json) as Record<string, unknown>
      kStatus = String(data.status ?? '').toUpperCase()
      kExternalId = String(data.externalId ?? data.external_id ?? '')
      kAmount = parseInt(String(data.amount ?? '0'), 10)
    } catch (e) {
      log.push({ check: checks, error: String(e), action: 'network_skip' })
      continue
    }

    if (kExternalId && kExternalId !== tx.external_id) {
      log.push({ check: checks, action: 'skip_external_id_mismatch', got: kExternalId, expected: tx.external_id })
      continue
    }
    if (kAmount && kAmount !== tx.amount) {
      log.push({ check: checks, action: 'skip_amount_mismatch', got: kAmount, expected: tx.amount })
      await supabase.from('admin_alerts').insert({
        user_id: tx.user_id,
        alert_type: 'kpay_amount_mismatch',
        severity: 'critical',
        title: 'Montant K-Pay diverge',
        description: `Tx ${tx.id} : amount K-Pay=${kAmount} differe du notre=${tx.amount}`,
        metadata: { tx_id: tx.id, kpay_amount: kAmount, our_amount: tx.amount },
      })
      continue
    }

    if (kStatus === 'COMPLETED' || kStatus === 'SUCCESS') {
      if (tx.transaction_type === 'DEPOSIT') {
        const { error: walletErr } = await supabase.rpc('wallet_apply_delta', {
          p_user_id: tx.user_id, p_delta: tx.amount,
          p_reason: 'mobile_money_deposit',
          p_ref_type: 'kpay_tx', p_ref_id: tx.id,
          p_metadata: { source: 'tx_watcher', checks, reference: tx.reference, external_id: tx.external_id, kpay_data: data },
          p_request_id: `kpay_dep_${tx.id}`,
        })
        if (walletErr) {
          await supabase.from('admin_alerts').insert({
            user_id: tx.user_id,
            alert_type: 'kpay_watcher_credit_failed',
            severity: 'critical',
            title: 'Echec credit wallet apres COMPLETED K-Pay',
            description: `Tx ${tx.id} : K-Pay COMPLETED mais wallet_apply_delta a echoue : ${walletErr.message}`,
            metadata: { tx_id: tx.id, error: walletErr.message, checks },
          })
          return new Response(JSON.stringify({ error: 'CREDIT_FAILED', detail: walletErr.message, checks }))
        }
      }
      await supabase.from('kpay_transactions').update({
        status: 'SUCCESS',
        callback_data: { source: 'tx_watcher', checks, kpay_response: data, date: new Date().toISOString() },
        updated_at: new Date().toISOString(),
      }).eq('id', tx.id)
      if (tx.transaction_type === 'DEPOSIT') {
        await notifyUser(tx.user_id, 'Dépôt réussi ✅',
          `${tx.amount} FCFA ont été crédités sur ton compte.`)
      } else {
        await notifyUser(tx.user_id, 'Retrait effectué ✅',
          `${tx.amount} FCFA ont été envoyés vers ton Mobile Money.`)
      }
      return new Response(JSON.stringify({ resolved: 'success', checks, log }))
    }

    if (['FAILED', 'EXPIRED', 'CANCELLED', 'REJECTED'].includes(kStatus)) {
      if (tx.transaction_type === 'WITHDRAW') {
        await supabase.rpc('wallet_apply_delta', {
          p_user_id: tx.user_id, p_delta: tx.amount,
          p_reason: 'mobile_money_withdraw_refund',
          p_ref_type: 'kpay_tx', p_ref_id: tx.external_id,
          p_metadata: { source: 'tx_watcher', reason: 'withdraw_failed', checks, reference: tx.external_id },
          p_request_id: `kpay_wd_refund_${tx.external_id}`,
        })
      }
      // Motif reel renvoye par K-Pay (ex: "Solde insuffisant sur le compte
      // Mobile Money du client.") -> stocke dans message pour affichage app.
      const failReason = (data as Record<string, unknown>).failureReason as string ||
        `K-Pay status: ${kStatus}`
      await supabase.from('kpay_transactions').update({
        status: 'FAILED',
        message: failReason,
        callback_data: { source: 'tx_watcher', checks, kpay_response: data, date: new Date().toISOString() },
        updated_at: new Date().toISOString(),
      }).eq('id', tx.id)
      if (tx.transaction_type === 'WITHDRAW') {
        await notifyUser(tx.user_id, 'Retrait échoué',
          `Ton retrait n'a pas abouti. ${tx.amount} FCFA ont été remboursés sur ton compte.`)
      } else {
        await notifyUser(tx.user_id, 'Dépôt échoué ❌',
          `Ton dépôt de ${tx.amount} FCFA n'a pas abouti. ${failReason}`)
      }
      return new Response(JSON.stringify({ resolved: 'failed', status: kStatus, checks, log }))
    }

    log.push({ check: checks, action: 'still_pending', kpay_status: kStatus })
  }

  await supabase.from('admin_alerts').insert({
    user_id: tx.user_id,
    alert_type: 'kpay_watcher_exhausted',
    severity: 'warning',
    title: 'Watcher K-Pay epuise',
    description: `Transaction ${tx.id} (${tx.amount} FCFA) toujours PENDING apres ${checks} checks. Le cron prendra le relai.`,
    metadata: { tx_id: tx.id, reference: tx.reference, checks, log },
  })

  return new Response(JSON.stringify({ resolved: 'exhausted', checks, log }))
})
