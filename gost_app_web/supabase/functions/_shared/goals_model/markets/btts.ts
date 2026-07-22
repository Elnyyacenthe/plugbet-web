// ============================================================
// Goals Model — Marché : BTTS (les deux équipes marquent) (ÉTAPE 2)
// ============================================================
// Fonction pure : BTTS oui = somme des cellules où i>=1 ET j>=1.
// Confiance : HAUTE (dérivation directe de la matrice).
// ============================================================

import type { ScoreMatrix } from "../types.ts";

export interface BttsProbs {
  yes: number;
  no: number;
}

export function deriveBtts(m: ScoreMatrix): BttsProbs {
  let yes = 0;
  for (let i = 1; i <= m.maxGoals; i++) {
    for (let j = 1; j <= m.maxGoals; j++) yes += m.cells[i][j];
  }
  return { yes, no: 1 - yes };
}
