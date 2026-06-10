// ============================================================
// StatpalDiskCache — Persistence disque des donnees StatPal
// ============================================================
// Backend : Hive box (deja en place dans le projet). On stocke du JSON
// sous forme de String pour eviter de maintenir des TypeAdapters Hive
// pour des objets qui changent souvent (MatchOdds + extra markets).
//
// Stockage (1 Box "statpal_cache") :
//   key 'live:{sport}'        -> JSON List<BettingMatch>
//   key 'daily:{sport}'       -> JSON List<BettingMatch>
//   key 'odds:{leagueId}'     -> JSON Map<matchId, MatchOdds>
//   key 'std:{sport}:{lid}'   -> JSON LeagueStanding
//   key 'at:{key}'            -> int millisecondsSinceEpoch (timestamps TTL)
//
// Pattern :
//   await StatpalDiskCache.instance.init();           // boot
//   final m = cache.getLive(Sport.soccer);            // synchrone
//   cache.saveLive(Sport.soccer, matches);            // debounced 1s
//   final age = cache.ageOf('live:soccer');           // pour TTL stale
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'statpal_service.dart';

class StatpalDiskCache {
  StatpalDiskCache._();
  static final StatpalDiskCache instance = StatpalDiskCache._();

  static const _boxName = 'statpal_cache';
  Box<String>? _box;
  bool _ready = false;
  bool get isReady => _ready;

  // Debounce write : coalesce 800ms pour eviter d'ecrire en boucle au splash
  final Map<String, Timer> _writeDebouncers = {};
  static const _debounce = Duration(milliseconds: 800);

  /// A appeler 1 fois au boot. Demande que Hive.initFlutter() ait deja
  /// ete execute (c'est le cas dans main.dart).
  Future<void> init() async {
    if (_ready) return;
    final sw = Stopwatch()..start();
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox<String>(_boxName);
      } else {
        _box = Hive.box<String>(_boxName);
      }
      _ready = true;
      if (kDebugMode) {
        debugPrint('[StatpalDiskCache] init in ${sw.elapsedMilliseconds}ms, '
            '${_box!.length} keys');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[StatpalDiskCache] init failed: $e');
      _ready = false;
    }
  }

  // ── Live matches ──
  String _kLive(Sport sport) => 'live:${sport.name}';

  List<BettingMatch>? getLive(Sport sport) => _readMatchList(_kLive(sport));
  void saveLive(Sport sport, List<BettingMatch> matches) {
    _writeMatchListDebounced(_kLive(sport), matches);
    touchKey(_kLive(sport));
  }

  // ── Daily matches ──
  String _kDaily(Sport sport) => 'daily:${sport.name}';

  List<BettingMatch>? getDaily(Sport sport) => _readMatchList(_kDaily(sport));
  void saveDaily(Sport sport, List<BettingMatch> matches) {
    _writeMatchListDebounced(_kDaily(sport), matches);
    touchKey(_kDaily(sport));
  }

  // ── League prematch odds (par match_id) ──
  String _kOdds(String leagueId) => 'odds:$leagueId';

  Map<String, MatchOdds>? getLeagueOdds(String leagueId) {
    if (!_ready) return null;
    final s = _box!.get(_kOdds(leagueId));
    if (s == null) return null;
    try {
      final m = jsonDecode(s);
      if (m is! Map) return null;
      final out = <String, MatchOdds>{};
      for (final e in m.entries) {
        if (e.value is Map) {
          out[e.key.toString()] = MatchOdds.fromJson(
              (e.value as Map).cast<String, dynamic>());
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  void saveLeagueOdds(String leagueId, Map<String, MatchOdds> odds) {
    _scheduleWrite(_kOdds(leagueId), () {
      final m = odds.map((k, v) => MapEntry(k, v.toJson()));
      _box!.put(_kOdds(leagueId), jsonEncode(m));
    });
    touchKey(_kOdds(leagueId));
  }

  // ── Standings ──
  String _kStanding(Sport sport, String leagueId) =>
      'std:${sport.name}:$leagueId';

  LeagueStanding? getStanding(Sport sport, String leagueId) {
    if (!_ready) return null;
    final s = _box!.get(_kStanding(sport, leagueId));
    if (s == null) return null;
    try {
      final m = jsonDecode(s);
      if (m is! Map) return null;
      final teamsRaw = m['teams'];
      if (teamsRaw is! List) return null;
      return LeagueStanding(
        leagueId: m['leagueId']?.toString() ?? leagueId,
        leagueName: m['leagueName']?.toString() ?? '',
        country: m['country']?.toString() ?? '',
        season: m['season']?.toString() ?? '',
        teams: teamsRaw
            .cast<Map<String, dynamic>>()
            .map((t) => TeamStanding(
                  position: t['p'] as int? ?? 0,
                  teamId: t['i'] as String? ?? '',
                  teamName: t['n'] as String? ?? '',
                  played: t['g'] as int? ?? 0,
                  wins: t['w'] as int? ?? 0,
                  draws: t['d'] as int? ?? 0,
                  losses: t['l'] as int? ?? 0,
                  goalsFor: t['gf'] as int? ?? 0,
                  goalsAgainst: t['ga'] as int? ?? 0,
                  points: t['pt'] as int? ?? 0,
                  form: t['f'] as String?,
                ))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  void saveStanding(Sport sport, String leagueId, LeagueStanding s) {
    _scheduleWrite(_kStanding(sport, leagueId), () {
      _box!.put(_kStanding(sport, leagueId), jsonEncode({
        'leagueId': s.leagueId,
        'leagueName': s.leagueName,
        'country': s.country,
        'season': s.season,
        'teams': s.teams.map((t) => {
          'p': t.position, 'i': t.teamId, 'n': t.teamName,
          'g': t.played, 'w': t.wins, 'd': t.draws, 'l': t.losses,
          'gf': t.goalsFor, 'ga': t.goalsAgainst, 'pt': t.points,
          if (t.form != null) 'f': t.form,
        }).toList(),
      }));
    });
    touchKey(_kStanding(sport, leagueId));
  }

  // ── Helpers prives ──
  List<BettingMatch>? _readMatchList(String key) {
    if (!_ready) return null;
    final s = _box!.get(key);
    if (s == null) return null;
    try {
      final list = jsonDecode(s);
      if (list is! List) return null;
      return list
          .cast<Map<String, dynamic>>()
          .map(BettingMatch.fromJson)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[StatpalDiskCache] decode $key failed: $e');
      return null;
    }
  }

  void _writeMatchListDebounced(String key, List<BettingMatch> list) {
    _scheduleWrite(key, () {
      _box!.put(key, jsonEncode(list.map((m) => m.toJson()).toList()));
    });
  }

  void _scheduleWrite(String key, void Function() write) {
    if (!_ready) return;
    _writeDebouncers[key]?.cancel();
    _writeDebouncers[key] = Timer(_debounce, () {
      try {
        final sw = Stopwatch()..start();
        write();
        if (kDebugMode) {
          debugPrint('[StatpalDiskCache] wrote $key in ${sw.elapsedMilliseconds}ms '
              '(${(_box!.get(key)?.length ?? 0) ~/ 1024}KB)');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[StatpalDiskCache] write $key failed: $e');
      }
      _writeDebouncers.remove(key);
    });
  }

  /// Persist tous les writes en attente (avant kill/dispose).
  Future<void> flush() async {
    for (final t in _writeDebouncers.values) {
      t.cancel();
    }
    _writeDebouncers.clear();
    if (_ready) await _box!.flush();
  }

  /// Timestamp d'ecriture d'une cle (pour decider si stale-while-revalidate).
  String _kAt(String key) => 'at:$key';

  void touchKey(String key) {
    if (!_ready) return;
    _box!.put(_kAt(key), DateTime.now().millisecondsSinceEpoch.toString());
  }

  Duration? ageOf(String key) {
    if (!_ready) return null;
    final atStr = _box!.get(_kAt(key));
    if (atStr == null) return null;
    final at = int.tryParse(atStr);
    if (at == null) return null;
    return DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(at));
  }

  /// True si l'entree existe et est plus jeune que maxAge.
  /// Sinon (manquant ou trop vieux) -> false -> refresh reseau necessaire.
  bool isFresh(String key, Duration maxAge) {
    final age = ageOf(key);
    return age != null && age < maxAge;
  }

  /// Purge complete (debug/reset).
  Future<void> clearAll() async {
    if (!_ready) return;
    await _box!.clear();
  }
}
