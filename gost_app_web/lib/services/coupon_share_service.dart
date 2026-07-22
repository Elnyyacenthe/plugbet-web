// ============================================================
// CouponShareService — partage / chargement de coupons entre joueurs
// ============================================================
// Un joueur partage les sélections de son coupon (en construction ou d'un
// ticket) via un CODE court temporaire (RPC create_shared_coupon). N'importe
// quel autre utilisateur connecté peut CHARGER ce code (RPC load_shared_coupon)
// pour récupérer les sélections dans son propre coupon. Aucun flux d'argent :
// simple passe-plat de sélections.
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/bet_slip_controller.dart';

class SharedCouponResult {
  final String code;
  final DateTime? expiresAt;
  final int count;
  SharedCouponResult({
    required this.code,
    required this.expiresAt,
    required this.count,
  });
}

class CouponShareService {
  final SupabaseClient _c = Supabase.instance.client;

  Map<String, dynamic> selectionToJson(BetSelection s) => {
        'match_id': s.matchId,
        'match_label': s.matchLabel,
        'market_code': s.marketCode,
        'market_label': s.marketLabel,
        'odds': s.odds,
        'kickoff': s.kickoff.toIso8601String(),
        'is_live': s.isLive,
        'is_virtual': s.isVirtual,
        'sport': s.sport,
        'sport_name': s.sportName,
        'league_key': s.leagueKey,
        'competition': s.competition,
      };

  BetSelection selectionFromJson(Map j) => BetSelection(
        matchId: j['match_id']?.toString() ?? '',
        matchLabel: j['match_label']?.toString() ?? '',
        marketCode: j['market_code']?.toString() ?? '',
        marketLabel: j['market_label']?.toString() ?? '',
        odds: (j['odds'] as num?)?.toDouble() ?? 1.01,
        kickoff: DateTime.tryParse(j['kickoff']?.toString() ?? '') ??
            DateTime.now().add(const Duration(hours: 1)),
        isLive: (j['is_live'] as bool?) ?? false,
        isVirtual: (j['is_virtual'] as bool?) ?? false,
        sport: j['sport']?.toString(),
        sportName: j['sport_name']?.toString(),
        leagueKey: j['league_key']?.toString(),
        competition: j['competition']?.toString(),
      );

  /// Crée un coupon partagé et renvoie son code temporaire.
  Future<SharedCouponResult> share(List<BetSelection> sels) async {
    final payload = sels.map(selectionToJson).toList();
    final res = await _c
        .rpc('create_shared_coupon', params: {'p_selections': payload});
    final m = Map<String, dynamic>.from(res as Map);
    return SharedCouponResult(
      code: m['code']?.toString() ?? '',
      expiresAt: DateTime.tryParse(m['expires_at']?.toString() ?? ''),
      count: (m['count'] as num?)?.toInt() ?? sels.length,
    );
  }

  /// Charge un coupon partagé par son code -> liste de sélections.
  Future<List<BetSelection>> load(String code) async {
    final res = await _c.rpc('load_shared_coupon',
        params: {'p_code': code.trim().toUpperCase()});
    final m = Map<String, dynamic>.from(res as Map);
    final list = (m['selections'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map(selectionFromJson)
        .where((s) => s.matchId.isNotEmpty)
        .toList();
  }
}
