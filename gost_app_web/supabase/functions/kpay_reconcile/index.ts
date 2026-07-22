// ============================================================
// Edge Function : kpay_reconcile
// ============================================================
// Filet de securite. Pour chaque kpay_transactions PENDING > 30s :
//   1. Si reference est encore un placeholder (= external_id) et tx
//      agee > 10 min -> echec d'init : FAILED (+ refund si WITHDRAW)
//   2. Sinon GET le statut K-Pay :
//        DEPOSIT  : GET /api/v1/payments/<id>
//        WITHDRAW : GET /api/v1/payments/withdraw/<id>
//   3. Validation amount (+ externalId si fourni)
//   4. COMPLETED -> credit (DEPOSIT) + status SUCCESS
//   5. FAILED/CANCELLED -> refund (WITHDRAW) + status FAILED
//
// DRY-RUN : ?dry_run=1 ou header X-Dry-Run: 1
//
// ENV : CRON_SECRET, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface KpayTx {
  id: string
  user_id: string
  reference: string
  external_id: string
  transaction_type: 'DEPOSIT' | 'WITHDRAW'
  amount: number
  status: string
  created_at: string
}

const KPAY_DEFAULT_BASE = 'https://admin.kpay.site'

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

function statusUrl(base: string, tx: KpayTx): string {
  return tx.transaction_type === 'WITHDRAW'
    ? `${base}/api/v1/payments/withdraw/${tx.reference}`
    : `${base}/api/v1/payments/${tx.reference}`
}

Deno.serve(async (req) => {
  const auth = req.headers.get('Authorization') ?? ''
  const expected = Deno.env.get('CRON_SECRET') ?? ''
  if (!expected || !auth.includes(expected)) {
    return new Response('Unauthorized', { status: 401 })
  }

  const url = new URL(req.url)
  const dryRun = url.searchParams.get('dry_run') === '1' || req.headers.get('x-dry-run') === '1'

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  const { data: cfgData, error: cfgErr } = await supabase
    .from('app_settings').select('value').eq('key', 'kpay_config').maybeSingle()
  if (cfgErr || !cfgData) {
    return new Response(JSON.stringify({ error: 'CONFIG_NOT_FOUND', detail: cfgErr?.message }), { status: 500 })
  }
  const cfg = cfgData.value as Record<string, unknown>
  const apiKey = cfg.apiKey as string | undefined
  const secretKey = cfg.secretKey as string | undefined
  const baseUrl = (cfg.baseUrl as string | undefined) || KPAY_DEFAULT_BASE
  if (!apiKey || !secretKey) {
    return new Response(JSON.stringify({ error: 'CONFIG_INCOMPLETE' }), { status: 500 })
  }
  const kpayHeaders = {
    'Content-Type': 'application/json',
    'X-API-Key': apiKey,
    'X-Secret-Key': secretKey,
  }

  const cutoff = new Date(Date.now() - 30 * 1000).toISOString()
  const { data: pending, error: pendErr } = await supabase
    .from('kpay_transactions')
    .select('*')
    .eq('status', 'PENDING')
    .lt('created_at', cutoff)
    .order('created_at', { ascending: true })
    .limit(50)

  if (pendErr) {
    return new Response(JSON.stringify({ error: 'FETCH_FAILED', detail: pendErr.message }), { status: 500 })
  }

  const txs = (pending ?? []) as KpayTx[]
  const summary = {
    mode: dryRun ? 'DRY_RUN' : 'EXECUTE',
    checked: txs.length,
    would_credit: 0, credited: 0,
    would_fail: 0, failed: 0,
    still_pending: 0, skipped_validation: 0, errors: 0,
    details: [] as Array<Record<string, unknown>>,
  }

  for (const tx of txs) {
    try {
      const isOurs = tx.external_id.startsWith('DEPOSIT_') || tx.external_id.startsWith('WITHDRAW_')
      if (!isOurs) {
        summary.skipped_validation++
        summary.details.push({ ref: tx.reference, result: 'SKIP_FOREIGN_FORMAT' })
        continue
      }

      const ageMs = Date.now() - new Date(tx.created_at).getTime()

      // Placeholder jamais resolu en id K-Pay -> init ratee
      if (tx.reference === tx.external_id) {
        if (ageMs < 10 * 60 * 1000) {
          summary.still_pending++
          summary.details.push({ ref: tx.reference, result: 'placeholder_recent' })
          continue
        }
        if (!dryRun) {
          if (tx.transaction_type === 'WITHDRAW') {
            await supabase.rpc('wallet_apply_delta', {
              p_user_id: tx.user_id, p_delta: tx.amount,
              p_reason: 'mobile_money_withdraw_refund',
              p_ref_type: 'kpay_tx', p_ref_id: tx.external_id,
              p_metadata: { reconciled: true, reason: 'init_never_completed', reference: tx.external_id },
              p_request_id: `kpay_wd_refund_${tx.external_id}`,
            })
          }
          await supabase.from('kpay_transactions').update({
            status: 'FAILED',
            message: 'Initiation K-Pay jamais aboutie',
            callback_data: { reconciled: true, reason: 'placeholder_stale' },
            updated_at: new Date().toISOString(),
          }).eq('id', tx.id)
        }
        summary.failed++
        summary.details.push({ ref: tx.reference, result: 'MARKED_FAILED_PLACEHOLDER' })
        continue
      }

      const resp = await fetch(statusUrl(baseUrl, tx), { method: 'GET', headers: kpayHeaders })
      if (!resp.ok) {
        summary.errors++
        summary.details.push({ ref: tx.reference, result: `http_${resp.status}` })
        continue
      }

      const json = await resp.json() as Record<string, unknown>
      const data = (json.data ?? json) as Record<string, unknown>
      const kStatus = String(data.status ?? '').toUpperCase()
      const kExternalId = String(data.externalId ?? data.external_id ?? '')
      const kAmount = parseInt(String(data.amount ?? '0'), 10)

      if (kExternalId && kExternalId !== tx.external_id) {
        summary.skipped_validation++
        summary.details.push({ ref: tx.reference, result: 'SKIP_EXTERNAL_ID_MISMATCH', ours: tx.external_id, kpay: kExternalId })
        continue
      }
      if (kAmount && kAmount !== tx.amount) {
        summary.skipped_validation++
        summary.details.push({ ref: tx.reference, result: 'SKIP_AMOUNT_MISMATCH', ours: tx.amount, kpay: kAmount })
        continue
      }

      // === COMPLETED ===
      if (kStatus === 'COMPLETED' || kStatus === 'SUCCESS') {
        const detail: Record<string, unknown> = {
          ref: tx.reference, user_id: tx.user_id, amount: tx.amount,
          type: tx.transaction_type, kpay_status: kStatus,
        }
        if (dryRun) {
          summary.would_credit++
          detail.result = tx.transaction_type === 'DEPOSIT' ? 'WOULD_CREDIT_DEPOSIT' : 'WOULD_MARK_WITHDRAW_SUCCESS'
        } else {
          if (tx.transaction_type === 'DEPOSIT') {
            const { error: walletErr } = await supabase.rpc('wallet_apply_delta', {
              p_user_id: tx.user_id, p_delta: tx.amount,
              p_reason: 'mobile_money_deposit',
              p_ref_type: 'kpay_tx', p_ref_id: tx.id,
              p_metadata: { reconciled: true, reference: tx.reference, external_id: tx.external_id, source: 'reconcile_cron', kpay_response: data },
              p_request_id: `kpay_dep_${tx.id}`,
            })
            if (walletErr) {
              summary.errors++
              detail.result = `wallet_err: ${walletErr.message}`
              summary.details.push(detail)
              continue
            }
          }
          await supabase.from('kpay_transactions').update({
            status: 'SUCCESS',
            callback_data: { reconciled: true, kpay_response: data, date: new Date().toISOString() },
            updated_at: new Date().toISOString(),
          }).eq('id', tx.id)
          if (tx.transaction_type === 'DEPOSIT') {
            await notifyUser(tx.user_id, 'Dépôt réussi ✅',
              `${tx.amount} FCFA ont été crédités sur ton compte.`)
          } else {
            await notifyUser(tx.user_id, 'Retrait effectué ✅',
              `${tx.amount} FCFA ont été envoyés vers ton Mobile Money.`)
          }
          summary.credited++
          detail.result = 'CREDITED'
        }
        summary.details.push(detail)
      }
      // === FAILED ===
      else if (['FAILED', 'EXPIRED', 'CANCELLED', 'REJECTED'].includes(kStatus)) {
        const detail: Record<string, unknown> = {
          ref: tx.reference, user_id: tx.user_id, amount: tx.amount,
          type: tx.transaction_type, kpay_status: kStatus,
        }
        if (dryRun) {
          summary.would_fail++
          detail.result = tx.transaction_type === 'WITHDRAW' ? 'WOULD_REFUND_WITHDRAW' : 'WOULD_MARK_FAILED'
        } else {
          if (tx.transaction_type === 'WITHDRAW') {
            const { error: walletErr } = await supabase.rpc('wallet_apply_delta', {
              p_user_id: tx.user_id, p_delta: tx.amount,
              p_reason: 'mobile_money_withdraw_refund',
              p_ref_type: 'kpay_tx', p_ref_id: tx.external_id,
              p_metadata: { reconciled: true, reason: 'withdraw_failed', reference: tx.external_id },
              p_request_id: `kpay_wd_refund_${tx.external_id}`,
            })
            if (walletErr) {
              summary.errors++
              detail.result = `refund_err: ${walletErr.message}`
              summary.details.push(detail)
              continue
            }
          }
          const failReason = (data as Record<string, unknown>).failureReason as string ||
            'Le paiement n\'a pas abouti.'
          await supabase.from('kpay_transactions').update({
            status: 'FAILED',
            message: failReason,
            callback_data: { reconciled: true, kpay_response: data, date: new Date().toISOString() },
            updated_at: new Date().toISOString(),
          }).eq('id', tx.id)
          if (tx.transaction_type === 'WITHDRAW') {
            await notifyUser(tx.user_id, 'Retrait échoué',
              `Ton retrait n'a pas abouti. ${tx.amount} FCFA ont été remboursés sur ton compte.`)
          } else {
            await notifyUser(tx.user_id, 'Dépôt échoué ❌',
              `Ton dépôt de ${tx.amount} FCFA n'a pas abouti. ${failReason}`)
          }
          summary.failed++
          detail.result = 'MARKED_FAILED'
        }
        summary.details.push(detail)
      }
      // === STILL PENDING ===
      else {
        summary.still_pending++
        summary.details.push({
          ref: tx.reference, result: 'still_pending', kpay_status: kStatus,
          age_minutes: Math.round(ageMs / 60000),
        })
      }
    } catch (e) {
      summary.errors++
      summary.details.push({ ref: tx.reference, result: `exception: ${String(e).slice(0, 100)}` })
    }
    await new Promise(r => setTimeout(r, 300))
  }

  if (!dryRun) {
    await supabase.rpc('log_event', {
      p_level: summary.errors > 0 ? 'warn' : 'info',
      p_source: 'kpay_reconcile',
      p_message: `Reconcile: ${summary.credited} credited, ${summary.failed} failed, ${summary.still_pending} pending, ${summary.skipped_validation} skipped, ${summary.errors} errors`,
      p_context: summary,
    }).then(() => {}, () => {})
  }

  return new Response(JSON.stringify(summary, null, 2), {
    headers: { 'Content-Type': 'application/json' },
  })
})
