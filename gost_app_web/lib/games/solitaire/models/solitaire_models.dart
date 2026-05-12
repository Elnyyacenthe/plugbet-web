// ============================================================
// Solitaire Klondike – Modèles V2 (immutable, audit-ready)
// ============================================================
// Changements vs V1 :
//   - PlayingCard.faceUp est final (immutable)
//   - SolitaireState.seed pour reproductibilité (replay anti-cheat)
//   - SolitaireState.moveHistory pour audit/server validation
//   - MoveAction enum/class pour logger chaque coup
// ============================================================
import 'dart:math';

/// Les 4 couleurs de carte
enum CardSuit { spades, hearts, diamonds, clubs }

extension CardSuitExt on CardSuit {
  String get symbol {
    switch (this) {
      case CardSuit.spades:
        return '♠';
      case CardSuit.hearts:
        return '♥';
      case CardSuit.diamonds:
        return '♦';
      case CardSuit.clubs:
        return '♣';
    }
  }

  bool get isRed => this == CardSuit.hearts || this == CardSuit.diamonds;
  bool get isBlack => !isRed;
  String get name => ['spades', 'hearts', 'diamonds', 'clubs'][index];
}

/// Une carte à jouer (IMMUTABLE)
class PlayingCard {
  final CardSuit suit;
  final int value; // 1=A, 2-10, 11=J, 12=Q, 13=K
  final bool faceUp;

  const PlayingCard({
    required this.suit,
    required this.value,
    this.faceUp = false,
  });

  String get label {
    switch (value) {
      case 1:
        return 'A';
      case 11:
        return 'J';
      case 12:
        return 'Q';
      case 13:
        return 'K';
      default:
        return '$value';
    }
  }

  bool get isRed => suit.isRed;
  bool get isBlack => suit.isBlack;

  /// Peut être posée sur `other` dans le tableau (couleur alternée, valeur -1).
  /// Le caller doit vérifier que CETTE carte est faceUp avant de l'autoriser.
  bool canStackOn(PlayingCard other) {
    return other.faceUp && isRed != other.isRed && value == other.value - 1;
  }

  /// Peut être posée sur la fondation après `top` (même couleur, valeur +1)
  bool canGoToFoundation(PlayingCard? top) {
    if (top == null) return value == 1; // As = début fondation
    return suit == top.suit && value == top.value + 1;
  }

  PlayingCard copyWith({bool? faceUp}) =>
      PlayingCard(suit: suit, value: value, faceUp: faceUp ?? this.faceUp);

  Map<String, dynamic> toJson() => {
        's': suit.index,
        'v': value,
        'f': faceUp,
      };

  factory PlayingCard.fromJson(Map<String, dynamic> json) => PlayingCard(
        suit: CardSuit.values[json['s'] as int],
        value: json['v'] as int,
        faceUp: json['f'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayingCard &&
          other.suit == suit &&
          other.value == value &&
          other.faceUp == faceUp;

  @override
  int get hashCode => Object.hash(suit, value, faceUp);

  @override
  String toString() => '$label${suit.symbol}${faceUp ? '↑' : '↓'}';
}

/// Crée un jeu de 52 cartes, mélangé déterministiquement avec un seed.
/// Le seed est REQUIS pour que le serveur puisse rejouer la partie.
List<PlayingCard> createShuffledDeck(int seed) {
  final deck = <PlayingCard>[];
  for (final suit in CardSuit.values) {
    for (int v = 1; v <= 13; v++) {
      deck.add(PlayingCard(suit: suit, value: v));
    }
  }
  deck.shuffle(Random(seed));
  return deck;
}

/// Type d'action loggée pour audit serveur
enum MoveType {
  drawFromStock,           // ouvrir une carte du stock
  recycleStock,            // recycler le waste vers le stock
  wasteToFoundation,       // talon → fondation
  wasteToTableau,          // talon → colonne
  tableauToFoundation,     // colonne → fondation
  tableauToTableau,        // colonne → colonne
}

/// Une action loggée. Sérialisée pour envoi serveur.
class MoveAction {
  final MoveType type;
  final int? srcCol;       // pour tableau → ...
  final int? cardIdx;      // pour tableau → tableau (carte du milieu)
  final int? dstCol;       // pour ... → tableau
  final int timestampMs;   // ms depuis le début de la partie

  const MoveAction({
    required this.type,
    this.srcCol,
    this.cardIdx,
    this.dstCol,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        't': type.index,
        if (srcCol != null) 's': srcCol,
        if (cardIdx != null) 'i': cardIdx,
        if (dstCol != null) 'd': dstCol,
        'ts': timestampMs,
      };

  factory MoveAction.fromJson(Map<String, dynamic> j) => MoveAction(
        type: MoveType.values[j['t'] as int],
        srcCol: j['s'] as int?,
        cardIdx: j['i'] as int?,
        dstCol: j['d'] as int?,
        timestampMs: j['ts'] as int? ?? 0,
      );
}

/// État complet d'une partie Solitaire (immutable)
class SolitaireState {
  /// 7 colonnes du tableau (tableau principal)
  final List<List<PlayingCard>> tableau;

  /// Pile de pioche (stock)
  final List<PlayingCard> stock;

  /// Pile de défausse visible (waste/talon)
  final List<PlayingCard> waste;

  /// 4 fondations (une par couleur, indexées par CardSuit.index)
  final List<List<PlayingCard>> foundations;

  /// Seed du shuffle (REQUIS pour replay serveur)
  final int seed;

  final int score;
  final int moves;
  final int elapsedSeconds;
  final bool isWon;
  final bool isLost;

  const SolitaireState({
    required this.tableau,
    required this.stock,
    required this.waste,
    required this.foundations,
    required this.seed,
    this.score = 0,
    this.moves = 0,
    this.elapsedSeconds = 0,
    this.isWon = false,
    this.isLost = false,
  });

  /// Copie avec modifications
  SolitaireState copyWith({
    List<List<PlayingCard>>? tableau,
    List<PlayingCard>? stock,
    List<PlayingCard>? waste,
    List<List<PlayingCard>>? foundations,
    int? seed,
    int? score,
    int? moves,
    int? elapsedSeconds,
    bool? isWon,
    bool? isLost,
  }) {
    return SolitaireState(
      tableau: tableau ?? this.tableau,
      stock: stock ?? this.stock,
      waste: waste ?? this.waste,
      foundations: foundations ?? this.foundations,
      seed: seed ?? this.seed,
      score: score ?? this.score,
      moves: moves ?? this.moves,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isWon: isWon ?? this.isWon,
      isLost: isLost ?? this.isLost,
    );
  }

  /// Partie initiale Klondike avec un seed pour reproductibilité.
  /// Si seed == null → seed aléatoire (mode pratique uniquement).
  factory SolitaireState.initial({int? seed}) {
    final actualSeed = seed ?? DateTime.now().millisecondsSinceEpoch;
    final deck = createShuffledDeck(actualSeed);
    int idx = 0;

    // Distribution Klondike : colonne i a i+1 cartes, dernière face visible
    final tableau = List.generate(7, (i) {
      final col = <PlayingCard>[];
      for (int j = 0; j <= i; j++) {
        // Plus de mutation : on copyWith
        col.add(deck[idx++].copyWith(faceUp: j == i));
      }
      return col;
    });

    // Le reste va dans le stock (face cachée)
    final stock = deck.sublist(idx).map((c) => c.copyWith(faceUp: false)).toList();

    return SolitaireState(
      tableau: tableau,
      stock: stock,
      waste: const [],
      foundations: const [[], [], [], []],
      seed: actualSeed,
    );
  }

  /// Vérifie si la partie est gagnée (4 fondations complètes à 13 cartes)
  bool get isComplete => foundations.every((f) => f.length == 13);

  /// Cartes visibles en jeu
  int get visibleCards {
    int count = 0;
    for (final col in tableau) {
      count += col.where((c) => c.faceUp).length;
    }
    return count + waste.length;
  }

  /// Total des cartes — invariant DOIT toujours == 52 (sécurité)
  int get totalCards {
    int count = stock.length + waste.length;
    for (final col in tableau) {
      count += col.length;
    }
    for (final f in foundations) {
      count += f.length;
    }
    return count;
  }

  Map<String, dynamic> toJson() => {
        'tableau': tableau.map((col) => col.map((c) => c.toJson()).toList()).toList(),
        'stock': stock.map((c) => c.toJson()).toList(),
        'waste': waste.map((c) => c.toJson()).toList(),
        'foundations': foundations.map((f) => f.map((c) => c.toJson()).toList()).toList(),
        'seed': seed,
        'score': score,
        'moves': moves,
      };

  factory SolitaireState.fromJson(Map<String, dynamic> json) {
    List<PlayingCard> parseList(dynamic raw) =>
        (raw as List).map((e) => PlayingCard.fromJson(e as Map<String, dynamic>)).toList();

    return SolitaireState(
      tableau: (json['tableau'] as List).map((col) => parseList(col)).toList(),
      stock: parseList(json['stock']),
      waste: parseList(json['waste']),
      foundations: (json['foundations'] as List).map((f) => parseList(f)).toList(),
      seed: json['seed'] as int? ?? 0,
      score: json['score'] as int? ?? 0,
      moves: json['moves'] as int? ?? 0,
    );
  }
}
