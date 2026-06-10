// ============================================================
// Edge Function — settle_real_bets
// ============================================================
// Cron-triggered. Toutes les 10 minutes :
//
//   1. Liste les match_ids des bet_selections pending non-virtual
//      (RPC list_pending_real_match_ids)
//   2. Pour chaque match :
//      - Fetch StatPal /soccer/matches/daily?offset={d} ou /nba/livescores
//        pour recuperer le statut + scores
//      - Si match termine (FT, ended, final), extrait home/away + ht_home/ht_away
//   3. Construit un payload jsonb[] avec les resultats
//   4. Appelle RPC settle_real_bets_with_results(payload)
//
// Le RPC applique le settlement atomique :
//   - Selections won/lost/void via _settle_virtual_selection (helper universel)
//   - Bets won -> payout via wallet_apply_delta
//   - Bets void -> refund
//   - Bets lost -> status updated, stake reste avec la maison
//
// Limitations :
//   - On fetch /matches/daily?offset=0..7 (matchs des 7 derniers jours)
//     pour avoir un large net. Couts API : ~16 calls / run = 96 / heure.
//   - Live matches (1xN paris en cours) : settlement quand le match
//     passe FT, pas pendant le live.
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STATPAL_API_KEY = Deno.env.get("STATPAL_API_KEY") ?? "";

const BASE_V1 = "https://statpal.io/api/v1";
const BASE_V2 = "https://statpal.io/api/v2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Cache court pour ne pas re-fetcher 1 ligue plusieurs fois dans le meme run
const fetchCache = new Map<string, unknown>();

async function statpalGet(
  path: string,
  query?: Record<string, string>,
): Promise<unknown | null> {
  const cacheKey = path + ":" + JSON.stringify(query ?? {});
  if (fetchCache.has(cacheKey)) return fetchCache.get(cacheKey);
  const isV1 = ["/nba/","/nfl/","/mlb/","/nhl/","/cricket/","/tennis/","/esports/","/f1/","/handball/","/volleyball/","/golf/"].some(p => path.startsWith(p));
  const base = isV1 ? BASE_V1 : BASE_V2;
  const params = new URLSearchParams({ access_key: STATPAL_API_KEY, ...(query ?? {}) });
  // path ne doit JAMAIS contenir de `?` (sinon double query string casse l'URL)
  const cleanPath = path.split("?")[0];
  const url = `${base}${cleanPath}?${params.toString()}`;
  try {
    const r = await fetch(url, { headers: { Accept: "application/json" } });
    if (r.status !== 200) return null;
    const json = await r.json();
    fetchCache.set(cacheKey, json);
    return json;
  } catch (_) {
    return null;
  }
}

// ── Soccer match parser ──
// Structure /soccer/matches/daily : matches.tournament[].match[]
// Status :  "FT" (full time) | "Live" | "Not started" | etc.
// Score   : match.home.score / match.away.score
// HT      : match.ht_score (ex: "1-0") ou match.scores.ht
function extractSoccerResult(matchObj: any): {
  is_finished: boolean;
  home_score: number | null;
  away_score: number | null;
  ht_home: number | null;
  ht_away: number | null;
} {
  const status = String(matchObj?.status ?? "").toLowerCase();
  const isFin = status === "ft" || status === "finished" || status === "ended" ||
    status === "after extra time" || status === "after penalties";
  // Try multiple shapes
  const homeScore = matchObj?.home?.score ?? matchObj?.home?.goals ?? null;
  const awayScore = matchObj?.away?.score ?? matchObj?.away?.goals ?? null;
  const ht = matchObj?.ht_score ?? matchObj?.scores?.ht ?? matchObj?.scores?.["1st-half"];
  let htHome: number | null = null, htAway: number | null = null;
  if (typeof ht === "string" && /^\d+\s*[-:]\s*\d+$/.test(ht)) {
    const parts = ht.replace(/\s+/g, "").split(/[-:]/);
    htHome = Number(parts[0]); htAway = Number(parts[1]);
  } else if (typeof matchObj?.home?.ht_score === "string") {
    htHome = Number(matchObj.home.ht_score);
    htAway = Number(matchObj?.away?.ht_score ?? "0");
  }
  return {
    is_finished: isFin,
    home_score: homeScore != null && homeScore !== "" ? Number(homeScore) : null,
    away_score: awayScore != null && awayScore !== "" ? Number(awayScore) : null,
    ht_home: htHome,
    ht_away: htAway,
  };
}

// ── NBA match parser ──
function extractNbaResult(matchObj: any): ReturnType<typeof extractSoccerResult> {
  const status = String(matchObj?.status ?? "").toLowerCase();
  const isFin = status === "finished" || status === "ended" || status === "ft" ||
    status === "final";
  const homeScore = matchObj?.home?.totalscore ?? null;
  const awayScore = matchObj?.away?.totalscore ?? null;
  // ht = q1 + q2
  const q1h = Number(matchObj?.home?.q1 ?? "0") || 0;
  const q2h = Number(matchObj?.home?.q2 ?? "0") || 0;
  const q1a = Number(matchObj?.away?.q1 ?? "0") || 0;
  const q2a = Number(matchObj?.away?.q2 ?? "0") || 0;
  return {
    is_finished: isFin,
    home_score: homeScore != null && homeScore !== "" ? Number(homeScore) : null,
    away_score: awayScore != null && awayScore !== "" ? Number(awayScore) : null,
    ht_home: (q1h + q2h) || null,
    ht_away: (q1a + q2a) || null,
  };
}

// ── Walk JSON to find match by main_id / id ──
function findMatchInPayload(payload: any, targetId: string, sport: string): any | null {
  // Soccer V2 daily shape : { matches.tournament[].match[] } or live
  // NBA V1 odds shape : { odds.category.matches.match[] }
  function walk(o: any): any | null {
    if (o == null) return null;
    if (Array.isArray(o)) {
      for (const e of o) {
        const r = walk(e);
        if (r) return r;
      }
      return null;
    }
    if (typeof o === "object") {
      // Match candidate?
      const id = String(o?.main_id ?? o?.id ?? "");
      if (id === targetId && (o?.home || o?.away)) {
        return o;
      }
      for (const k of Object.keys(o)) {
        const r = walk(o[k]);
        if (r) return r;
      }
    }
    return null;
  }
  return walk(payload);
}

async function findMatchResult(matchId: string): Promise<any | null> {
  // Try soccer first (most cases)
  // Strategy: /soccer/matches/daily?offset=-7..+7 (15 jours fenetre StatPal)
  // On commence par les jours PASSES proches (matchs deja joues) puis futurs.
  const offsets = [0, -1, -2, -3, -4, -5, -6, -7, 1, 2, 3, 4, 5, 6, 7];
  for (const off of offsets) {
    const p = await statpalGet(`/soccer/matches/daily`, { offset: String(off) });
    if (p) {
      const found = findMatchInPayload(p, matchId, "soccer");
      if (found) {
        const r = extractSoccerResult(found);
        return { ...r, sport: "soccer" };
      }
    }
  }
  // Try soccer live (in case status pas encore FT mais en cours)
  const live = await statpalGet(`/soccer/odds/live`);
  if (live) {
    const found = findMatchInPayload(live, matchId, "soccer");
    if (found) {
      const r = extractSoccerResult(found);
      return { ...r, sport: "soccer" };
    }
  }
  // Try NBA
  const nbaLive = await statpalGet(`/nba/livescores`);
  if (nbaLive) {
    const found = findMatchInPayload(nbaLive, matchId, "nba");
    if (found) {
      const r = extractNbaResult(found);
      return { ...r, sport: "basketball" };
    }
  }
  const nbaOdds = await statpalGet(`/nba/odds`);
  if (nbaOdds) {
    const found = findMatchInPayload(nbaOdds, matchId, "nba");
    if (found) {
      const r = extractNbaResult(found);
      return { ...r, sport: "basketball" };
    }
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  if (!STATPAL_API_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(
      JSON.stringify({ error: "missing env STATPAL_API_KEY or SUPABASE_SERVICE_ROLE_KEY" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  fetchCache.clear();

  try {
    // 1. Liste matchs pending
    const { data: matchInfos, error: listErr } = await sb.rpc("list_pending_real_match_ids");
    if (listErr) throw listErr;
    const ids: { match_id: string; is_live: boolean }[] = Array.isArray(matchInfos) ? matchInfos : [];

    if (ids.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, pending_matches: 0, settled: 0 }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 2. Fetch StatPal pour chaque match (de-dup)
    const results: Array<{
      match_id: string;
      sport: string;
      home_score: number | null;
      away_score: number | null;
      ht_home: number | null;
      ht_away: number | null;
      is_finished: boolean;
    }> = [];
    const seen = new Set<string>();
    for (const info of ids) {
      if (seen.has(info.match_id)) continue;
      seen.add(info.match_id);
      const r = await findMatchResult(info.match_id);
      if (r) {
        results.push({
          match_id: info.match_id,
          sport: r.sport,
          home_score: r.home_score,
          away_score: r.away_score,
          ht_home: r.ht_home,
          ht_away: r.ht_away,
          is_finished: r.is_finished,
        });
      }
    }

    // 3. Applique le settlement
    const { data: settled, error: setErr } = await sb.rpc(
      "settle_real_bets_with_results",
      { p_results: results },
    );
    if (setErr) throw setErr;

    return new Response(
      JSON.stringify({
        ok: true,
        pending_matches: ids.length,
        fetched: results.length,
        finished: results.filter(r => r.is_finished).length,
        settled,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "settle_error", detail: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
