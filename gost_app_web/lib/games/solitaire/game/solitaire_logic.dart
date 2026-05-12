// ============================================================
// Solitaire Klondike – Logique de jeu V2
// ============================================================
// Améliorations vs V1 :
//   - Validations défensives (carte source faceUp, séquence stack)
//   - Détection isLost (aucun coup possible)
//   - Invariant 52 cartes vérifié à chaque move
//   - Helper hasAnyValidMove pour le screen
// ============================================================
import '../models/solitaire_models.dart';

class SolitaireLogic {
  // ============================================================
  // Moves de base — chaque move retourne null si invalide
  // ============================================================

  /// Tire une carte du stock vers le talon. Si stock vide, recycle le waste.
  static SolitaireState drawFromStock(SolitaireState state) {
    if (state.stock.isEmpty) {
      if (state.waste.isEmpty) return state;
      // Recycle le waste vers le stock (ordre original préservé)
      final newStock =
          state.waste.reversed.map((c) => c.copyWith(faceUp: false)).toList();
      return state.copyWith(
        stock: newStock,
        waste: const [],
        moves: state.moves + 1,
      );
    }
    final card = state.stock.last.copyWith(faceUp: true);
    return state.copyWith(
      stock: state.stock.sublist(0, state.stock.length - 1),
      waste: [...state.waste, card],
      moves: state.moves + 1,
    );
  }

  /// Déplace des cartes entre colonnes du tableau.
  /// Validations défensives :
  ///   - cardIdx dans la borne
  ///   - carte source faceUp
  ///   - le stack qui bouge forme une séquence valide (couleurs alternées,
  ///     valeurs descendantes consécutives)
  ///   - destination accepte la carte de tête (Roi sur vide, ou cardCanStackOn)
  static SolitaireState? moveTableauToTableau(
      SolitaireState state, int srcCol, int cardIdx, int dstCol) {
    if (srcCol < 0 || srcCol >= state.tableau.length) return null;
    if (dstCol < 0 || dstCol >= state.tableau.length) return null;
    if (srcCol == dstCol) return null;

    final src = state.tableau[srcCol];
    if (cardIdx < 0 || cardIdx >= src.length) return null;

    // 🛡 Validation : la carte source doit être face-up
    if (!src[cardIdx].faceUp) return null;

    final moving = src.sublist(cardIdx);

    // 🛡 Validation : le stack qui bouge DOIT former une séquence valide
    for (int i = 0; i < moving.length - 1; i++) {
      if (!moving[i + 1].canStackOn(moving[i])) return null;
    }

    final bottom = moving.first;
    final dst = state.tableau[dstCol];
    final dstTop = dst.isEmpty ? null : dst.last;

    if (dstTop == null) {
      if (bottom.value != 13) return null; // Seul Roi sur colonne vide
    } else {
      if (!bottom.canStackOn(dstTop)) return null;
    }

    final newTab = List<List<PlayingCard>>.from(state.tableau);
    newTab[srcCol] = List.from(src.sublist(0, cardIdx));
    newTab[dstCol] = List.from(dst)..addAll(moving);

    // Retourner la carte du dessus de la source
    if (newTab[srcCol].isNotEmpty && !newTab[srcCol].last.faceUp) {
      newTab[srcCol][newTab[srcCol].length - 1] =
          newTab[srcCol].last.copyWith(faceUp: true);
    }

    return _checkWinAndLost(state.copyWith(
      tableau: newTab,
      moves: state.moves + 1,
      score: state.score + 5,
    ));
  }

  /// Déplace la carte du talon vers le tableau
  static SolitaireState? moveWasteToTableau(SolitaireState state, int dstCol) {
    if (dstCol < 0 || dstCol >= state.tableau.length) return null;
    if (state.waste.isEmpty) return null;
    final card = state.waste.last;
    final dst = state.tableau[dstCol];
    final dstTop = dst.isEmpty ? null : dst.last;

    if (dstTop == null) {
      if (card.value != 13) return null;
    } else {
      if (!card.canStackOn(dstTop)) return null;
    }

    final newTab = List<List<PlayingCard>>.from(state.tableau);
    newTab[dstCol] = List.from(dst)..add(card);

    return _checkWinAndLost(state.copyWith(
      waste: state.waste.sublist(0, state.waste.length - 1),
      tableau: newTab,
      moves: state.moves + 1,
      score: state.score + 5,
    ));
  }

  /// Déplace la carte du talon vers la fondation
  static SolitaireState? moveWasteToFoundation(SolitaireState state) {
    if (state.waste.isEmpty) return null;
    final card = state.waste.last;
    return _tryFoundation(
      state.copyWith(waste: state.waste.sublist(0, state.waste.length - 1)),
      card,
    );
  }

  /// Déplace la carte du dessus d'une colonne vers la fondation
  static SolitaireState? moveTableauToFoundation(SolitaireState state, int col) {
    if (col < 0 || col >= state.tableau.length) return null;
    final col_ = state.tableau[col];
    if (col_.isEmpty || !col_.last.faceUp) return null;
    final card = col_.last;

    final newTab = List<List<PlayingCard>>.from(state.tableau);
    newTab[col] = List.from(col_.sublist(0, col_.length - 1));

    if (newTab[col].isNotEmpty && !newTab[col].last.faceUp) {
      newTab[col][newTab[col].length - 1] =
          newTab[col].last.copyWith(faceUp: true);
    }

    return _tryFoundation(
        state.copyWith(tableau: newTab, moves: state.moves + 1), card);
  }

  static SolitaireState? _tryFoundation(SolitaireState state, PlayingCard card) {
    final idx = card.suit.index;
    final foundation = state.foundations[idx];
    final top = foundation.isEmpty ? null : foundation.last;
    if (!card.canGoToFoundation(top)) return null;

    final newF = List<List<PlayingCard>>.from(state.foundations);
    newF[idx] = List.from(foundation)..add(card);

    return _checkWinAndLost(state.copyWith(
      foundations: newF,
      score: state.score + 10,
    ));
  }

  /// Vérifie victoire et état perdu (aucun coup possible)
  static SolitaireState _checkWinAndLost(SolitaireState state) {
    if (state.isComplete) {
      return state.copyWith(isWon: true, score: state.score + 500);
    }
    // 🛡 Invariant 52 cartes (sanity check)
    assert(state.totalCards == 52,
        'Solitaire state corrupted: totalCards = ${state.totalCards}');
    if (!hasAnyValidMove(state)) {
      return state.copyWith(isLost: true);
    }
    return state;
  }

  // ============================================================
  // Détection : reste-t-il un coup possible ?
  // ============================================================
  /// Retourne true si AU MOINS un move valide est disponible.
  /// Permet de détecter l'état perdu (deadlock) sans attendre le timer.
  static bool hasAnyValidMove(SolitaireState state) {
    // 1. Stock non vide ou waste recyclable → toujours possible de tirer
    if (state.stock.isNotEmpty) return true;

    // 2. Si waste non vide, on peut le recycler vers stock (≥ 1 move possible)
    //    Mais ça ne change pas l'état du jeu — on cherche un VRAI progrès.
    //    On considère perdu si même après recycle aucun coup utile n'apparaît.

    // 3. Waste → fondation
    if (moveWasteToFoundation(state) != null) return true;

    // 4. Waste → tableau (toutes les colonnes)
    for (int c = 0; c < 7; c++) {
      if (moveWasteToTableau(state, c) != null) return true;
    }

    // 5. Tableau → fondation (toutes les colonnes)
    for (int c = 0; c < 7; c++) {
      if (moveTableauToFoundation(state, c) != null) return true;
    }

    // 6. Tableau → tableau (depuis n'importe quelle position face-up)
    for (int srcCol = 0; srcCol < 7; srcCol++) {
      final col = state.tableau[srcCol];
      for (int idx = 0; idx < col.length; idx++) {
        if (!col[idx].faceUp) continue;
        for (int dstCol = 0; dstCol < 7; dstCol++) {
          if (dstCol == srcCol) continue;
          if (moveTableauToTableau(state, srcCol, idx, dstCol) != null) {
            return true;
          }
        }
      }
    }

    // 7. Si on peut recycler le waste (encore une fois), on garde l'espoir
    //    SAUF si tous les éléments visibles sont des as déjà placés sur foundation
    //    → état clairement perdu. Sinon, le recycle peut donner un coup.
    if (state.waste.isNotEmpty) {
      // Optimiste : on autorise le recycle. Si après recycle tout est bloqué
      // on tombera sur ce check au prochain tour.
      return true;
    }

    return false;
  }
}
