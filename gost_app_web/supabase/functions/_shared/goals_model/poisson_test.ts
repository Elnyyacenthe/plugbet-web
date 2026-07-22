import { assert, assertClose } from "./test_util.ts";
import { logFactorial, poissonPmf, poissonVector } from "./poisson.ts";

Deno.test("poisson pmf λ=1 (valeurs connues)", () => {
  const e1 = Math.exp(-1);
  assertClose(poissonPmf(1, 0), e1, 1e-12);
  assertClose(poissonPmf(1, 1), e1, 1e-12);
  assertClose(poissonPmf(1, 2), e1 / 2, 1e-12);
});

Deno.test("poisson λ=0 dégénéré", () => {
  assertClose(poissonPmf(0, 0), 1, 1e-15);
  assertClose(poissonPmf(0, 3), 0, 1e-15);
});

Deno.test("poissonVector somme ≈ 1 sur support large", () => {
  const v = poissonVector(2.5, 40);
  assertClose(v.reduce((a, b) => a + b, 0), 1, 1e-9);
});

Deno.test("logFactorial", () => {
  assertClose(logFactorial(0), 0, 1e-15);
  assertClose(logFactorial(5), Math.log(120), 1e-12);
});

Deno.test("poisson k non entier / négatif -> 0", () => {
  assert(poissonPmf(2, -1) === 0);
  assert(poissonPmf(2, 1.5) === 0);
});
