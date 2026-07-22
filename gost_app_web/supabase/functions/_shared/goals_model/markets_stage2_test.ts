import { assert, assertClose } from "./test_util.ts";
import { buildScoreMatrix, matrix1x2, matrixOver } from "./matrix.ts";
import { deriveTotals } from "./markets/totals.ts";
import { deriveBtts } from "./markets/btts.ts";
import {
  correctScoreCode,
  deriveCorrectScore,
} from "./markets/correct_score.ts";
import { deriveResultTotal, resultTotalCode } from "./markets/result_total.ts";

// ── Totaux ──
Deno.test("totaux : over+under=1 par ligne", () => {
  const m = buildScoreMatrix(1.6, 1.1);
  for (const t of deriveTotals(m)) assertClose(t.over + t.under, 1, 1e-12);
});

Deno.test("totaux : over décroît quand la ligne monte (monotonie)", () => {
  const m = buildScoreMatrix(1.7, 1.3);
  const lines = deriveTotals(m);
  for (let i = 1; i < lines.length; i++) {
    assert(lines[i].over <= lines[i - 1].over);
  }
});

Deno.test("totaux : over 0.5 = 1 - P(0-0)", () => {
  const m = buildScoreMatrix(1.4, 1.2);
  const t = deriveTotals(m, [0.5])[0];
  assertClose(t.over, 1 - m.cells[0][0], 1e-12);
});

// ── BTTS ──
Deno.test("btts : yes+no=1", () => {
  const m = buildScoreMatrix(1.5, 1.2);
  const b = deriveBtts(m);
  assertClose(b.yes + b.no, 1, 1e-12);
});

Deno.test("btts : faible espérance -> yes faible ; forte -> yes élevé", () => {
  assert(deriveBtts(buildScoreMatrix(0.4, 0.3)).yes < 0.2);
  assert(deriveBtts(buildScoreMatrix(2.2, 2.0)).yes > 0.7);
});

// ── Score exact ──
Deno.test("score exact : somme sur toute la grille ≈ 1", () => {
  const m = buildScoreMatrix(1.5, 1.2);
  const scores = deriveCorrectScore(m, m.maxGoals);
  assertClose(scores.reduce((a, s) => a + s.prob, 0), 1, 1e-9);
});

Deno.test("score exact : trié par proba décroissante + plancher", () => {
  const m = buildScoreMatrix(1.3, 1.1);
  const scores = deriveCorrectScore(m, 5, 0.01);
  for (let i = 1; i < scores.length; i++) {
    assert(scores[i].prob <= scores[i - 1].prob);
    assert(scores[i].prob >= 0.01);
  }
  assertClose(0, 0); // marqueur
  assert(correctScoreCode(2, 1) === "cs_2_1");
});

// ── Résultat + Total ──
Deno.test("résultat+total : les 6 issues somment à 1", () => {
  const m = buildScoreMatrix(1.7, 1.0);
  const r = deriveResultTotal(m, 2.5);
  const s = r.homeOver + r.homeUnder + r.drawOver + r.drawUnder + r.awayOver +
    r.awayUnder;
  assertClose(s, 1, 1e-12);
});

Deno.test("résultat+total : cohérent avec 1X2 et Totaux", () => {
  const m = buildScoreMatrix(1.6, 1.2);
  const r = deriveResultTotal(m, 2.5);
  const x = matrix1x2(m);
  assertClose(r.homeOver + r.homeUnder, x.home, 1e-12);
  assertClose(r.drawOver + r.drawUnder, x.draw, 1e-12);
  assertClose(r.awayOver + r.awayUnder, x.away, 1e-12);
  // La somme des "Over" par résultat = P(Over 2.5) global.
  assertClose(r.homeOver + r.drawOver + r.awayOver, matrixOver(m, 2.5), 1e-12);
});

Deno.test("résultat+total : codes marché stables", () => {
  assert(resultTotalCode("1", "o", 2.5) === "rt_1_o25");
  assert(resultTotalCode("2", "u", 2.5) === "rt_2_u25");
  assert(resultTotalCode("x", "o", 2.5) === "rt_x_o25");
});
