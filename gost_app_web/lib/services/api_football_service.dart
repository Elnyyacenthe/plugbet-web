// ============================================================
// Plugbet – Service API football-data.org (v4)
// Optimisé pour Huawei CAN-L11 (Android 7) : timeouts courts,
// check connectivité, fallback proxy intelligent
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/football_models.dart';
import '../utils/env.dart';
import '../utils/logger.dart';

const _log = Logger('API-FD');

/// Top-level function pour compute() — decode JSON dans un isolate
/// (evite de bloquer le main thread sur les gros payloads ~180KB)
Map<String, dynamic>? _decodeJsonInIsolate(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

class ApiFootballService {
  static const String _apiKey = Env.footballDataApiKey;
  static const String _baseUrl = 'https://api.football-data.org/v4';

  // Proxies pour contourner blocages réseau / CORS
  static const List<String> _proxyPrefixes = [
    'https://api.allorigins.win/raw?url=',
    'https://corsproxy.io/?',
  ];

  final http.Client _client;
  DateTime? _lastRequestTime;
  bool _proxyBlocked = false; // Les proxies retournent 403 → ne plus essayer
  bool _hasConnectivity = true; // Éviter les tentatives DNS si offline
  DateTime? _lastConnectivityCheck;

  ApiFootballService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
    'X-Auth-Token': _apiKey,
    'Content-Type': 'application/json',
  };

  Future<void> _respectRateLimit() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      // football-data.org free tier : 10 requêtes/minute
      if (elapsed.inMilliseconds < 6000) {
        await Future.delayed(
          Duration(milliseconds: 6000 - elapsed.inMilliseconds),
        );
      }
    }
    _lastRequestTime = DateTime.now();
  }

  /// Test rapide de connectivité (évite les tentatives DNS répétées si offline)
  Future<bool> _checkConnectivity() async {
    // Sur le web, Socket.connect() n'existe pas - on assume toujours connecté
    if (kIsWeb) {
      return true;
    }

    // Vérifier max 1 fois par minute
    if (_lastConnectivityCheck != null) {
      final elapsed = DateTime.now().difference(_lastConnectivityCheck!);
      if (elapsed.inSeconds < 300) { // Cache 5 min au lieu de 1 min
        return _hasConnectivity;
      }
    }

    try {
      // Test simple : connexion socket vers Google DNS
      final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 3));
      socket.destroy();
      _hasConnectivity = true;
      _lastConnectivityCheck = DateTime.now();
      return true;
    } catch (e) {
      _log.info('Pas de connectivité réseau: $e');
      _hasConnectivity = false;
      _lastConnectivityCheck = DateTime.now();
      return false;
    }
  }

  /// Requête GET : direct d'abord, proxy seulement si direct échoue ET proxy pas bloqué
  Future<Map<String, dynamic>?> _get(String endpoint) async {
    // Vérifier la connectivité avant de tenter des DNS lookup
    final hasNetwork = await _checkConnectivity();
    if (!hasNetwork) {
      _log.info('Pas de réseau - skip $endpoint');
      return null;
    }

    await _respectRateLimit();
    final directUrl = '$_baseUrl$endpoint';
    _log.info('Requête: $endpoint');

    // 1. Essayer l'Edge Function Supabase en premier (cle serveur cachee)
    final edgeResult = await _tryEdgeFunction(endpoint);
    if (edgeResult != null) return edgeResult;

    // 2. Fallback direct (utilise la cle du client — expose dans l'APK)
    final directResult = await _tryDirect(directUrl);
    if (directResult != null) return directResult;

    // 3. Proxy CORS seulement si pas déjà bloqué (403)
    if (!_proxyBlocked) {
      for (final proxy in _proxyPrefixes) {
        await _respectRateLimit();
        final proxyResult = await _tryProxy(directUrl, proxy);
        if (proxyResult != null) return proxyResult;
      }
    }

    _log.info('Échec pour $endpoint');
    return null;
  }

  /// Tente l'appel via l'Edge Function Supabase `football_proxy`.
  /// La cle API reste cote serveur, jamais expose dans l'APK.
  Future<Map<String, dynamic>?> _tryEdgeFunction(String endpoint) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke(
            'football_proxy',
            body: {'path': endpoint},
          )
          .timeout(const Duration(seconds: 12));

      if (res.status == 200 && res.data != null) {
        _log.info('EdgeFn HTTP 200');
        if (res.data is Map<String, dynamic>) {
          return res.data as Map<String, dynamic>;
        }
        if (res.data is String) {
          final body = res.data as String;
          if (body.length > 20000) {
            return await compute(_decodeJsonInIsolate, body);
          }
          return jsonDecode(body) as Map<String, dynamic>;
        }
      }
      _log.info('EdgeFn HTTP ${res.status}');
    } on TimeoutException {
      _log.info('EdgeFn timeout');
    } catch (e) {
      _log.info('EdgeFn erreur: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _tryDirect(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 12));

      _log.info('Direct HTTP ${response.statusCode} (${response.body.length} bytes)');

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        // Parse en isolate si payload > 20KB (evite le jank sur main thread)
        if (response.body.length > 20000) {
          return await compute(_decodeJsonInIsolate, response.body);
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 429) {
        _log.info('Rate limit 429 – attente 10s');
        await Future.delayed(const Duration(seconds: 10));
      }
    } on TimeoutException {
      _log.info('Timeout direct (12s)');
    } on SocketException catch (e) {
      _log.info('Socket erreur: $e');
    } on HandshakeException catch (e) {
      _log.info('SSL handshake erreur: $e');
    } catch (e) {
      _log.info('Erreur directe: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _tryProxy(String directUrl, String proxyPrefix) async {
    try {
      // Construire l'URL proxy avec le header d'auth encodé dans l'URL
      final separator = directUrl.contains('?') ? '&' : '?';
      final urlWithToken = '$directUrl${separator}X-Auth-Token=$_apiKey';
      final proxyUrl = '$proxyPrefix${Uri.encodeComponent(urlWithToken)}';
      final response = await _client
          .get(Uri.parse(proxyUrl))
          .timeout(const Duration(seconds: 12));

      _log.info('Proxy HTTP ${response.statusCode} (${response.body.length} bytes)');

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        if (response.body.length > 20000) {
          return await compute(_decodeJsonInIsolate, response.body);
        }
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      if (response.statusCode == 403) {
        _log.info('Proxy 403 → désactivé');
        _proxyBlocked = true;
        return null;
      }
    } on TimeoutException {
      _log.info('Timeout proxy');
    } on SocketException catch (e) {
      _log.info('Socket proxy erreur: $e');
    } catch (e) {
      _log.info('Erreur proxy: $e');
    }
    return null;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ============================================================
  // Récupérer les matchs du jour
  // UNE SEULE requête ±3j pour éviter les cascades de rate limit
  // (le free tier ne permet que 10 req/min = 6s entre chaque)
  // ============================================================
  Future<List<FootballMatch>> fetchTodayMatches() async {
    final today = DateTime.now();

    // Requête unique ±3 jours (couvre hier, aujourd'hui, demain + marge)
    // Évite les 3 requêtes cascadées qui bloquent 18s+
    final from = today.subtract(const Duration(days: 3));
    final to = today.add(const Duration(days: 3));
    var matches = await _fetchMatchesForRange(from, to);
    if (matches.isNotEmpty) {
      _log.info('${matches.length} matchs dans ±3j');
      return matches;
    }

    // Si vraiment rien en ±3j, élargir à ±5j (max du free tier)
    _log.info('0 matchs ±3j, élargissement ±5j');
    final weekPast = today.subtract(const Duration(days: 5));
    final weekFuture = today.add(const Duration(days: 5));
    matches = await _fetchMatchesForRange(weekPast, weekFuture);

    return matches;
  }

  Future<List<FootballMatch>> _fetchMatchesForRange(DateTime from, DateTime to) async {
    final fromStr = _formatDate(from);
    final toStr = _formatDate(to);
    final data = await _get('/matches?dateFrom=$fromStr&dateTo=$toStr');
    if (data == null) return [];

    final matchesList = data['matches'] as List? ?? [];
    _log.info('Plage $fromStr → $toStr : ${matchesList.length} matchs');
    return matchesList
        .map((json) {
          try {
            return FootballMatch.fromJson(json as Map<String, dynamic>);
          } catch (e) {
            _log.info('Erreur parsing match: $e');
            return null;
          }
        })
        .whereType<FootballMatch>()
        .toList();
  }

  Future<List<FootballMatch>> fetchMatchesInRange({
    required DateTime from,
    required DateTime to,
  }) async => _fetchMatchesForRange(from, to);

  Future<List<FootballMatch>> fetchCompetitionMatches(String code) async {
    final data = await _get('/competitions/$code/matches?status=SCHEDULED,LIVE,IN_PLAY,PAUSED,FINISHED');
    if (data == null) return [];
    return (data['matches'] as List? ?? [])
        .map((json) {
          try {
            return FootballMatch.fromJson(json as Map<String, dynamic>);
          } catch (e) {
            _log.info('Erreur parsing match: $e');
            return null;
          }
        })
        .whereType<FootballMatch>()
        .toList();
  }

  Future<FootballMatch?> fetchMatchDetail(int matchId) async {
    final data = await _get('/matches/$matchId');
    if (data == null) return null;
    try {
      return FootballMatch.fromJson(data);
    } catch (e) {
      _log.info('Erreur parsing match detail $matchId: $e');
      return null;
    }
  }

  /// Throws [FetchException] si l'API echoue (distingue d'une vraie liste vide).
  Future<List<FootballMatch>> fetchLiveMatches() async {
    final data = await _get('/matches?status=LIVE,IN_PLAY,PAUSED');
    if (data == null) {
      throw const FetchException('fetchLiveMatches failed');
    }
    return (data['matches'] as List? ?? [])
        .map((json) {
          try {
            return FootballMatch.fromJson(json as Map<String, dynamic>);
          } catch (e) {
            _log.info('Erreur parsing live match: $e');
            return null;
          }
        })
        .whereType<FootballMatch>()
        .toList();
  }

  Future<Map<String, Lineup>?> fetchLineups(int matchId) async {
    final data = await _get('/matches/$matchId');
    if (data == null) return null;
    final home = data['homeTeam'] as Map<String, dynamic>?;
    final away = data['awayTeam'] as Map<String, dynamic>?;
    if (home == null || away == null) return null;
    final hl = _parseLineup(home);
    final al = _parseLineup(away);
    if (hl == null && al == null) return null;
    return {if (hl != null) 'home': hl, if (al != null) 'away': al};
  }

  Lineup? _parseLineup(Map<String, dynamic> teamData) {
    final lineup = teamData['lineup'] as List?;
    final bench = teamData['bench'] as List?;
    if (lineup == null || lineup.isEmpty) return null;
    return Lineup(
      formation: teamData['formation'] as String?,
      startingXI: lineup.map((p) => Player.fromJson(p as Map<String, dynamic>)).toList(),
      substitutes: bench?.map((p) => Player.fromJson(p as Map<String, dynamic>)).toList() ?? [],
      coach: teamData['coach']?['name'] as String?,
    );
  }

  /// Détail complet : événements + compositions (depuis /matches/{id})
  Future<MatchDetailData?> fetchMatchDetailFull(int matchId) async {
    final data = await _get('/matches/$matchId');
    if (data == null) return null;
    try {
      final homeTeamData = data['homeTeam'] as Map<String, dynamic>? ?? {};
      final awayTeamData = data['awayTeam'] as Map<String, dynamic>? ?? {};
      final homeTeamId = homeTeamData['id'] as int? ?? 0;

      // Compositions
      final homeLineup = _parseLineup(homeTeamData);
      final awayLineup = _parseLineup(awayTeamData);

      // Événements
      final events = <MatchEvent>[];

      // Buts
      for (final g in (data['goals'] as List? ?? [])) {
        final goal = g as Map<String, dynamic>;
        final teamId = goal['team']?['id'] as int? ?? 0;
        events.add(MatchEvent(
          minute: goal['minute'] as int? ?? 0,
          type: 'GOAL',
          detail: goal['type'] as String?,
          playerName: goal['scorer']?['name'] as String?,
          teamName: goal['team']?['name'] as String?,
          isHomeTeam: teamId == homeTeamId,
          assistPlayerName: goal['assist']?['name'] as String?,
        ));
      }

      // Cartons
      for (final b in (data['bookings'] as List? ?? [])) {
        final booking = b as Map<String, dynamic>;
        final teamId = booking['team']?['id'] as int? ?? 0;
        events.add(MatchEvent(
          minute: booking['minute'] as int? ?? 0,
          type: booking['card'] as String? ?? 'YELLOW_CARD',
          playerName: booking['player']?['name'] as String?,
          teamName: booking['team']?['name'] as String?,
          isHomeTeam: teamId == homeTeamId,
        ));
      }

      // Remplacements
      for (final s in (data['substitutions'] as List? ?? [])) {
        final sub = s as Map<String, dynamic>;
        final teamId = sub['team']?['id'] as int? ?? 0;
        events.add(MatchEvent(
          minute: sub['minute'] as int? ?? 0,
          type: 'SUBSTITUTION',
          playerName: sub['player']?['name'] as String?,
          teamName: sub['team']?['name'] as String?,
          isHomeTeam: teamId == homeTeamId,
          assistPlayerName: sub['playerOut']?['name'] as String?,
        ));
      }

      events.sort((a, b) => a.minute.compareTo(b.minute));

      return MatchDetailData(
        events: events,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
      );
    } catch (e) {
      _log.info('fetchMatchDetailFull error: $e');
      return null;
    }
  }

  void dispose() => _client.close();
}

/// Exception levee quand l'API fetch echoue (timeout, proxy bloque, offline).
/// Distingue d'une vraie liste vide retournee par l'API.
class FetchException implements Exception {
  final String message;
  const FetchException(this.message);
  @override
  String toString() => 'FetchException: $message';
}
