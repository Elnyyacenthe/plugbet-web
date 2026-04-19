// ============================================================
// Edge Function — football-data.org proxy
//
// Cache la cle API cote serveur. Le client Flutter ne voit jamais
// la vraie cle, il appelle simplement cette Edge Function.
//
// Deploiement :
// 1. Definir la variable d'env dans Supabase Dashboard :
//    Settings → Edge Functions → Secrets → FOOTBALL_DATA_API_KEY
// 2. Deployer avec la CLI Supabase :
//    supabase functions deploy football_proxy
//
// Usage cote Flutter :
//   final res = await _client.functions.invoke('football_proxy', body: {
//     'path': '/matches?dateFrom=2026-04-10&dateTo=2026-04-16'
//   });
// ============================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const FOOTBALL_API_KEY = Deno.env.get("FOOTBALL_DATA_API_KEY") ?? "";
const BASE_URL = "https://api.football-data.org/v4";

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

  try {
    if (!FOOTBALL_API_KEY) {
      return new Response(
        JSON.stringify({ error: "FOOTBALL_DATA_API_KEY not configured" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verifier l'auth utilisateur (optionnel mais recommande)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "unauthorized" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json();
    const path: string = body.path ?? "";

    // Whitelist des endpoints autorises
    if (!path.startsWith("/matches") && !path.startsWith("/competitions")) {
      return new Response(
        JSON.stringify({ error: "endpoint not allowed" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Appeler l'API avec la cle secrete
    const url = `${BASE_URL}${path}`;
    const apiRes = await fetch(url, {
      headers: {
        "X-Auth-Token": FOOTBALL_API_KEY,
      },
    });

    const data = await apiRes.text();
    return new Response(data, {
      status: apiRes.status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
