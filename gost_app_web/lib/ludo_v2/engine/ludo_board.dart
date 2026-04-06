// ============================================================
// LUDO V2 — Board constants (15x15 grid, Ludo King layout)
// ============================================================

/// Couleurs des joueurs : 0=Red, 1=Green, 2=Blue, 3=Yellow
enum LudoColor { red, green, blue, yellow }

/// Constantes du plateau Ludo 15×15
///
/// Disposition :
///   Red    = haut-gauche  (base rows 0-5, cols 0-5)
///   Yellow = haut-droite  (base rows 0-5, cols 9-14)
///   Blue   = bas-droite   (base rows 9-14, cols 9-14)
///   Green  = bas-gauche   (base rows 9-14, cols 0-5)
///
/// Circuit de 52 cases, sens HORAIRE :
///   Red(0) → Yellow(13) → Blue(26) → Green(39) → boucle
class LudoBoard {
  LudoBoard._();

  static const int gridSize = 15;

  // ── Offsets de départ sur le circuit de 52 cases ────────
  // Ordre des couleurs : [Red, Green, Blue, Yellow]
  // Red=0, Yellow=13, Blue=26, Green=39
  static const List<int> startOffsets = [0, 39, 26, 13];

  // ── Cases sûres (absolues sur le circuit 0-51) ──────────
  // Cases de départ de chaque couleur + cases étoile milieu
  static const Set<int> safeCells = {0, 8, 13, 21, 26, 34, 39, 47};

  // ── Home bases (4 pions par joueur dans leur coin) ──────
  static const List<List<List<int>>> homeBases = [
    // 0=Red (haut-gauche)
    [[1, 1], [1, 4], [4, 1], [4, 4]],
    // 1=Green (bas-gauche)
    [[10, 1], [10, 4], [13, 1], [13, 4]],
    // 2=Blue (bas-droite)
    [[10, 10], [10, 13], [13, 10], [13, 13]],
    // 3=Yellow (haut-droite)
    [[1, 10], [1, 13], [4, 10], [4, 13]],
  ];

  // ── Circuit principal (52 cases, sens horaire) ──────────
  // Chaque case est [row, col]. Toutes les cases sont adjacentes.
  //
  // Red(0)→RIGHT sur row 6 → UP sur col 6 → RIGHT en haut →
  // Yellow(13)→DOWN sur col 8 → RIGHT sur row 6 → DOWN à droite →
  // Blue(26)→LEFT sur row 8 → DOWN sur col 8 → LEFT en bas →
  // Green(39)→UP sur col 6 → LEFT sur row 8 → UP à gauche → boucle
  static const List<List<int>> track = [
    // ═══ QUARTER 1 : Red start → Yellow start (indices 0-12) ═══
    // Red sort de sa base (haut-gauche), va RIGHT sur row 6
    [6, 1], [6, 2], [6, 3], [6, 4], [6, 5],        // 0-4
    // Tourne UP dans le bras supérieur, col 6
    [5, 6], [4, 6], [3, 6], [2, 6], [1, 6], [0, 6], // 5-10
    // Tourne RIGHT le long du bord supérieur
    [0, 7],                                           // 11
    [0, 8],                                           // 12

    // ═══ QUARTER 2 : Yellow start → Blue start (indices 13-25) ═══
    // Yellow sort de sa base (haut-droite), va DOWN sur col 8
    [1, 8], [2, 8], [3, 8], [4, 8], [5, 8],         // 13-17
    // Tourne RIGHT dans le bras droit, row 6
    [6, 9], [6, 10], [6, 11], [6, 12], [6, 13], [6, 14], // 18-23
    // Tourne DOWN le long du bord droit
    [7, 14],                                          // 24
    [8, 14],                                          // 25

    // ═══ QUARTER 3 : Blue start → Green start (indices 26-38) ═══
    // Blue sort de sa base (bas-droite), va LEFT sur row 8
    [8, 13], [8, 12], [8, 11], [8, 10], [8, 9],     // 26-30
    // Tourne DOWN dans le bras inférieur, col 8
    [9, 8], [10, 8], [11, 8], [12, 8], [13, 8], [14, 8], // 31-36
    // Tourne LEFT le long du bord inférieur
    [14, 7],                                          // 37
    [14, 6],                                          // 38

    // ═══ QUARTER 4 : Green start → Red loop (indices 39-51) ═══
    // Green sort de sa base (bas-gauche), va UP sur col 6
    [13, 6], [12, 6], [11, 6], [10, 6], [9, 6],     // 39-43
    // Tourne LEFT dans le bras gauche, row 8
    [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0], // 44-49
    // Tourne UP le long du bord gauche
    [7, 0],                                           // 50
    [6, 0],                                           // 51
    // → Ensuite c'est [6,1] = index 0, la boucle est fermée
  ];

  // ── Home stretches (6 cases vers le centre) ─────────────
  // Chaque joueur entre dans son couloir APRÈS avoir fait le tour complet.
  // Red entre après [6,0] (index 51) → tourne dans row 7 vers la droite
  // Green entre après [14,6] (index 38) → tourne dans col 7 vers le haut
  // Blue entre après [8,14] (index 25) → tourne dans row 7 vers la gauche
  // Yellow entre après [0,8] (index 12) → tourne dans col 7 vers le bas
  static const List<List<List<int>>> homeStretches = [
    // 0=Red : row 7, cols 1→6 (va vers le centre)
    [[7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6]],
    // 1=Green : col 7, rows 13→8 (va vers le centre)
    [[13, 7], [12, 7], [11, 7], [10, 7], [9, 7], [8, 7]],
    // 2=Blue : row 7, cols 13→8 (va vers le centre)
    [[7, 13], [7, 12], [7, 11], [7, 10], [7, 9], [7, 8]],
    // 3=Yellow : col 7, rows 1→6 (va vers le centre)
    [[1, 7], [2, 7], [3, 7], [4, 7], [5, 7], [6, 7]],
  ];

  // Centre du plateau (case finale "home")
  static const List<int> center = [7, 7];

  /// Convertit un step logique en position grille [row, col]
  /// step 0 = en base, 1-51 = sur le track (relatif), 52-57 = home stretch, 58 = arrivé (centre)
  static List<int> stepToGrid(int step, int colorIndex, {int pawnIndex = 0}) {
    if (step <= 0) return homeBases[colorIndex][pawnIndex];
    if (step >= 58) return center;

    // Home stretch (52-57) → 6 cases avant l'arrivée
    if (step >= 52) {
      final idx = step - 52; // 0..5
      return homeStretches[colorIndex][idx];
    }

    // Track principal (1-51) → position absolue sur le circuit
    final absPos = ((step - 1) + startOffsets[colorIndex]) % 52;
    return track[absPos];
  }

  /// Position absolue sur le circuit (0-51) depuis un step relatif
  static int toAbsolute(int relativeStep, int colorIndex) {
    if (relativeStep < 1 || relativeStep > 51) return -1;
    return ((relativeStep - 1) + startOffsets[colorIndex]) % 52;
  }

  /// Vérifie si une position absolue est une case sûre
  static bool isSafe(int absolutePos) => safeCells.contains(absolutePos);
}
