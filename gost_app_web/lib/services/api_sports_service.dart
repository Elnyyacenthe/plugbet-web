// ============================================================
// Plugbet – Service apifootball.com (v3)
// Matchs en direct, résultats, événements, compositions
// https://apifootball.com/documentation/
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/football_models.dart';

class ApiSportsService {
  static const String _baseUrl = 'https://apiv3.apifootball.com/';

  String _apiKey;
  final http.Client _client;
  DateTime? _lastRequestTime;
  bool _hasConnectivity = true;
  DateTime? _lastConnectivityCheck;

  ApiSportsService({String? apiKey, http.Client? client})
      : _apiKey = apiKey ?? '',
        _client = client ?? http.Client();

  void setApiKey(String key) => _apiKey = key;
  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Rate limit basique (500ms entre requêtes)
  Future<void> _respectRateLimit() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed.inMilliseconds < 500) {
        await Future.delayed(
          Duration(milliseconds: 500 - elapsed.inMilliseconds),
        );
      }
    }
    _lastRequestTime = DateTime.now();
  }

  Future<bool> _checkConnectivity() async {
    if (kIsWeb) return true;
    if (_lastConnectivityCheck != null) {
      final elapsed = DateTime.now().difference(_lastConnectivityCheck!);
      if (elapsed.inSeconds < 60) {
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
      debugPrint('[APIFOOTBALL] Pas de connectivité réseau: $e');
      _hasConnectivity = false;
      _lastConnectivityCheck = DateTime.now();
      return false;
    }
  }

  Future<List<dynamic>?> _get(String params) async {
    if (!hasApiKey) {
      debugPrint('[APIFOOTBALL] Pas de clé API configurée');
      return null;
    }

    // Vérifier la connectivité avant DNS lookup
    final hasNetwork = await _checkConnectivity();
    if (!hasNetwork) {
      debugPrint('[APIFOOTBALL] Pas de réseau - skip');
      return null;
    }

    await _respectRateLimit();
    // Forcer timezone UTC pour que les heures soient converties correctement
    // en heure locale sur chaque appareil via DateTime.toLocal()
    final url = '$_baseUrl?APIkey=$_apiKey&timezone=Etc/UTC&$params';
    debugPrint('[APIFOOTBALL] Requête: $params');

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);

        // L'API renvoie un objet {"error":...} en cas d'erreur
        if (decoded is Map && decoded.containsKey('error')) {
          debugPrint('[APIFOOTBALL] Erreur API: ${decoded['error']} – ${decoded['message'] ?? ''}');
          return null;
        }

        if (decoded is List) {
          debugPrint('[APIFOOTBALL] Succès: ${decoded.length} résultats');
          return decoded;
        }

        debugPrint('[APIFOOTBALL] Réponse inattendue: ${response.body.substring(0, 200.clamp(0, response.body.length))}');
        return null;
      }
      debugPrint('[APIFOOTBALL] HTTP ${response.statusCode}');
    } on TimeoutException {
      debugPrint('[APIFOOTBALL] Timeout (12s)');
    } on SocketException catch (e) {
      debugPrint('[APIFOOTBALL] Socket erreur: $e');
    } on HandshakeException catch (e) {
      debugPrint('[APIFOOTBALL] SSL handshake erreur: $e');
    } catch (e) {
      debugPrint('[APIFOOTBALL] Erreur: $e');
    }
    return null;
  }

  // ============================================================
  // Matchs du jour
  // ============================================================
  Future<List<FootballMatch>> fetchTodayMatches() async {
    final today = _formatDate(DateTime.now());
    final data = await _get('action=get_events&from=$today&to=$today');
    if (data == null) return [];
    return _parseMatches(data);
  }

  // ============================================================
  // Matchs en direct
  // ============================================================
  Future<List<FootballMatch>> fetchLiveMatches() async {
    final data = await _get('action=get_events&match_live=1');
    if (data == null) return [];
    return _parseMatches(data);
  }

  // ============================================================
  // Matchs par plage de dates
  // ============================================================
  Future<List<FootballMatch>> fetchMatchesInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final fromStr = _formatDate(from);
    final toStr = _formatDate(to);
    final data = await _get('action=get_events&from=$fromStr&to=$toStr');
    if (data == null) return [];
    return _parseMatches(data);
  }

  // ============================================================
  // Détail d'un match
  // ============================================================
  Future<FootballMatch?> fetchMatchDetail(int matchId) async {
    final data = await _get('action=get_events&match_id=$matchId');
    if (data == null || data.isEmpty) return null;
    final matches = _parseMatches(data);
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Détail complet : événements + stats + compositions (action=get_events&match_id)
  Future<MatchDetailData?> fetchMatchDetailFull(int matchId) async {
    final data = await _get('action=get_events&match_id=$matchId');
    if (data == null || data.isEmpty) return null;
    final m = data.first as Map<String, dynamic>;
    try {
      final events = <MatchEvent>[];

      // Buteurs
      for (final g in (m['goalscorer'] as List? ?? [])) {
        final gs = g as Map<String, dynamic>;
        final time = int.tryParse(gs['time']?.toString() ?? '') ?? 0;
        final homeScorer = gs['home_scorer'] as String? ?? '';
        final awayScorer = gs['away_scorer'] as String? ?? '';
        final info = gs['score_info'] as String?;
        if (homeScorer.isNotEmpty) {
          events.add(MatchEvent(
            minute: time, type: 'GOAL', detail: info,
            playerName: homeScorer,
            assistPlayerName: gs['home_assist'] as String?,
            isHomeTeam: true,
          ));
        } else if (awayScorer.isNotEmpty) {
          events.add(MatchEvent(
            minute: time, type: 'GOAL', detail: info,
            playerName: awayScorer,
            assistPlayerName: gs['away_assist'] as String?,
            isHomeTeam: false,
          ));
        }
      }

      // Cartons
      for (final c in (m['cards'] as List? ?? [])) {
        final card = c as Map<String, dynamic>;
        final time = int.tryParse(card['time']?.toString() ?? '') ?? 0;
        final cardStr = (card['card'] as String? ?? '').toLowerCase();
        final type = cardStr.contains('red') ? 'RED_CARD' : 'YELLOW_CARD';
        final homeFault = card['home_fault'] as String? ?? '';
        final awayFault = card['away_fault'] as String? ?? '';
        if (homeFault.isNotEmpty) {
          events.add(MatchEvent(minute: time, type: type, playerName: homeFault, isHomeTeam: true));
        } else if (awayFault.isNotEmpty) {
          events.add(MatchEvent(minute: time, type: type, playerName: awayFault, isHomeTeam: false));
        }
      }

      // Remplacements
      final subs = m['substitutions'] as Map<String, dynamic>?;
      if (subs != null) {
        for (final s in (subs['home'] as List? ?? [])) {
          final sub = s as Map<String, dynamic>;
          final time = int.tryParse(sub['time']?.toString() ?? '') ?? 0;
          events.add(MatchEvent(
            minute: time, type: 'SUBSTITUTION',
            playerName: sub['scorer'] as String?,
            assistPlayerName: sub['assist'] as String?,
            isHomeTeam: true,
          ));
        }
        for (final s in (subs['away'] as List? ?? [])) {
          final sub = s as Map<String, dynamic>;
          final time = int.tryParse(sub['time']?.toString() ?? '') ?? 0;
          events.add(MatchEvent(
            minute: time, type: 'SUBSTITUTION',
            playerName: sub['scorer'] as String?,
            assistPlayerName: sub['assist'] as String?,
            isHomeTeam: false,
          ));
        }
      }

      events.sort((a, b) => a.minute.compareTo(b.minute));

      // Statistiques
      MatchStats? stats;
      final statsData = m['statistics'] as List? ?? [];
      if (statsData.isNotEmpty) {
        int? homePoss, awayPoss, homeShots, awayShots, homeSOT, awaySOT, homeCorners, awayCorners, homeFouls, awayFouls;
        for (final s in statsData) {
          final stat = s as Map<String, dynamic>;
          final type = (stat['type'] as String? ?? '').toLowerCase();
          final home = stat['home'] as String? ?? '';
          final away = stat['away'] as String? ?? '';
          if (type.contains('possession')) {
            homePoss = int.tryParse(home.replaceAll('%', '').trim());
            awayPoss = int.tryParse(away.replaceAll('%', '').trim());
          } else if (type.contains('shots on target')) {
            homeSOT = int.tryParse(home.trim());
            awaySOT = int.tryParse(away.trim());
          } else if (type.contains('shots') && !type.contains('on')) {
            homeShots = int.tryParse(home.trim());
            awayShots = int.tryParse(away.trim());
          } else if (type.contains('corner')) {
            homeCorners = int.tryParse(home.trim());
            awayCorners = int.tryParse(away.trim());
          } else if (type.contains('foul')) {
            homeFouls = int.tryParse(home.trim());
            awayFouls = int.tryParse(away.trim());
          }
        }
        stats = MatchStats(
          homePossession: homePoss, awayPossession: awayPoss,
          homeShots: homeShots, awayShots: awayShots,
          homeShotsOnTarget: homeSOT, awayShotsOnTarget: awaySOT,
          homeCorners: homeCorners, awayCorners: awayCorners,
          homeFouls: homeFouls, awayFouls: awayFouls,
        );
      }

      // Compositions
      Lineup? homeLineup, awayLineup;
      final lineupsData = m['lineups'] as Map<String, dynamic>?;
      if (lineupsData != null) {
        homeLineup = _parseApiSportsLineup(lineupsData['home'] as Map<String, dynamic>?);
        awayLineup = _parseApiSportsLineup(lineupsData['away'] as Map<String, dynamic>?);
      }

      return MatchDetailData(events: events, stats: stats, homeLineup: homeLineup, awayLineup: awayLineup);
    } catch (e) {
      debugPrint('[APIFOOTBALL] fetchMatchDetailFull error: $e');
      return null;
    }
  }

  Lineup? _parseApiSportsLineup(Map<String, dynamic>? data) {
    if (data == null) return null;
    final starting = data['starting_lineups'] as List? ?? [];
    if (starting.isEmpty) return null;
    Player playerFromJson(Map<String, dynamic> p) => Player(
      id: int.tryParse(p['player_id']?.toString() ?? '0') ?? 0,
      name: p['lineup_player'] as String? ?? '',
      shirtNumber: int.tryParse(p['lineup_number']?.toString() ?? ''),
      position: p['lineup_position'] as String?,
    );
    final coaches = data['coach'] as List? ?? [];
    return Lineup(
      formation: data['formation'] as String?,
      startingXI: starting.map((p) => playerFromJson(p as Map<String, dynamic>)).toList(),
      substitutes: (data['substitutes'] as List? ?? []).map((p) => playerFromJson(p as Map<String, dynamic>)).toList(),
      coach: coaches.isNotEmpty ? (coaches.first as Map<String, dynamic>)['lineup_player'] as String? : null,
    );
  }

  // ============================================================
  // PARSING
  // ============================================================

  List<FootballMatch> _parseMatches(List<dynamic> data) {
    return data.map((json) {
      final m = json as Map<String, dynamic>;

      // Events et stats supprimés pour optimisation performances

      final homeScore = int.tryParse(m['match_hometeam_score']?.toString() ?? '');
      final awayScore = int.tryParse(m['match_awayteam_score']?.toString() ?? '');
      final homeHt = int.tryParse(m['match_hometeam_halftime_score']?.toString() ?? '');
      final awayHt = int.tryParse(m['match_awayteam_halftime_score']?.toString() ?? '');

      return FootballMatch(
        id: int.tryParse(m['match_id']?.toString() ?? '0') ?? 0,
        competition: Competition(
          id: int.tryParse(m['league_id']?.toString() ?? '0') ?? 0,
          name: m['league_name'] as String? ?? 'Inconnu',
          emblemUrl: m['league_logo'] as String?,
          code: null,
          areaName: m['country_name'] as String?,
        ),
        homeTeam: Team(
          id: int.tryParse(m['match_hometeam_id']?.toString() ?? '0') ?? 0,
          name: m['match_hometeam_name'] as String? ?? 'Inconnu',
          shortName: _shortName(m['match_hometeam_name'] as String? ?? 'Inconnu'),
          crestUrl: m['team_home_badge'] as String?,
          tla: _tla(m['match_hometeam_name'] as String? ?? 'INC'),
        ),
        awayTeam: Team(
          id: int.tryParse(m['match_awayteam_id']?.toString() ?? '0') ?? 0,
          name: m['match_awayteam_name'] as String? ?? 'Inconnu',
          shortName: _shortName(m['match_awayteam_name'] as String? ?? 'Inconnu'),
          crestUrl: m['team_away_badge'] as String?,
          tla: _tla(m['match_awayteam_name'] as String? ?? 'INC'),
        ),
        score: Score(
          homeFullTime: homeScore,
          awayFullTime: awayScore,
          homeHalfTime: homeHt,
          awayHalfTime: awayHt,
        ),
        statusStr: _mapStatus(m['match_status'] as String?, m['match_live'] as String?),
        utcDate: _buildUtcDate(m['match_date'] as String?, m['match_time'] as String?),
        matchday: int.tryParse(m['match_round']?.toString() ?? ''),
        minute: _extractMinute(m['match_status'] as String?, m['match_live'] as String?),
        stage: m['match_round'] as String?,
      );
    }).toList();
  }

  /// Mappe le statut apifootball.com → notre format
  /// IMPORTANT: verifier le statut textuel AVANT matchLive
  /// car matchLive='1' meme pendant Half Time, After ET, etc.
  String _mapStatus(String? status, String? matchLive) {
    if (status == null || status.isEmpty) return 'TIMED';

    final s = status.trim();

    // Verifier les statuts explicites EN PREMIER (avant matchLive)
    switch (s) {
      case 'Finished':
      case 'After ET':
      case 'After Pen.':
        return 'FINISHED';
      case 'Half Time':
        return 'PAUSED';
      case 'Extra Time':
      case 'Pen.':
      case 'Penalty':
        return 'IN_PLAY';
      case 'Not Started':
      case '':
        return 'TIMED';
      case 'Postponed':
        return 'POSTPONED';
      case 'Cancelled':
        return 'CANCELLED';
      case 'Suspended':
        return 'SUSPENDED';
      case 'Awarded':
        return 'AWARDED';
    }

    // Ensuite: si matchLive = 1, c'est en cours
    if (matchLive == '1') return 'IN_PLAY';

    // Si c'est un nombre (minute), c'est en cours
    if (RegExp(r'^\d').hasMatch(s)) return 'IN_PLAY';

    return 'TIMED';
  }

  /// Extrait la minute du match depuis match_status
  /// apifootball.com met la minute dans match_status pour les matchs live (ex: "45", "67", "45+2")
  /// Pour "Half Time" → 45, "Finished" → 90, sinon parse le nombre
  int? _extractMinute(String? status, String? matchLive) {
    if (status == null || status.isEmpty) return null;
    final s = status.trim();

    if (s == 'Half Time') return 45;
    if (s == 'Finished') return 90;
    if (s == 'After ET') return 120;
    if (s == 'After Pen.') return 120;
    if (s == 'Extra Time') return 91;
    if (s == 'Pen.' || s == 'Penalty') return 120;
    if (s == 'Not Started') return null;

    // Extraire le nombre (ex: "45", "45+2", "90+3")
    final m = RegExp(r'(\d+)').firstMatch(s);
    if (m != null) {
      final base = int.tryParse(m.group(1)!) ?? 0;
      // Gérer "45+2" → 47
      final extra = RegExp(r'\+(\d+)').firstMatch(s);
      if (extra != null) {
        return base + (int.tryParse(extra.group(1)!) ?? 0);
      }
      // Si c'est 0 et le match est live, c'est le coup d'envoi
      if (base == 0 && matchLive == '1') return 1;
      return base > 0 ? base : null;
    }

    return null;
  }

  String _buildUtcDate(String? date, String? time) {
    if (date == null) return DateTime.now().toIso8601String();
    final t = time ?? '00:00';
    return '${date}T$t:00Z';
  }

  String _shortName(String name) {
    if (name.length <= 12) return name;
    // Essayer de prendre le premier mot significatif
    final parts = name.split(' ');
    if (parts.length > 1 && parts[0].length > 2) return parts[0];
    return name.substring(0, 12);
  }

  String _tla(String name) {
    if (name.length < 3) return name.toUpperCase();
    return name.substring(0, 3).toUpperCase();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void dispose() => _client.close();
}
