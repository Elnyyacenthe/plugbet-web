// ============================================================
// Edge Function : kpay_initiate_deposit
// ============================================================
// Proxy server-side pour initier un depot K-Pay.
//
// MOTIVATION : l'app web (navigateur) est bloquee par CORS sur
// admin.kpay.site. Cette function fait le POST server-side et
// INSERT la tx PENDING. Le client (web ou mobile) recoit la
// reference (id K-Pay) et peut poller.
//
// API K-Pay :
//   POST https://admin.kpay.site/api/v1/payments/init
//   Headers: X-API-Key, X-Secret-Key
//   Body: { amount, phoneNumber, externalId, description }
//   -> 201 { id: "pay_xxx", status: "PENDING", amount, phoneNumber, ... }
//
// INPUT (JSON) : { amount: number, payer: "237xxxxxxxxx" }
// OUTPUT       : 200 { success, reference, externalId, message }
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const KPAY_DEFAULT_BASE = 'https://admin.kpay.site'

function uuidShort(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 8)
}

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
    const payer = String(body.payer ?? '').trim()
    const paymentMethod = String(body.paymentMethod ?? '').trim().toUpperCase()

    if (!Number.isFinite(amount) || amount <= 0 || !Number.isInteger(amount)) {
      return j({ success: false, message: 'INVALID_AMOUNT' }, 400)
    }
    if (!payer || payer.length < 8 || payer.length > 20) {
      return j({ success: false, message: 'INVALID_PAYER' }, 400)
    }
    if (paymentMethod !== 'MTN_MONEY' && paymentMethod !== 'ORANGE_MONEY') {
      return j({ success: false, message: 'INVALID_PAYMENT_METHOD' }, 400)
    }

    // DEDUP : tx PENDING identique dans les 60s -> on la retourne
    const dedupWindowSeconds = 60
    const { data: existing } = await supabase
      .from('kpay_transactions')
      .select('reference, external_id, message, created_at')
      .eq('user_id', uid)
      .eq('transaction_type', 'DEPOSIT')
      .eq('status', 'PENDING')
      .eq('amount', amount)
      .eq('phone', payer)
      .gte('created_at', new Date(Date.now() - dedupWindowSeconds * 1000).toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (existing) {
      return j({
        success: true,
        reference: existing.reference,
        externalId: existing.external_id,
        message: existing.message ?? 'Transaction deja en cours. Validez sur votre telephone.',
        deduplicated: true,
      })
    }

    // Config K-Pay
    const { data: settings, error: cfgErr } = await supabase
      .from('app_settings').select('value').eq('key', 'kpay_config').maybeSingle()
    if (cfgErr || !settings?.value) {
      return j({ success: false, message: 'Configuration paiement manquante. Contactez le support.' }, 500)
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

    const externalId = `DEPOSIT_${uuidShort()}_${uid}`

    // Code operateur K-Pay exact (predict-provider, repli mapping local)
    const provider = await resolveProvider(baseUrl, apiKey, secretKey, payer, paymentMethod)
    if (!provider) {
      return j({ success: false, message: 'Operateur Mobile Money indetermine pour ce numero.' }, 400)
    }

    // Placeholder PENDING avant POST (anti-race retry)
    const { error: phErr } = await supabase.from('kpay_transactions').insert({
      user_id: uid,
      reference: externalId,           // temp = unique
      external_id: externalId,
      transaction_type: 'DEPOSIT',
      amount,
      status: 'PENDING',
      phone: payer,
      message: 'Initiation en cours...',
    })
    if (phErr) {
      console.error('[kpay_deposit] placeholder insert failed', phErr)
      return j({ success: false, message: 'Erreur interne (init placeholder).' }, 500)
    }

    // POST K-Pay
    let resp: Response
    try {
      resp = await fetch(`${baseUrl}/api/v1/payments/init`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
          'X-Secret-Key': secretKey,
        },
        body: JSON.stringify({
          amount,
          phoneNumber: payer,
          provider,
          externalId,
          description: `Depot de ${amount} FCFA`,
        }),
        signal: AbortSignal.timeout(20000),
      })
    } catch (e) {
      console.error('[kpay_deposit] fetch error', e)
      await supabase.from('kpay_transactions')
        .update({ status: 'FAILED', message: 'Network error toward K-Pay' })
        .eq('external_id', externalId)
      return j({ success: false, message: 'Erreur reseau cote K-Pay. Reessayez plus tard.' }, 502)
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
        : (typeof data.error === 'string' ? data.error : 'Erreur lors de l\'initialisation du paiement.')
      await supabase.from('kpay_transactions')
        .update({ status: 'FAILED', message: msg })
        .eq('external_id', externalId)
      console.warn('[kpay_deposit] refused', data)
      return j({ success: false, message: msg }, 400)
    }

    // UPDATE placeholder avec le vrai id K-Pay
    const { error: updErr } = await supabase.from('kpay_transactions')
      .update({ reference: kId, message: 'Paiement initie' })
      .eq('external_id', externalId)
    if (updErr) {
      console.error('[kpay_deposit] update placeholder failed', updErr, { kId, externalId })
    }

    return j({
      success: true,
      reference: kId,
      externalId,
      message: 'Transaction initiee. Validez le paiement sur votre telephone.',
    })
  } catch (e) {
    console.error('[kpay_deposit] uncaught', e)
    return j({ success: false, message: 'Erreur interne. Reessayez plus tard.' }, 500)
  }
})
