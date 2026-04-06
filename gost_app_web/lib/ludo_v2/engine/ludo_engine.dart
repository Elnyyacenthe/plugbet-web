// ============================================================
// LUDO V2 — Game Engine (logique pure, pas de dépendance UI)
// ============================================================

import 'ludo_board.dart';

/// Résultat d'une évaluation de coup possible
class PawnMove {
  final int pawnIndex;
  final int fromStep;
  final int toStep;
  final bool isExit;     // Sortie de base
  final bool isCapture;  // Capture possible (pas garanti côté client)
  final bool isHome;     // Arrivée au centre

  const PawnMove({
    required this.pawnIndex,
    required this.fromStep,
    required this.toStep,
    this.isExit = false,
    this.isCapture = false,
    this.isHome = false,
  });
}

/// Moteur de jeu Ludo (logique pure côté client pour l'UI)
/// Les décisions finales sont prises côté serveur (RPC)
class LudoEngine {
  LudoEngine._();

  /// Calcule tous les coups possibles pour un joueur
  static List<PawnMove> getPlayableMoves({
    required List<int> myPawns,       // [step0, step1, step2, step3]
    required int dice,
    required int myColor,
    required Map<String, List<int>> allPawns,
    required Map<String, int> colorMap,
    required String myId,
  }) {
    final moves = <PawnMove>[];

    for (int i = 0; i < 4; i++) {
      final step = myPawns[i];

      // Pion en base → besoin d'un 6
      if (step == 0) {
        if (dice == 6) {
          moves.add(PawnMove(
            pawnIndex: i,
            fromStep: 0,
            toStep: 1,
            isExit: true,
          ));
        }
        continue;
      }

      // Pion déjà arrivé
      if (step >= 58) continue;

      final newStep = step + dice;

      // Dépassement → pas jouable (score exact requis)
      if (newStep > 58) continue;

      // Vérifier capture potentielle
      bool possibleCapture = false;
      if (newStep >= 1 && newStep <= 51) {
        final myAbs = LudoBoard.toAbsolute(newStep, myColor);
        if (!LudoBoard.isSafe(myAbs)) {
          possibleCapture = _wouldCapture(myAbs, myId, allPawns, colorMap);
        }
      }

      moves.add(PawnMove(
        pawnIndex: i,
        fromStep: step,
        toStep: newStep,
        isCapture: possibleCapture,
        isHome: newStep == 58,
      ));
    }

    return moves;
  }

  /// Vérifie si un mouvement vers une position absolue capturerait un adversaire
  static bool _wouldCapture(
    int absPos,
    String myId,
    Map<String, List<int>> allPawns,
    Map<String, int> colorMap,
  ) {
    for (final entry in allPawns.entries) {
      if (entry.key == myId) continue;
      final oppColor = colorMap[entry.key] ?? 0;
      for (final oppStep in entry.value) {
        if (oppStep >= 1 && oppStep <= 51) {
          final oppAbs = LudoBoard.toAbsolute(oppStep, oppColor);
          if (oppAbs == absPos) return true;
        }
      }
    }
    return false;
  }

  /// Vérifie si un joueur peut jouer (au moins un coup possible)
  static bool canPlay({
    required List<int> myPawns,
    required int dice,
    required int myColor,
    required Map<String, List<int>> allPawns,
    required Map<String, int> colorMap,
    required String myId,
  }) {
    return getPlayableMoves(
      myPawns: myPawns,
      dice: dice,
      myColor: myColor,
      allPawns: allPawns,
      colorMap: colorMap,
      myId: myId,
    ).isNotEmpty;
  }

  /// Vérifie si un joueur a gagné (tous les pions >= 58)
  static bool hasWon(List<int> pawns) {
    return pawns.every((s) => s >= 58);
  }

  /// Calcule le chemin animé entre deux steps (waypoints intermédiaires)
  static List<List<int>> buildPath(int fromStep, int toStep, int colorIndex) {
    final path = <List<int>>[];
    if (fromStep == 0 && toStep == 1) {
      // Sortie de base → directement à la case de départ
      path.add(LudoBoard.stepToGrid(1, colorIndex));
      return path;
    }

    final start = fromStep < 1 ? 1 : fromStep;
    for (int s = start + 1; s <= toStep; s++) {
      path.add(LudoBoard.stepToGrid(s, colorIndex));
    }
    return path;
  }

  /// Calcule le pourcentage de progression d'un joueur (0.0 - 1.0)
  static double progress(List<int> pawns) {
    // Max = 58 * 4 = 232
    final total = pawns.fold<int>(0, (sum, s) => sum + (s >= 58 ? 58 : s));
    return total / 232;
  }
}
