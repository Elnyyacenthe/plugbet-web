// ============================================================
// FANTASY MODULE – Service API FPL
// Endpoints officiels FPL + cache Hive + polling intelligent
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/fpl_models.dart';

class FplService {
  static const String _base = 'https://fantasy.premierleague.com/api';

  static const String _boxName    = 'fpl_cache';
  static const String _keyBootstrap = 'bootstrap';
  static const String _keyLivePrefix = 'live_gw_';
  static const String _keyEntryPrefix = 'entry_';
  static const String _keyPicksPrefix = 'picks_';
  static const String _keyElemPrefix = 'element_';

  static const Duration _cacheTtlBootstrap = Duration(hours: 1);
  static const Duration _cacheTtlLive      = Duration(seconds: 30);
  static const Duration _cacheTtlEntry     = Duration(minutes: 5);
  static const Duration _cacheTtlElement   = Duration(hours: 6);

  late Box _box;
  bool _boxOpen = false;

  static final FplService instance = FplService._();
  FplService._();

  Future<void> init() async {
    if (_boxOpen) return;
    _box = await Hive.openBox(_boxName);
    _boxOpen = true;
  }

  // ─── Helpers cache ──────────────────────────────────────

  T? _getCached<T>(String key, Duration ttl, T Function(dynamic) parse) {
    if (!_boxOpen) return null;
    final entry = _box.get(key);
    if (entry == null) return null;
    final ts = entry['ts'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - ts > ttl.inMilliseconds) {
      return null;
    }
    try {
      return parse(entry['data']);
    } catch (_) {
      return null;
    }
  }

  Future<void> _putCache(String key, dynamic data) async {
    if (!_boxOpen) return;
    await _box.put(key, {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
  }

  // ─── HTTP helper ────────────────────────────────────────

  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final uri = Uri.parse('$_base$path');
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      debugPrint('FPL API ${resp.statusCode} for $path');
      return null;
    } catch (e) {
      debugPrint('FPL API error $path: $e');
      return null;
    }
  }

  // ─── Bootstrap Static ───────────────────────────────────

  /// Données globales : joueurs, équipes, GW
  Future<FplBootstrap?> fetchBootstrap({bool forceRefresh = false}) async {
    await init();

    if (!forceRefresh) {
      final cached = _getCached<FplBootstrap>(
        _keyBootstrap, _cacheTtlBootstrap,
        (d) => FplBootstrap.fromJson(d as Map<String, dynamic>),
      );
      if (cached != null) return cached;
    }

    final data = await _get('/bootstrap-static/');
    if (data == null) return null;

    await _putCache(_keyBootstrap, data);
    return FplBootstrap.fromJson(data);
  }

  // ─── Live Gameweek ──────────────────────────────────────

  /// Points live du GW spécifié
  Future<Map<int, FplLiveElement>?> fetchLiveGw(int gw) async {
    await init();
    final key = '$_keyLivePrefix$gw';

    final cached = _getCached<Map<int, FplLiveElement>>(
      key, _cacheTtlLive,
      (d) {
        final map = <int, FplLiveElement>{};
        for (final e in (d as List)) {
          final el = FplLiveElement.fromJson(e as Map<String, dynamic>);
          map[el.id] = el;
        }
        return map;
      },
    );
    if (cached != null) return cached;

    final data = await _get('/event/$gw/live/');
    if (data == null) return null;

    final elements = data['elements'] as List? ?? [];
    await _putCache(key, elements);

    final map = <int, FplLiveElement>{};
    for (final e in elements) {
      final el = FplLiveElement.fromJson(e as Map<String, dynamic>);
      map[el.id] = el;
    }
    return map;
  }

  // ─── Element Summary ────────────────────────────────────

  /// Historique + prochains matchs d'un joueur
  Future<FplElementSummary?> fetchElementSummary(int elementId) async {
    await init();
    final key = '$_keyElemPrefix$elementId';

    final cached = _getCached<FplElementSummary>(
      key, _cacheTtlElement,
      (d) => FplElementSummary.fromJson(d as Map<String, dynamic>),
    );
    if (cached != null) return cached;

    final data = await _get('/element-summary/$elementId/');
    if (data == null) return null;

    await _putCache(key, data);
    return FplElementSummary.fromJson(data);
  }

  // ─── Entry (équipe utilisateur) ─────────────────────────

  /// Infos générales d'un manager FPL
  Future<FplEntry?> fetchEntry(int entryId) async {
    await init();
    final key = '$_keyEntryPrefix$entryId';

    final cached = _getCached<FplEntry>(
      key, _cacheTtlEntry,
      (d) => FplEntry.fromJson(d as Map<String, dynamic>),
    );
    if (cached != null) return cached;

    final data = await _get('/entry/$entryId/');
    if (data == null) return null;

    await _putCache(key, data);
    return FplEntry.fromJson(data);
  }

  /// Picks de l'équipe pour un GW donné
  Future<FplMyTeam?> fetchEntryPicks(int entryId, int gw) async {
    await init();
    final key = '$_keyPicksPrefix${entryId}_$gw';

    final cached = _getCached<FplMyTeam>(
      key, _cacheTtlEntry,
      (d) => FplMyTeam.fromJson(d as Map<String, dynamic>),
    );
    if (cached != null) return cached;

    final data = await _get('/entry/$entryId/event/$gw/picks/');
    if (data == null) return null;

    await _putCache(key, data);
    return FplMyTeam.fromJson(data);
  }

  // ─── Fixtures ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchFixtures({int? gw}) async {
    final path = gw != null ? '/fixtures/?event=$gw' : '/fixtures/';
    final data = await _get(path);
    if (data == null) return [];
    // fixtures endpoint retourne une liste directement
    return [];
  }

  // ─── Value picks (top forme / prix) ─────────────────────

  /// Retourne les meilleurs joueurs < budget £M, triés par forme
  List<FplElement> getValuePicks(
    FplBootstrap bootstrap, {
    double maxCost = 6.0,
    int limit = 5,
  }) {
    return bootstrap.elements
        .where((e) =>
            e.costInMillions <= maxCost &&
            e.chanceOfPlayingNextRound >= 75 &&
            (e.news == null || e.news!.isEmpty))
        .toList()
      ..sort((a, b) =>
          double.parse(b.form).compareTo(double.parse(a.form)))
      ..take(limit);
  }

  /// Top performers du GW (par total_points live)
  List<MapEntry<FplElement, int>> getTopLive(
    FplBootstrap bootstrap,
    Map<int, FplLiveElement> live, {
    int limit = 5,
  }) {
    final result = <MapEntry<FplElement, int>>[];
    for (final entry in live.entries) {
      final el = bootstrap.elementById(entry.key);
      if (el != null) {
        result.add(MapEntry(el, entry.value.stats.totalPoints));
      }
    }
    result.sort((a, b) => b.value.compareTo(a.value));
    return result.take(limit).toList();
  }

  // ─── Clear cache ────────────────────────────────────────

  Future<void> clearCache() async {
    await init();
    await _box.clear();
  }
}
