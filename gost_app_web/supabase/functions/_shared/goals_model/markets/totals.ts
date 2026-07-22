// ============================================================
// Goals Model — Marché : Totaux (Over/Under) multi-lignes (ÉTAPE 2)
// ============================================================
// Fonction pure sur la matrice. Permet de générer des lignes que The Odds API
// ne fournit pas (0.5 / 1.5 / 3.5 / 4.5 ...) en plus de la ligne principale.
// Confiance : HAUTE.
// ============================================================

import type { ScoreMatrix } from "../types.ts";
import { matrixOver, matrixUnder } from "../matrix.ts";

export const DEFAULT_TOTAL_LINES = [0.5, 1.5, 2.5, 3.5, 4.5];

export interface TotalsLineProbs {
  line: number;
  over: number;
  under: number;
}

/// Probabilités « fair » Over/Under pour chaque ligne demandée.
export function deriveTotals(
  m: ScoreMatrix,
  lines: number[] = DEFAULT_TOTAL_LINES,
): TotalsLineProbs[] {
  return lines.map((line) => ({
    line,
    over: matrixOver(m, line),
    under: matrixUnder(m, line),
  }));
}
