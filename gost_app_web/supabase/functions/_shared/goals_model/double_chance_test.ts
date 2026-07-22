import { assert, assertClose } from "./test_util.ts";
import { buildScoreMatrix, matrix1x2 } from "./matrix.ts";
import { deriveDoubleChance } from "./markets/double_chance.ts";

Deno.test("DC = compléments du 1X2", () => {
  const m = buildScoreMatrix(1.7, 1.0);
  const r = matrix1x2(m);
  const dc = deriveDoubleChance(m);
  assertClose(dc.dc1x, 1 - r.away, 1e-12); // domicile ou nul = pas de défaite dom
  assertClose(dc.dc12, 1 - r.draw, 1e-12); // pas de nul
  assertClose(dc.dcx2, 1 - r.home, 1e-12); // nul ou extérieur
});

Deno.test("chaque DC dans ]0,1[ et > la proba simple correspondante", () => {
  const m = buildScoreMatrix(1.4, 1.3);
  const r = matrix1x2(m);
  const dc = deriveDoubleChance(m);
  for (const v of [dc.dc1x, dc.dc12, dc.dcx2]) assert(v > 0 && v < 1);
  assert(dc.dc1x > r.home && dc.dc1x > r.draw);
});

Deno.test("somme des 3 DC = 2", () => {
  const m = buildScoreMatrix(1.9, 0.8);
  const dc = deriveDoubleChance(m);
  assertClose(dc.dc1x + dc.dc12 + dc.dcx2, 2, 1e-12);
});
