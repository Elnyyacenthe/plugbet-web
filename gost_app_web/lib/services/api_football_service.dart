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
import '../models/football_models.dart';

class ApiFootballService {
  static const String _apiKey = '5bb26437b46b43689663390841d6f469';
  static const String _baseUrl = kIsWeb
      ? '/api/proxy?target=football-data&path='
      : 'https://api.football-data.org/v4';

  // Proxies pour contourner blocages réseau / CORS (mobile uniquement)
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

  /// Test rapide de connectivité — sur le web Socket n'existe pas
  Future<bool> _checkConnectivity() async {
    if (kIsWeb) return true;
    if (_lastConnectivityCheck != null) {
      final elapsed = DateTime.now().difference(_lastConnectivityCheck!);
      if (elapsed.inSeconds < 300) {
        return _hasConnectivity;
      }
    }

    try {
      final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 3));
      socket.destroy();
      _hasConnectivity = true;
      _lastConnectivityCheck = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('[API-FD] Pas de connectivité réseau: $e');
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
      debugPrint('[API-FD] Pas de réseau - skip $endpoint');
      return null;
    }

    await _respectRateLimit();
    final directUrl = '$_baseUrl$endpoint';
    debugPrint('[API-FD] Requête: $endpoint');

    // 1. Toujours essayer en direct d'abord (fonctionne sur mobile)
    final directResult = await _tryDirect(directUrl);
    if (directResult != null) return directResult;

    // 2. Proxy seulement si pas déjà bloqué (403)
    if (!_proxyBlocked) {
      for (final proxy in _proxyPrefixes) {
        await _respectRateLimit();
        final proxyResult = await _tryProxy(directUrl, proxy);
        if (proxyResult != null) return proxyResult;
      }
    }

    debugPrint('[API-FD] Échec pour $endpoint');
    return null;
  }

  Future<Map<String, dynamic>?> _tryDirect(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 12));

      debugPrint('[API-FD] Direct HTTP ${response.statusCode} (${response.body.length} bytes)');

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 429) {
        debugPrint('[API-FD] Rate limit 429 – attente 10s');
        await Future.delayed(const Duration(seconds: 10));
      }
    } on TimeoutException {
      debugPrint('[API-FD] Timeout direct (12s)');
    } on SocketException catch (e) {
      debugPrint('[API-FD] Socket erreur: $e');
    } on HandshakeException catch (e) {
      debugPrint('[API-FD] SSL handshake erreur: $e');
    } catch (e) {
      debugPrint('[API-FD] Erreur directe: $e');
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

      debugPrint('[API-FD] Proxy HTTP ${response.statusCode} (${response.body.length} bytes)');

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      if (response.statusCode == 403) {
        debugPrint('[API-FD] Proxy 403 → désactivé');
        _proxyBlocked = true;
        return null;
      }
    } on TimeoutException {
      debugPrint('[API-FD] Timeout proxy');
    } on SocketException catch (e) {
      debugPrint('[API-FD] Socket proxy erreur: $e');
    } catch (e) {
      debugPrint('[API-FD] Erreur proxy: $e');
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
      debugPrint('[API-FD] ${matches.length} matchs dans ±3j');
      return matches;
    }

    // Si vraiment rien en ±3j, élargir à ±5j (max du free tier)
    debugPrint('[API-FD] 0 matchs ±3j, élargissement ±5j');
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
    debugPrint('[API-FD] Plage $fromStr → $toStr : ${matchesList.length} matchs');
    return matchesList
        .map((json) {
          try {
            return FootballMatch.fromJson(json as Map<String, dynamic>);
          } catch (e) {
            debugPrint('[API-FD] Erreur parsing match: $e');
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
            debugPrint('[API-FD] Erreur parsing match: $e');
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
      debugPrint('[API-FD] Erreur parsing match detail $matchId: $e');
      return null;
    }
  }

  Future<List<FootballMatch>> fetchLiveMatches() async {
    final data = await _get('/matches?status=LIVE,IN_PLAY,PAUSED');
    if (data == null) return [];
    return (data['matches'] as List? ?? [])
        .map((json) {
          try {
            return FootballMatch.fromJson(json as Map<String, dynamic>);
          } catch (e) {
            debugPrint('[API-FD] Erreur parsing live match: $e');
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
      debugPrint('[API-FD] fetchMatchDetailFull error: $e');
      return null;
    }
  }

  void dispose() => _client.close();
}
