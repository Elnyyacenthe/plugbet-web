// ============================================================
// BetSlipOddsRefresher — Polling des cotes du panier (style 1xBet)
// ============================================================
// But : refresh automatique des cotes des selections presentes dans le
// panier BetSlipController. Si une cote change entre l'ajout au panier
// et la validation finale, on affiche une fleche up/down dans l'UI et
// (selon la policy) on demande confirmation a l'utilisateur.
//
// Strategie :
// 1. Listener sur BetSlipController : detecte ajout/retrait de selection
// 2. Polling toutes les 10s tant que le panier est non vide
// 3. Pour chaque match du panier :
//    - Live  : fetch /soccer/odds/live ou /nba/odds (cache 90s)
//    - Prematch : pas de re-fetch (cotes prematch sont stables)
// 4. Compare l'ancienne cote vs nouvelle -> appelle controller.updateOdds()
//
// Cout reseau : zero appel HTTP si cache hit (90s TTL deja en place).
// 1 panier * 2 sports * 10s = 6 calls/min MAX, mais en pratique caches.
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../state/bet_slip_controller.dart';
import 'statpal_service.dart';

class BetSlipOddsRefresher {
  BetSlipOddsRefresher._();
  static final BetSlipOddsRefresher instance = BetSlipOddsRefresher._();

  Timer? _timer;
  bool _running = false;
  bool _started = false;
  static const _interval = Duration(seconds: 10);

  /// A appeler 1 fois au boot (depuis main.dart apres init).
  /// Branche le listener sur BetSlipController et lance le polling
  /// uniquement quand il y a des selections.
  void attach() {
    if (_started) return;
    _started = true;
    final ctrl = BetSlipController.instance;
    ctrl.addListener(_onSlipChanged);
    _onSlipChanged();
  }

  void detach() {
    if (!_started) return;
    BetSlipController.instance.removeListener(_onSlipChanged);
    _timer?.cancel();
    _timer = null;
    _running = false;
    _started = false;
  }

  void _onSlipChanged() {
    final hasItems = BetSlipController.instance.count > 0;
    if (hasItems && _timer == null) {
      _kickoff();
    } else if (!hasItems) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _kickoff() {
    // 1er refresh immediat (sinon 10s d'attente apres ajout)
    Future.microtask(_refresh);
    _timer = Timer.periodic(_interval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_running) return;
    final ctrl = BetSlipController.instance;
    final items = ctrl.items;
    if (items.isEmpty) return;
    _running = true;
    try {
      final svc = StatpalService.instance;

      // Group selections by sport pour limiter les calls
      final hasSoccer = items.any((s) =>
          !s.isVirtual && (s.sportName == null || s.sportName == 'soccer'));
      final hasBasket = items.any(
          (s) => !s.isVirtual && s.sportName == 'basketball');

      // Live odds (le seul cas ou ca bouge)
      final liveByMatchId = <String, BettingMatch>{};
      if (hasSoccer) {
        try {
          final list = await svc.getLiveMatches(sport: Sport.soccer);
          for (final m in list) {
            liveByMatchId[m.id] = m;
          }
        } catch (_) {/* ignore */}
      }
      if (hasBasket) {
        try {
          final list = await svc.getLiveMatches(sport: Sport.basketball);
          for (final m in list) {
            liveByMatchId[m.id] = m;
          }
        } catch (_) {/* ignore */}
      }

      // Process chaque selection
      for (final sel in items) {
        if (sel.isVirtual) continue;  // pas de polling sur virtuels (cotes fixes)
        final live = liveByMatchId[sel.matchId];
        if (live == null) continue;
        final newOdds = _extractOdds(live.odds, sel.marketCode);
        if (newOdds == null) continue;
        // Update toujours les scores/minute meme si cote inchangee
        ctrl.updateOdds(
          matchId: sel.matchId,
          marketCode: sel.marketCode,
          newOdds: newOdds,
          homeScore: live.homeScore,
          awayScore: live.awayScore,
          minute: live.minute,
          isLive: live.isLive,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BetSlipOddsRefresher] error: $e');
    } finally {
      _running = false;
    }
  }

  /// Extrait la cote correspondant au marketCode depuis MatchOdds.
  /// Supporte les principaux codes : home/draw/away, over25/under25, btts,
  /// ht_*, spread, dc_*, ah_*@line, extra markets generiques.
  double? _extractOdds(MatchOdds? o, String code) {
    if (o == null) return null;
    // Codes simples
    switch (code) {
      case 'home':       return o.home;
      case 'draw':       return o.draw;
      case 'away':       return o.away;
      case 'over25':     return o.over25;
      case 'under25':    return o.under25;
      case 'btts_yes':   return o.bttsYes;
      case 'btts_no':    return o.bttsNo;
      case 'ht_home':    return o.htHome;
      case 'ht_draw':    return o.htDraw;
      case 'ht_away':    return o.htAway;
      case 'ht_over15':  return o.htOver15;
      case 'ht_under15': return o.htUnder15;
      case 'spread_home':return o.spreadHomeOdds;
      case 'spread_away':return o.spreadAwayOdds;
      case 'dc_1x':      return o.dc1X;
      case 'dc_12':      return o.dc12;
      case 'dc_x2':      return o.dcX2;
    }
    // Asian Handicap : "ah_home@-1.5" / "ah_away@+0.5"
    if (code.startsWith('ah_') && code.contains('@')) {
      final at = code.indexOf('@');
      final side = code.substring(0, at);
      final lineStr = code.substring(at + 1);
      final line = double.tryParse(lineStr);
      if (line == null) return null;
      for (final l in o.asianHandicap) {
        if ((l.line - line).abs() < 0.001) {
          return side == 'ah_home' ? l.homeOdds : l.awayOdds;
        }
        // Pour ah_away, la line est inversee
        if (side == 'ah_away' && (l.line + line).abs() < 0.001) {
          return l.awayOdds;
        }
      }
      return null;
    }
    // Extra markets : code "{market_code}_{slug}@{line}" ou "{market_code}_{slug}"
    for (final extra in o.extraMarkets) {
      for (final eo in extra.odds) {
        if (eo.code == code) return eo.value;
      }
    }
    return null;
  }
}
