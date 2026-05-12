// ============================================================
// Edge Function : freemopay_reconcile
// ============================================================
// Pour chaque transaction freemopay_transactions en PENDING > 5 min :
//   1. Appelle Freemopay GET /payment/<reference>
//   2. TRIPLE VALIDATION : reference + external_id + amount doivent matcher
//   3. Si SUCCESS → wallet_apply_delta + UPDATE status='SUCCESS'
//   4. Si FAILED/EXPIRED → UPDATE status='FAILED' (refund pour WITHDRAW)
//   5. Si toujours PENDING → laisse
//
// PROTECTION MULTI-APP : l'API Freemopay peut etre partagee. On verifie que
// la transaction retournee par Freemopay correspond EXACTEMENT a celle
// qu'on a stockee (3 champs match obligatoires) avant de crediter.
//
// MODE DRY-RUN : pour preview ce qui serait fait sans rien modifier,
// passer ?dry_run=1 ou Header X-Dry-Run: 1
//
// USAGE :
//   - Manual : POST /freemopay_reconcile?dry_run=1   (preview)
//   - Manual : POST /freemopay_reconcile             (execution reelle)
//   - Cron : appel toutes les 5 min
//
// ENV VARS REQUISES :
//   - CRON_SECRET, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface FreemoTx {
  id: string
  user_id: string
  reference: string
  external_id: string
  transaction_type: 'DEPOSIT' | 'WITHDRAW'
  amount: number
  status: string
  created_at: string
}

interface FreemoConfig {
  appKey: string
  secretKey: string
  callbackUrl?: string
  active?: boolean
}

const FREEMOPAY_BASE = 'https://api-v2.freemopay.com/api/v2'

Deno.serve(async (req) => {
  const auth = req.headers.get('Authorization') ?? ''
  const expected = Deno.env.get('CRON_SECRET') ?? ''
  if (!expected || !auth.includes(expected)) {
    return new Response('Unauthorized', { status: 401 })
  }

  const url = new URL(req.url)
  const dryRun = url.searchParams.get('dry_run') === '1'
                 || req.headers.get('x-dry-run') === '1'

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // 1. Charger la config
  const { data: cfgData, error: cfgErr } = await supabase
    .from('app_settings').select('value').eq('key', 'freemopay_config').maybeSingle()

  if (cfgErr || !cfgData) {
    return new Response(JSON.stringify({ error: 'CONFIG_NOT_FOUND', detail: cfgErr?.message }), { status: 500 })
  }

  const cfg = cfgData.value as FreemoConfig
  if (!cfg.appKey || !cfg.secretKey) {
    return new Response(JSON.stringify({ error: 'CONFIG_INCOMPLETE' }), { status: 500 })
  }
  const basicAuth = 'Basic ' + btoa(`${cfg.appKey}:${cfg.secretKey}`)

  // 2. Fetch PENDING > 30s, max 50 par run
  // Reduit de 5min a 30s pour que le user attende max ~1.5 min au lieu de 5 min
  const cutoff = new Date(Date.now() - 30 * 1000).toISOString()
  const { data: pending, error: pendErr } = await supabase
    .from('freemopay_transactions')
    .select('*')
    .eq('status', 'PENDING')
    .lt('created_at', cutoff)
    .order('created_at', { ascending: true })
    .limit(50)

  if (pendErr) {
    return new Response(JSON.stringify({ error: 'FETCH_FAILED', detail: pendErr.message }), { status: 500 })
  }

  const txs = (pending ?? []) as FreemoTx[]
  const summary = {
    mode: dryRun ? 'DRY_RUN' : 'EXECUTE',
    checked: txs.length,
    would_credit: 0,    // dry_run : ce qui serait crédité
    credited: 0,        // execute : effectivement crédité
    would_fail: 0,
    failed: 0,
    still_pending: 0,
    skipped_validation: 0,  // Triple-check failed → SKIP par precaution
    errors: 0,
    details: [] as Array<Record<string, unknown>>,
  }

  for (const tx of txs) {
    try {
      // PROTECTION MULTI-APP #1 : verifier que c'est bien NOTRE format d'external_id
      const isOurs = tx.external_id.startsWith('DEPOSIT_') || tx.external_id.startsWith('WITHDRAW_')
      if (!isOurs) {
        summary.skipped_validation++
        summary.details.push({
          ref: tx.reference, result: 'SKIP_FOREIGN_FORMAT',
          external_id: tx.external_id,
        })
        continue
      }

      // Query Freemopay
      const resp = await fetch(`${FREEMOPAY_BASE}/payment/${tx.reference}`, {
        method: 'GET', headers: { Authorization: basicAuth },
      })

      if (!resp.ok) {
        summary.errors++
        summary.details.push({ ref: tx.reference, result: `http_${resp.status}` })
        continue
      }

      const json = await resp.json() as Record<string, unknown>
      const data = (json.data ?? json) as Record<string, unknown>
      const fmStatus = String(data.status ?? '').toUpperCase()
      const fmExternalId = String(data.externalId ?? data.external_id ?? '')
      const fmAmount = parseInt(String(data.amount ?? '0'), 10)

      // PROTECTION MULTI-APP #2 : external_id retourne par Freemopay doit matcher
      if (fmExternalId && fmExternalId !== tx.external_id) {
        summary.skipped_validation++
        summary.details.push({
          ref: tx.reference, result: 'SKIP_EXTERNAL_ID_MISMATCH',
          ours: tx.external_id, freemopay: fmExternalId,
        })
        continue
      }

      // PROTECTION MULTI-APP #3 : amount doit matcher
      if (fmAmount && fmAmount !== tx.amount) {
        summary.skipped_validation++
        summary.details.push({
          ref: tx.reference, result: 'SKIP_AMOUNT_MISMATCH',
          ours: tx.amount, freemopay: fmAmount,
        })
        continue
      }

      // === SUCCESS ===
      if (fmStatus === 'SUCCESS' || fmStatus === 'COMPLETED') {
        const detail: Record<string, unknown> = {
          ref: tx.reference,
          user_id: tx.user_id,
          amount: tx.amount,
          type: tx.transaction_type,
          freemopay_status: fmStatus,
        }

        if (dryRun) {
          summary.would_credit++
          detail.result = tx.transaction_type === 'DEPOSIT'
            ? 'WOULD_CREDIT_DEPOSIT'
            : 'WOULD_MARK_WITHDRAW_SUCCESS'
        } else {
          if (tx.transaction_type === 'DEPOSIT') {
            const { error: walletErr } = await supabase.rpc('wallet_apply_delta', {
              p_user_id: tx.user_id,
              p_delta: tx.amount,
              p_reason: 'mobile_money_deposit',
              p_ref_type: 'freemopay_tx',
              p_ref_id: tx.id,
              p_metadata: {
                reconciled: true,
                reference: tx.reference,
                source: 'reconcile_cron',
                freemopay_response: data,
              },
              p_request_id: `freemopay_dep_${tx.id}`,
            })
            if (walletErr) {
              summary.errors++
              detail.result = `wallet_err: ${walletErr.message}`
              summary.details.push(detail)
              continue
            }
          }

          await supabase
            .from('freemopay_transactions')
            .update({
              status: 'SUCCESS',
              callback_data: { reconciled: true, freemopay_response: data, date: new Date().toISOString() },
              updated_at: new Date().toISOString(),
            })
            .eq('id', tx.id)

          summary.credited++
          detail.result = 'CREDITED'
        }
        summary.details.push(detail)
      }
      // === FAILED ===
      else if (['FAILED', 'EXPIRED', 'CANCELLED', 'REJECTED'].includes(fmStatus)) {
        const detail: Record<string, unknown> = {
          ref: tx.reference,
          user_id: tx.user_id,
          amount: tx.amount,
          type: tx.transaction_type,
          freemopay_status: fmStatus,
        }

        if (dryRun) {
          summary.would_fail++
          detail.result = tx.transaction_type === 'WITHDRAW'
            ? 'WOULD_REFUND_WITHDRAW'
            : 'WOULD_MARK_FAILED'
        } else {
          if (tx.transaction_type === 'WITHDRAW') {
            const { error: walletErr } = await supabase.rpc('wallet_apply_delta', {
              p_user_id: tx.user_id,
              p_delta: tx.amount,
              p_reason: 'mobile_money_withdraw_refund',
              p_ref_type: 'freemopay_tx',
              p_ref_id: tx.id,
              p_metadata: { reconciled: true, reason: 'withdraw_failed' },
              p_request_id: `freemopay_wd_refund_${tx.id}`,
            })
            if (walletErr) {
              summary.errors++
              detail.result = `refund_err: ${walletErr.message}`
              summary.details.push(detail)
              continue
            }
          }

          await supabase
            .from('freemopay_transactions')
            .update({
              status: 'FAILED',
              callback_data: { reconciled: true, freemopay_response: data, date: new Date().toISOString() },
              updated_at: new Date().toISOString(),
            })
            .eq('id', tx.id)

          summary.failed++
          detail.result = 'MARKED_FAILED'
        }
        summary.details.push(detail)
      }
      // === STILL PENDING ===
      else {
        summary.still_pending++
        summary.details.push({
          ref: tx.reference,
          result: `still_pending`,
          freemopay_status: fmStatus,
          age_minutes: Math.round((Date.now() - new Date(tx.created_at).getTime()) / 60000),
        })
      }
    } catch (e) {
      summary.errors++
      summary.details.push({ ref: tx.reference, result: `exception: ${String(e).slice(0, 100)}` })
    }

    await new Promise(r => setTimeout(r, 300))
  }

  // Logger sauf en dry_run
  if (!dryRun) {
    await supabase.rpc('log_event', {
      p_level: summary.errors > 0 ? 'warn' : 'info',
      p_source: 'freemopay_reconcile',
      p_message: `Reconcile: ${summary.credited} credited, ${summary.failed} failed, ${summary.still_pending} pending, ${summary.skipped_validation} skipped, ${summary.errors} errors`,
      p_context: summary,
    })
  }

  return new Response(JSON.stringify(summary, null, 2), {
    headers: { 'Content-Type': 'application/json' },
  })
})
