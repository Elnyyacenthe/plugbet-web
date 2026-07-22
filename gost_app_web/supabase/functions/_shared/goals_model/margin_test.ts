import { assert, assertClose, assertThrows } from "./test_util.ts";
import {
  impliedProbs,
  normalize1x2,
  normalizeTotals,
  overround,
} from "./margin.ts";

Deno.test("proportional : somme à 1", () => {
  const p = impliedProbs([2.0, 3.5, 4.0]);
  assertClose(p.reduce((a, b) => a + b, 0), 1, 1e-12);
});

Deno.test("overround > 0 sur marché avec marge", () => {
  assert(overround([2.0, 3.5, 4.0]) > 0);
});

Deno.test("overround ≈ 0 sur marché fair", () => {
  // 1/2 + 1/4 + 1/4 = 1
  assertClose(overround([2, 4, 4]), 0, 1e-12);
});

Deno.test("normalize1x2 : somme 1 + ordre conservé", () => {
  const r = normalize1x2({ home: 1.8, draw: 3.6, away: 4.5 });
  assertClose(r.home + r.draw + r.away, 1, 1e-12);
  assert(r.home > r.away);
});

Deno.test("normalizeTotals : over + under = 1", () => {
  const t = normalizeTotals({ line: 2.5, over: 1.9, under: 1.95 });
  assertClose(t.over + t.under, 1, 1e-12);
  assertClose(t.line, 2.5, 1e-15);
});

Deno.test("cote invalide (<= 1) lève", () => {
  assertThrows(() => impliedProbs([1.0, 2, 3]));
  assertThrows(() => impliedProbs([0.5, 2, 3]));
  assertThrows(() => impliedProbs([]));
});
