import { assert, assertClose } from "./test_util.ts";
import { buildScoreMatrix, matrix1x2 } from "./matrix.ts";
import {
  deriveEuropeanHandicap,
  handicapCode,
} from "./markets/handicap.ts";
import {
  deriveAsianHandicap,
  isHalfLine,
} from "./markets/asian_handicap.ts";

// ── Handicap européen (3 issues) ──
Deno.test("handicap européen : chaque ligne somme à 1", () => {
  const m = buildScoreMatrix(1.6, 1.2);
  for (const h of deriveEuropeanHandicap(m)) {
    assertClose(h.home + h.draw + h.away, 1, 1e-12);
  }
});

Deno.test("handicap 0 (implicite) = 1X2 brut", () => {
  const m = buildScoreMatrix(1.5, 1.1);
  const [h0] = deriveEuropeanHandicap(m, [0]);
  const x = matrix1x2(m);
  assertClose(h0.home, x.home, 1e-12);
  assertClose(h0.draw, x.draw, 1e-12);
  assertClose(h0.away, x.away, 1e-12);
});

Deno.test("handicap -1 domicile réduit P(home) vs 1X2 ; +1 l'augmente", () => {
  const m = buildScoreMatrix(1.7, 1.1);
  const x = matrix1x2(m);
  const [hm1] = deriveEuropeanHandicap(m, [-1]);
  const [hp1] = deriveEuropeanHandicap(m, [1]);
  assert(hm1.home < x.home); // domicile -1 : plus dur de gagner
  assert(hp1.home > x.home); // domicile +1 : plus facile
});

Deno.test("handicap : symétrie dom -h ≈ 1X2 avec équipes échangées", () => {
  // Domicile -1 : P(home) = P(dom gagne d'au moins 2 buts).
  const m = buildScoreMatrix(2.0, 1.0);
  const [hm1] = deriveEuropeanHandicap(m, [-1]);
  // recompute directement : somme cells i-1>j
  let manual = 0;
  for (let i = 0; i <= m.maxGoals; i++) {
    for (let j = 0; j <= m.maxGoals; j++) if (i - 1 > j) manual += m.cells[i][j];
  }
  assertClose(hm1.home, manual, 1e-12);
});

Deno.test("codes handicap stables", () => {
  assert(handicapCode("home", -1) === "eh_home_m1");
  assert(handicapCode("away", 2) === "eh_away_p2");
  assert(handicapCode("draw", -2) === "eh_draw_m2");
});

// ── Handicap asiatique (2 issues, référence) ──
Deno.test("asiatique ligne demi-entière : home+away=1, pas de push", () => {
  const m = buildScoreMatrix(1.6, 1.3);
  const ah = deriveAsianHandicap(m, -1.5);
  assertClose(ah.push, 0, 1e-12);
  assertClose(ah.home + ah.away, 1, 1e-12);
});

Deno.test("asiatique -0.5 = 1X2 (home = P(home win))", () => {
  const m = buildScoreMatrix(1.4, 1.2);
  const ah = deriveAsianHandicap(m, -0.5);
  const x = matrix1x2(m);
  assertClose(ah.home, x.home, 1e-12); // dom couvre -0.5 <=> dom gagne
  assertClose(ah.away, x.draw + x.away, 1e-12);
});

Deno.test("asiatique ligne entière : push = P(écart == -line)", () => {
  const m = buildScoreMatrix(1.8, 1.0);
  const ah = deriveAsianHandicap(m, -1);
  // push = P(dom gagne exactement de 1 but)
  let pushManual = 0;
  for (let i = 0; i <= m.maxGoals; i++) {
    for (let j = 0; j <= m.maxGoals; j++) if (i - 1 === j) pushManual += m.cells[i][j];
  }
  assertClose(ah.push, pushManual, 1e-12);
  assertClose(ah.home + ah.away + ah.push, 1, 1e-12);
});

Deno.test("isHalfLine", () => {
  assert(isHalfLine(-1.5) && isHalfLine(-0.5) && isHalfLine(0.5));
  assert(!isHalfLine(-1) && !isHalfLine(0) && !isHalfLine(2));
});
