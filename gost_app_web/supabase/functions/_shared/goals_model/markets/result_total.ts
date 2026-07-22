// ============================================================
// Goals Model — Marché : Résultat + Total (combo) (ÉTAPE 2)
// ============================================================
// Fonction pure : probabilité conjointe (résultat 1/N/2) ET (total >/< ligne),
// par somme des cellules filtrées sur les deux conditions.
// Confiance : HAUTE (dérivation directe).
//
// Les 6 issues (1&Over, 1&Under, N&Over, N&Under, 2&Over, 2&Under) sont
// mutuellement exclusives et exhaustives -> leur somme = 1.
// ============================================================

import type { ScoreMatrix } from "../types.ts";

export interface ResultTotalProbs {
  line: number;
  homeOver: number;
  homeUnder: number;
  drawOver: number;
  drawUnder: number;
  awayOver: number;
  awayUnder: number;
}

export function deriveResultTotal(
  m: ScoreMatrix,
  line = 2.5,
): ResultTotalProbs {
  let homeOver = 0, homeUnder = 0, drawOver = 0, drawUnder = 0, awayOver = 0,
    awayUnder = 0;
  for (let i = 0; i <= m.maxGoals; i++) {
    for (let j = 0; j <= m.maxGoals; j++) {
      const p = m.cells[i][j];
      const over = i + j > line;
      if (i > j) over ? (homeOver += p) : (homeUnder += p);
      else if (i === j) over ? (drawOver += p) : (drawUnder += p);
      else over ? (awayOver += p) : (awayUnder += p);
    }
  }
  return { line, homeOver, homeUnder, drawOver, drawUnder, awayOver, awayUnder };
}

/// Codes marché stables (ligne 2.5 -> "rt_1_o25", etc.).
export function resultTotalCode(
  result: "1" | "x" | "2",
  ou: "o" | "u",
  line: number,
): string {
  const l = String(line).replace(".", "");
  const r = result === "1" ? "1" : result === "2" ? "2" : "x";
  return `rt_${r}_${ou}${l}`;
}
