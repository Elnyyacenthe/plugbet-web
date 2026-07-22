// ============================================================
// Goals Model — Marché : Double Chance (ÉTAPE 1)
// ============================================================
// Fonction PURE prenant la matrice de scores en entrée. Le Double Chance se
// dérive directement du 1X2 modèle (somme de deux issues) :
//   1X = P(home) + P(draw)      (le domicile ne perd pas)
//   12 = P(home) + P(away)      (pas de nul)
//   X2 = P(draw) + P(away)      (l'extérieur ne perd pas)
//
// Équivalent à la formule « Phase A » 1/(1/cote_1 + 1/cote_X) une fois exprimé
// en cotes, mais ici on part des PROBABILITÉS modèle (issues de la matrice
// calibrée sur le marché sans marge) — donc cohérent et sans double marge.
//
// Confiance : HAUTE (dérivation directe, aucune hypothèse supplémentaire).
// La fonction renvoie des PROBABILITÉS « fair » (sans marge). L'application de
// la marge de sécurité et le passage en cotes offertes se font en aval
// (orchestrateur), selon la config de risque.
// ============================================================

import type { ScoreMatrix } from "../types.ts";
import { matrix1x2 } from "../matrix.ts";

export interface DoubleChanceProbs {
  /// P(domicile ou nul) — code marché "dc_1x".
  dc1x: number;
  /// P(domicile ou extérieur) — code marché "dc_12".
  dc12: number;
  /// P(nul ou extérieur) — code marché "dc_x2".
  dcx2: number;
}

/// Probabilités « fair » (sans marge) des trois Double Chance, dérivées de la
/// matrice de scores calibrée.
export function deriveDoubleChance(m: ScoreMatrix): DoubleChanceProbs {
  const { home, draw, away } = matrix1x2(m);
  return {
    dc1x: home + draw,
    dc12: home + away,
    dcx2: draw + away,
  };
}
