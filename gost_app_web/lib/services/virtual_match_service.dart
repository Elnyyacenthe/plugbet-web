// ============================================================
// VirtualMatchService — Server-driven (Phase 2 RNG)
// ============================================================
// Toute la generation est dans Postgres (cf migration
// zz_20260602_virtual_matches_server.sql) :
// - pg_cron maintain_virtual_pipeline() toutes les 15s -> 5 matchs en pipeline
// - pg_cron settle_virtual_bets() toutes les 10s -> resoud bets pending
// - Realtime push : insert sur public.virtual_match -> client refresh
//
// Cote Dart :
// - get_virtual_matches() RPC au start (charge pipeline initial)
// - Subscription Realtime sur virtual_match (INSERT events)
// - Timer 1s local : notifyListeners pour rafraichir l'affichage
//   (les getters state/scores sont calcules depuis kickoff+goals+now())
// - Re-fetch RPC toutes les 30s en fallback si Realtime drop
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logger.dart';
import 'statpal_service.dart';
import 'team_logo_service.dart';

enum VirtualState { upcoming, live, finished }

class VirtualGoal {
  final int sec;       // 1..29
  final String team;   // 'home' | 'away'
  const VirtualGoal({required this.sec, required this.team});

  factory VirtualGoal.fromJson(Map<String, dynamic> j) => VirtualGoal(
        sec: (j['sec'] as num).toInt(),
        team: j['team'] as String,
      );
}

class VirtualMatch {
  final String id;
  final Sport sport;
  final String homeName;
  final String awayName;
  final int homeRating;
  final int awayRating;
  final DateTime kickoff;      // server-issued (UTC)
  final double homeOdds;
  final double? drawOdds;       // null pour basket
  final double awayOdds;
  final List<VirtualGoal> goals;     // soccer : timeline buts
  // basket : scores finals stockes au spawn (interp lineaire cote client)
  final int? finalHomeScore;
  final int? finalAwayScore;

  const VirtualMatch({
    required this.id,
    required this.sport,
    required this.homeName,
    required this.awayName,
    required this.homeRating,
    required this.awayRating,
    required this.kickoff,
    required this.homeOdds,
    this.drawOdds,
    required this.awayOdds,
    required this.goals,
    this.finalHomeScore,
    this.finalAwayScore,
  });

  factory VirtualMatch.fromJson(Map<String, dynamic> j) {
    DateTime kick;
    final raw = j['kickoff'];
    if (raw is num) {
      kick = DateTime.fromMillisecondsSinceEpoch(
          (raw * 1000).toInt(),
          isUtc: true);
    } else if (raw is String) {
      kick = DateTime.parse(raw).toUtc();
    } else {
      kick = DateTime.now().toUtc();
    }
    final goalsRaw = j['goals'];
    final goals = <VirtualGoal>[];
    if (goalsRaw is List) {
      for (final g in goalsRaw) {
        if (g is Map<String, dynamic>) {
          goals.add(VirtualGoal.fromJson(g));
        } else if (g is Map) {
          goals.add(VirtualGoal.fromJson(g.cast<String, dynamic>()));
        }
      }
    }
    final sportStr = j['sport']?.toString() ?? 'soccer';
    return VirtualMatch(
      id: j['id'].toString(),
      sport: sportStr == 'basketball' ? Sport.basketball : Sport.soccer,
      homeName: j['home_name'] as String,
      awayName: j['away_name'] as String,
      homeRating: (j['home_rating'] as num).toInt(),
      awayRating: (j['away_rating'] as num).toInt(),
      kickoff: kick,
      homeOdds: (j['home_odds'] as num).toDouble(),
      drawOdds: (j['draw_odds'] as num?)?.toDouble(),
      awayOdds: (j['away_odds'] as num).toDouble(),
      goals: goals,
      finalHomeScore: (j['final_home_score'] as num?)?.toInt(),
      finalAwayScore: (j['final_away_score'] as num?)?.toInt(),
    );
  }

  // ── Etats deduits (computed depuis kickoff + goals + now()) ──

  static const _matchDurationSec = 30;

  Duration get _elapsed => DateTime.now().toUtc().difference(kickoff);

  VirtualState get state {
    final e = _elapsed;
    if (e.isNegative) return VirtualState.upcoming;
    if (e.inSeconds < _matchDurationSec) return VirtualState.live;
    return VirtualState.finished;
  }

  bool get isLive => state == VirtualState.live;
  bool get isFinished => state == VirtualState.finished;

  /// Secondes ecoulees depuis kickoff (0..30).
  int get elapsedSec => _elapsed.inSeconds.clamp(0, _matchDurationSec);

  /// 1 s reelle = 3 min virtuelles.
  int get virtualMinute => (elapsedSec * 3).clamp(0, 90);

  /// Score actuel selon sport :
  /// - Soccer : compte des buts dont sec <= elapsedSec
  /// - Basket : interpolation lineaire entre 0 et final score
  int get homeScore {
    if (sport == Sport.basketball) {
      if (finalHomeScore == null) return 0;
      if (isFinished) return finalHomeScore!;
      return ((finalHomeScore! * elapsedSec) / _matchDurationSec).round();
    }
    return goals.where((g) => g.sec <= elapsedSec && g.team == 'home').length;
  }

  int get awayScore {
    if (sport == Sport.basketball) {
      if (finalAwayScore == null) return 0;
      if (isFinished) return finalAwayScore!;
      return ((finalAwayScore! * elapsedSec) / _matchDurationSec).round();
    }
    return goals.where((g) => g.sec <= elapsedSec && g.team == 'away').length;
  }

  String? get winnerCode {
    if (!isFinished) return null;
    if (homeScore > awayScore) return 'home';
    if (awayScore > homeScore) return 'away';
    return 'draw';
  }

  /// Nom de la ligue affichee dans la card selon le sport.
  String get leagueLabel => sport == Sport.basketball
      ? 'Plugbet Virtual NBA'
      : 'Plugbet Virtual League';

  /// Genere 5 lignes AH coherentes avec le 1X2.
  /// Heuristique : favori a une main line -1.5 (si fort) ou -0.5 (si serre),
  /// outsider l'oppose. Cotes derivees de l'implicit probability du 1X2.
  ///
  /// Soccer typique : favori cote 1.6 -> main AH -1.5 ~1.85 / 1.85 outsider
  /// NBA typique : favori cote 1.7 -> main AH -3.5 ~1.90 / 1.90 outsider
  List<AsianHandicapLine> generateAh() {
    final h = homeOdds, a = awayOdds;
    if (h <= 0 || a <= 0) return const [];
    // Implicit probas
    final ph = 1 / h, pa = 1 / a;
    final favHome = ph > pa;
    // Ecart : si proche -> lines courtes ; sinon longues
    final ratio = favHome ? (ph / pa) : (pa / ph);
    final double mainLine = sport == Sport.basketball
        ? (ratio > 2.5 ? -7.5 : ratio > 1.8 ? -4.5 : ratio > 1.3 ? -2.5 : -1.5)
        : (ratio > 2.5 ? -2.5 : ratio > 1.6 ? -1.5 : ratio > 1.15 ? -0.5 : 0);
    // Lignes generees : 5 autour de la main (entiers + demis pour soccer,
    // demis pour NBA car spread NBA est typiquement en .5)
    final List<double> lines;
    if (sport == Sport.basketball) {
      lines = <double>[
        mainLine - 2.0, mainLine - 1.0, mainLine, mainLine + 1.0, mainLine + 2.0
      ];
    } else {
      lines = <double>[
        mainLine - 1.0, mainLine - 0.5, mainLine, mainLine + 0.5, mainLine + 1.0
      ];
    }
    return lines.map((line) {
      // Cote home : si line = -1.5 et favHome -> autour de 1.85
      // Cote away : symetrique
      final basePh = favHome ? ph : pa;
      // Ajustement progressif : +1 ligne dans le sens du favori = +0.15 cote
      final adjust = (line - mainLine) * (favHome ? -1 : 1);
      final homeRaw = 1 / (basePh + adjust * 0.05);
      final awayRaw = 1 / ((1 - basePh) + adjust * 0.05 * -1);
      final homeOddsAh = homeRaw.clamp(1.05, 50).toDouble();
      final awayOddsAh = awayRaw.clamp(1.05, 50).toDouble();
      return AsianHandicapLine(
        line: line,
        homeOdds: (homeOddsAh * 100).round() / 100,
        awayOdds: (awayOddsAh * 100).round() / 100,
        isMain: line == mainLine,
      );
    }).toList();
  }

  /// Convertit en BettingMatch pour reutiliser BettingMatchCard.
  BettingMatch toBettingMatch() {
    return BettingMatch(
      id: id,
      sport: sport,
      leagueId: 'virt',
      homeName: homeName,
      awayName: awayName,
      league: leagueLabel,
      startTime: kickoff.toLocal(),
      isLive: isLive,
      minute: isLive ? virtualMinute : null,
      homeScore: state != VirtualState.upcoming ? homeScore : null,
      awayScore: state != VirtualState.upcoming ? awayScore : null,
      odds: MatchOdds(
        home: homeOdds,
        draw: drawOdds,
        away: awayOdds,
        asianHandicap: generateAh(),
      ),
    );
  }
}

class VirtualMatchService extends ChangeNotifier {
  VirtualMatchService._();
  static final VirtualMatchService instance = VirtualMatchService._();

  static const _log = Logger('VIRTUAL');

  final List<VirtualMatch> _matches = [];
  Timer? _localTicker;       // 1s -> notifyListeners
  Timer? _refreshTimer;      // 30s -> re-fetch fallback
  RealtimeChannel? _channel;
  int _refCount = 0;

  List<VirtualMatch> get matches => List.unmodifiable(_matches);

  /// Start (idempotent + refcount).
  Future<void> start() async {
    _refCount++;
    if (_localTicker != null) return;
    await _refresh();
    _subscribeRealtime();
    _localTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _pruneOld();
      notifyListeners();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refresh();
    });
  }

  void stop() {
    _refCount = (_refCount - 1).clamp(0, 999);
    if (_refCount > 0) return;
    _localTicker?.cancel(); _localTicker = null;
    _refreshTimer?.cancel(); _refreshTimer = null;
    _unsubscribeRealtime();
  }

  /// Recharge la liste depuis la RPC (trigger aussi maintain_pipeline cote serveur).
  Future<void> _refresh() async {
    try {
      final res = await Supabase.instance.client.rpc('get_virtual_matches');
      if (res is! List) return;
      final fresh = <VirtualMatch>[];
      for (final item in res) {
        if (item is Map<String, dynamic>) {
          fresh.add(VirtualMatch.fromJson(item));
        } else if (item is Map) {
          fresh.add(VirtualMatch.fromJson(item.cast<String, dynamic>()));
        }
      }
      _replaceAll(fresh);
      _log.info('refreshed ${fresh.length} virtual matches');
    } catch (e) {
      _log.warn('refresh error: $e');
    }
  }

  void _replaceAll(List<VirtualMatch> fresh) {
    _matches
      ..clear()
      ..addAll(fresh);
    _matches.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    // Prefetch logos (TheSportsDB) pour tous les matchs charges. Les noms
    // virtuels (Real Madrid, Bayern, Al Ahly, NBA teams) sont des equipes
    // reelles -> matchent presque tous via overrides ou recherche directe.
    final logoSvc = TeamLogoService.instance;
    final seen = <String>{};
    for (final m in _matches) {
      if (seen.add('${m.sport.name}:${m.homeName}')) {
        logoSvc.prefetch(m.homeName, m.sport);
      }
      if (seen.add('${m.sport.name}:${m.awayName}')) {
        logoSvc.prefetch(m.awayName, m.sport);
      }
    }
    notifyListeners();
  }

  void _subscribeRealtime() {
    _unsubscribeRealtime();
    final client = Supabase.instance.client;
    _channel = client.channel('virtual_match_changes')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'virtual_match',
        callback: (payload) {
          try {
            final m = VirtualMatch.fromJson(
                payload.newRecord.cast<String, dynamic>());
            _addOrReplace(m);
          } catch (e) {
            _log.warn('realtime parse error: $e');
          }
        },
      )
      ..subscribe();
  }

  void _unsubscribeRealtime() {
    final ch = _channel;
    if (ch == null) return;
    Supabase.instance.client.removeChannel(ch);
    _channel = null;
  }

  void _addOrReplace(VirtualMatch m) {
    final idx = _matches.indexWhere((e) => e.id == m.id);
    if (idx >= 0) {
      _matches[idx] = m;
    } else {
      _matches.add(m);
    }
    _matches.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    notifyListeners();
  }

  /// Supprime localement les matchs > 40s post-kickoff (s'aligne sur SQL).
  void _pruneOld() {
    final now = DateTime.now().toUtc();
    final before = _matches.length;
    _matches.removeWhere(
        (m) => now.difference(m.kickoff).inSeconds > 40);
    if (_matches.length != before) {
      // Pas de notifyListeners ici : sera fait par le ticker
    }
  }
}
