// ============================================================
// Edge Function — StatPal.io proxy (clé serveur)
// ============================================================
// Cache la clé d'accès StatPal côté serveur. Le client Flutter
// (mobile + web) ne voit JAMAIS la vraie clé : il appelle simplement
// cette Edge Function avec un `path` (ex. '/soccer/livescores').
//
// ── Trial active depuis : 2026-06-01 ──
// Souscription : Soccer and NBA - Data API (Stripe.com)
// Prix après trial : $29 / mois (cycle mensuel)
// ⚠️ Trial expire le ~2026-06-15 — facturation auto si non résiliée.
//   support@statpal.io pour annuler.
//
// Déploiement :
// 1. Ajouter le secret depuis le dashboard Supabase :
//    Settings → Edge Functions → Secrets
//    Name : STATPAL_API_KEY
//    Value : <ta clé d'accès reçue par mail>
//    (OU via CLI : supabase secrets set STATPAL_API_KEY=xxx)
// 2. Déployer :
//    supabase functions deploy statpal_proxy
//
// Usage côté Flutter :
//   final res = await _client.functions.invoke('statpal_proxy', body: {
//     'path': '/soccer/livescores',
//     'query': { 'foo': 'bar' }  // optionnel
//   });
//
// Doc StatPal : https://statpal.io/documentation
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const STATPAL_API_KEY = Deno.env.get("STATPAL_API_KEY") ?? "";

// Routage par sport :
// - Soccer : V2 (odds prematch + live + matches/daily + leagues/{id}/matches)
// - NBA / NFL / MLB / NHL / Cricket / Tennis / Esports / F1 / Handball /
//   Volleyball / Golf : V1 (StatPal n'a pas migre ces sports vers V2).
const BASE_URL_V1 = "https://statpal.io/api/v1";
const BASE_URL_V2 = "https://statpal.io/api/v2";

// Sports V1 (tout le reste est V2 par defaut)
const V1_PREFIXES = [
  "/nba/", "/nfl/", "/mlb/", "/nhl/",
  "/cricket/", "/tennis/", "/esports/",
  "/f1/", "/handball/", "/volleyball/", "/golf/",
];

function pickBaseUrl(path: string): string {
  for (const prefix of V1_PREFIXES) {
    if (path.startsWith(prefix)) return BASE_URL_V1;
  }
  return BASE_URL_V2;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // Preflight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!STATPAL_API_KEY) {
    return new Response(
      JSON.stringify({ error: "STATPAL_API_KEY missing in env" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const body = await req.json().catch(() => ({}));
    const path = (body.path as string | undefined) ?? "";
    const extraQuery = (body.query as Record<string, string> | undefined) ?? {};

    if (!path || !path.startsWith("/")) {
      return new Response(
        JSON.stringify({ error: "missing or invalid 'path' (must start with /)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // StatPal exige le access_key en query param (pattern V1/V2)
    const params = new URLSearchParams({ access_key: STATPAL_API_KEY, ...extraQuery });
    const baseUrl = pickBaseUrl(path);
    const url = `${baseUrl}${path}?${params.toString()}`;

    const upstream = await fetch(url, {
      method: "GET",
      headers: { "Accept": "application/json" },
    });
    const text = await upstream.text();

    return new Response(text, {
      status: upstream.status,
      headers: {
        ...corsHeaders,
        "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
      },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "proxy_error", detail: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
