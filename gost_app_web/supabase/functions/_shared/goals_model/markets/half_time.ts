// ============================================================
// Goals Model — Marché : Mi-temps (1N2 + Totaux) (ÉTAPE 4, confidence=medium)
// ============================================================
// HYPOTHÈSE SUPPLÉMENTAIRE (pas déductible des cotes de base) : on répartit les
// buts attendus du match entre 1re et 2e mi-temps par une proportion FIXE
// `splitFirst` (~0.44 empirique : ~44 % des buts en 1re période). On construit
// une matrice de score « mi-temps » à partir de (λ_dom·split, λ_ext·split) puis
// on en dérive le 1X2 et les Totaux de la mi-temps.
//
// C'est une APPROXIMATION (indépendance des périodes, taux réduit uniforme) —
// d'où confidence='medium' et une marge de sécurité plus élevée. AUCUNE
// référence marché (The Odds API ne fournit pas la mi-temps).
// ============================================================

import type { ScoreMatrix } from "../types.ts";
import {
  buildScoreMatrix,
  matrix1x2,
  matrixOver,
  matrixUnder,
} from "../matrix.ts";

export const DEFAULT_HT_TOTAL_LINES = [0.5, 1.5];

export interface HalfTimeProbs {
  home: number;
  draw: number;
  away: number;
  totals: { line: number; over: number; under: number }[];
  matrix: ScoreMatrix;
}

export function deriveHalfTime(
  lambdaHome: number,
  lambdaAway: number,
  splitFirst: number,
  maxGoals = 10,
  lines: number[] = DEFAULT_HT_TOTAL_LINES,
): HalfTimeProbs {
  const m = buildScoreMatrix(
    lambdaHome * splitFirst,
    lambdaAway * splitFirst,
    maxGoals,
  );
  const x = matrix1x2(m);
  const totals = lines.map((line) => ({
    line,
    over: matrixOver(m, line),
    under: matrixUnder(m, line),
  }));
  return { home: x.home, draw: x.draw, away: x.away, totals, matrix: m };
}
