// ============================================================
// Solitaire Klondike – Modèles de données
// ============================================================

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

/// Une carte à jouer
class PlayingCard {
  final CardSuit suit;
  final int value; // 1=A, 2-10, 11=J, 12=Q, 13=K
  bool faceUp;

  PlayingCard({required this.suit, required this.value, this.faceUp = false});

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

  /// Peut être posée sur `other` dans le tableau (couleur alternée, valeur -1)
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
}

/// Crée un jeu de 52 cartes mélangées
List<PlayingCard> createShuffledDeck() {
  final deck = <PlayingCard>[];
  for (final suit in CardSuit.values) {
    for (int v = 1; v <= 13; v++) {
      deck.add(PlayingCard(suit: suit, value: v));
    }
  }
  deck.shuffle();
  return deck;
}

/// État complet d'une partie Solitaire
class SolitaireState {
  /// 7 colonnes du tableau (tableau principal)
  final List<List<PlayingCard>> tableau;

  /// Pile de pioche (stock)
  final List<PlayingCard> stock;

  /// Pile de défausse visible (waste/talon)
  final List<PlayingCard> waste;

  /// 4 fondations (une par couleur)
  final List<List<PlayingCard>> foundations;

  final int score;
  final int moves;
  final int elapsedSeconds;
  final bool isWon;
  final bool isLost;

  SolitaireState({
    required this.tableau,
    required this.stock,
    required this.waste,
    required this.foundations,
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
      score: score ?? this.score,
      moves: moves ?? this.moves,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isWon: isWon ?? this.isWon,
      isLost: isLost ?? this.isLost,
    );
  }

  /// Partie initiale standard Klondike
  factory SolitaireState.initial() {
    final deck = createShuffledDeck();
    int idx = 0;

    // Distribution Klondike : colonne i a i+1 cartes, dernière face visible
    final tableau = List.generate(7, (i) {
      final col = <PlayingCard>[];
      for (int j = 0; j <= i; j++) {
        final card = deck[idx++];
        card.faceUp = (j == i);
        col.add(card);
      }
      return col;
    });

    // Le reste va dans le stock (face cachée)
    final stock = deck.sublist(idx).map((c) {
      c.faceUp = false;
      return c;
    }).toList();

    return SolitaireState(
      tableau: tableau,
      stock: stock,
      waste: [],
      foundations: [[], [], [], []],
    );
  }

  /// Vérifie si la partie est gagnée (4 fondations complètes à 13 cartes)
  bool get isComplete =>
      foundations.every((f) => f.length == 13);

  /// Cartes visibles en jeu
  int get visibleCards {
    int count = 0;
    for (final col in tableau) {
      count += col.where((c) => c.faceUp).length;
    }
    return count + waste.length;
  }

  Map<String, dynamic> toJson() => {
        'tableau': tableau.map((col) => col.map((c) => c.toJson()).toList()).toList(),
        'stock': stock.map((c) => c.toJson()).toList(),
        'waste': waste.map((c) => c.toJson()).toList(),
        'foundations': foundations.map((f) => f.map((c) => c.toJson()).toList()).toList(),
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
      score: json['score'] as int? ?? 0,
      moves: json['moves'] as int? ?? 0,
    );
  }
}
