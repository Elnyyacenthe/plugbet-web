// ============================================================
// Goals Model — Types partagés
// ============================================================
// Moteur de dérivation de marchés football à partir des seules cotes de base
// (1X2 + Totaux) fournies par The Odds API, par modélisation Poisson.
//
// Couches (toutes testables indépendamment) :
//   1. margin.ts     — retrait de marge (overround) -> probas implicites
//   2. poisson.ts    — pmf Poisson (log-espace)
//   3. matrix.ts     — matrice de scores exacts P(i-j) à partir de (λ_dom, λ_ext)
//   4. calibrate.ts  — calibration (λ_dom, λ_ext) par optimisation numérique
//   5. markets/*.ts  — dérivation par marché (fonctions PURES sur la matrice)
//
// Aucune de ces couches ne fait d'I/O : elles sont pures et déterministes.
// ============================================================

/// Cotes décimales 1X2 (Résultat final).
export interface OneX2Odds {
  home: number;
  draw: number;
  away: number;
}

/// Cotes décimales Totaux (Over/Under) à une ligne donnée (ex. 2.5).
export interface TotalsOdds {
  line: number;
  over: number;
  under: number;
}

/// Probabilités de marché SANS marge (normalisées), obtenues après retrait de
/// l'overround. `totals` est optionnel : The Odds API ne fournit pas toujours
/// une ligne Totaux.
export interface MarketProbs {
  home: number;
  draw: number;
  away: number;
  totals?: { line: number; over: number; under: number };
}

/// Matrice de probabilités de score exact.
/// cells[i][j] = P(domicile marque i, extérieur marque j).
export interface ScoreMatrix {
  maxGoals: number;
  lambdaHome: number;
  lambdaAway: number;
  cells: number[][];
}

/// Résultat d'une calibration (λ_dom, λ_ext) + diagnostics de qualité.
export interface CalibrationResult {
  lambdaHome: number;
  lambdaAway: number;
  /// Racine de l'erreur quadratique moyenne sur les cibles ajustées.
  rmse: number;
  /// Écart absolu MAX entre proba modèle et proba marché (sert au garde-fou).
  maxDeviation: number;
  iterations: number;
  /// Cibles utilisées : true si la ligne Totaux a pu être ajustée aussi.
  usedTotals: boolean;
}
