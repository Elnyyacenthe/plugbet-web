// ============================================================
// Edge Function — team_logo_proxy
// ============================================================
// Resoud le logo d'une equipe via TheSportsDB en partageant le
// resultat entre tous les users via la table team_logo_cache.
//
// Pourquoi ?
// TheSportsDB free tier renvoie HTTP 429 (Cloudflare error 1015)
// si on tape trop souvent. Chaque user qui ouvre l'app declenche
// ~100 lookups -> rate limit immediat -> initiales partout.
//
// Cette function centralise les appels : 1 fetch global par equipe,
// resultat partage avec tous les clients via la DB.
//
// Usage cote Flutter :
//   final res = await supabase.functions.invoke('team_logo_proxy', body: {
//     'sport': 'soccer',     // 'soccer' | 'basketball'
//     'name': 'Real Madrid', // nom StatPal brut
//   });
//   // res.data = { url: 'https://...' | null, source: 'cache' | 'fetched' }
//
// Deploiement :
//   supabase functions deploy team_logo_proxy
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const TSDB_SEARCH = "https://www.thesportsdb.com/api/v1/json/3/searchteams.php";
// Timeout par tentative. 6s -> 2.5s pour reduire le worst-case latency.
// TheSportsDB repond < 1s en steady state ; 2.5s couvre les pics.
const FETCH_TIMEOUT_MS = 2500;
// Plafonne le nombre de tentatives par equipe : evite la cascade
// 14 attempts × 6s = 84s sur les noms exotiques.
// 4 attempts × 2.5s = 10s max.
const MAX_ATTEMPTS_PER_TEAM = 4;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ============================================================
// Overrides : noms StatPal -> noms TheSportsDB (audience Plugbet)
// ============================================================
const OVERRIDES: Record<string, string> = {
  // Cameroun
  "coton sport": "Cotonsport Garoua", "coton sport fc": "Cotonsport Garoua",
  "union de douala": "Union Douala", "pwd bamenda": "PWD Bamenda",
  "canon yaounde": "Canon Yaounde", "astres fc": "Astres FC",
  "dragon club de yaounde": "Dragon Yaounde", "eding sport": "Eding Sport",
  "ums de loum": "UMS Loum", "apejes academy": "Apejes Mfou",
  "fovu de baham": "Fovu Baham",
  // Senegal
  "as pikine": "AS Pikine", "casa sport": "Casa Sports",
  "jaraaf de dakar": "Jaraaf", "us goree": "US Goree",
  // Cote d'Ivoire
  "asec mimosas": "ASEC Mimosas", "africa sports": "Africa Sports",
  "sewe sport": "Sewe Sport",
  // Maghreb
  "wydad athletic club": "Wydad Casablanca", "wydad ac": "Wydad Casablanca",
  "raja club athletic": "Raja Casablanca", "es tunis": "Esperance Tunis",
  "esperance sportive de tunis": "Esperance Tunis",
  "club africain": "Club Africain Tunis",
  "al ahly": "Al Ahly", "zamalek": "Zamalek",
  // Top europe
  "fc barcelona": "Barcelona", "fc bayern munchen": "Bayern Munich",
  "fc bayern munich": "Bayern Munich", "paris saint germain": "Paris Saint-Germain",
  "paris saint-germain fc": "Paris Saint-Germain", "paris sg": "Paris Saint-Germain",
  "tottenham hotspur": "Tottenham", "manchester city fc": "Manchester City",
  "manchester united fc": "Manchester United", "liverpool fc": "Liverpool",
  "chelsea fc": "Chelsea", "arsenal fc": "Arsenal",
  "real madrid cf": "Real Madrid", "real madrid c.f.": "Real Madrid",
  "atletico de madrid": "Atletico Madrid", "atletico madrid": "Atletico Madrid",
  "fc internazionale milano": "Inter Milan", "internazionale": "Inter Milan",
  "inter milano": "Inter Milan", "ac milan": "AC Milan",
  "juventus fc": "Juventus", "as roma": "Roma", "ssc napoli": "Napoli",
  // Pool virtuel
  "olympique marseille": "Marseille", "olympique lyonnais": "Olympique Lyonnais",
  "monaco": "AS Monaco", "ajax": "Ajax", "benfica": "SL Benfica",
  "porto": "FC Porto", "sporting cp": "Sporting CP",
  "flamengo": "Flamengo", "river plate": "River Plate",
  "boca juniors": "Boca Juniors", "palmeiras": "Palmeiras",
  "tp mazembe": "TP Mazembe", "mamelodi sundowns": "Mamelodi Sundowns",
  "esperance tunis": "Esperance Tunis", "wydad casablanca": "Wydad Casablanca",
  "al hilal": "Al-Hilal", "al nassr": "Al-Nassr",
  // NBA
  "la lakers": "Los Angeles Lakers", "la clippers": "Los Angeles Clippers",
  "ny knicks": "New York Knicks", "phila 76ers": "Philadelphia 76ers",
};

function stripAccents(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "");
}

function normalize(name: string): string {
  return stripAccents(name).toLowerCase().trim();
}

function buildVariants(name: string): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const add = (s: string) => {
    const t = s.trim();
    if (!t) return;
    const k = t.toLowerCase();
    if (!seen.has(k)) { seen.add(k); out.push(t); }
  };

  // 1. Override prioritaire
  const norm = normalize(name);
  if (OVERRIDES[norm]) add(OVERRIDES[norm]);

  // 2. Nom brut
  add(name);

  // 3. Sans articles
  let stripped = name.replace(
    /\b(de|do|da|du|le|la|les|el|al|of)\b/gi, " "
  ).replace(/\s+/g, " ").trim();
  add(stripped);

  // 4. Sans suffixes club etendus
  let cleaned = name.replace(
    /\b(F\.?C\.?|S\.?C\.?|C\.?F\.?|A\.?C\.?|A\.?F\.?C\.?|U\.?S\.?L\.?|C\.?D\.?|F\.?K\.?|S\.?K\.?|N\.?K\.?|R\.?C\.?|E\.?C\.?|S\.?L\.?|A\.?S\.?|U\.?S\.?|K\.?S\.?|CSKA|CD|SC|FC|AC|CF|RC|RCD|CSD|FK|SK|NK|EC|SL|CR|AS|US|KS|KAA|GD|VFB|VFL|TSG)\b/gi,
    " "
  ).replace(/\s+/g, " ").trim();
  add(cleaned);

  // 5. Sans pays parentheses
  add(name.replace(/\s*\([^)]+\)\s*/g, " ").trim());

  // 6. Sans accents
  add(stripAccents(name));
  add(stripAccents(cleaned));

  // 7. 1er mot (>= 4 chars)
  const firstWord = name.split(/\s+/)[0];
  if (firstWord.length >= 4) add(firstWord);

  return out;
}

type FetchResult = { url: string | null; transient: boolean };

async function fetchOne(query: string, queryParam: "t" | "sname", wantedSport: string): Promise<FetchResult> {
  try {
    const url = `${TSDB_SEARCH}?${queryParam}=${encodeURIComponent(query)}`;
    const ctrl = new AbortController();
    const timeout = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    let res: Response;
    try {
      res = await fetch(url, { signal: ctrl.signal });
    } catch (e) {
      clearTimeout(timeout);
      // AbortError (timeout) ou erreur reseau = transient
      console.log(`thesportsdb network/timeout for ${query}: ${e}`);
      return { url: null, transient: true };
    }
    clearTimeout(timeout);

    // 429 / 503 = rate limit Cloudflare ou serveur sature = transient
    if (res.status === 429 || res.status === 503 || res.status >= 500) {
      console.log(`thesportsdb HTTP ${res.status} (transient) for ${query}`);
      return { url: null, transient: true };
    }
    if (res.status !== 200) {
      console.log(`thesportsdb HTTP ${res.status} for ${query}`);
      return { url: null, transient: false };
    }
    const body = await res.json();
    if (!body?.teams || !Array.isArray(body.teams)) return { url: null, transient: false };
    const teams: any[] = body.teams;
    if (teams.length === 0) return { url: null, transient: false };

    const badgeOf = (t: any): string | null => {
      for (const f of ["strBadge", "strTeamBadge", "strLogo"]) {
        const v = t[f];
        if (typeof v === "string" && v.length > 0) return v;
      }
      return null;
    };

    const filtered: any[] = [];
    const anySport: any[] = [];
    const youthRegex = /\b(u15|u16|u17|u18|u19|u20|u21|u23|youth|women|reserves?|academy|junior)\b/i;

    for (const t of teams) {
      const tname = (t.strTeam ?? "").toLowerCase();
      if (youthRegex.test(tname)) continue;
      const badge = badgeOf(t);
      if (!badge) continue;
      const sport = (t.strSport ?? "").toLowerCase();
      if (sport === wantedSport.toLowerCase()) filtered.push(t);
      else anySport.push(t);
    }
    const pool = filtered.length > 0 ? filtered : anySport;
    if (pool.length === 0) return { url: null, transient: false };
    pool.sort((a, b) =>
      parseInt(b.intLoved ?? "0") - parseInt(a.intLoved ?? "0")
    );
    return { url: badgeOf(pool[0]), transient: false };
  } catch (e) {
    console.log(`fetch error for ${query}: ${e}`);
    // Erreur inattendue = transient (laisse une chance au retry)
    return { url: null, transient: true };
  }
}

async function resolveLogo(name: string, sport: string): Promise<FetchResult> {
  const wanted = sport === "basketball" ? "Basketball" : "Soccer";
  const variants = buildVariants(name);

  let attempts = 0;
  let anyTransient = false;
  let anyNonTransientMiss = false;

  // 1) Boucle endpoint t= (max MAX_ATTEMPTS_PER_TEAM tentatives total)
  for (const v of variants) {
    if (attempts >= MAX_ATTEMPTS_PER_TEAM) break;
    attempts++;
    const r = await fetchOne(v, "t", wanted);
    if (r.url) return r;
    if (r.transient) anyTransient = true;
    else anyNonTransientMiss = true;
  }
  // 2) Fallback sname= (continue dans la limite globale)
  for (const v of variants) {
    if (attempts >= MAX_ATTEMPTS_PER_TEAM) break;
    attempts++;
    const r = await fetchOne(v, "sname", wanted);
    if (r.url) return r;
    if (r.transient) anyTransient = true;
    else anyNonTransientMiss = true;
  }
  // Si TOUS les essais ont ete transient (timeout/429), on signale transient
  // pour que le client ne mette pas en cache negatif.
  // Si au moins un retour 200 sans match, c'est un vrai "introuvable".
  return { url: null, transient: anyTransient && !anyNonTransientMiss };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(
      JSON.stringify({ error: "missing env vars" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const body = await req.json().catch(() => ({}));
    const sport = (body.sport as string | undefined) ?? "";
    const name = (body.name as string | undefined) ?? "";

    if (!["soccer", "basketball"].includes(sport)) {
      return new Response(
        JSON.stringify({ error: "invalid_sport (must be 'soccer' or 'basketball')" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    if (!name || name.trim() === "") {
      return new Response(
        JSON.stringify({ error: "missing_name" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 1) Cache DB hit ?
    const { data: cached } = await supabase.rpc("get_team_logo", {
      p_sport: sport,
      p_name: name,
    });

    if (cached?.hit && !cached?.stale) {
      return new Response(
        JSON.stringify({ url: cached.url, source: "cache" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 2) Cache miss ou stale -> fetch TheSportsDB
    const result = await resolveLogo(name, sport);

    // 3) Sauve resultat en DB UNIQUEMENT si non-transient.
    //    Sinon on laisse le miss en cache local court (1j) et on retentera.
    if (!result.transient) {
      await supabase.rpc("upsert_team_logo", {
        p_sport: sport,
        p_name: name,
        p_url: result.url,
      });
    }

    return new Response(
      JSON.stringify({
        url: result.url,
        source: "fetched",
        transient: result.transient,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "proxy_error", detail: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
