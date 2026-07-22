// ============================================================
// DerivedMarketsService — marchés dérivés (Goals Model) d'un match
// ============================================================
// Lit les marchés dérivés ACTIFS d'un match via l'RPC get_active_derived_markets
// (cotes issues du moteur Poisson serveur, taguées origin='derived'). Ces
// marchés ÉTENDENT l'offre 1X2/Totaux/etc. sans nouveau fournisseur de données.
// La cote envoyée au coupon doit être exactement offered_odds : le serveur la
// re-valide à la pose (anti-triche).
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';

class DerivedMarket {
  final String code;
  final String label;
  final double odds;
  final String confidence; // 'high' | 'medium'

  DerivedMarket({
    required this.code,
    required this.label,
    required this.odds,
    required this.confidence,
  });

  factory DerivedMarket.fromJson(Map<String, dynamic> j) => DerivedMarket(
        code: j['market_code']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        odds: (j['odds'] as num?)?.toDouble() ?? 0,
        confidence: j['confidence']?.toString() ?? 'high',
      );

  bool get isMedium => confidence == 'medium';

  /// Famille d'affichage déduite du code marché.
  String get family {
    if (code == 'btts_yes' || code == 'btts_no') return 'BTTS';
    if (code.startsWith('cs_')) return 'Score exact';
    if (code.startsWith('eh_')) return 'Handicap';
    if (code.startsWith('rt_')) return 'Résultat + Total';
    if (code.startsWith('over') || code.startsWith('under')) return 'Totaux';
    if (code.startsWith('ht_')) return 'Mi-temps';
    return 'Autres';
  }

  bool get isTotal => code.startsWith('over') || code.startsWith('under');
  bool get isOver => code.startsWith('over');

  /// Ligne de but pour un code totaux (over15 -> 1.5), sinon null.
  double? get totalLine {
    if (!isTotal) return null;
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.parse(digits) / 10.0;
  }
}

class DerivedMarketsService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Marchés dérivés actifs d'un match (vide si aucun / offline).
  Future<List<DerivedMarket>> getActive(String matchId) async {
    try {
      final r = await _client.rpc(
        'get_active_derived_markets',
        params: {'p_match_id': matchId},
      );
      if (r is List) {
        return r
            .whereType<Map>()
            .map((e) => DerivedMarket.fromJson(e.cast<String, dynamic>()))
            .where((m) => m.odds >= 1.01 && m.code.isNotEmpty)
            .toList();
      }
    } catch (_) {/* RPC absente / offline */}
    return [];
  }
}
