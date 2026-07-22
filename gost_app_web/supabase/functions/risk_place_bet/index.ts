// ============================================================
// Edge Function : risk_place_bet
// ============================================================
// Place le Risk Engine DEVANT la RPC place_bet existante.
// Elle ne remplace PAS place_bet : elle l'encadre.
//
// FLUX :
//   1. Auth user (JWT Supabase)
//   2. POST {RISK_ENGINE_URL}/risk/validate-bet   (header X-Internal-Secret)
//        ACCEPT -> on continue
//        REDUCE -> renvoie max_stake au client (aucun debit)
//        REJECT -> renvoie la raison    (aucun debit)
//   3. RPC place_bet / place_bet_with_bonus  (debit wallet + insert, atomique)
//   4. Succes -> /risk/confirm-bet   |   Echec -> /risk/release (compensation)
//
// FAIL-CLOSED : si le Risk Engine ne repond pas, on REFUSE le pari.
//
// INPUT  : { p_bet_type, p_stake, p_selections[], p_request_id, p_bonus_code? }
//          (exactement les params de la RPC place_bet)
// OUTPUT : succes -> { bet_id, new_balance, potential_payout, total_odds, ... }
//          refus  -> { accepted:false, reason, reduce?, max_stake? }
//
// SECRETS (Supabase -> Edge Functions -> Secrets) :
//   RISK_ENGINE_URL   ex: https://risk.mondomaine.com
//   RISK_INTERNAL_SECRET
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const j = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

const RISK_URL = (Deno.env.get('RISK_ENGINE_URL') ?? '').replace(/\/+$/, '')
const RISK_SECRET = Deno.env.get('RISK_INTERNAL_SECRET') ?? ''

async function risk(path: string, body: unknown): Promise<Record<string, unknown>> {
  const r = await fetch(`${RISK_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Internal-Secret': RISK_SECRET },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(6000),
  })
  return await r.json() as Record<string, unknown>
}

// marketCode cote app = l'ISSUE ('home' | 'draw' | 'away' | 'over_2_5' ...).
// Le Risk Engine raisonne par (match, market_type, outcome) : il calcule la
// pire perte en comparant les issues d'un MEME marche. On regroupe donc
// home/draw/away sous '1X2' ; sinon on isole le code (prudent).
function marketTypeOf(code: string): string {
  const c = code.toLowerCase()
  if (c === 'home' || c === 'draw' || c === 'away') return '1X2'
  if (c.startsWith('over_') || c.startsWith('under_')) return 'OU_' + c.replace(/^(over|under)_/, '')
  if (c === 'btts_yes' || c === 'btts_no') return 'BTTS'
  return code.slice(0, 32)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return j({ accepted: false, reason: 'METHOD_NOT_ALLOWED' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const authHeader = req.headers.get('Authorization') ?? ''

  // Client "as user" : la RPC place_bet s'appuie sur auth.uid()
  const asUser = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  })

  const { data: u } = await asUser.auth.getUser()
  if (!u?.user) return j({ accepted: false, reason: 'NOT_AUTHENTICATED' }, 401)
  const uid = u.user.id

  let b: Record<string, unknown>
  try { b = await req.json() } catch { return j({ accepted: false, reason: 'INVALID_JSON' }, 400) }

  const betType = String(b.p_bet_type ?? '')
  const stake = Number(b.p_stake)
  const selections = Array.isArray(b.p_selections) ? b.p_selections as Record<string, unknown>[] : []
  const requestId = String(b.p_request_id ?? '')
  const bonusCode = b.p_bonus_code ? String(b.p_bonus_code) : null

  if (!betType || !Number.isInteger(stake) || stake <= 0 || selections.length === 0 || requestId.length < 8) {
    return j({ accepted: false, reason: 'INVALID_BET' }, 400)
  }

  // ── Derivation de l'exposition a valider ──
  // simple  : la selection elle-meme
  // combine : un "marche" COMBO dedie, cote = produit des cotes (le book ne
  //           paie que si TOUTES les jambes passent)
  const first = selections[0]
  const matchId = String(first.match_id ?? '')
  let marketType: string
  let outcome: string
  let odds: number

  if (betType === 'combine' && selections.length > 1) {
    marketType = 'COMBO'
    outcome = selections.map((s) => `${s.match_id}:${s.market_code}`).join('|').slice(0, 32)
    odds = selections.reduce((acc, s) => acc * (Number(s.odds) || 1), 1)
  } else {
    const code = String(first.market_code ?? '')
    marketType = marketTypeOf(code)
    outcome = code.slice(0, 32)
    odds = Number(first.odds) || 0
  }
  odds = Math.round(odds * 1000) / 1000   // le Risk Engine accepte 3 decimales
  if (!matchId || !outcome || !(odds > 1)) {
    return j({ accepted: false, reason: 'INVALID_SELECTION' }, 400)
  }

  // ── 1) Decision de risque (FAIL-CLOSED) ──
  let decision: Record<string, unknown>
  try {
    decision = await risk('/risk/validate-bet', {
      request_id: requestId, user_id: uid, match_id: matchId,
      market_type: marketType, outcome, stake, odds,
    })
  } catch (e) {
    console.error('[risk_place_bet] risk engine unreachable', e)
    return j({ accepted: false, reason: 'RISK_UNAVAILABLE' }, 503)
  }

  const d = String(decision.decision ?? 'REJECT')
  if (d === 'REDUCE') {
    return j({ accepted: false, reduce: true, max_stake: decision.max_stake, reason: 'RISK_LIMIT' })
  }
  if (d !== 'ACCEPT') {
    return j({ accepted: false, reason: String(decision.reason ?? 'RISK_REJECTED') })
  }

  // ── 2) Placement reel : la RPC existante (atomique : debit + insert) ──
  const params: Record<string, unknown> = {
    p_bet_type: betType,
    p_stake: stake,
    p_selections: selections,
    p_request_id: requestId,
  }
  if (bonusCode) params.p_bonus_code = bonusCode

  const { data: bet, error: betErr } = await asUser.rpc(
    bonusCode ? 'place_bet_with_bonus' : 'place_bet', params,
  )

  if (betErr || !bet) {
    // Compensation : on libere l'exposition reservee (idempotent)
    await risk('/risk/release', { request_id: requestId }).catch(() => {})
    console.warn('[risk_place_bet] place_bet failed', betErr?.message)
    return j({
      accepted: false,
      reason: 'PLACE_BET_FAILED',
      db_error: betErr?.message ?? 'unknown',
    }, 200)
  }

  const row = bet as Record<string, unknown>

  // ── 3) Confirmation cote risk (lie bet_id a la reservation) ──
  await risk('/risk/confirm-bet', {
    request_id: requestId, bet_id: String(row.bet_id ?? ''),
  }).catch(() => {})

  // Meme forme de reponse que la RPC -> le client ne change quasiment pas
  return j({
    accepted: true,
    bet_id: row.bet_id,
    new_balance: row.new_balance,
    potential_payout: row.potential_payout,
    total_odds: row.total_odds,
    liability_after: decision.liability_after,
  })
})
