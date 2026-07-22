// ============================================================
// Edge Function — settle_derived_markets
// ============================================================
// Règle les paris sur marchés DÉRIVÉS (matchs The Odds API `oa_`) que le
// pipeline StatPal ne couvre pas. Cron : récupère les scores FINAUX via The
// Odds API /scores et note les sélections dérivées (score final uniquement).
//
//   1. list_pending_derived_matches  -> matchs oa_ avec sélections dérivées
//      actives en attente
//   2. /v4/sports/{league}/scores/?daysFrom=3  -> scores
//   3. settle_derived_for_match(match_id, home, away) UNIQUEMENT si completed
//      (le grading dérivé repose sur le score FINAL)
//
// Auth : verify_jwt=true (bearer service_role du cron).
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_KEY = Deno.env.get("THE_ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ODDS_BASE = "https://api.the-odds-api.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

function readScore(
  scores: Array<{ name: string; score: string }> | null,
  team: string,
): number | null {
  if (!scores) return null;
  for (const s of scores) {
    if (s.name === team) {
      const n = parseInt(s.score, 10);
      return Number.isNaN(n) ? null : n;
    }
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  const { data: pendingRaw, error } = await admin.rpc(
    "list_pending_derived_matches",
  );
  if (error) return json({ error: "list_failed", detail: error.message }, 500);
  const pending = (pendingRaw ?? []) as {
    match_id: string;
    league_key: string | null;
    external_id: string | null;
  }[];
  if (pending.length === 0) return json({ ok: true, pending: 0, settled: 0 });

  const byLeague = new Map<string, typeof pending>();
  for (const m of pending) {
    if (!m.league_key || !m.external_id) continue;
    const arr = byLeague.get(m.league_key) ?? [];
    arr.push(m);
    byLeague.set(m.league_key, arr);
  }

  let settledTotal = 0;
  const details: unknown[] = [];

  for (const [leagueKey, matches] of byLeague) {
    const url =
      `${ODDS_BASE}/v4/sports/${leagueKey}/scores/?apiKey=${ODDS_KEY}&daysFrom=3`;
    let resp: Response;
    try {
      resp = await fetch(url, { headers: { Accept: "application/json" } });
    } catch (_) {
      continue;
    }
    if (!resp.ok) continue;
    const events = (await resp.json().catch(() => [])) as Array<{
      id: string;
      completed?: boolean;
      home_team: string;
      away_team: string;
      scores: Array<{ name: string; score: string }> | null;
    }>;
    const byId = new Map(events.map((e) => [e.id, e]));

    for (const m of matches) {
      const ev = byId.get(m.external_id!);
      // Grading par score FINAL -> uniquement matchs terminés.
      if (!ev || ev.completed !== true || !ev.scores) continue;
      const home = readScore(ev.scores, ev.home_team);
      const away = readScore(ev.scores, ev.away_team);
      if (home === null || away === null) continue;

      const { data: settled, error: e2 } = await admin.rpc(
        "settle_derived_for_match",
        { p_match_id: m.match_id, p_home: home, p_away: away },
      );
      if (!e2 && typeof settled === "number" && settled > 0) {
        settledTotal += settled;
        details.push({ match_id: m.match_id, score: `${home}-${away}`, settled });
      }
    }
  }

  return json({ ok: true, pending: pending.length, settled: settledTotal, details });
});
