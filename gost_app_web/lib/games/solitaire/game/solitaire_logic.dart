// ============================================================
// Solitaire Klondike – Logique de jeu pure
// ============================================================
import '../models/solitaire_models.dart';

class SolitaireLogic {
  /// Tire une carte du stock vers le talon
  static SolitaireState drawFromStock(SolitaireState state) {
    if (state.stock.isEmpty) {
      if (state.waste.isEmpty) return state;
      final newStock = state.waste.reversed.map((c) => c.copyWith(faceUp: false)).toList();
      return state.copyWith(stock: newStock, waste: []);
    }
    final card = state.stock.last.copyWith(faceUp: true);
    return state.copyWith(
      stock: state.stock.sublist(0, state.stock.length - 1),
      waste: [...state.waste, card],
      moves: state.moves + 1,
    );
  }

  /// Déplace des cartes entre colonnes du tableau
  static SolitaireState? moveTableauToTableau(
      SolitaireState state, int srcCol, int cardIdx, int dstCol) {
    final src = state.tableau[srcCol];
    if (cardIdx >= src.length) return null;
    final moving = src.sublist(cardIdx);
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
      final lst = newTab[srcCol].removeLast();
      newTab[srcCol].add(lst.copyWith(faceUp: true));
    }

    return _checkWin(state.copyWith(
      tableau: newTab,
      moves: state.moves + 1,
      score: state.score + 5,
    ));
  }

  /// Déplace la carte du talon vers le tableau
  static SolitaireState? moveWasteToTableau(SolitaireState state, int dstCol) {
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

    return _checkWin(state.copyWith(
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
    final col_ = state.tableau[col];
    if (col_.isEmpty || !col_.last.faceUp) return null;
    final card = col_.last;

    final newTab = List<List<PlayingCard>>.from(state.tableau);
    newTab[col] = List.from(col_.sublist(0, col_.length - 1));

    if (newTab[col].isNotEmpty && !newTab[col].last.faceUp) {
      final lst = newTab[col].removeLast();
      newTab[col].add(lst.copyWith(faceUp: true));
    }

    return _tryFoundation(state.copyWith(tableau: newTab, moves: state.moves + 1), card);
  }

  static SolitaireState? _tryFoundation(SolitaireState state, PlayingCard card) {
    final idx = card.suit.index;
    final foundation = state.foundations[idx];
    final top = foundation.isEmpty ? null : foundation.last;
    if (!card.canGoToFoundation(top)) return null;

    final newF = List<List<PlayingCard>>.from(state.foundations);
    newF[idx] = List.from(foundation)..add(card);

    return _checkWin(state.copyWith(foundations: newF, score: state.score + 10));
  }

  static SolitaireState _checkWin(SolitaireState state) {
    if (state.isComplete) return state.copyWith(isWon: true, score: state.score + 500);
    return state;
  }
}
