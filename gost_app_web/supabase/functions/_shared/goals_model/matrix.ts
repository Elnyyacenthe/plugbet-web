// ============================================================
// Goals Model — Couche 3 : matrice de scores exacts
// ============================================================
// À partir de (λ_dom, λ_ext), on construit la matrice P(i-j) sous l'hypothèse
// de DEUX Poisson INDÉPENDANTS (baseline standard) :
//   P(dom = i, ext = j) = Poisson(λ_dom; i) · Poisson(λ_ext; j)
//
// La matrice est TRONQUÉE à maxGoals buts par équipe puis RENORMALISÉE pour que
// Σ cells = 1 (absorbe la masse de queue perdue par la troncature). Avec
// maxGoals = 10 et des λ réalistes (< ~4), la masse tronquée est négligeable.
//
// Les fonctions de lecture (matrix1x2, matrixOver, …) sont PURES et servent à
// la fois à la calibration et aux marchés dérivés.
// ============================================================

import type { ScoreMatrix } from "./types.ts";
import { poissonVector } from "./poisson.ts";

export const DEFAULT_MAX_GOALS = 10;

/// Construit la matrice de scores exacts pour (λ_dom, λ_ext).
export function buildScoreMatrix(
  lambdaHome: number,
  lambdaAway: number,
  maxGoals: number = DEFAULT_MAX_GOALS,
  renormalize = true,
): ScoreMatrix {
  if (lambdaHome < 0 || lambdaAway < 0) {
    throw new Error("buildScoreMatrix: lambda négatif");
  }
  const ph = poissonVector(lambdaHome, maxGoals);
  const pa = poissonVector(lambdaAway, maxGoals);
  const cells: number[][] = ph.map((h) => pa.map((a) => h * a));

  if (renormalize) {
    let s = 0;
    for (const row of cells) for (const c of row) s += c;
    if (s > 0) {
      for (let i = 0; i < cells.length; i++) {
        for (let j = 0; j < cells[i].length; j++) cells[i][j] /= s;
      }
    }
  }
  return { maxGoals, lambdaHome, lambdaAway, cells };
}

/// Probabilités 1X2 dérivées de la matrice (home = i>j, draw = i==j, away = i<j).
export function matrix1x2(m: ScoreMatrix): {
  home: number;
  draw: number;
  away: number;
} {
  let home = 0, draw = 0, away = 0;
  for (let i = 0; i <= m.maxGoals; i++) {
    for (let j = 0; j <= m.maxGoals; j++) {
      const p = m.cells[i][j];
      if (i > j) home += p;
      else if (i === j) draw += p;
      else away += p;
    }
  }
  return { home, draw, away };
}

/// P(total de buts > line). `line` est une ligne bookmaker (souvent demi-
/// entière, ex. 2.5 -> i+j >= 3). Gère aussi les lignes entières (push exclu :
/// on renvoie strictement > line, cohérent avec matrixUnder pour un push).
export function matrixOver(m: ScoreMatrix, line: number): number {
  let p = 0;
  for (let i = 0; i <= m.maxGoals; i++) {
    for (let j = 0; j <= m.maxGoals; j++) {
      if (i + j > line) p += m.cells[i][j];
    }
  }
  return p;
}

/// P(total de buts < line). Pour une ligne demi-entière, over + under = 1.
export function matrixUnder(m: ScoreMatrix, line: number): number {
  let p = 0;
  for (let i = 0; i <= m.maxGoals; i++) {
    for (let j = 0; j <= m.maxGoals; j++) {
      if (i + j < line) p += m.cells[i][j];
    }
  }
  return p;
}
