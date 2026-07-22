// ============================================================
// Goals Model — Marché : Handicap CLASSIQUE (européen, 3 issues) (ÉTAPE 3)
// ============================================================
// Fonction pure : on applique un handicap ENTIER au score DOMICILE
// (score_dom + handicap), puis on lit le 1X2 sur le score ajusté par simple
// décalage de la matrice. h négatif = domicile désavantagé (« Domicile -1 »),
// h positif = domicile avantagé (« Domicile +1 »).
//
// Confiance : HAUTE (dérivation directe, même mécanique que le 1X2).
// ============================================================

import type { ScoreMatrix } from "../types.ts";

export const DEFAULT_HANDICAPS = [-2, -1, 1, 2];

export interface HandicapResult {
  handicap: number;
  home: number;
  draw: number;
  away: number;
}

export function deriveEuropeanHandicap(
  m: ScoreMatrix,
  handicaps: number[] = DEFAULT_HANDICAPS,
): HandicapResult[] {
  return handicaps.map((h) => {
    let home = 0, draw = 0, away = 0;
    for (let i = 0; i <= m.maxGoals; i++) {
      for (let j = 0; j <= m.maxGoals; j++) {
        const adj = i + h;
        const p = m.cells[i][j];
        if (adj > j) home += p;
        else if (adj === j) draw += p;
        else away += p;
      }
    }
    return { handicap: h, home, draw, away };
  });
}

/// Code marché stable : handicap sur domicile. h=-1 -> "eh_home_m1" / "eh_draw_m1"
/// / "eh_away_m1" ; h=+1 -> "..._p1".
export function handicapCode(
  side: "home" | "draw" | "away",
  h: number,
): string {
  const s = h >= 0 ? `p${h}` : `m${-h}`;
  return `eh_${side}_${s}`;
}
