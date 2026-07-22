// ============================================================
// Edge Function : kpay_initiate_withdrawal
// ============================================================
// Pendant de kpay_initiate_deposit pour les retraits.
//
// FLOW :
//   1. Client appelle d'abord la RPC kpay_debit_for_withdrawal
//      (debit ledger atomique + idempotence par external_id)
//   2. Client appelle cette function avec { amount, receiver, externalId }
//   3. Function POST K-Pay /api/v1/payments/withdraw
//   4. Si OK  : tx PENDING avec reference = id K-Pay (wdr_xxx)
//   5. Si KO  : tx FAILED, client appelle kpay_refund_withdrawal
//
// API K-Pay :
//   POST https://admin.kpay.site/api/v1/payments/withdraw
//   Headers: X-API-Key, X-Secret-Key
//   Body: { amount, phoneNumber, description }
//   -> { id: "wdr_xxx", status: "PENDING", ... }
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const KPAY_DEFAULT_BASE = 'https://admin.kpay.site'

function j(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// Resout le code `provider` K-Pay exact (ex: MTN_MOMO_CMR) pour un numero.
// Source d'autorite : POST /api/v1/payments/predict-provider. Repli sur un
// mapping operateur -> code si l'API utilitaire est indisponible.
async function resolveProvider(
  baseUrl: string, apiKey: string, secretKey: string, phone: string, hint: string,
): Promise<string> {
  try {
    const r = await fetch(`${baseUrl}/api/v1/payments/predict-provider`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-API-Key': apiKey, 'X-Secret-Key': secretKey },
      body: JSON.stringify({ phoneNumber: phone }),
      signal: AbortSignal.timeout(10000),
    })
    if (r.ok) {
      const d = await r.json() as Record<string, unknown>
      const p = String(d.provider ?? '').trim()
      if (p) return p
    }
  } catch (_) { /* repli ci-dessous */ }
  const map: Record<string, string> = { MTN_MONEY: 'MTN_MOMO_CMR', ORANGE_MONEY: 'ORANGE_CMR' }
  return map[hint] ?? (hint || '')
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return j({ success: false, message: 'METHOD_NOT_ALLOWED' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!

  const authHeader = req.headers.get('Authorization') ?? ''
  const supabaseUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  try {
    const { data: userData, error: userErr } = await supabaseUser.auth.getUser()
    if (userErr || !userData?.user) return j({ success: false, message: 'NOT_AUTHENTICATED' }, 401)
    const uid = userData.user.id

    let body: Record<string, unknown>
    try { body = await req.json() } catch { return j({ success: false, message: 'INVALID_JSON' }, 400) }

    const amount = Number(body.amount)
    const receiver = String(body.receiver ?? '').trim()
    const externalId = String(body.externalId ?? '').trim()
    const paymentMethod = String(body.paymentMethod ?? '').trim().toUpperCase()

    if (!Number.isFinite(amount) || amount <= 0 || !Number.isInteger(amount)) {
      return j({ success: false, message: 'INVALID_AMOUNT' }, 400)
    }
    if (!receiver || receiver.length < 8 || receiver.length > 20) {
      return j({ success: false, message: 'INVALID_RECEIVER' }, 400)
    }
    if (!externalId || !externalId.startsWith('WITHDRAW_')) {
      return j({ success: false, message: 'INVALID_EXTERNAL_ID' }, 400)
    }
    if (!externalId.endsWith(`_${uid}`)) {
      return j({ success: false, message: 'EXTERNAL_ID_MISMATCH' }, 400)
    }
    if (paymentMethod !== 'MTN_MONEY' && paymentMethod !== 'ORANGE_MONEY') {
      return j({ success: false, message: 'INVALID_PAYMENT_METHOD' }, 400)
    }

    // DEDUP : tx avec ce externalId existe deja -> on la retourne
    const { data: existingTx } = await supabase
      .from('kpay_transactions')
      .select('reference, external_id, message, status')
      .eq('user_id', uid)
      .eq('external_id', externalId)
      .eq('transaction_type', 'WITHDRAW')
      .maybeSingle()

    if (existingTx) {
      return j({
        success: true,
        reference: existingTx.reference,
        externalId,
        message: existingTx.message ?? 'Retrait deja en cours.',
        deduplicated: true,
      })
    }

    // Config K-Pay
    const { data: settings, error: cfgErr } = await supabase
      .from('app_settings').select('value').eq('key', 'kpay_config').maybeSingle()
    if (cfgErr || !settings?.value) {
      return j({ success: false, message: 'Configuration paiement manquante.' }, 500)
    }
    const cfg = settings.value as Record<string, unknown>
    if (cfg.active !== true) {
      return j({ success: false, message: 'Service paiement temporairement indisponible.' }, 503)
    }
    const apiKey = cfg.apiKey as string | undefined
    const secretKey = cfg.secretKey as string | undefined
    const baseUrl = (cfg.baseUrl as string | undefined) || KPAY_DEFAULT_BASE
    if (!apiKey || !secretKey) {
      return j({ success: false, message: 'Configuration paiement incomplete.' }, 500)
    }

    // Code operateur K-Pay exact (predict-provider, repli mapping local)
    const provider = await resolveProvider(baseUrl, apiKey, secretKey, receiver, paymentMethod)
    if (!provider) {
      return j({ success: false, message: 'Operateur Mobile Money indetermine pour ce numero.' }, 400)
    }

    // Placeholder PENDING avant POST (anti-race retry)
    const { error: phErr } = await supabase.from('kpay_transactions').insert({
      user_id: uid,
      reference: externalId,           // temp = unique externalId
      external_id: externalId,
      transaction_type: 'WITHDRAW',
      amount,
      status: 'PENDING',
      phone: receiver,
      message: 'Initiation retrait en cours...',
    })
    if (phErr) {
      console.error('[kpay_withdraw] placeholder insert failed', phErr)
      return j({ success: false, message: 'Erreur interne (init placeholder).' }, 500)
    }

    // POST K-Pay
    let resp: Response
    try {
      resp = await fetch(`${baseUrl}/api/v1/payments/withdraw`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
          'X-Secret-Key': secretKey,
        },
        body: JSON.stringify({
          amount,
          phoneNumber: receiver,
          provider,
          externalId,
          description: `Retrait de ${amount} FCFA`,
        }),
        signal: AbortSignal.timeout(20000),
      })
    } catch (e) {
      console.error('[kpay_withdraw] fetch error', e)
      await supabase.from('kpay_transactions')
        .update({ status: 'FAILED', message: 'Network error toward K-Pay' })
        .eq('external_id', externalId)
      return j({ success: false, message: 'Erreur reseau cote K-Pay.' }, 502)
    }

    let data: Record<string, unknown> = {}
    try { data = await resp.json() } catch { /* ignore */ }

    const kStatus = String(data.status ?? '').toUpperCase()
    const kId = String(data.id ?? '')
    const accepted = resp.ok && kId.length > 0 &&
      !['FAILED', 'CANCELLED', 'REJECTED'].includes(kStatus)

    if (!accepted) {
      const msg = typeof data.message === 'string'
        ? data.message
        : (typeof data.error === 'string' ? data.error : 'Erreur lors de l\'initialisation du retrait.')
      await supabase.from('kpay_transactions')
        .update({ status: 'FAILED', message: msg })
        .eq('external_id', externalId)
      console.warn('[kpay_withdraw] refused', data)
      return j({ success: false, message: msg }, 400)
    }

    const { error: updErr } = await supabase.from('kpay_transactions')
      .update({ reference: kId, message: 'Retrait initie' })
      .eq('external_id', externalId)
    if (updErr) {
      console.error('[kpay_withdraw] update placeholder failed', updErr, { kId, externalId })
    }

    return j({
      success: true,
      reference: kId,
      externalId,
      message: 'Retrait en cours. Vous recevrez l\'argent sous peu.',
    })
  } catch (e) {
    console.error('[kpay_withdraw] uncaught', e)
    return j({ success: false, message: 'Erreur interne.' }, 500)
  }
})
