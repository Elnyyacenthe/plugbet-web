// ============================================================
// Goals Model — Handicap ASIATIQUE (2 issues) — pour RÉFÉRENCE (ÉTAPE 3)
// ============================================================
// The Odds API fournit les « spreads » = handicap asiatique. On dérive donc le
// handicap asiatique du modèle pour le COMPARER à cette référence marché (comme
// on l'a fait pour les Totaux). Même mécanique de décalage que le handicap
// européen -> valider l'asiatique (avec référence) valide aussi la mécanique du
// handicap classique.
//
// Handicap `line` appliqué au DOMICILE (peut être demi-entier : -1.5, -0.5,
// +0.5 ...). Sur une ligne demi-entière il n'y a PAS de push -> home + away = 1.
// Sur une ligne entière, un push est possible (remboursement) : on l'expose
// séparément et l'appelant décide (pour la comparaison on n'utilise que les
// lignes demi-entières).
// ============================================================

import type { ScoreMatrix } from "../types.ts";

export interface AsianHandicapProbs {
  line: number;
  home: number; // P(domicile couvre)
  away: number; // P(extérieur couvre)
  push: number; // P(remboursement) — 0 sur ligne demi-entière
}

export function deriveAsianHandicap(
  m: ScoreMatrix,
  line: number,
): AsianHandicapProbs {
  let home = 0, away = 0, push = 0;
  for (let i = 0; i <= m.maxGoals; i++) {
    for (let j = 0; j <= m.maxGoals; j++) {
      const diff = i + line - j;
      const p = m.cells[i][j];
      if (diff > 0) home += p;
      else if (diff < 0) away += p;
      else push += p;
    }
  }
  return { line, home, away, push };
}

/// Ligne demi-entière (pas de push) ?
export function isHalfLine(line: number): boolean {
  return Math.abs(line * 2 - Math.round(line * 2)) < 1e-9 &&
    Math.abs(line - Math.round(line)) > 1e-9;
}
