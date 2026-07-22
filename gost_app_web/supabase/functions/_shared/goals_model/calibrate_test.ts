import { assert, assertClose } from "./test_util.ts";
import { buildScoreMatrix, matrix1x2, matrixOver } from "./matrix.ts";
import { calibrateGoalsModel } from "./calibrate.ts";
import type { MarketProbs } from "./types.ts";

// Marché "parfait" généré depuis des λ connus : la calibration doit les
// retrouver (round-trip), c'est le test le plus important de la couche.
function marketFromLambdas(lh: number, la: number, line = 2.5): MarketProbs {
  const m = buildScoreMatrix(lh, la);
  const r = matrix1x2(m);
  const over = matrixOver(m, line);
  return {
    home: r.home,
    draw: r.draw,
    away: r.away,
    totals: { line, over, under: 1 - over },
  };
}

Deno.test("round-trip équilibré", () => {
  const c = calibrateGoalsModel(marketFromLambdas(1.5, 1.2));
  assertClose(c.lambdaHome, 1.5, 0.05);
  assertClose(c.lambdaAway, 1.2, 0.05);
  assert(c.rmse < 1e-3, `rmse=${c.rmse}`);
  assert(c.usedTotals);
});

Deno.test("round-trip gros favori domicile (cas limite déséquilibré)", () => {
  const c = calibrateGoalsModel(marketFromLambdas(2.6, 0.5));
  assertClose(c.lambdaHome, 2.6, 0.1);
  assertClose(c.lambdaAway, 0.5, 0.1);
});

Deno.test("round-trip gros favori extérieur (cas limite déséquilibré)", () => {
  const c = calibrateGoalsModel(marketFromLambdas(0.5, 2.4));
  assertClose(c.lambdaHome, 0.5, 0.1);
  assertClose(c.lambdaAway, 2.4, 0.1);
});

Deno.test("round-trip faible total (cas limite)", () => {
  const c = calibrateGoalsModel(marketFromLambdas(0.7, 0.6));
  assertClose(c.lambdaHome, 0.7, 0.08);
  assertClose(c.lambdaAway, 0.6, 0.08);
});

Deno.test("round-trip fort total (cas limite)", () => {
  const c = calibrateGoalsModel(marketFromLambdas(2.9, 2.3));
  assertClose(c.lambdaHome, 2.9, 0.15);
  assertClose(c.lambdaAway, 2.3, 0.15);
});

Deno.test("sans Totaux : ajuste le 1X2 seul", () => {
  const m = buildScoreMatrix(1.6, 1.1);
  const r = matrix1x2(m);
  const c = calibrateGoalsModel({ home: r.home, draw: r.draw, away: r.away });
  assert(!c.usedTotals);
  const mm = buildScoreMatrix(c.lambdaHome, c.lambdaAway);
  const rr = matrix1x2(mm);
  assertClose(rr.home, r.home, 5e-3);
  assertClose(rr.draw, r.draw, 5e-3);
});

Deno.test("cotes réelles plausibles -> écart maîtrisé", () => {
  // Favori net + total moyen (probas déjà sans marge).
  const c = calibrateGoalsModel({
    home: 0.62,
    draw: 0.24,
    away: 0.14,
    totals: { line: 2.5, over: 0.52, under: 0.48 },
  });
  // Poisson indépendant ne reproduit pas parfaitement l'inflation des nuls :
  // on tolère un petit écart, mais il doit rester borné.
  assert(c.maxDeviation < 0.05, `maxDev=${c.maxDeviation}`);
});
