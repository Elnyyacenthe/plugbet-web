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

/// Distribution des 48 segments :
///   0..23  -> 1   (24 segments, p=50%)
///   24..35 -> 2   (12 segments, p=25%)
///   36..41 -> 5   (6 segments,  p=12.5%)
///   42..44 -> 10  (3 segments,  p=6.25%)
///   45..46 -> 20  (2 segments,  p=4.17%)
///   47     -> 40  (1 segment,   p=2.08%)
///
/// Le mapping segment -> tile sert UNIQUEMENT pour l'animation
/// graphique du client. Le serveur tire son propre segment, c'est
/// lui qui decide du resultat reel.
const int kWheelSegments = 48;

int segmentToTileValue(int segment) {
  if (segment < 24) return 1;
  if (segment < 36) return 2;
  if (segment < 42) return 5;
  if (segment < 45) return 10;
  if (segment < 47) return 20;
  return 40;
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

/// Denominations des jetons (FCFA). Le joueur tap un jeton puis tap
/// une tuile pour deposer ce montant dessus.
const List<int> kChipDenominations = [25, 100, 500, 5000, 10000, 40000];

/// Limites RPC :
const int kMinBetPerTile = 25;
const int kMaxBetPerTile = 5000;
const int kMinTotalBet = 25;
const int kMaxTotalBet = 25000;

// ── Resultat d'un spin ──────────────────────────────────────

class WheelSpinResult {
  /// 0..47, choisi serveur.
  final int segment;
  /// Tuile gagnante derivee du segment (1, 2, 5, 10, 20 ou 40).
  final int winningTile;
  /// Somme creditee au wallet (= stakeOnWinningTile × (winningTile + 1)).
  final int winnings;
  /// Total des mises debitees au depart.
  final int totalBet;
  /// Solde apres credit (= initial - totalBet + winnings).
  final int newBalance;
  /// Mises envoyees par le client (echo serveur).
  final Map<int, int> bets;

  const WheelSpinResult({
    required this.segment,
    required this.winningTile,
    required this.winnings,
    required this.totalBet,
    required this.newBalance,
    required this.bets,
  });

  bool get isWin => winnings > 0;
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
