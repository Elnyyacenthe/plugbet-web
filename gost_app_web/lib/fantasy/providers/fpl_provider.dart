// ============================================================
// FANTASY MODULE – Provider FPL
// State management : bootstrap, live, my team, AI suggestions
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/fpl_models.dart';
import '../services/fpl_service.dart';
import '../services/fantasy_service.dart';
import '../services/fpl_scoring_service.dart';
import '../../providers/wallet_provider.dart';

enum FplLoadState { idle, loading, loaded, error }

// ─── Constantes de conversion ─────────────────────────────
// now_cost FPL (ex: 45) × kFplCoinRate (10) = coins app (450)
// Budget de départ : 1000 FPL units × 10 = 10 000 coins
const int kFplCoinRate = 10;
const int kFplDefaultBudget = 10000; // coins = £100M FPL

class FplProvider extends ChangeNotifier {
  final FplService _service = FplService.instance;
  WalletProvider? _wallet;

  // Lie le WalletProvider pour afficher le solde réel
  void attachWallet(WalletProvider w) {
    _wallet = w;
    w.addListener(_onWalletChange);
  }

  void _onWalletChange() => notifyListeners();

  /// Solde disponible pour les transferts Fantasy (= coins du wallet)
  int get availableCoins => _wallet?.coins ?? 0;

  /// Vrai si le joueur peut se permettre ce joueur
  bool canAfford(FplElement el) => availableCoins >= el.coinsValue;

  // ─── State ────────────────────────────────────────────────

  FplLoadState state = FplLoadState.idle;
  FplBootstrap? bootstrap;
  Map<int, FplLiveElement> liveElements = {};

  // Équipe connectée
  int? entryId;
  FplEntry? entry;
  FplMyTeam? myTeam;

  // Points live de mon équipe
  int myLivePoints = 0;

  // Suggestions IA
  String aiSuggestion = '';
  bool aiLoading = false;

  // Polling live
  Timer? _liveTimer;
  static const Duration _livePollInterval = Duration(seconds: 45);

  // Hive box pour persister l'entry ID
  static const String _boxName = 'fpl_prefs';
  static const String _keyEntryId = 'entry_id';

  FplProvider() {
    _loadEntryId();
    loadBootstrap();
  }

  // ─── Entry ID ─────────────────────────────────────────────

  Future<void> _loadEntryId() async {
    try {
      final box = await Hive.openBox(_boxName);
      final saved = box.get(_keyEntryId) as int?;
      if (saved != null) {
        entryId = saved;
        await _loadMyTeam();
      }
    } catch (_) {}
  }

  Future<void> connectEntry(int id) async {
    entryId = id;
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_keyEntryId, id);
    } catch (_) {}
    await _loadMyTeam();
  }

  Future<void> disconnectEntry() async {
    entryId = null;
    entry = null;
    myTeam = null;
    myLivePoints = 0;
    try {
      final box = await Hive.openBox(_boxName);
      await box.delete(_keyEntryId);
    } catch (_) {}
    notifyListeners();
  }

  // ─── Bootstrap ────────────────────────────────────────────

  Future<void> loadBootstrap({bool force = false}) async {
    if (state == FplLoadState.loading) return;
    state = FplLoadState.loading;
    notifyListeners();

    try {
      bootstrap = await _service.fetchBootstrap(forceRefresh: force);
      state = bootstrap != null ? FplLoadState.loaded : FplLoadState.error;

      // Sync deadline vers FantasyService
      final nextGw = bootstrap?.nextEvent ?? bootstrap?.currentEvent;
      FantasyService.instance.setDeadline(nextGw?.deadlineTime);

      // Démarrer polling si GW live
      final gw = bootstrap?.currentEvent;
      if (gw != null && gw.isLive) {
        _startLivePolling(gw.id);
        // Calculer les points automatiquement
        FplScoringService.instance.calculateAndSync(bootstrap: bootstrap!);
      }
    } catch (e) {
      state = FplLoadState.error;
    }
    notifyListeners();
  }

  // ─── Live GW ──────────────────────────────────────────────

  int _liveFailStreak = 0;
  static const int _maxLiveFails = 3;

  Future<void> loadLiveGw(int gw) async {
    try {
      final live = await _service.fetchLiveGw(gw);
      if (live != null) {
        liveElements = live;
        _liveFailStreak = 0;
        _recalcMyPoints();
        notifyListeners();
      }
    } catch (_) {
      _liveFailStreak++;
      if (_liveFailStreak >= _maxLiveFails) {
        debugPrint('[FPL] Live polling arrete apres $_liveFailStreak echecs');
        _liveTimer?.cancel();
        _liveTimer = null;
      }
    }
  }

  void _startLivePolling(int gw) {
    _liveTimer?.cancel();
    _liveFailStreak = 0;
    _liveTimer = Timer.periodic(_livePollInterval, (_) => loadLiveGw(gw));
    loadLiveGw(gw); // chargement immediat
  }

  void pausePolling() => _liveTimer?.cancel();

  void resumePolling() {
    final gw = bootstrap?.currentEvent;
    if (gw != null && gw.isLive) _startLivePolling(gw.id);
  }

  // ─── Mon équipe ───────────────────────────────────────────

  Future<void> _loadMyTeam() async {
    if (entryId == null) return;
    try {
      entry = await _service.fetchEntry(entryId!);
      final gw = bootstrap?.currentEvent;
      if (gw != null) {
        myTeam = await _service.fetchEntryPicks(entryId!, gw.id);
        _recalcMyPoints();
      }
      notifyListeners();
    } catch (_) {}
  }

  void _recalcMyPoints() {
    if (myTeam == null || liveElements.isEmpty) return;
    int pts = 0;
    for (final pick in myTeam!.starters) {
      final live = liveElements[pick.elementId];
      if (live != null) {
        pts += live.stats.totalPoints * pick.multiplier;
      }
    }
    myLivePoints = pts;
  }

  // ─── Value picks ──────────────────────────────────────────

  /// Value picks sous un budget en coins (ex: 600 coins = £6.0M)
  List<FplElement> valuePicks({int maxCoins = 600, int limit = 5}) {
    if (bootstrap == null) return [];
    final maxCost = maxCoins / kFplCoinRate / 10; // reconvertir en £M FPL
    return _service.getValuePicks(bootstrap!, maxCost: maxCost, limit: limit);
  }

  List<MapEntry<FplElement, int>> topLive({int limit = 5}) {
    if (bootstrap == null || liveElements.isEmpty) return [];
    return _service.getTopLive(bootstrap!, liveElements, limit: limit);
  }

  // ─── Formation starters ───────────────────────────────────

  /// Retourne les starters groupés par ligne (GK / DEF / MID / FWD)
  Map<int, List<FplElement>> get startersByLine {
    if (myTeam == null || bootstrap == null) return {};
    final result = <int, List<FplElement>>{1: [], 2: [], 3: [], 4: []};
    for (final pick in myTeam!.starters) {
      final el = bootstrap!.elementById(pick.elementId);
      if (el != null) {
        result[el.elementType]?.add(el);
      }
    }
    return result;
  }

  /// Pions de remplaçants
  List<FplElement> get benchElements {
    if (myTeam == null || bootstrap == null) return [];
    return myTeam!.bench
        .map((p) => bootstrap!.elementById(p.elementId))
        .whereType<FplElement>()
        .toList();
  }

  FplPick? pickFor(int elementId) =>
      myTeam?.picks.where((p) => p.elementId == elementId).firstOrNull;

  int livePointsFor(int elementId) {
    final pick = pickFor(elementId);
    final live = liveElements[elementId];
    if (pick == null || live == null) return 0;
    return live.stats.totalPoints * pick.multiplier;
  }

  // ─── IA Suggestions ───────────────────────────────────────

  /// Appel stub vers Gemini/Grok – à compléter avec votre clé API
  Future<void> fetchAiSuggestion({String? apiKey}) async {
    if (bootstrap == null) return;
    aiLoading = true;
    notifyListeners();

    try {
      // Construction du prompt avec données contextuelles
      final gw = bootstrap!.currentEvent;
      final tops = valuePicks(maxCoins: 550, limit: 3)
          .map((e) => '${e.webName} (${e.coinsValue} coins, form ${e.form})')
          .join(', ');

      final prompt = '''
Tu es un expert Fantasy Premier League 2025/26.
GW actuel : ${gw?.name ?? 'N/A'}
Meilleurs value picks (<5.5M) : $tops
Donne 3 recommandations concrètes en français :
1. Meilleur captain cette semaine
2. Un differential value pick (<5.5M)
3. Un joueur à transférer cette semaine
Sois direct et concis (max 3 phrases par conseil).
''';

      if (apiKey != null && apiKey.isNotEmpty) {
        // Appel Gemini Flash (gratuit)
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-1.5-flash:generateContent?key=$apiKey',
        );
        final resp = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {'parts': [{'text': prompt}]}
            ]
          }),
        ).timeout(const Duration(seconds: 20));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          aiSuggestion = data['candidates']?[0]?['content']?['parts']?[0]
                  ?['text'] as String? ??
              _fallbackSuggestion();
        } else {
          aiSuggestion = _fallbackSuggestion();
        }
      } else {
        aiSuggestion = _fallbackSuggestion();
      }
    } catch (_) {
      aiSuggestion = _fallbackSuggestion();
    }

    aiLoading = false;
    notifyListeners();
  }

  String _fallbackSuggestion() {
    if (bootstrap == null) return '';
    final tops = valuePicks(maxCoins: 550, limit: 3);
    if (tops.isEmpty) return 'Chargez vos données pour voir les suggestions IA.';
    final best = tops.first;
    return '💡 Value pick: ${best.webName} (${best.coinsValue} coins, '
        'forme ${best.form}) – sélectionné par ${best.selectedByPercent}% '
        'des managers. Idéal comme transfert cette semaine.';
  }

  // ─── Coins App intégration ────────────────────────────────

  /// Retourne les coins gagnés selon les points FPL (+10 pts = +100 coins)
  int coinsFromPoints(int points) => (points ~/ 10) * 100;

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }
}

