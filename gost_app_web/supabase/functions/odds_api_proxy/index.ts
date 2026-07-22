// ============================================================
// Edge Function — The Odds API proxy (cle serveur)
// ============================================================
// Cache la clef The Odds API (the-odds-api.com) cote serveur. Le client
// Flutter ne voit JAMAIS la vraie clef : il appelle cette Edge Function
// avec un `path` (ex. '/v4/sports/soccer_epl/odds') + `query`.
//
// Fonctions :
//  - Injection de la clef en query param `apiKey` (jamais exposee client)
//  - Cache court en isolate chaud (defaut 25s odds / 15s scores) pour
//    eviter de depasser la frequence reelle de maj (~30s) et menager le
//    quota partage entre toutes les instances de l'app
//  - Retry backoff sur 429 (quota) / 5xx, sans bloquer l'affichage
//  - Log de la consommation quota (headers x-requests-*) dans
//    public.odds_api_quota via RPC service_role (best-effort)
//
// Deploiement :
// 1. Secret depuis le dashboard Supabase (Settings -> Edge Functions ->
//    Secrets) :  Name: THE_ODDS_API_KEY  Value: <ta clef>
//    (OU via CLI : supabase secrets set THE_ODDS_API_KEY=xxx)
//    SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY sont injectes d'office.
// 2. supabase functions deploy odds_api_proxy
//
// Usage cote Flutter :
//   final res = await client.functions.invoke('odds_api_proxy', body: {
//     'path': '/v4/sports/soccer_epl/odds',
//     'query': { 'regions': 'eu', 'markets': 'h2h,totals,spreads',
//                'oddsFormat': 'decimal' },
//   });
//
// Doc : https://the-odds-api.com/liveapi/guides/v4/
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const THE_ODDS_API_KEY = Deno.env.get("THE_ODDS_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const BASE_URL = "https://api.the-odds-api.com";

// Cache court en memoire (isolate chaud). Best-effort : si l'isolate est
// recycle, on refait un appel upstream — sans risque de correction.
type CacheEntry = { body: string; status: number; ts: number };
const cache = new Map<string, CacheEntry>();

function ttlForPath(path: string): number {
  if (path.includes("/scores")) return 15_000; // scores : 15s
  if (path.includes("/odds")) return 25_000;   // cotes : 25s
  return 60_000;                                 // /sports : 60s
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Log quota (non-bloquant). Necessite SERVICE_ROLE_KEY.
async function logQuota(
  endpoint: string,
  sportKey: string | null,
  headers: Headers,
) {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return;
  const used = parseInt(headers.get("x-requests-used") ?? "", 10);
  const remaining = parseInt(headers.get("x-requests-remaining") ?? "", 10);
  const last = parseInt(headers.get("x-requests-last") ?? "", 10);
  if (Number.isNaN(used) && Number.isNaN(remaining)) return;
  try {
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    await admin.rpc("log_odds_api_quota", {
      p_endpoint: endpoint,
      p_sport_key: sportKey,
      p_used: Number.isNaN(used) ? null : used,
      p_remaining: Number.isNaN(remaining) ? null : remaining,
      p_last_cost: Number.isNaN(last) ? null : last,
    });
  } catch (_) {
    // best-effort : ne jamais casser la reponse pour un log quota
  }
}

function classifyEndpoint(path: string): string {
  if (path.includes("/scores")) return "scores";
  if (path.includes("/odds")) return "odds";
  return "sports";
}

// Extrait le sport_key d'un path /v4/sports/{key}/...
function extractSportKey(path: string): string | null {
  const m = path.match(/\/v4\/sports\/([^/]+)\//);
  return m ? m[1] : null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!THE_ODDS_API_KEY) {
    return new Response(
      JSON.stringify({ error: "THE_ODDS_API_KEY missing in env" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const body = await req.json().catch(() => ({}));
    const path = (body.path as string | undefined) ?? "";
    const extraQuery = (body.query as Record<string, string> | undefined) ?? {};

    if (!path || !path.startsWith("/v4/")) {
      return new Response(
        JSON.stringify({ error: "missing or invalid 'path' (must start with /v4/)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const params = new URLSearchParams({ apiKey: THE_ODDS_API_KEY, ...extraQuery });
    const url = `${BASE_URL}${path}?${params.toString()}`;
    const cacheKey = `${path}?${new URLSearchParams(extraQuery).toString()}`;
    const ttl = ttlForPath(path);
    const now = Date.now();

    // Cache hit frais ?
    const hit = cache.get(cacheKey);
    if (hit && now - hit.ts < ttl) {
      return new Response(hit.body, {
        status: hit.status,
        headers: { ...corsHeaders, "Content-Type": "application/json", "x-cache": "HIT" },
      });
    }

    // Fetch upstream avec retry backoff sur 429 / 5xx
    const endpoint = classifyEndpoint(path);
    const sportKey = extractSportKey(path);
    let upstream: Response | null = null;
    const delays = [0, 500, 1200]; // 3 tentatives
    for (let i = 0; i < delays.length; i++) {
      if (delays[i] > 0) await sleep(delays[i]);
      upstream = await fetch(url, { method: "GET", headers: { Accept: "application/json" } });
      // Log quota a chaque reponse portant les headers
      logQuota(endpoint, sportKey, upstream.headers);
      if (upstream.status !== 429 && upstream.status < 500) break;
    }

    if (!upstream) {
      return new Response(
        JSON.stringify({ error: "no_upstream_response" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const text = await upstream.text();

    // Quota depasse / erreur amont : servir le cache perime si dispo
    if ((upstream.status === 429 || upstream.status >= 500) && hit) {
      return new Response(hit.body, {
        status: hit.status,
        headers: { ...corsHeaders, "Content-Type": "application/json", "x-cache": "STALE" },
      });
    }

    // Succes : on met en cache
    if (upstream.status === 200) {
      cache.set(cacheKey, { body: text, status: 200, ts: now });
    }

    return new Response(text, {
      status: upstream.status,
      headers: {
        ...corsHeaders,
        "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
        "x-cache": "MISS",
        "x-quota-remaining": upstream.headers.get("x-requests-remaining") ?? "",
      },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "proxy_error", detail: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
