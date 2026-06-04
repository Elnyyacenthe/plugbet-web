// ============================================================
// Big Win 777 — Modeles
// ============================================================
// 3 rouleaux, 1 ligne centrale.
// Symboles + paytable + RNG : tout est tunable ici sans toucher
// au reste de l'app. Phase 2 (real money) : la paytable cote serveur
// doit MATCHER exactement celle-ci, sinon divergence client/serveur.
// ============================================================

import 'dart:math';

/// Symboles du rouleau. emoji = rendu Phase 1 (rapide).
/// assetPath = remplir plus tard pour passer aux vraies images dorees.
enum SlotSymbol {
  cherry('🍒', 'Cerises'),
  lemon('🍋', 'Citron'),
  orange('🍊', 'Orange'),
  grape('🍇', 'Raisin'),
  bell('🔔', 'Cloche'),
  bar('BAR', 'BAR'),
  seven('7', 'Seven'),
  blank('·', '');

  final String emoji;
  final String label;
  const SlotSymbol(this.emoji, this.label);

  bool get isWildBar => this == SlotSymbol.bar;
  bool get isSeven   => this == SlotSymbol.seven;
  bool get isBlank   => this == SlotSymbol.blank;
}

/// Poids relatifs par rouleau (somme = 32 stops virtuels, classique).
/// Plus une valeur est haute, plus le symbole apparait souvent.
/// Difficulte calibree ~78% RTP (house edge ~22%).
/// CES VALEURS DOIVENT MATCHER EXACTEMENT slots_spin() SQL.
const Map<SlotSymbol, int> kReelWeights = {
  SlotSymbol.cherry: 7,
  SlotSymbol.lemon : 6,
  SlotSymbol.orange: 5,
  SlotSymbol.grape : 4,
  SlotSymbol.bell  : 3,
  SlotSymbol.bar   : 3,
  SlotSymbol.seven : 1,
  SlotSymbol.blank : 3,
}; // total = 32

/// Multiplicateurs de gain par combinaison.
/// Le gain final = bet * multiplier.
class Paytable {
  /// 3 symboles identiques sur la payline centrale.
  static const Map<SlotSymbol, int> threeOfAKind = {
    SlotSymbol.seven : 500, // JACKPOT
    SlotSymbol.bar   : 100,
    SlotSymbol.bell  : 50,
    SlotSymbol.grape : 25,
    SlotSymbol.orange: 15,
    SlotSymbol.lemon : 10,
    SlotSymbol.cherry: 5,
  };

  /// Exactement 2 symboles identiques (les 2 autres peuvent etre n'importe quoi).
  /// Seuls les symboles ici declenchent un mini-gain pair.
  /// Calibration "rude" : 2-of-a-kind reduit pour baisser le RTP de 90% -> 78%.
  static const Map<SlotSymbol, int> twoOfAKind = {
    SlotSymbol.seven : 18,
    SlotSymbol.bar   : 4,
    SlotSymbol.bell  : 2,
    SlotSymbol.cherry: 2,
  };

  /// True si le multiplier renvoyé déclenche l'overlay "BIG WIN".
  static bool isBigWin(int multiplier) => multiplier >= 25;

  /// True si c'est le JACKPOT (777).
  static bool isJackpot(int multiplier) => multiplier >= 500;
}

/// Resultat d'un spin (client Demo OU serveur Phase 2).
class SpinResult {
  final List<SlotSymbol> reels; // 3 symboles affiches sur la payline
  final int bet;
  final int multiplier;         // 0 si pas de gain
  final int payout;             // bet * multiplier
  final int newBalance;
  final String? winLabel;       // 'JACKPOT', 'BIG WIN', 'WIN', null

  const SpinResult({
    required this.reels,
    required this.bet,
    required this.multiplier,
    required this.payout,
    required this.newBalance,
    this.winLabel,
  });

  bool get isWin     => multiplier > 0;
  bool get isJackpot => Paytable.isJackpot(multiplier);
  bool get isBigWin  => Paytable.isBigWin(multiplier);
}

/// Tire un symbole selon les poids de [kReelWeights].
/// Rejection sampling sur Random.secure() (Phase 1). Phase 2 = serveur.
SlotSymbol pickSymbol(Random rng) {
  final total = kReelWeights.values.fold<int>(0, (a, b) => a + b);
  final r = rng.nextInt(total);
  int acc = 0;
  for (final e in kReelWeights.entries) {
    acc += e.value;
    if (r < acc) return e.key;
  }
  return SlotSymbol.blank;
}

/// Calcule le multiplier d'un trio (1 ligne centrale).
int evaluateLine(List<SlotSymbol> reels) {
  assert(reels.length == 3);
  // 3 identiques (et pas blank)
  if (reels[0] == reels[1] &&
      reels[1] == reels[2] &&
      !reels[0].isBlank) {
    final m = Paytable.threeOfAKind[reels[0]];
    if (m != null) return m;
  }
  // 2 identiques (sur n'importe quelle paire des 3 positions)
  final pairs = <SlotSymbol>{};
  for (var i = 0; i < 3; i++) {
    for (var j = i + 1; j < 3; j++) {
      if (reels[i] == reels[j] && !reels[i].isBlank) {
        pairs.add(reels[i]);
      }
    }
  }
  int best = 0;
  for (final s in pairs) {
    final m = Paytable.twoOfAKind[s];
    if (m != null && m > best) best = m;
  }
  return best;
}

/// Mise libre [kMinBet, kMaxBet] : le joueur peut taper n'importe
/// quel entier dans cet intervalle (comme Penalty).
const int kMinBet = 10;
const int kMaxBet = 1000;

/// Suggestions rapides (chips) pour eviter de tout taper a la main.
/// Le joueur peut tap un chip OU saisir une valeur libre dans le champ.
const List<int> kQuickBetLevels = [10, 50, 100, 500, 1000];

/// True si [bet] est une mise valide. A utiliser cote client AVANT
/// d'envoyer l'RPC.
bool isValidBet(int bet) => bet >= kMinBet && bet <= kMaxBet;
