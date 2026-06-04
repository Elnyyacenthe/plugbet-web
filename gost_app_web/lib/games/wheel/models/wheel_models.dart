// ============================================================
// Plugbet Wheel — Modeles
// ============================================================
// Roue 48 segments, 6 tuiles (1, 2, 5, 10, 20, 40). Multi-mise.
// IMPORTANT : kSegmentMap[i] doit MATCHER exactement la logique
// SQL slots_spin (sinon divergence client/serveur).
// ============================================================

/// Les 6 tuiles sur lesquelles le joueur peut miser. La valeur de
/// l'enum = multiplicateur de gain (formule : stake × (value + 1)).
enum WheelTile {
  one(1),
  two(2),
  five(5),
  ten(10),
  twenty(20),
  forty(40);

  final int value;
  const WheelTile(this.value);

  static WheelTile fromValue(int v) {
    for (final t in values) {
      if (t.value == v) return t;
    }
    throw ArgumentError('Unknown tile value: $v');
  }
}

/// Distribution des 50 segments (Phase 2 : ajout 2x/7x) :
///   0..23  -> tile 1  (24 segments, p=48%)
///   24..35 -> tile 2  (12 segments, p=24%)
///   36..41 -> tile 5  (6 segments,  p=12%)
///   42..44 -> tile 10 (3 segments,  p=6%)
///   45..46 -> tile 20 (2 segments,  p=4%)
///   47     -> tile 40 (1 segment,   p=2%)
///   48     -> "2x"    (1 segment,   p=2%)  -> free spin x2
///   49     -> "7x"    (1 segment,   p=2%)  -> free spin x7
///
/// Le mapping segment -> tile sert UNIQUEMENT pour l'animation
/// graphique du client. Le serveur tire son propre segment, c'est
/// lui qui decide du resultat reel.
const int kWheelSegments = 50;

/// Type de segment pour le rendu.
enum SegmentType { money, multiplier2x, multiplier7x }

SegmentType segmentType(int segment) {
  if (segment == 48) return SegmentType.multiplier2x;
  if (segment == 49) return SegmentType.multiplier7x;
  return SegmentType.money;
}

int segmentToTileValue(int segment) {
  if (segment < 24) return 1;
  if (segment < 36) return 2;
  if (segment < 42) return 5;
  if (segment < 45) return 10;
  if (segment < 47) return 20;
  if (segment == 47) return 40;
  return 0; // special (2x/7x)
}

/// Multiplicateur du segment special (48 -> 2, 49 -> 7, sinon 0).
int segmentSpecialMultiplier(int segment) {
  if (segment == 48) return 2;
  if (segment == 49) return 7;
  return 0;
}

WheelTile segmentToTile(int segment) =>
    WheelTile.fromValue(segmentToTileValue(segment));

/// Pour l'animation : on a besoin de l'angle du segment cible.
/// Segment 0 commence en haut (12h) et tourne dans le sens horaire.
double segmentToAngleRadians(int segment) {
  // 1 segment = 2π / 48
  const per = (2 * 3.141592653589793) / kWheelSegments;
  // Centre du segment (pour aligner le pointeur dessus)
  return per * segment + per / 2;
}

// ── Mises ───────────────────────────────────────────────────

/// Limites RPC (alignees sur le constraint SQL) :
const int kMinBetPerTile = 25;
const int kMaxBetPerTile = 5000;
const int kMinTotalBet = 25;
const int kMaxTotalBet = 25000;

/// Suggestions rapides (chips) sous le champ libre — comme Penalty/Slots.
/// Le joueur peut tap un chip OU saisir n'importe quelle valeur dans
/// [kMinBetPerTile, kMaxBetPerTile].
const List<int> kQuickAmounts = [25, 100, 500, 1000, 5000];

// ── Resultat d'un spin ──────────────────────────────────────

/// Free spin pending : retourne par wheel_spin / wheel_use_free_spin
/// quand la roue tombe sur 2x ou 7x. Le client doit appeler
/// wheel_use_free_spin avec cet id pour declencher le tour gratuit.
class WheelFreeSpin {
  final String id;            // 'fs_<uuid>'
  final int multiplier;       // multiplicateur accumule (2, 7, 14, 49, ...)
  final Map<int, int> bets;   // mises a rejouer (echo serveur)
  final int cascadeDepth;     // 1..3 (1 = premiere cascade)

  const WheelFreeSpin({
    required this.id,
    required this.multiplier,
    required this.bets,
    required this.cascadeDepth,
  });
}

class WheelSpinResult {
  /// 0..49, choisi serveur.
  final int segment;
  /// Tuile gagnante derivee du segment (1, 2, 5, 10, 20, 40)
  /// OU 0 si segment special (2x/7x = pas de payout direct).
  final int winningTile;
  /// Multiplier applique sur ce spin (1 pour les spins normaux,
  /// 2/7/14/... pour les free spins).
  final int multiplier;
  /// Somme creditee au wallet (deja multiplier-applique).
  final int winnings;
  /// Total des mises debitees (0 si c'est un free spin).
  final int totalBet;
  /// Solde apres credit.
  final int newBalance;
  /// Mises (echo serveur).
  final Map<int, int> bets;
  /// Free spin a utiliser ensuite, ou null.
  final WheelFreeSpin? pendingFreeSpin;

  const WheelSpinResult({
    required this.segment,
    required this.winningTile,
    required this.multiplier,
    required this.winnings,
    required this.totalBet,
    required this.newBalance,
    required this.bets,
    this.pendingFreeSpin,
  });

  bool get isWin => winnings > 0;
  bool get isSpecial => winningTile == 0;
  bool get isPush => winningTile == 1 && bets[1] != null && bets[1]! > 0
      && winnings == bets[1]! * 2;
  int get netResult => winnings - totalBet;
}

/// Helper : convertit une Map<WheelTile, int> -> Map<String, int>
/// pour l'envoi RPC (cles JSON = valeurs des tuiles).
Map<String, int> tilesToJsonMap(Map<WheelTile, int> chipsByTile) {
  final out = <String, int>{};
  for (final e in chipsByTile.entries) {
    if (e.value > 0) {
      out['${e.key.value}'] = e.value;
    }
  }
  return out;
}
