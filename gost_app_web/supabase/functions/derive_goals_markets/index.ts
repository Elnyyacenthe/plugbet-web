// ============================================================
// Edge Function — derive_goals_markets (ÉTAPES 1 + 2)
// ============================================================
// Orchestre le moteur de buts sur les cotes de base persistées (event_odds) :
//   1. retrait de marge (probas marché)                [_shared/goals_model/margin]
//   2. calibration (λ_dom, λ_ext), MISE EN CACHE       [.../calibrate]
//   3. matrice de scores                               [.../matrix]
//   4. dérivation par marché (fonctions pures)         [.../markets/*]
//        Étape 1 : Double Chance
//        Étape 2 : Totaux (multi-lignes), BTTS, Score exact, Résultat+Total
//   5. garde-fou : écart vs cote de référence (si dispo) OU qualité de
//      calibration -> guard_tripped
//   6. écrit derived_markets tagué. L'ACTIVATION (is_active) n'est PAS décidée
//      ici : le trigger BD `_trg_derived_activation` la déduit du code marché
//      (_derived_code_is_active) à chaque insert/update -> auto pour les
//      nouveaux matchs. Upsert GROUPÉ par match (perf).
//
// Auth : verify_jwt=true (gateway valide le JWT service_role du cron).
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { normalize1x2, normalizeTotals } from "../_shared/goals_model/margin.ts";
import { calibrateGoalsModel } from "../_shared/goals_model/calibrate.ts";
import { buildScoreMatrix } from "../_shared/goals_model/matrix.ts";
import { deriveDoubleChance } from "../_shared/goals_model/markets/double_chance.ts";
import { deriveTotals } from "../_shared/goals_model/markets/totals.ts";
import { deriveBtts } from "../_shared/goals_model/markets/btts.ts";
import {
  correctScoreCode,
  deriveCorrectScore,
} from "../_shared/goals_model/markets/correct_score.ts";
import {
  deriveResultTotal,
  resultTotalCode,
} from "../_shared/goals_model/markets/result_total.ts";
import {
  deriveEuropeanHandicap,
  handicapCode,
} from "../_shared/goals_model/markets/handicap.ts";
import {
  deriveAsianHandicap,
  isHalfLine,
} from "../_shared/goals_model/markets/asian_handicap.ts";
import { deriveHalfTime } from "../_shared/goals_model/markets/half_time.ts";
import type { MarketProbs } from "../_shared/goals_model/types.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

// Un marché à écrire : proba « fair » + éventuelle proba de référence marché.
interface Mk {
  code: string;
  label: string;
  fair: number;
  ref: number | null;
}

const totalCode = (line: number, side: "over" | "under") =>
  `${side}${String(line).replace(".", "")}`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  const { data: cfg } = await admin.from("goals_model_config").select("*").eq(
    "id",
    1,
  ).maybeSingle();
  if (!cfg || cfg.enabled === false) {
    return json({ ok: false, reason: "model_disabled" });
  }
  const modelVersion: string = cfg.model_version ?? "v1";
  const maxGoals: number = cfg.max_goals ?? 10;
  const guardThreshold: number = Number(cfg.guard_deviation_threshold ?? 0.15);
  const marginHigh: number = Number(cfg.safety_margin_high ?? 0.06);
  const marginCS: number = Number(cfg.safety_margin_correct_score ?? 0.20);
  const marginRT: number = Number(cfg.safety_margin_result_total ?? 0.12);
  const marginHand: number = Number(cfg.safety_margin_handicap ?? 0.08);
  const marginHt: number = Number(cfg.safety_margin_ht ?? 0.10);
  const marginFts: number = Number(cfg.safety_margin_fts ?? 0.15);
  const htSplit: number = Number(cfg.ht_split_first ?? 0.45);
  // Marge de sécurité selon la famille de marché.
  const marginFor = (code: string): number =>
    code.startsWith("cs_")
      ? marginCS
      : code.startsWith("rt_")
      ? marginRT
      : code.startsWith("eh_")
      ? marginHand
      : code.startsWith("ht_")
      ? marginHt
      : code.startsWith("fts_")
      ? marginFts
      : marginHigh; // dc_*, over/under, btts_*, ah_*
  // Marchés à confiance MOYENNE (hypothèses supplémentaires -> badge « Estimation »).
  const confidenceFor = (code: string): "high" | "medium" =>
    code.startsWith("ht_") || code.startsWith("fts_") ? "medium" : "high";

  const { data: rows, error } = await admin
    .from("event_odds")
    .select("*")
    .eq("sport", "football")
    .not("home_odds", "is", null)
    .not("draw_odds", "is", null)
    .not("away_odds", "is", null);
  if (error) return json({ ok: false, error: error.message }, 500);

  let processed = 0, calibrated = 0, cacheHits = 0, marketsWritten = 0,
    guardTripped = 0;

  for (const e of rows ?? []) {
    try {
      // 1. probas marché sans marge.
      const p = normalize1x2(
        { home: e.home_odds, draw: e.draw_odds, away: e.away_odds },
        cfg.margin_method ?? "proportional",
      );
      const market: MarketProbs = { home: p.home, draw: p.draw, away: p.away };
      if (e.total_line != null && e.over_odds != null && e.under_odds != null) {
        const t = normalizeTotals(
          { line: e.total_line, over: e.over_odds, under: e.under_odds },
          cfg.margin_method ?? "proportional",
        );
        market.totals = { line: t.line, over: t.over, under: t.under };
      }

      // 2. calibration avec cache.
      const { data: cached } = await admin
        .from("goals_model_calibration")
        .select("*")
        .eq("match_id", e.match_id)
        .maybeSingle();

      let lambdaHome: number, lambdaAway: number, maxDeviation: number;
      if (
        cached && cached.odds_signature === e.odds_signature &&
        cached.model_version === modelVersion
      ) {
        lambdaHome = Number(cached.lambda_home);
        lambdaAway = Number(cached.lambda_away);
        maxDeviation = Number(cached.max_deviation ?? 0);
        cacheHits++;
      } else {
        const c = calibrateGoalsModel(market, maxGoals);
        lambdaHome = c.lambdaHome;
        lambdaAway = c.lambdaAway;
        maxDeviation = c.maxDeviation;
        await admin.from("goals_model_calibration").upsert({
          match_id: e.match_id,
          lambda_home: lambdaHome,
          lambda_away: lambdaAway,
          rmse: c.rmse,
          max_deviation: c.maxDeviation,
          used_totals: c.usedTotals,
          odds_signature: e.odds_signature,
          model_version: modelVersion,
          calibrated_at: new Date().toISOString(),
        }, { onConflict: "match_id" });
        calibrated++;
      }

      // 3. matrice.
      const matrix = buildScoreMatrix(lambdaHome, lambdaAway, maxGoals);

      // 4. dérivation par marché -> liste unifiée.
      const mk: Mk[] = [];

      // Double Chance (réf = DC directe depuis le 1X2 marché).
      const dc = deriveDoubleChance(matrix);
      mk.push({ code: "dc_1x", label: "Double Chance — 1X", fair: dc.dc1x, ref: p.home + p.draw });
      mk.push({ code: "dc_12", label: "Double Chance — 12", fair: dc.dc12, ref: p.home + p.away });
      mk.push({ code: "dc_x2", label: "Double Chance — X2", fair: dc.dcx2, ref: p.draw + p.away });

      // Totaux multi-lignes (réf = marché uniquement sur la ligne ingérée).
      for (const t of deriveTotals(matrix)) {
        const isMktLine = !!market.totals &&
          Math.abs(market.totals.line - t.line) < 1e-9;
        mk.push({
          code: totalCode(t.line, "over"),
          label: `Plus de ${t.line} buts`,
          fair: t.over,
          ref: isMktLine ? market.totals!.over : null,
        });
        mk.push({
          code: totalCode(t.line, "under"),
          label: `Moins de ${t.line} buts`,
          fair: t.under,
          ref: isMktLine ? market.totals!.under : null,
        });
      }

      // BTTS.
      const b = deriveBtts(matrix);
      mk.push({ code: "btts_yes", label: "Les deux marquent — Oui", fair: b.yes, ref: null });
      mk.push({ code: "btts_no", label: "Les deux marquent — Non", fair: b.no, ref: null });

      // Score exact (au-dessus d'un plancher de proba pour éviter le bruit).
      for (const s of deriveCorrectScore(matrix, 5, 0.01)) {
        mk.push({
          code: correctScoreCode(s.home, s.away),
          label: `Score exact ${s.home}-${s.away}`,
          fair: s.prob,
          ref: null,
        });
      }

      // Résultat + Total (ligne 2.5).
      const rt = deriveResultTotal(matrix, 2.5);
      const rtItems: [string, string, number][] = [
        [resultTotalCode("1", "o", 2.5), "Domicile & +2.5", rt.homeOver],
        [resultTotalCode("1", "u", 2.5), "Domicile & -2.5", rt.homeUnder],
        [resultTotalCode("x", "o", 2.5), "Nul & +2.5", rt.drawOver],
        [resultTotalCode("x", "u", 2.5), "Nul & -2.5", rt.drawUnder],
        [resultTotalCode("2", "o", 2.5), "Extérieur & +2.5", rt.awayOver],
        [resultTotalCode("2", "u", 2.5), "Extérieur & -2.5", rt.awayUnder],
      ];
      for (const [code, label, fair] of rtItems) {
        mk.push({ code, label, fair, ref: null });
      }

      // Handicap EUROPÉEN (classique, 3 issues) — pariable, pas de réf marché.
      for (const h of deriveEuropeanHandicap(matrix)) {
        const tag = h.handicap >= 0 ? `+${h.handicap}` : `${h.handicap}`;
        mk.push({ code: handicapCode("home", h.handicap), label: `Handicap Domicile ${tag} — 1`, fair: h.home, ref: null });
        mk.push({ code: handicapCode("draw", h.handicap), label: `Handicap Domicile ${tag} — N`, fair: h.draw, ref: null });
        mk.push({ code: handicapCode("away", h.handicap), label: `Handicap Domicile ${tag} — 2`, fair: h.away, ref: null });
      }

      // Handicap ASIATIQUE (2 issues) — RÉFÉRENCE marché (spread The Odds API),
      // uniquement sur ligne demi-entière (pas de push) pour une comparaison propre.
      if (
        e.ah_line != null && e.ah_home_odds != null && e.ah_away_odds != null &&
        isHalfLine(Number(e.ah_line))
      ) {
        const ah = deriveAsianHandicap(matrix, Number(e.ah_line));
        const invH = 1 / Number(e.ah_home_odds), invA = 1 / Number(e.ah_away_odds);
        const sum = invH + invA;
        const refHome = invH / sum, refAway = invA / sum; // 2-way marché sans marge
        const tag = Number(e.ah_line) >= 0 ? `+${e.ah_line}` : `${e.ah_line}`;
        mk.push({ code: "ah_home", label: `Handicap asiatique Dom ${tag}`, fair: ah.home, ref: refHome });
        mk.push({ code: "ah_away", label: `Handicap asiatique Ext`, fair: ah.away, ref: refAway });
      }

      // ── ÉTAPE 4 (confidence=medium, hypothèses supplémentaires) ──
      // Mi-temps (1N2 + Totaux), buts répartis par htSplit.
      const ht = deriveHalfTime(lambdaHome, lambdaAway, htSplit, maxGoals);
      mk.push({ code: "ht_home", label: "Mi-temps — 1", fair: ht.home, ref: null });
      mk.push({ code: "ht_draw", label: "Mi-temps — N", fair: ht.draw, ref: null });
      mk.push({ code: "ht_away", label: "Mi-temps — 2", fair: ht.away, ref: null });
      for (const t of ht.totals) {
        const lc = String(t.line).replace(".", "");
        mk.push({ code: `ht_over${lc}`, label: `Mi-temps +${t.line} buts`, fair: t.over, ref: null });
        mk.push({ code: `ht_under${lc}`, label: `Mi-temps -${t.line} buts`, fair: t.under, ref: null });
      }
      // (Premier buteur-équipe retiré : non réglable — aucune donnée « qui a
      //  marqué en premier » dans le pipeline de résultats.)

      // 5-6. garde-fou + lignes derived_markets (upsert GROUPÉ).
      const dbRows: Record<string, unknown>[] = [];
      for (const item of mk) {
        const fp = item.fair;
        if (!(fp > 0 && fp < 1)) continue;
        const fairOdds = 1 / fp;
        const refOdds = item.ref && item.ref > 0 ? 1 / item.ref : null;
        const deviation = refOdds ? Math.abs(fairOdds - refOdds) / refOdds : null;
        let tripped = false;
        let reason: string | null = null;
        if (deviation != null && deviation > guardThreshold) {
          tripped = true;
          reason = `ecart_ref ${(deviation * 100).toFixed(1)}%`;
        } else if (maxDeviation > guardThreshold) {
          tripped = true;
          reason = `calibration maxDev ${(maxDeviation * 100).toFixed(1)}%`;
        }
        if (tripped) guardTripped++;
        const offeredOdds = 1 / (fp * (1 + marginFor(item.code)));
        // Une cote offerte < 1.01 (issue quasi-certaine + marge) n'est pas un
        // pari valide -> on n'écrit pas ce marché.
        if (offeredOdds < 1.01) continue;
        dbRows.push({
          match_id: e.match_id,
          market_code: item.code,
          selection_label: item.label,
          fair_prob: fp,
          fair_odds: fairOdds,
          offered_odds: offeredOdds,
          reference_odds: refOdds,
          deviation,
          confidence: confidenceFor(item.code),
          origin: "derived",
          model_version: modelVersion,
          lambda_home: lambdaHome,
          lambda_away: lambdaAway,
          guard_tripped: tripped,
          guard_reason: reason,
          // is_active volontairement omis : fixé par le trigger BD
          // `_trg_derived_activation` (source unique = code marché).
          computed_at: new Date().toISOString(),
        });
      }
      if (dbRows.length > 0) {
        const { error: upErr } = await admin.from("derived_markets").upsert(
          dbRows,
          { onConflict: "match_id,market_code" },
        );
        if (!upErr) marketsWritten += dbRows.length;
      }
      processed++;
    } catch (_) { /* best-effort par match */ }
  }

  return json({
    ok: true,
    model_version: modelVersion,
    processed,
    calibrated,
    cache_hits: cacheHits,
    markets_written: marketsWritten,
    guard_tripped: guardTripped,
  });
});
