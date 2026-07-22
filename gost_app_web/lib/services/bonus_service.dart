// ============================================================
// BonusService — Codes bonus (vouchers) promotionnels
// ============================================================
// Lit les codes bonus de l'utilisateur (RPC get_my_bonus_codes) generes par
// les promotions PlugSafe / PlugShield / PlugBoost. Un code est utilisable une
// seule fois sur un coupon (voir BetSlipController.submit + place_bet_with_bonus).
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';

class BonusCode {
  final String id;
  final String code;
  final int amount;
  final String source; // plugsafe | plugshield | plugboost
  final String status; // active | used | expired
  final DateTime? createdAt;
  final DateTime? usedAt;

  BonusCode({
    required this.id,
    required this.code,
    required this.amount,
    required this.source,
    required this.status,
    this.createdAt,
    this.usedAt,
  });

  factory BonusCode.fromJson(Map<String, dynamic> j) => BonusCode(
        id: j['id']?.toString() ?? '',
        code: j['code']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        source: j['source']?.toString() ?? '',
        status: j['status']?.toString() ?? 'active',
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        usedAt: DateTime.tryParse(j['used_at']?.toString() ?? ''),
      );

  bool get isActive => status == 'active';

  String get sourceLabel {
    switch (source) {
      case 'plugsafe':
        return 'PlugSafe';
      case 'plugshield':
        return 'PlugShield';
      case 'plugboost':
        return 'PlugBoost';
      default:
        return source;
    }
  }

  /// Petite phrase expliquant l'origine du bonus.
  String get originText {
    switch (source) {
      case 'plugsafe':
        return 'Ton 1er pari perdu t\'a été remboursé.';
      case 'plugshield':
        return 'Une seule sélection a fait tomber ton combiné : mise remboursée.';
      case 'plugboost':
        return 'Boost sur les gains de ton pari gagnant.';
      default:
        return 'Bonus promotionnel.';
    }
  }
}

class BonusService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Tous les codes bonus de l'utilisateur (actifs d'abord, puis les plus recents).
  Future<List<BonusCode>> getMyBonusCodes() async {
    try {
      final r = await _client.rpc('get_my_bonus_codes');
      if (r is List) {
        return r
            .whereType<Map>()
            .map((e) => BonusCode.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {/* offline / RPC absente */}
    return [];
  }
}
