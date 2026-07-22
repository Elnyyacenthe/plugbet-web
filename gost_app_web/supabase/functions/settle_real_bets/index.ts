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

// Source PRINCIPALE des scores : The Odds API. Les paris reels sont poses sur
// ses matchs (match_id = "oa_" + id d'evenement) ; StatPal utilise des
// identifiants incompatibles et ne pouvait donc JAMAIS les retrouver.
const THE_ODDS_API_KEY = Deno.env.get("THE_ODDS_API_KEY") ?? "";
const ODDS_BASE = "https://api.the-odds-api.com";

interface OddsScoreEvent {
  id: string;
  completed: boolean;
  home_team: string;
  away_team: string;
  scores: Array<{ name: string; score: string }> | null;
}

function readOddsScore(
  scores: Array<{ name: string; score: string }>,
  team: string,
): number | null {
  for (const s of scores) {
    if (s.name === team) {
      const n = parseInt(s.score, 10);
      return Number.isNaN(n) ? null : n;
    }
  }
  return null;
}

// Risk Engine : a la cloture d'un pari il faut LIBERER l'exposition reservee
// a son acceptation, sinon elle s'accumule indefiniment et le book finit par
// refuser des paris sains. Alimente aussi le P&L joueur (detection sharp).
const RISK_URL = (Deno.env.get("RISK_ENGINE_URL") ?? "").replace(/\/+$/, "");
const RISK_SECRET = Deno.env.get("RISK_INTERNAL_SECRET") ?? "";

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

  if (!SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(
      JSON.stringify({ error: "missing env SUPABASE_SERVICE_ROLE_KEY" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  if (!THE_ODDS_API_KEY && !STATPAL_API_KEY) {
    return new Response(
      JSON.stringify({ error: "missing env THE_ODDS_API_KEY (et pas de STATPAL_API_KEY de repli)" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  fetchCache.clear();

  try {
    // ── 1. Selections reelles encore pending ────────────────────────
    // On lit bet_selections directement (et non list_pending_real_match_ids)
    // car il nous faut league_key : c'est la cle de l'endpoint scores de
    // The Odds API. sport sert au RPC de settlement.
    const { data: pendingSel, error: listErr } = await sb
      .from("bet_selections")
      .select("match_id, league_key, sport")
      .eq("selection_status", "pending")
      .eq("is_virtual", false)
      .limit(2000);
    if (listErr) throw listErr;

    const pending = new Map<string, { league_key: string | null; sport: string | null }>();
    for (const s of pendingSel ?? []) {
      if (!pending.has(s.match_id)) {
        pending.set(s.match_id, { league_key: s.league_key, sport: s.sport });
      }
    }

    if (pending.size === 0) {
      return new Response(
        JSON.stringify({ ok: true, pending_matches: 0, settled: 0 }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 2. Recuperation des scores ──────────────────────────────────
    // Les paris sont poses sur des matchs The Odds API : match_id =
    // "oa_" + <id d'evenement>. On interroge donc /v4/sports/{league}/scores
    // et on matche par IDENTIFIANT (fiable), pas par nom d'equipe.
    // StatPal reste en repli pour d'eventuels matchs d'une autre source.
    const results: Array<{
      match_id: string;
      sport: string;
      home_score: number | null;
      away_score: number | null;
      ht_home: number | null;
      ht_away: number | null;
      is_finished: boolean;
    }> = [];

    // Regroupement par ligue (1 appel API par ligue, pas par match)
    const byLeague = new Map<string, string[]>();
    const legacy: string[] = [];
    for (const [matchId, info] of pending) {
      if (matchId.startsWith("oa_") && info.league_key) {
        const arr = byLeague.get(info.league_key) ?? [];
        arr.push(matchId);
        byLeague.set(info.league_key, arr);
      } else {
        legacy.push(matchId);
      }
    }

    let api_calls = 0;
    for (const [leagueKey, matchIds] of byLeague) {
      if (!THE_ODDS_API_KEY) break;
      const url =
        `${ODDS_BASE}/v4/sports/${leagueKey}/scores/?apiKey=${THE_ODDS_API_KEY}&daysFrom=3`;
      let resp: Response;
      try {
        resp = await fetch(url, { headers: { Accept: "application/json" } });
        api_calls++;
      } catch (_) {
        continue; // reseau : on retentera au prochain tick (cron 10 min)
      }
      if (!resp.ok) continue; // 429 / 5xx -> retry au prochain tick

      const events = (await resp.json().catch(() => [])) as OddsScoreEvent[];
      const byId = new Map<string, OddsScoreEvent>();
      for (const ev of events) byId.set(ev.id, ev);

      for (const matchId of matchIds) {
        const ev = byId.get(matchId.slice(3)); // retire le prefixe "oa_"
        if (!ev || !ev.completed || !ev.scores) continue; // pas encore fini
        const home = readOddsScore(ev.scores, ev.home_team);
        const away = readOddsScore(ev.scores, ev.away_team);
        if (home === null || away === null) continue;
        results.push({
          match_id: matchId,
          sport: pending.get(matchId)?.sport ?? "football",
          home_score: home,
          away_score: away,
          // The Odds API ne fournit PAS les scores de mi-temps : les marches
          // mi-temps ne peuvent pas etre regles par cette voie (restent pending).
          ht_home: null,
          ht_away: null,
          is_finished: true,
        });
      }
    }

    // Repli StatPal pour les matchs qui ne viennent pas de The Odds API
    if (STATPAL_API_KEY) {
      for (const matchId of legacy) {
        const r = await findMatchResult(matchId);
        if (r) {
          results.push({
            match_id: matchId,
            sport: r.sport,
            home_score: r.home_score,
            away_score: r.away_score,
            ht_home: r.ht_home,
            ht_away: r.ht_away,
            is_finished: r.is_finished,
          });
        }
      }
    }

    // 3. Applique le settlement
    const { data: settled, error: setErr } = await sb.rpc(
      "settle_real_bets_with_results",
      { p_results: results },
    );
    if (setErr) throw setErr;

    // ── 4. Liberation de l'exposition cote Risk Engine ──────────────
    // Le RPC ne renvoie qu'un compteur : on relit donc les paris reels
    // clotures recemment. /risk/settle n'agit que sur une reservation
    // encore RESERVED/CONFIRMED -> rappeler un pari deja traite est un
    // no-op, la fenetre de 30 min (cron = 10 min) sert de filet de rattrapage.
    let risk_released = 0;
    let risk_errors = 0;
    if (RISK_URL && RISK_SECRET) {
      const since = new Date(Date.now() - 30 * 60 * 1000).toISOString();
      const { data: closed } = await sb
        .from("bets")
        .select("id, status")
        .eq("is_virtual", false)
        .in("status", ["won", "lost", "void", "cashed_out"])
        .gte("settled_at", since)
        .limit(500);

      for (const b of closed ?? []) {
        // cashed_out : l'exposition doit etre liberee comme pour un void
        const result = b.status === "won"
          ? "WON"
          : b.status === "lost"
          ? "LOST"
          : "VOID";
        try {
          const r = await fetch(`${RISK_URL}/risk/settle`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Internal-Secret": RISK_SECRET,
            },
            body: JSON.stringify({ bet_id: b.id, result }),
            signal: AbortSignal.timeout(6000),
          });
          if (r.ok) {
            // 200 + {"settled":false} = aucune reservation a liberer
            // (pari anterieur au Risk Engine, ou deja traite) -> pas un echec
            const jr = await r.json().catch(() => ({}));
            if (jr?.settled === true) risk_released++;
          } else {
            risk_errors++;
          }
        } catch (_) {
          risk_errors++;   // best-effort : ne bloque jamais le settlement
        }
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        pending_matches: pending.size,
        odds_api_calls: api_calls,
        legacy_statpal: legacy.length,
        fetched: results.length,
        finished: results.filter(r => r.is_finished).length,
        settled,
        risk_released,
        risk_errors,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    // Les erreurs Supabase sont des OBJETS : String(e) donnait "[object Object]",
    // ce qui rendait tout diagnostic impossible. On serialise proprement.
    let detail: unknown;
    if (e && typeof e === "object") {
      const o = e as Record<string, unknown>;
      detail = {
        message: o.message ?? null,
        code: o.code ?? null,
        details: o.details ?? null,
        hint: o.hint ?? null,
        raw: JSON.stringify(e, Object.getOwnPropertyNames(e as object)),
      };
    } else {
      detail = String(e);
    }
    return new Response(
      JSON.stringify({ error: "settle_error", detail }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
