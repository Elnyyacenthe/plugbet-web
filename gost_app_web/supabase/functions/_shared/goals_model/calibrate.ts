// ============================================================
// Goals Model — Couche 4 : calibration (λ_dom, λ_ext)
// ============================================================
// Problème d'OPTIMISATION NUMÉRIQUE (pas de formule directe) : on cherche
// (λ_dom, λ_ext) tels que les probabilités du MODÈLE (matrice de Poisson)
// reproduisent au mieux les probabilités du MARCHÉ (1X2 + Totaux, sans marge).
//
// - Cibles ajustées : P(home), P(draw), et P(over ligne) si Totaux fourni.
//   (away et under sont les compléments — pas des cibles indépendantes.)
// - Fonction objectif : somme des écarts quadratiques modèle vs marché.
// - Optimiseur : Nelder-Mead (sans dérivées), en variables log(λ) pour garantir
//   λ > 0, avec plusieurs points de départ (robustesse sur cotes déséquilibrées).
//
// Déterministe (pas d'aléatoire) : mêmes cotes -> même (λ_dom, λ_ext).
// ============================================================

import type { CalibrationResult, MarketProbs } from "./types.ts";
import { buildScoreMatrix, matrix1x2, matrixOver } from "./matrix.ts";

const LAMBDA_MIN = 0.02;
const LAMBDA_MAX = 8;

function clampLambda(x: number): number {
  return Math.min(Math.max(x, LAMBDA_MIN), LAMBDA_MAX);
}

/// Écarts modèle vs marché pour un couple (λ_dom, λ_ext).
function residuals(
  lambdaHome: number,
  lambdaAway: number,
  market: MarketProbs,
  maxGoals: number,
): number[] {
  const m = buildScoreMatrix(lambdaHome, lambdaAway, maxGoals);
  const r = matrix1x2(m);
  const errs = [r.home - market.home, r.draw - market.draw];
  if (market.totals) {
    errs.push(matrixOver(m, market.totals.line) - market.totals.over);
  }
  return errs;
}

function objective(
  x: number[],
  market: MarketProbs,
  maxGoals: number,
): number {
  const lh = clampLambda(Math.exp(x[0]));
  const la = clampLambda(Math.exp(x[1]));
  const errs = residuals(lh, la, market, maxGoals);
  return errs.reduce((acc, e) => acc + e * e, 0);
}

/// Nelder-Mead 2D minimal (simplex). Retourne le meilleur point trouvé.
function nelderMead(
  f: (x: number[]) => number,
  x0: number[],
  opts: { maxIter?: number; tol?: number } = {},
): { x: number[]; fx: number; iters: number } {
  const maxIter = opts.maxIter ?? 400;
  const tol = opts.tol ?? 1e-10;
  const alpha = 1, gamma = 2, rho = 0.5, sigma = 0.5;
  const step = 0.5;

  // Simplex initial : x0 + perturbations sur chaque axe.
  let simplex = [x0.slice(), [x0[0] + step, x0[1]], [x0[0], x0[1] + step]];
  let fvals = simplex.map(f);
  let iters = 0;

  for (; iters < maxIter; iters++) {
    // Trie par valeur croissante.
    const order = [0, 1, 2].sort((a, b) => fvals[a] - fvals[b]);
    simplex = order.map((i) => simplex[i]);
    fvals = order.map((i) => fvals[i]);

    if (Math.abs(fvals[2] - fvals[0]) < tol) break;

    // Centroïde des 2 meilleurs.
    const c = [
      (simplex[0][0] + simplex[1][0]) / 2,
      (simplex[0][1] + simplex[1][1]) / 2,
    ];
    // Réflexion.
    const xr = [c[0] + alpha * (c[0] - simplex[2][0]),
      c[1] + alpha * (c[1] - simplex[2][1])];
    const fr = f(xr);

    if (fr < fvals[0]) {
      // Expansion.
      const xe = [c[0] + gamma * (xr[0] - c[0]), c[1] + gamma * (xr[1] - c[1])];
      const fe = f(xe);
      if (fe < fr) { simplex[2] = xe; fvals[2] = fe; }
      else { simplex[2] = xr; fvals[2] = fr; }
    } else if (fr < fvals[1]) {
      simplex[2] = xr; fvals[2] = fr;
    } else {
      // Contraction.
      const xc = [c[0] + rho * (simplex[2][0] - c[0]),
        c[1] + rho * (simplex[2][1] - c[1])];
      const fc = f(xc);
      if (fc < fvals[2]) { simplex[2] = xc; fvals[2] = fc; }
      else {
        // Rétrécissement vers le meilleur.
        for (let i = 1; i < 3; i++) {
          simplex[i] = [
            simplex[0][0] + sigma * (simplex[i][0] - simplex[0][0]),
            simplex[0][1] + sigma * (simplex[i][1] - simplex[0][1]),
          ];
          fvals[i] = f(simplex[i]);
        }
      }
    }
  }
  // Meilleur sommet.
  let bi = 0;
  for (let i = 1; i < 3; i++) if (fvals[i] < fvals[bi]) bi = i;
  return { x: simplex[bi], fx: fvals[bi], iters };
}

/// Calibre (λ_dom, λ_ext) à partir des probabilités de marché sans marge.
/// Multistart pour éviter les minima locaux sur cotes très déséquilibrées.
export function calibrateGoalsModel(
  market: MarketProbs,
  maxGoals = 10,
): CalibrationResult {
  const f = (x: number[]) => objective(x, market, maxGoals);

  // Points de départ (log λ) couvrant favori dom / favori ext / équilibré.
  const starts: number[][] = [
    [Math.log(1.4), Math.log(1.1)],
    [Math.log(1.1), Math.log(1.1)],
    [Math.log(2.0), Math.log(0.7)],
    [Math.log(0.7), Math.log(2.0)],
    [Math.log(1.8), Math.log(1.4)],
    [Math.log(0.9), Math.log(0.9)],
  ];

  let best: { x: number[]; fx: number; iters: number } | null = null;
  let totalIters = 0;
  for (const s of starts) {
    const res = nelderMead(f, s);
    totalIters += res.iters;
    if (best === null || res.fx < best.fx) best = res;
  }

  const lambdaHome = clampLambda(Math.exp(best!.x[0]));
  const lambdaAway = clampLambda(Math.exp(best!.x[1]));
  const errs = residuals(lambdaHome, lambdaAway, market, maxGoals);
  const rmse = Math.sqrt(errs.reduce((a, e) => a + e * e, 0) / errs.length);
  const maxDeviation = errs.reduce((mx, e) => Math.max(mx, Math.abs(e)), 0);

  return {
    lambdaHome,
    lambdaAway,
    rmse,
    maxDeviation,
    iterations: totalIters,
    usedTotals: !!market.totals,
  };
}
