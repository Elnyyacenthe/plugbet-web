// ============================================================
// Edge Function : freemopay_tx_watcher
// ============================================================
// Watcher dedie a UNE seule transaction. Declenche par trigger DB
// sur INSERT freemopay_transactions (PENDING).
//
// Strategie : backoff progressif sur ~2 minutes.
//   - 15s, +30s, +60s = 105s max
// A chaque check :
//   1. Verifie l'etat actuel de la transaction (peut etre deja resolue
//      par polling Flutter ou par realtime)
//   2. Si encore PENDING, query Freemopay
//   3. Si SUCCESS/FAILED -> applique + return
//   4. Sinon, loop
//
// Garantie : idempotent via request_id 'freemopay_dep_<tx_id>'
// Si watcher epuise sans resolution -> admin_alerts + cron prend le relai
//
// ENV VARS REQUISES :
//   - CRON_SECRET, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface FreemoConfig {
  appKey: string
  secretKey: string
}

const FREEMOPAY_BASE = 'https://api-v2.freemopay.com/api/v2'
const INTERVALS_SEC = [15, 30, 60] // total ~105s, sous la limite Edge Function

Deno.serve(async (req) => {
  const auth = req.headers.get('Authorization') ?? ''
  const expected = Deno.env.get('CRON_SECRET') ?? ''
  if (!expected || !auth.includes(expected)) {
    return new Response('Unauthorized', { status: 401 })
  }

  const body = await req.json().catch(() => ({})) as { tx_id?: string }
  const txId = body.tx_id
  if (!txId) {
    return new Response(JSON.stringify({ error: 'MISSING_TX_ID' }), { status: 400 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // 1. Charger config Freemopay
  const { data: cfgData, error: cfgErr } = await supabase
    .from('app_settings').select('value').eq('key', 'freemopay_config').maybeSingle()
  if (cfgErr || !cfgData) {
    return new Response(JSON.stringify({ error: 'CONFIG_NOT_FOUND' }), { status: 500 })
  }
  const cfg = cfgData.value as FreemoConfig
  if (!cfg.appKey || !cfg.secretKey) {
    return new Response(JSON.stringify({ error: 'CONFIG_INCOMPLETE' }), { status: 500 })
  }
  const basicAuth = 'Basic ' + btoa(`${cfg.appKey}:${cfg.secretKey}`)

  // 2. Charger transaction
  const { data: txInit, error: txErr } = await supabase
    .from('freemopay_transactions').select('*').eq('id', txId).maybeSingle()
  if (txErr || !txInit) {
    return new Response(JSON.stringify({ error: 'TX_NOT_FOUND' }), { status: 404 })
  }
  if (txInit.status !== 'PENDING') {
    return new Response(JSON.stringify({ resolved: 'already', status: txInit.status }))
  }

  const tx = txInit
  let checks = 0
  const log: Array<Record<string, unknown>> = []

  // 3. Backoff loop
  for (const delay of INTERVALS_SEC) {
    await new Promise(r => setTimeout(r, delay * 1000))
    checks++

    // Re-check etat (peut avoir ete resolu par polling Flutter ou cron)
    const { data: txNow } = await supabase
      .from('freemopay_transactions').select('status').eq('id', txId).maybeSingle()
    if (!txNow || txNow.status !== 'PENDING') {
      log.push({ check: checks, action: 'resolved_externally', status: txNow?.status })
      return new Response(JSON.stringify({ resolved: 'external', checks, log }))
    }

    // Query Freemopay
    let fmStatus = ''
    let fmExternalId = ''
    let fmAmount = 0
    let data: Record<string, unknown> = {}
    try {
      const resp = await fetch(`${FREEMOPAY_BASE}/payment/${tx.reference}`, {
        method: 'GET', headers: { Authorization: basicAuth },
      })
      if (!resp.ok) {
        log.push({ check: checks, http: resp.status, action: 'skip' })
        continue
      }
      const json = await resp.json() as Record<string, unknown>
      data = (json.data ?? json) as Record<string, unknown>
      fmStatus = String(data.status ?? '').toUpperCase()
      fmExternalId = String(data.externalId ?? data.external_id ?? '')
      fmAmount = parseInt(String(data.amount ?? '0'), 10)
    } catch (e) {
      log.push({ check: checks, error: String(e), action: 'network_skip' })
      continue
    }

    // Triple validation
    if (fmExternalId && fmExternalId !== tx.external_id) {
      log.push({ check: checks, action: 'skip_external_id_mismatch', got: fmExternalId, expected: tx.external_id })
      continue
    }
    if (fmAmount && fmAmount !== tx.amount) {
      log.push({ check: checks, action: 'skip_amount_mismatch', got: fmAmount, expected: tx.amount })
      // ANOMALIE GRAVE : amount different -> alert
      await supabase.from('admin_alerts').insert({
        user_id: tx.user_id,
        alert_type: 'freemopay_amount_mismatch',
        severity: 'critical',
        title: 'Montant Freemopay diverge',
        description: `Tx ${tx.id} : amount Freemopay=${fmAmount} differe du notre=${tx.amount}`,
        metadata: { tx_id: tx.id, fm_amount: fmAmount, our_amount: tx.amount }
      })
      continue
    }

    // SUCCESS
    if (fmStatus === 'SUCCESS') {
      if (tx.transaction_type === 'DEPOSIT') {
        const { error: walletErr } = await supabase.rpc('wallet_apply_delta', {
          p_user_id: tx.user_id,
          p_delta: tx.amount,
          p_reason: 'mobile_money_deposit',
          p_ref_type: 'freemopay_tx',
          p_ref_id: tx.id,
          p_metadata: { source: 'tx_watcher', checks, freemopay_data: data },
          p_request_id: `freemopay_dep_${tx.id}`,
        })
        if (walletErr) {
          // Credit echoue -> alert mais on ne marque PAS SUCCESS
          await supabase.from('admin_alerts').insert({
            user_id: tx.user_id,
            alert_type: 'freemopay_watcher_credit_failed',
            severity: 'critical',
            title: 'Echec credit wallet apres SUCCESS Freemopay',
            description: `Tx ${tx.id} : Freemopay SUCCESS mais wallet_apply_delta a echoue : ${walletErr.message}`,
            metadata: { tx_id: tx.id, error: walletErr.message, checks }
          })
          return new Response(JSON.stringify({ error: 'CREDIT_FAILED', detail: walletErr.message, checks }))
        }
      }
      await supabase.from('freemopay_transactions').update({
        status: 'SUCCESS',
        callback_data: { source: 'tx_watcher', checks, freemopay_response: data, date: new Date().toISOString() },
        updated_at: new Date().toISOString(),
      }).eq('id', tx.id)
      return new Response(JSON.stringify({ resolved: 'success', checks, log }))
    }

    // FAILED / EXPIRED / CANCELLED / REJECTED
    if (['FAILED', 'EXPIRED', 'CANCELLED', 'REJECTED'].includes(fmStatus)) {
      if (tx.transaction_type === 'WITHDRAW') {
        await supabase.rpc('wallet_apply_delta', {
          p_user_id: tx.user_id,
          p_delta: tx.amount,
          p_reason: 'mobile_money_withdraw_refund',
          p_ref_type: 'freemopay_tx',
          p_ref_id: tx.id,
          p_metadata: { source: 'tx_watcher', reason: 'withdraw_failed', checks },
          p_request_id: `freemopay_wd_refund_${tx.id}`,
        })
      }
      await supabase.from('freemopay_transactions').update({
        status: 'FAILED',
        message: `Freemopay status: ${fmStatus}`,
        callback_data: { source: 'tx_watcher', checks, freemopay_response: data, date: new Date().toISOString() },
        updated_at: new Date().toISOString(),
      }).eq('id', tx.id)
      return new Response(JSON.stringify({ resolved: 'failed', status: fmStatus, checks, log }))
    }

    // Still PENDING, loop continues
    log.push({ check: checks, action: 'still_pending', fm_status: fmStatus })
  }

  // Watcher epuise sans resolution -> alert + laisse le cron prendre le relai
  await supabase.from('admin_alerts').insert({
    user_id: tx.user_id,
    alert_type: 'freemopay_watcher_exhausted',
    severity: 'warning',
    title: 'Watcher epuise',
    description: `Transaction ${tx.id} (${tx.amount} FCFA) toujours PENDING apres ${checks} checks via watcher. Le cron prendra le relai.`,
    metadata: { tx_id: tx.id, reference: tx.reference, checks, log }
  })

  return new Response(JSON.stringify({ resolved: 'exhausted', checks, log }))
})
