import { assert, assertClose } from "./test_util.ts";
import {
  buildScoreMatrix,
  matrix1x2,
  matrixOver,
  matrixUnder,
} from "./matrix.ts";

Deno.test("matrice renormalisée somme à 1", () => {
  const m = buildScoreMatrix(1.6, 1.2);
  let s = 0;
  for (const row of m.cells) for (const c of row) s += c;
  assertClose(s, 1, 1e-12);
});

Deno.test("λ égaux -> P(home) ≈ P(away)", () => {
  const m = buildScoreMatrix(1.3, 1.3);
  const r = matrix1x2(m);
  assertClose(r.home, r.away, 1e-12);
  assertClose(r.home + r.draw + r.away, 1, 1e-12);
});

Deno.test("over + under = 1 sur ligne demi-entière", () => {
  const m = buildScoreMatrix(1.5, 1.1);
  assertClose(matrixOver(m, 2.5) + matrixUnder(m, 2.5), 1, 1e-12);
});

Deno.test("over 0.5 = 1 - P(0-0)", () => {
  const m = buildScoreMatrix(1.4, 1.2);
  assertClose(matrixOver(m, 0.5), 1 - m.cells[0][0], 1e-12);
});

Deno.test("faible espérance -> majorité d'unders (cas limite)", () => {
  const m = buildScoreMatrix(0.4, 0.3);
  assert(matrixUnder(m, 2.5) > 0.85);
});

Deno.test("forte espérance -> majorité d'overs (cas limite)", () => {
  const m = buildScoreMatrix(2.8, 2.4);
  assert(matrixOver(m, 2.5) > 0.75);
});

Deno.test("gros favori -> P(home) très élevé (cas limite)", () => {
  const m = buildScoreMatrix(2.6, 0.4);
  const r = matrix1x2(m);
  assert(r.home > 0.8);
  assert(r.away < 0.06);
});
