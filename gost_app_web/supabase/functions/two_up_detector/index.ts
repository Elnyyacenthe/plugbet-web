// ============================================================
// Edge Function — Detecteur 2Up (cron 60s)
// ============================================================
// Modele POLLING (The Odds API n'offre pas de webhook). A chaque tick :
//   1. RPC list_2up_pending_matches -> matchs avec selections 2Up eligibles
//      pending [{ match_id, sport, league_key, external_id }]
//   2. Pour chaque league_key concernee : GET /v4/sports/{key}/scores
//      (scores live, ~30s de fraicheur cote fournisseur)
//   3. Pour chaque match : extrait home/away score (match par NOM), puis
//      RPC settle_2up_for_match(match_id, sport, home, away) qui detecte le
//      seuil + regle le pari anticipe (idempotent).
//
// Secrets requis : THE_ODDS_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
// Appelee par pg_cron (voir zz_20260716_2up_detector_cron.sql), Bearer =
// service_role (vault). N'echoue jamais l'affichage des cotes : best-effort.
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const THE_ODDS_API_KEY = Deno.env.get("THE_ODDS_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ODDS_BASE = "https://api.the-odds-api.com";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface PendingMatch {
  match_id: string;
  sport: string | null;
  league_key: string | null;
  external_id: string | null;
}

interface ScoreEvent {
  id: string;
  home_team: string;
  away_team: string;
  completed: boolean;
  scores: Array<{ name: string; score: string }> | null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (!THE_ODDS_API_KEY || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return json({ error: "missing_env" }, 500);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  try {
    // 1. Matchs a surveiller
    const { data: pendingRaw, error: e1 } = await admin.rpc("list_2up_pending_matches");
    if (e1) return json({ error: "list_pending_failed", detail: e1.message }, 500);
    const pending = (pendingRaw ?? []) as PendingMatch[];
    if (pending.length === 0) return json({ ok: true, pending: 0, settled: 0 });

    // 2. Regroupe par league_key (sport_key). Ignore les selections sans
    //    league_key (anciens paris) : non detectables precisement.
    const byLeague = new Map<string, PendingMatch[]>();
    for (const m of pending) {
      if (!m.league_key || !m.external_id) continue;
      const arr = byLeague.get(m.league_key) ?? [];
      arr.push(m);
      byLeague.set(m.league_key, arr);
    }

    let settledTotal = 0;
    const details: unknown[] = [];

    for (const [leagueKey, matches] of byLeague) {
      // 3. Scores live de la ligue
      const url =
        `${ODDS_BASE}/v4/sports/${leagueKey}/scores/?apiKey=${THE_ODDS_API_KEY}&daysFrom=1`;
      let resp: Response;
      try {
        resp = await fetch(url, { headers: { Accept: "application/json" } });
      } catch (_) {
        continue; // provider down -> on saute cette ligue, pas de faux reglement
      }
      // Log quota (best-effort)
      logQuota(admin, "scores", leagueKey, resp.headers);
      if (!resp.ok) continue; // 429 / 5xx -> on retentera au prochain tick

      const events = (await resp.json().catch(() => [])) as ScoreEvent[];
      const byId = new Map<string, ScoreEvent>();
      for (const ev of events) byId.set(ev.id, ev);

      for (const m of matches) {
        const ev = byId.get(m.external_id!);
        if (!ev || !ev.scores) continue; // pas de score live -> rien
        const home = readScore(ev.scores, ev.home_team);
        const away = readScore(ev.scores, ev.away_team);
        if (home === null || away === null) continue;

        const { data: settled, error: e2 } = await admin.rpc("settle_2up_for_match", {
          p_match_id: m.match_id,
          p_sport: m.sport,
          p_home_score: home,
          p_away_score: away,
        });
        if (!e2 && typeof settled === "number" && settled > 0) {
          settledTotal += settled;
          details.push({ match_id: m.match_id, score: `${home}-${away}`, settled });
        }
      }
    }

    return json({ ok: true, pending: pending.length, settled: settledTotal, details });
  } catch (e) {
    return json({ error: "detector_error", detail: String(e) }, 500);
  }
});

function readScore(
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

// deno-lint-ignore no-explicit-any
async function logQuota(admin: any, endpoint: string, sportKey: string, headers: Headers) {
  const used = parseInt(headers.get("x-requests-used") ?? "", 10);
  const remaining = parseInt(headers.get("x-requests-remaining") ?? "", 10);
  const last = parseInt(headers.get("x-requests-last") ?? "", 10);
  if (Number.isNaN(used) && Number.isNaN(remaining)) return;
  try {
    await admin.rpc("log_odds_api_quota", {
      p_endpoint: endpoint,
      p_sport_key: sportKey,
      p_used: Number.isNaN(used) ? null : used,
      p_remaining: Number.isNaN(remaining) ? null : remaining,
      p_last_cost: Number.isNaN(last) ? null : last,
    });
  } catch (_) { /* best-effort */ }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
