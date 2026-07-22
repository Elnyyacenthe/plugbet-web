import { assert, assertClose } from "./test_util.ts";
import { buildScoreMatrix, matrix1x2, matrixOver } from "./matrix.ts";
import { deriveHalfTime } from "./markets/half_time.ts";

// ── Mi-temps ──
Deno.test("mi-temps : 1X2 somme à 1", () => {
  const ht = deriveHalfTime(1.6, 1.2, 0.45);
  assertClose(ht.home + ht.draw + ht.away, 1, 1e-12);
});

Deno.test("mi-temps : Totaux over+under=1 par ligne", () => {
  const ht = deriveHalfTime(1.6, 1.2, 0.45);
  for (const t of ht.totals) assertClose(t.over + t.under, 1, 1e-12);
});

Deno.test("mi-temps : over 0.5 mi-temps < over 0.5 plein match (cohérence)", () => {
  const lh = 1.7, la = 1.3;
  const ht = deriveHalfTime(lh, la, 0.45);
  const full = buildScoreMatrix(lh, la);
  const htOver05 = ht.totals.find((t) => t.line === 0.5)!.over;
  assert(htOver05 < matrixOver(full, 0.5));
});

Deno.test("mi-temps : split=1 -> mi-temps == plein match (sanity)", () => {
  const lh = 1.5, la = 1.1;
  const ht = deriveHalfTime(lh, la, 1.0);
  const full = matrix1x2(buildScoreMatrix(lh, la));
  assertClose(ht.home, full.home, 1e-12);
  assertClose(ht.draw, full.draw, 1e-12);
  assertClose(ht.away, full.away, 1e-12);
});

Deno.test("mi-temps : plus de nuls qu'en plein match (moins de buts)", () => {
  const ht = deriveHalfTime(1.6, 1.2, 0.45);
  const full = matrix1x2(buildScoreMatrix(1.6, 1.2));
  assert(ht.draw > full.draw); // à la pause, le 0-0/nul est plus probable
});

// ── Premier buteur (équipe) ──




