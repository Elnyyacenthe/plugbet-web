// ============================================================
// Goals Model — Marché : Score exact (ÉTAPE 2)
// ============================================================
// Fonction pure : chaque cellule de la matrice EST la probabilité du score
// correspondant. On renvoie les scores i-j (0..maxScore) au-dessus d'un
// plancher de probabilité (évite d'écrire des scores improbables), triés
// par probabilité décroissante.
// Confiance : HAUTE (dérivation directe).
// ============================================================

import type { ScoreMatrix } from "../types.ts";

export interface ScoreProb {
  home: number;
  away: number;
  prob: number;
}

export const DEFAULT_MAX_SCORE = 5;

export function deriveCorrectScore(
  m: ScoreMatrix,
  maxScore: number = DEFAULT_MAX_SCORE,
  floor = 0,
): ScoreProb[] {
  const out: ScoreProb[] = [];
  const cap = Math.min(maxScore, m.maxGoals);
  for (let i = 0; i <= cap; i++) {
    for (let j = 0; j <= cap; j++) {
      const p = m.cells[i][j];
      if (p >= floor) out.push({ home: i, away: j, prob: p });
    }
  }
  out.sort((a, b) => b.prob - a.prob);
  return out;
}

/// Code marché stable pour un score exact (ex. 2-1 -> "cs_2_1").
export function correctScoreCode(home: number, away: number): string {
  return `cs_${home}_${away}`;
}
