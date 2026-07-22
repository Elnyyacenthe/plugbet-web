// ============================================================
// Edge Function — ingest_base_odds
// ============================================================
// Récupère les cotes de base (1X2 + Totaux) des matchs football via The Odds
// API et les persiste dans public.event_odds. C'est la SOURCE serveur que lit
// derive_goals_markets (le moteur n'a rien à lire sans elle).
//
// Déclenchée par cron (Bearer = service_role du vault) ou manuellement.
// Étape 1 : football uniquement, sur un sous-ensemble de ligues actives.
//
// Auth : verify_jwt=true (la gateway Supabase valide le JWT service_role du
// cron), même convention que two_up_detector. Pas de contrôle custom.
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_KEY = Deno.env.get("THE_ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ODDS_BASE = "https://api.the-odds-api.com";

// Ligues football grand public visées à l'Étape 1 (seules les ACTIVES du
// moment renverront des matchs ; les hors-saison renvoient une liste vide).
const DEFAULT_LEAGUES = [
  "soccer_epl",
  "soccer_spain_la_liga",
  "soccer_italy_serie_a",
  "soccer_germany_bundesliga",
  "soccer_france_ligue_one",
  "soccer_uefa_champs_league",
  "soccer_uefa_europa_league",
  "soccer_netherlands_eredivisie",
  "soccer_portugal_primeira_liga",
  "soccer_usa_mls",
  "soccer_brazil_campeonato",
  "soccer_fifa_world_cup",
];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

/// Extrait 1X2 + Totaux d'un événement The Odds API. Choisit le bookmaker le
/// plus complet (h2h + totals si possible). Renvoie null si pas de 1X2.
function extractOdds(ev: any): {
  home: number;
  draw: number;
  away: number;
  totalLine: number | null;
  over: number | null;
  under: number | null;
  ahLine: number | null;
  ahHome: number | null;
  ahAway: number | null;
} | null {
  const home = ev.home_team, away = ev.away_team;
  const books: any[] = Array.isArray(ev.bookmakers) ? ev.bookmakers : [];
  let best: any = null;
  for (const b of books) {
    const has = (k: string) => (b.markets ?? []).some((m: any) => m.key === k);
    if (has("h2h") && has("totals")) {
      best = b;
      break;
    }
    if (has("h2h") && !best) best = b;
  }
  if (!best) return null;

  const h2h = (best.markets ?? []).find((m: any) => m.key === "h2h");
  if (!h2h) return null;
  let hO: number | null = null, dO: number | null = null, aO: number | null = null;
  for (const o of h2h.outcomes ?? []) {
    if (o.name === home) hO = o.price;
    else if (o.name === away) aO = o.price;
    else if (o.name === "Draw") dO = o.price;
  }
  if (!hO || !dO || !aO) return null;

  // Totaux : ligne principale = point le plus proche de 2.5 (Over/Under).
  let totalLine: number | null = null, over: number | null = null,
    under: number | null = null;
  const tot = (best.markets ?? []).find((m: any) => m.key === "totals");
  if (tot) {
    const byLine = new Map<number, { over?: number; under?: number }>();
    for (const o of tot.outcomes ?? []) {
      const pt = Number(o.point);
      if (!Number.isFinite(pt)) continue;
      const slot = byLine.get(pt) ?? {};
      if (o.name === "Over") slot.over = o.price;
      else if (o.name === "Under") slot.under = o.price;
      byLine.set(pt, slot);
    }
    let bestPt: number | null = null;
    for (const [pt, v] of byLine) {
      if (v.over && v.under) {
        if (bestPt === null || Math.abs(pt - 2.5) < Math.abs(bestPt - 2.5)) {
          bestPt = pt;
        }
      }
    }
    if (bestPt !== null) {
      totalLine = bestPt;
      over = byLine.get(bestPt)!.over!;
      under = byLine.get(bestPt)!.under!;
    }
  }

  // Handicap asiatique (spreads) — ligne principale : on cherche dans N'IMPORTE
  // quel bookmaker (indépendamment du choix h2h/totals). On prend la ligne dont
  // |point| est le plus petit (la plus proche de l'équilibre = principale).
  let ahLine: number | null = null, ahHome: number | null = null,
    ahAway: number | null = null;
  for (const bk of books) {
    const sp = (bk.markets ?? []).find((m: any) => m.key === "spreads");
    if (!sp) continue;
    let hPoint: number | null = null, hPrice: number | null = null,
      aPrice: number | null = null;
    for (const o of sp.outcomes ?? []) {
      if (o.name === home) { hPoint = Number(o.point); hPrice = o.price; }
      else if (o.name === away) aPrice = o.price;
    }
    if (hPoint != null && Number.isFinite(hPoint) && hPrice && aPrice) {
      if (ahLine === null || Math.abs(hPoint) < Math.abs(ahLine)) {
        ahLine = hPoint;
        ahHome = hPrice;
        ahAway = aPrice;
      }
    }
  }

  return { home: hO, draw: dO, away: aO, totalLine, over, under, ahLine, ahHome, ahAway };
}

/// Signature des cotes (arrondi 2 déc.) : détecte un changement significatif.
function signature(o: {
  home: number;
  draw: number;
  away: number;
  totalLine: number | null;
  over: number | null;
  under: number | null;
  ahLine: number | null;
  ahHome: number | null;
  ahAway: number | null;
}): string {
  const r = (x: number | null) => (x == null ? "-" : x.toFixed(2));
  return [
    r(o.home), r(o.draw), r(o.away), r(o.totalLine), r(o.over), r(o.under),
    r(o.ahLine), r(o.ahHome), r(o.ahAway),
  ].join("|");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  // Auth gérée par la gateway (verify_jwt=true).
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  let leagues = DEFAULT_LEAGUES;
  try {
    const body = await req.json();
    if (Array.isArray(body?.leagues) && body.leagues.length > 0) {
      leagues = body.leagues;
    }
  } catch (_) { /* body optionnel */ }

  let fetched = 0, upserted = 0;
  const perLeague: Record<string, number> = {};

  for (const key of leagues) {
    try {
      const url =
        `${ODDS_BASE}/v4/sports/${key}/odds?apiKey=${ODDS_KEY}&regions=eu&markets=h2h,totals,spreads&oddsFormat=decimal`;
      const res = await fetch(url);
      if (!res.ok) {
        perLeague[key] = -res.status;
        continue;
      }
      const events = await res.json();
      if (!Array.isArray(events)) continue;
      perLeague[key] = events.length;
      for (const ev of events) {
        fetched++;
        const o = extractOdds(ev);
        if (!o) continue;
        const matchId = "oa_" + ev.id;
        const row = {
          match_id: matchId,
          sport: "football",
          league_key: key,
          home_name: ev.home_team,
          away_name: ev.away_team,
          commence_time: ev.commence_time,
          home_odds: o.home,
          draw_odds: o.draw,
          away_odds: o.away,
          total_line: o.totalLine,
          over_odds: o.over,
          under_odds: o.under,
          ah_line: o.ahLine,
          ah_home_odds: o.ahHome,
          ah_away_odds: o.ahAway,
          odds_signature: signature(o),
          fetched_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        };
        const { error } = await admin.from("event_odds").upsert(row, {
          onConflict: "match_id",
        });
        if (!error) upserted++;
      }
    } catch (e) {
      perLeague[key] = -1;
    }
  }

  return json({ ok: true, leagues: leagues.length, fetched, upserted, perLeague });
});
