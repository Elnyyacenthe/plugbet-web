// ============================================================
// FANTASY MODULE – Service Supabase
// Gestion équipes, picks, ligues — tout dans l'app
// L'API FPL est seulement utilisée pour les données joueurs
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// ─── Exceptions métier ────────────────────────────────────

class FantasyException implements Exception {
  final String code;    // identifiant machine
  final String message; // message lisible utilisateur

  const FantasyException(this.code, this.message);

  @override
  String toString() => 'FantasyException[$code]: $message';
}

// Codes d'erreur constants
abstract class FantasyError {
  static const notLoggedIn    = 'NOT_LOGGED_IN';
  static const alreadyExists  = 'TEAM_ALREADY_EXISTS';
  static const notFound       = 'TEAM_NOT_FOUND';
  static const budgetInsuffisant = 'BUDGET_INSUFFISANT';
  static const playerAlreadyIn   = 'PLAYER_ALREADY_IN_TEAM';
  static const leagueNotFound    = 'LEAGUE_NOT_FOUND';
  static const networkError      = 'NETWORK_ERROR';
  static const serverError       = 'SERVER_ERROR';
}

// ─── Service ──────────────────────────────────────────────

class FantasyService {
  static final FantasyService instance = FantasyService._();
  FantasyService._();

  SupabaseClient get _db => Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw const FantasyException(
          FantasyError.notLoggedIn, 'Vous devez être connecté.');
    }
    return uid;
  }

  // ─── Équipe ───────────────────────────────────────────────

  /// Retourne l'équipe ou null si elle n'existe pas.
  Future<Map<String, dynamic>?> getMyTeam() async {
    try {
      _requireUid();
      final res = await _db
          .from('fantasy_teams')
          .select()
          .eq('user_id', _uid!)
          .maybeSingle();
      return res;
    } on FantasyException {
      rethrow;
    } catch (e) {
      debugPrint('getMyTeam: $e');
      return null; // pas d'équipe ou erreur réseau → affiche le banner
    }
  }

  /// Crée une équipe.
  /// Lance [FantasyException] avec un message lisible en cas d'échec.
  Future<Map<String, dynamic>> createTeam({
    required String teamName,
    required int initialBudget,
  }) async {
    final uid = _requireUid();

    // Equipe déjà existante ?
    final existing = await getMyTeam();
    if (existing != null) return existing;

    try {
      final res = await _db.from('fantasy_teams').insert({
        'user_id': uid,
        'team_name': teamName,
        'budget': initialBudget,
        'total_value': initialBudget,
        'total_points': 0,
        'gameweek_points': 0,
      }).select().single();
      return res;
    } on PostgrestException catch (e) {
      debugPrint('createTeam Postgrest: ${e.code} ${e.message}');
      if (e.code == '23505') {
        throw const FantasyException(
            FantasyError.alreadyExists, 'Vous avez déjà une équipe Fantasy.');
      }
      throw FantasyException(FantasyError.serverError,
          'Impossible de créer l\'équipe : ${e.message}');
    } catch (e) {
      debugPrint('createTeam: $e');
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau. Vérifiez votre connexion.');
    }
  }

  Future<void> updateTeamName(String teamId, String name) async {
    try {
      await _db
          .from('fantasy_teams')
          .update({'team_name': name})
          .eq('id', teamId);
    } on PostgrestException catch (e) {
      throw FantasyException(FantasyError.serverError,
          'Impossible de renommer l\'équipe : ${e.message}');
    } catch (e) {
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  /// Met à jour la formation tactique de l'équipe.
  Future<void> saveFormation(String teamId, String formation) async {
    try {
      await _db
          .from('fantasy_teams')
          .update({'formation': formation})
          .eq('id', teamId);
    } on PostgrestException catch (e) {
      throw FantasyException(FantasyError.serverError,
          'Erreur sauvegarde formation : ${e.message}');
    } catch (e) {
      throw const FantasyException(FantasyError.networkError, 'Erreur réseau.');
    }
  }

  /// Sauvegarde les ordres tactiques du coach.
  Future<void> saveTactics({
    required String teamId,
    required String playStyle,
    required String mentality,
    required String pressing,
    required String tempo,
    required String width,
  }) async {
    try {
      await _db.from('fantasy_teams').update({
        'tactics': {
          'play_style': playStyle,
          'mentality': mentality,
          'pressing': pressing,
          'tempo': tempo,
          'width': width,
        },
      }).eq('id', teamId);
    } on PostgrestException catch (e) {
      throw FantasyException(FantasyError.serverError,
          'Erreur sauvegarde tactiques : ${e.message}');
    } catch (e) {
      throw const FantasyException(FantasyError.networkError, 'Erreur réseau.');
    }
  }

  /// Sauvegarde l'ordre de priorité des remplaçants.
  Future<void> saveBenchOrder({
    required String teamId,
    required List<Map<String, dynamic>> benchPicks,
  }) async {
    try {
      for (final pick in benchPicks) {
        await _db
            .from('fantasy_picks')
            .update({'bench_order': pick['bench_order'] as int? ?? 99})
            .eq('team_id', teamId)
            .eq('element_id', pick['element_id'] as int);
      }
    } on PostgrestException catch (e) {
      throw FantasyException(FantasyError.serverError,
          'Erreur sauvegarde ordre banc : ${e.message}');
    } catch (e) {
      throw const FantasyException(FantasyError.networkError, 'Erreur réseau.');
    }
  }

  // ─── Deadline ─────────────────────────────────────────────

  /// La deadline du prochain GW. Null = pas de deadline connue.
  DateTime? _nextDeadline;

  /// Met à jour la deadline depuis le bootstrap FPL.
  void setDeadline(DateTime? deadline) => _nextDeadline = deadline;

  /// Vérifie si les transferts sont encore autorisés.
  /// Lance [FantasyException] si la deadline est passée.
  /// Le Wildcard et Free Hit ignorent la deadline.
  void _checkDeadline({bool hasWildcard = false}) {
    if (hasWildcard) return; // Wildcard bypass
    if (_nextDeadline != null && DateTime.now().isAfter(_nextDeadline!)) {
      throw const FantasyException(
        'DEADLINE_PASSED',
        'La deadline est passée. Transferts bloqués jusqu\'au prochain GW.',
      );
    }
  }

  // ─── Picks ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPicks(String teamId) async {
    try {
      final res = await _db
          .from('fantasy_picks')
          .select()
          .eq('team_id', teamId)
          .order('position');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('getPicks: $e');
      return [];
    }
  }

  /// Ajoute un joueur.
  /// Lance [FantasyException] si budget insuffisant, joueur déjà présent ou max 3 par club.
  Future<void> addPlayer({
    required String teamId,
    required int elementId,
    required int position,
    required int coinsPrice,
    required int clubTeamId,
  }) async {
    final uid = _requireUid();
    _checkDeadline();

    // ── Vérif max 3 joueurs du même club ──
    try {
      final existing = await _db
          .from('fantasy_picks')
          .select('element_id')
          .eq('team_id', teamId);
      // On ne peut pas faire le JOIN facilement ici, on passe clubTeamId
      // depuis le front pour compter les joueurs du même club
      final sameClubCount = (existing as List)
          .where((p) => p['club_team_id'] == clubTeamId)
          .length;
      if (sameClubCount >= 3) {
        throw const FantasyException(
          'MAX_CLUB',
          'Vous avez déjà 3 joueurs de ce club (règle FPL max 3).',
        );
      }
    } on FantasyException {
      rethrow;
    } catch (_) {}

    try {
      await _db.from('fantasy_picks').upsert({
        'team_id': teamId,
        'user_id': uid,
        'element_id': elementId,
        'position': position,
        'is_captain': false,
        'is_vice_captain': false,
        'is_starter': position <= 11,
        'purchase_price': coinsPrice,
        'club_team_id': clubTeamId,
      });

      await _db.rpc('fantasy_spend_budget', params: {
        'p_team_id': teamId,
        'p_amount': coinsPrice,
      });

      // Incrémenter gw_transfers (pour la pénalité)
      await _db.rpc('fantasy_increment_gw_transfers',
          params: {'p_team_id': teamId});
    } on PostgrestException catch (e) {
      debugPrint('addPlayer Postgrest: ${e.code} ${e.message}');
      if (e.code == '23505') {
        throw const FantasyException(FantasyError.playerAlreadyIn,
            'Ce joueur est déjà dans votre équipe.');
      }
      if (e.message.contains('BUDGET_INSUFFISANT')) {
        throw const FantasyException(FantasyError.budgetInsuffisant,
            'Budget insuffisant pour ce joueur.');
      }
      throw FantasyException(
          FantasyError.serverError, 'Erreur ajout joueur : ${e.message}');
    } on FantasyException {
      rethrow;
    } catch (e) {
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  // ─── Composition (starters / banc) ───────────────────────

  /// Sauvegarde la composition : is_starter pour chaque pick.
  Future<void> saveLineup({
    required String teamId,
    required List<Map<String, dynamic>> picks,
  }) async {
    _requireUid();
    try {
      for (final pick in picks) {
        await _db
            .from('fantasy_picks')
            .update({'is_starter': pick['is_starter'] as bool? ?? true})
            .eq('team_id', teamId)
            .eq('element_id', pick['element_id'] as int);
      }
    } on PostgrestException catch (e) {
      throw FantasyException(
          FantasyError.serverError, 'Erreur sauvegarde composition : ${e.message}');
    } catch (e) {
      throw const FantasyException(FantasyError.networkError, 'Erreur réseau.');
    }
  }

  // ─── Chips ────────────────────────────────────────────────

  /// Retourne la liste des chips déjà utilisés.
  Future<List<String>> getChipsUsed(String teamId) async {
    try {
      final res = await _db
          .from('fantasy_teams')
          .select('chips_used')
          .eq('id', teamId)
          .single();
      final raw = res['chips_used'];
      if (raw == null) return [];
      return List<String>.from(raw as List);
    } catch (_) {
      return [];
    }
  }

  /// Active un chip.
  /// Lance [FantasyException] si déjà utilisé.
  Future<void> activateChip({
    required String teamId,
    required String chipName, // ex: 'wildcard_1', 'triplecap_2'
  }) async {
    _requireUid();
    final used = await getChipsUsed(teamId);
    if (used.contains(chipName)) {
      throw FantasyException('CHIP_USED', 'Ce chip a déjà été utilisé.');
    }
    try {
      await _db.rpc('fantasy_use_chip', params: {
        'p_team_id': teamId,
        'p_chip': chipName,
      });
    } on PostgrestException catch (e) {
      throw FantasyException(FantasyError.serverError,
          'Erreur activation chip : ${e.message}');
    } catch (e) {
      throw const FantasyException(FantasyError.networkError, 'Erreur réseau.');
    }
  }

  // ─── Transferts libres ────────────────────────────────────

  /// Retourne {free_transfers, gw_transfers, penalty_points}.
  Future<Map<String, int>> getTransferInfo(String teamId) async {
    try {
      final res = await _db
          .from('fantasy_teams')
          .select('free_transfers, gw_transfers')
          .eq('id', teamId)
          .single();
      final free = res['free_transfers'] as int? ?? 1;
      final used = res['gw_transfers'] as int? ?? 0;
      final penalty = used > free ? (used - free) * 4 : 0;
      return {'free_transfers': free, 'gw_transfers': used, 'penalty': penalty};
    } catch (_) {
      return {'free_transfers': 1, 'gw_transfers': 0, 'penalty': 0};
    }
  }

  /// Retire un joueur et rembourse le budget.
  Future<void> removePlayer({
    required String teamId,
    required int elementId,
    required int coinsRefund,
  }) async {
    _checkDeadline();
    try {
      await _db
          .from('fantasy_picks')
          .delete()
          .eq('team_id', teamId)
          .eq('element_id', elementId);

      await _db.rpc('fantasy_spend_budget', params: {
        'p_team_id': teamId,
        'p_amount': -coinsRefund,
      });
    } on PostgrestException catch (e) {
      throw FantasyException(
          FantasyError.serverError, 'Erreur retrait joueur : ${e.message}');
    } catch (e) {
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  /// Définit le captain / vice-captain.
  Future<void> setCaptain({
    required String teamId,
    required int captainElementId,
    required int vcElementId,
  }) async {
    try {
      await _db
          .from('fantasy_picks')
          .update({'is_captain': false, 'is_vice_captain': false})
          .eq('team_id', teamId);

      await _db
          .from('fantasy_picks')
          .update({'is_captain': true})
          .eq('team_id', teamId)
          .eq('element_id', captainElementId);

      await _db
          .from('fantasy_picks')
          .update({'is_vice_captain': true})
          .eq('team_id', teamId)
          .eq('element_id', vcElementId);
    } on PostgrestException catch (e) {
      throw FantasyException(
          FantasyError.serverError, 'Erreur mise à jour captain : ${e.message}');
    } catch (e) {
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  /// Met à jour les points GW et synchronise les ligues.
  Future<void> updateTeamPoints(String teamId, int gwPoints) async {
    try {
      await _db.from('fantasy_teams')
          .update({'gameweek_points': gwPoints})
          .eq('id', teamId);

      await _db.rpc('fantasy_add_points', params: {
        'p_team_id': teamId,
        'p_points': gwPoints,
      });
    } on PostgrestException catch (e) {
      debugPrint('updateTeamPoints: ${e.message}');
    } catch (e) {
      debugPrint('updateTeamPoints: $e');
    }
  }

  // ─── Ligues ───────────────────────────────────────────────

  /// Cree une ligue avec mise d'entree optionnelle.
  /// Si [entryFee] > 0, le createur sera automatiquement debite et inscrit.
  Future<Map<String, dynamic>> createLeague({
    required String name,
    required bool isPrivate,
    int entryFee = 0,
  }) async {
    final uid = _requireUid();

    try {
      final code = isPrivate ? _generateCode() : null;
      final res = await _db.from('fantasy_leagues').insert({
        'name': name,
        'creator_id': uid,
        'is_private': isPrivate,
        'private_code': code,
        'entry_fee': entryFee,
      }).select().single();

      await joinLeague(res['id'] as String);
      return res;
    } on PostgrestException catch (e) {
      throw FantasyException(
          FantasyError.serverError, 'Impossible de créer la ligue : ${e.message}');
    } catch (e) {
      if (e is FantasyException) rethrow;
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  /// Rejoint une ligue. Si entry_fee > 0, deduit les coins via RPC.
  Future<void> joinLeague(String leagueId) async {
    _requireUid();
    try {
      // Tentative via RPC (gere automatiquement entry_fee)
      final result = await _db.rpc('fantasy_join_league_with_fee', params: {
        'p_league_id': leagueId,
      });

      if (result is Map && result['success'] == false) {
        final err = result['error'] as String? ?? 'Erreur inconnue';
        if (err.contains('Solde insuffisant')) {
          throw FantasyException(
              FantasyError.budgetInsuffisant, 'Solde insuffisant pour la mise d\'entrée.');
        }
        if (err.contains('deja membre')) {
          // Pas une vraie erreur, on continue silencieusement
          return;
        }
        throw FantasyException(FantasyError.serverError, err);
      }
    } on PostgrestException catch (e) {
      throw FantasyException(
          FantasyError.serverError, 'Impossible de rejoindre la ligue : ${e.message}');
    } catch (e) {
      if (e is FantasyException) rethrow;
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  Future<void> joinLeagueByCode(String code) async {
    try {
      final league = await _db
          .from('fantasy_leagues')
          .select('id')
          .eq('private_code', code.toUpperCase())
          .maybeSingle();
      if (league == null) {
        throw const FantasyException(
            FantasyError.leagueNotFound, 'Code de ligue invalide ou inexistant.');
      }
      await joinLeague(league['id'] as String);
    } on FantasyException {
      rethrow;
    } catch (e) {
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  /// Termine une ligue : distribue le pot au gagnant (apres 15% commission).
  /// Seul le createur de la ligue peut appeler cette methode.
  Future<Map<String, dynamic>> finishLeague({
    required String leagueId,
    required String winnerId,
  }) async {
    _requireUid();
    try {
      final result = await _db.rpc('fantasy_finish_league', params: {
        'p_league_id': leagueId,
        'p_winner_id': winnerId,
      });
      if (result is Map && result['success'] == false) {
        throw FantasyException(
            FantasyError.serverError, result['error'] as String? ?? 'Erreur');
      }
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      throw FantasyException(
          FantasyError.serverError, 'Impossible de terminer la ligue : ${e.message}');
    } catch (e) {
      if (e is FantasyException) rethrow;
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau.');
    }
  }

  Future<List<Map<String, dynamic>>> getMyLeagues() async {
    try {
      _requireUid();
      final res = await _db
          .from('fantasy_league_members')
          .select('*, fantasy_leagues(*)')
          .eq('user_id', _uid!);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('getMyLeagues: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getLeagueStandings(
      String leagueId) async {
    try {
      final res = await _db
          .from('fantasy_league_members')
          .select('*, user_profiles(username, coins)')
          .eq('league_id', leagueId)
          .order('total_points', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('getLeagueStandings: $e');
      return [];
    }
  }

  // ─── Génération aléatoire d'équipe ───────────────────────

  /// Génère 15 joueurs aléatoires (2 GK · 5 DEF · 5 MID · 3 FWD)
  /// respectant le budget et insère les picks + met à jour le budget.
  Future<List<Map<String, dynamic>>> generateRandomTeam({
    required String teamId,
    required List<dynamic> allPlayers, // FplElement list passé depuis le provider
    int budget = 10000,
  }) async {
    final uid = _requireUid();

    // Distribution FPL standard
    const distribution = {1: 2, 2: 5, 3: 5, 4: 3};

    // Grouper par position
    final byPos = <int, List<dynamic>>{1: [], 2: [], 3: [], 4: []};
    for (final p in allPlayers) {
      final pos = p.elementType as int;
      if (byPos.containsKey(pos)) byPos[pos]!.add(p);
    }

    final picks = <dynamic>[];
    int spent = 0;

    // Mélanger et sélectionner par position
    for (final entry in distribution.entries) {
      final posPlayers = List.from(byPos[entry.key]!);
      posPlayers.shuffle();
      int count = 0;
      for (final p in posPlayers) {
        final remaining = budget - spent;
        final slotsLeft = 15 - picks.length;
        if (slotsLeft <= 0) break;
        // Réserver au moins 300 coins par slot restant
        final maxForThis = remaining - (slotsLeft - 1) * 300;
        if ((p.coinsValue as int) <= maxForThis) {
          picks.add(p);
          spent += p.coinsValue as int;
          count++;
          if (count >= entry.value) break;
        }
      }
    }

    if (picks.isEmpty) return [];

    // Construire les rows — positions 1-11 starters, 12-15 bench
    // GK starter = pos 1, GK bench = pos 12, DEF=2-6, MID=7-11, FWD=12→on adapte
    int position = 1;
    final rows = picks.map((p) {
      return {
        'team_id': teamId,
        'user_id': uid,
        'element_id': p.id as int,
        'position': position++,
        'is_captain': false,
        'is_vice_captain': false,
        'purchase_price': p.coinsValue as int,
      };
    }).toList();

    try {
      await _db.from('fantasy_picks').insert(rows);

      // Déduire du budget de l'équipe
      await _db.from('fantasy_teams')
          .update({'budget': budget - spent})
          .eq('id', teamId);

      // Captain = joueur avec le plus de points totaux
      final sorted = List.from(picks)
        ..sort((a, b) => (b.totalPoints as int).compareTo(a.totalPoints as int));
      final cap = sorted.first;
      final vc = sorted.length > 1 ? sorted[1] : sorted.first;

      await _db.from('fantasy_picks')
          .update({'is_captain': true})
          .eq('team_id', teamId)
          .eq('element_id', cap.id as int);

      await _db.from('fantasy_picks')
          .update({'is_vice_captain': true})
          .eq('team_id', teamId)
          .eq('element_id', vc.id as int);

      return rows;
    } on PostgrestException catch (e) {
      throw FantasyException(FantasyError.serverError,
          'Erreur génération équipe : ${e.message}');
    } catch (e) {
      throw const FantasyException(
          FantasyError.networkError, 'Erreur réseau lors de la génération.');
    }
  }

  // ─── Realtime ─────────────────────────────────────────────

  RealtimeChannel subscribeToTeam(
      String teamId, void Function(Map<String, dynamic>) onUpdate) {
    return _db
        .channel('fantasy_team_$teamId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'fantasy_teams',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: teamId,
          ),
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .subscribe();
  }

  // ─── Helpers ──────────────────────────────────────────────

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = DateTime.now().millisecondsSinceEpoch;
    return String.fromCharCodes(
      List.generate(6, (i) => chars.codeUnitAt((rng + i * 7) % chars.length)),
    );
  }
}
