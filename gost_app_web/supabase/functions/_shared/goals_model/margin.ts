// ============================================================
// Goals Model — Couche 1 : retrait de marge (overround)
// ============================================================
// Transforme des cotes décimales en probabilités implicites SANS marge.
// Méthode de départ : NORMALISATION PROPORTIONNELLE (la plus simple et
// robuste). La méthode de Shin (retrait de marge non uniforme, tenant compte
// du biais favori/outsider) pourra être ajoutée ici plus tard sans toucher le
// reste du moteur — d'où l'API `impliedProbs(odds, method)`.
// ============================================================

import type { OneX2Odds, TotalsOdds } from "./types.ts";

export type MarginMethod = "proportional";

/// Overround (marge brute) d'un jeu d'outcomes : Σ(1/cote) − 1.
/// > 0 en présence de marge bookmaker ; ≈ 0 pour un marché « fair ».
export function overround(odds: number[]): number {
  return odds.reduce((acc, o) => acc + 1 / o, 0) - 1;
}

/// Probabilités implicites SANS marge, par normalisation proportionnelle :
///   p_i = (1/cote_i) / Σ_j (1/cote_j)
/// Les cotes doivent être > 1. Lève si une cote est invalide.
export function impliedProbs(
  odds: number[],
  method: MarginMethod = "proportional",
): number[] {
  if (odds.length === 0) throw new Error("impliedProbs: aucune cote");
  for (const o of odds) {
    if (!Number.isFinite(o) || o <= 1) {
      throw new Error(`impliedProbs: cote invalide (${o}), doit être > 1`);
    }
  }
  switch (method) {
    case "proportional": {
      const raw = odds.map((o) => 1 / o);
      const s = raw.reduce((a, b) => a + b, 0);
      return raw.map((r) => r / s);
    }
    default:
      throw new Error(`impliedProbs: méthode inconnue ${method}`);
  }
}

/// Probabilités 1X2 sans marge (ordre : home, draw, away).
export function normalize1x2(
  o: OneX2Odds,
  method: MarginMethod = "proportional",
): { home: number; draw: number; away: number } {
  const [home, draw, away] = impliedProbs([o.home, o.draw, o.away], method);
  return { home, draw, away };
}

/// Probabilités Over/Under sans marge à la ligne donnée.
export function normalizeTotals(
  t: TotalsOdds,
  method: MarginMethod = "proportional",
): { line: number; over: number; under: number } {
  const [over, under] = impliedProbs([t.over, t.under], method);
  return { line: t.line, over, under };
}
