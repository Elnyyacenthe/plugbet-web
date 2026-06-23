// ============================================================
// BetSlipController — Etat global du panier de paris
// ============================================================
// Singleton ChangeNotifier : utilisable depuis n'importe ou via
// `BetSlipController.instance`. Tap sur une cote -> toggle.
// Tap sur la pill flottante -> bottom sheet avec mise + cote totale.
//
// Phase 1 : `submit()` est un stub (retourne false, ne debite rien).
// Phase 2 : appel RPC place_bet idempotent (debit wallet + insert).
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum BetMode { simple, combine }

/// Politique en cas de cote modifiee pendant que le panier est ouvert.
/// Aligne sur la pratique 1xBet/Bet365 :
/// - askConfirm  : on demande confirmation avant submit (defaut)
/// - acceptAll   : on accepte automatiquement tous les changements
/// - acceptUp    : on accepte si la cote monte, on demande si elle baisse
/// - refuseDown  : on refuse net si la cote baisse (pas de confirm)
enum OddsChangePolicy { askConfirm, acceptAll, acceptUp, refuseDown }

/// Type de resultat d'un toggle() pour que l'UI puisse afficher un feedback adapte.
enum ToggleKind { added, removed, replaced }

/// Resultat d'un toggle() : permet a l'UI de savoir si la selection
/// a ete ajoutee, retiree ou si elle a remplace une autre selection
/// du meme match (regle pro : 1 market par match dans un combine).
class ToggleResult {
  final ToggleKind kind;
  /// Selection remplacee (uniquement si kind == replaced).
  /// Permet d'afficher "X retire" puis "Y ajoute" dans un seul message.
  final BetSelection? previous;
  const ToggleResult._(this.kind, [this.previous]);
  static const ToggleResult added = ToggleResult._(ToggleKind.added);
  static const ToggleResult removed = ToggleResult._(ToggleKind.removed);
  static ToggleResult replaced(BetSelection prev) =>
      ToggleResult._(ToggleKind.replaced, prev);

  bool get wasAdded    => kind == ToggleKind.added;
  bool get wasRemoved  => kind == ToggleKind.removed;
  bool get wasReplaced => kind == ToggleKind.replaced;
}

/// Resultat d'un placement de pari.
class BetResult {
  final bool success;
  final String? betId;
  final int? newBalance;
  final int? potentialPayout;
  final double? totalOdds;
  final String? error;     // user-facing
  final String? code;      // technical (PLACE_BET_INVALID_STAKE, etc.)

  const BetResult.ok({
    required this.betId,
    required this.newBalance,
    required this.potentialPayout,
    required this.totalOdds,
  })  : success = true,
        error = null,
        code = null;

  const BetResult.fail({required this.error, this.code})
      : success = false,
        betId = null,
        newBalance = null,
        potentialPayout = null,
        totalOdds = null;
}

class BetSelection {
  final String matchId;
  final String matchLabel;    // "Alanyaspor vs Fatih Karagumruk"
  final String marketCode;    // 'home' | 'draw' | 'away'
  final String marketLabel;   // "1X2 — Domicile"
  final double odds;
  final DateTime kickoff;
  final bool isLive;
  final bool isVirtual;       // true = match virtuel (badge VIRT dans panier)
  // Champs d'enrichissement pour l'UI style 1xBet (tous optionnels)
  final String? competition;  // "Coupe du monde 2026. Phase de groupes."
  final String? sportName;    // 'soccer' | 'basketball' | 'tennis' | etc.
  final int? homeScore;       // score actuel (live uniquement)
  final int? awayScore;
  final int? minute;          // minute de jeu (live uniquement)
  // Tracking du changement de cote (pour fleche up/down dans le panier)
  final double? previousOdds; // null = cote inchangee, sinon = ancienne valeur

  const BetSelection({
    required this.matchId,
    required this.matchLabel,
    required this.marketCode,
    required this.marketLabel,
    required this.odds,
    required this.kickoff,
    required this.isLive,
    this.isVirtual = false,
    this.competition,
    this.sportName,
    this.homeScore,
    this.awayScore,
    this.minute,
    this.previousOdds,
  });

  BetSelection copyWith({
    String? matchLabel,
    String? marketLabel,
    double? odds,
    bool? isLive,
    String? competition,
    String? sportName,
    int? homeScore,
    int? awayScore,
    int? minute,
    Object? previousOdds = _sentinel,  // pour explicitement passer null
  }) => BetSelection(
    matchId: matchId,
    matchLabel: matchLabel ?? this.matchLabel,
    marketCode: marketCode,
    marketLabel: marketLabel ?? this.marketLabel,
    odds: odds ?? this.odds,
    kickoff: kickoff,
    isLive: isLive ?? this.isLive,
    isVirtual: isVirtual,
    competition: competition ?? this.competition,
    sportName: sportName ?? this.sportName,
    homeScore: homeScore ?? this.homeScore,
    awayScore: awayScore ?? this.awayScore,
    minute: minute ?? this.minute,
    previousOdds: previousOdds == _sentinel
        ? this.previousOdds
        : previousOdds as double?,
  );
}

// Sentinel pour distinguer "passer null explicitement" vs "ne pas passer"
const Object _sentinel = Object();

class BetSlipController extends ChangeNotifier {
  BetSlipController._();
  static final BetSlipController instance = BetSlipController._();

  final List<BetSelection> _items = [];
  int _stake = 1000;          // XAF (FCFA). Min 100, Max 1 000 000.
  BetMode _mode = BetMode.combine;
  OddsChangePolicy _oddsPolicy = OddsChangePolicy.askConfirm;

  List<BetSelection> get items => List.unmodifiable(_items);
  int get count => _items.length;
  int get stake => _stake;
  BetMode get mode => _mode;
  OddsChangePolicy get oddsPolicy => _oddsPolicy;

  /// True si au moins une selection a une cote modifiee non acquittee
  /// (previousOdds != null). L'UI peut afficher une banniere de confirmation.
  bool get hasOddsChanges =>
      _items.any((s) => s.previousOdds != null && s.previousOdds != s.odds);

  void setOddsPolicy(OddsChangePolicy p) {
    if (p == _oddsPolicy) return;
    _oddsPolicy = p;
    notifyListeners();
  }

  /// Met a jour la cote d'une selection apres polling reseau.
  /// Si la nouvelle cote est differente de l'ancienne :
  ///   - on stocke l'ancienne dans previousOdds (pour fleche up/down UI)
  ///   - on remplace par la nouvelle
  /// Si elle est identique, on ne fait rien (et on garde previousOdds nul).
  /// Retourne true si une mise a jour a eu lieu.
  bool updateOdds({
    required String matchId,
    required String marketCode,
    required double newOdds,
    String? newMarketLabel,
    int? homeScore,
    int? awayScore,
    int? minute,
    bool? isLive,
  }) {
    final idx = _items.indexWhere(
        (e) => e.matchId == matchId && e.marketCode == marketCode);
    if (idx < 0) return false;
    final current = _items[idx];
    final scoreChanged = (homeScore != null && homeScore != current.homeScore) ||
        (awayScore != null && awayScore != current.awayScore) ||
        (minute != null && minute != current.minute);
    final oddsChanged = (newOdds - current.odds).abs() > 0.001;
    if (!oddsChanged && !scoreChanged) return false;
    _items[idx] = current.copyWith(
      odds: newOdds,
      marketLabel: newMarketLabel,
      homeScore: homeScore,
      awayScore: awayScore,
      minute: minute,
      isLive: isLive,
      // Stocke l'ancienne cote uniquement si vraiment changee
      previousOdds: oddsChanged
          ? (current.previousOdds ?? current.odds)
          : current.previousOdds,
    );
    notifyListeners();
    return oddsChanged;
  }

  /// Acquitter les changements de cote (apres confirmation utilisateur ou
  /// apres submission acceptee). Reset tous les previousOdds.
  void ackOddsChanges() {
    bool any = false;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].previousOdds != null) {
        _items[i] = _items[i].copyWith(previousOdds: null);
        any = true;
      }
    }
    if (any) notifyListeners();
  }

  /// Decide si le panier doit demander confirmation avant submit
  /// en fonction de la policy + des changements de cote.
  /// Retourne :
  ///   null     -> submit OK directement
  ///   'ask'    -> demander confirmation
  ///   'refuse' -> refuser (baisse de cote avec policy refuseDown)
  String? checkOddsChangePolicy() {
    if (!hasOddsChanges) return null;
    // Compte les hausses vs baisses
    bool anyDown = false;
    for (final s in _items) {
      if (s.previousOdds != null && s.odds < s.previousOdds!) {
        anyDown = true;
        break;
      }
    }
    switch (_oddsPolicy) {
      case OddsChangePolicy.acceptAll:
        return null;
      case OddsChangePolicy.acceptUp:
        return anyDown ? 'ask' : null;
      case OddsChangePolicy.refuseDown:
        return anyDown ? 'refuse' : null;
      case OddsChangePolicy.askConfirm:
        return 'ask';
    }
  }

  /// Y a-t-il deja une selection pour ce match ?
  bool hasMatch(String matchId) =>
      _items.any((e) => e.matchId == matchId);

  /// Quel marche est selectionne pour ce match ? (null si aucun)
  String? marketFor(String matchId) {
    for (final e in _items) {
      if (e.matchId == matchId) return e.marketCode;
    }
    return null;
  }

  /// Toggle d'une cote :
  /// - meme match + meme marche -> retire la selection
  /// - meme match + autre marche -> REMPLACE (regle pro : 1 market par match
  ///   dans un combine, sinon les evenements ne sont pas independants et le
  ///   bookmaker ne paye pas ce genre de tickets). Retourne `replaced` pour
  ///   que l'UI puisse afficher un toast/snackbar explicite.
  /// - nouveau match -> ajoute
  ToggleResult toggle(BetSelection s) {
    final idx = _items.indexWhere((e) => e.matchId == s.matchId);
    if (idx >= 0) {
      if (_items[idx].marketCode == s.marketCode) {
        _items.removeAt(idx);
        notifyListeners();
        return ToggleResult.removed;
      } else {
        final previous = _items[idx];
        _items[idx] = s;
        notifyListeners();
        return ToggleResult.replaced(previous);
      }
    } else {
      _items.add(s);
      notifyListeners();
      return ToggleResult.added;
    }
  }

  void remove(String matchId) {
    final before = _items.length;
    _items.removeWhere((e) => e.matchId == matchId);
    if (_items.length != before) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  void setStake(int v) {
    final clamped = v.clamp(100, 1000000);
    if (clamped == _stake) return;
    _stake = clamped;
    notifyListeners();
  }

  void setMode(BetMode m) {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
  }

  /// Cote totale combinée (produit des cotes).
  double get combinedOdds {
    if (_items.isEmpty) return 0;
    return _items.fold<double>(1.0, (acc, s) => acc * s.odds);
  }

  /// Gain potentiel net (mise comprise dans le retour).
  /// - combine : stake * cote_combinée
  /// - simple  : Σ(stake * cote_i)
  int get potentialWin {
    if (_items.isEmpty) return 0;
    if (_mode == BetMode.combine) {
      return (_stake * combinedOdds).round();
    }
    final total = _items.fold<double>(0, (acc, s) => acc + (_stake * s.odds));
    return total.round();
  }

  /// Mise totale debitee (combine : 1 fois ; simple : N fois).
  int get totalStake =>
      _mode == BetMode.combine ? _stake : _stake * _items.length;

  /// Soumet le panier au backend via RPC place_bet.
  /// - combine : 1 ticket = N selections, debit stake une fois
  /// - simple  : 1 RPC call par selection (chacune debite stake)
  ///   -> retourne le PREMIER echec rencontre s'il y en a un.
  Future<BetResult> submit() async {
    if (_items.isEmpty) {
      return const BetResult.fail(error: 'Panier vide', code: 'EMPTY');
    }

    if (_mode == BetMode.combine) {
      final res = await _placeBetRpc(
        betType: 'combine',
        stake: _stake,
        selections: _items,
        requestId: 'combine:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (res.success) clear();
      return res;
    }

    // Mode simple : on poste chaque selection comme un ticket independant.
    // 1ere erreur -> on retourne (les precedents OK restent debites).
    BetResult? last;
    final items = [..._items];
    for (var i = 0; i < items.length; i++) {
      final sel = items[i];
      final res = await _placeBetRpc(
        betType: 'simple',
        stake: _stake,
        selections: [sel],
        requestId: 'simple:${DateTime.now().microsecondsSinceEpoch}:$i',
      );
      last = res;
      if (!res.success) return res;
    }
    clear();
    return last!;
  }

  /// Pari simple direct (ne touche pas au panier).
  /// Utilise par showSingleBetSheet quand l'utilisateur tape une cote.
  Future<BetResult> submitSingle(BetSelection sel, int stake) async {
    return _placeBetRpc(
      betType: 'simple',
      stake: stake,
      selections: [sel],
      requestId: 'single:${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  Future<BetResult> _placeBetRpc({
    required String betType,
    required int stake,
    required List<BetSelection> selections,
    required String requestId,
  }) async {
    try {
      final payload = selections.map((s) => {
            'match_id': s.matchId,
            'match_label': s.matchLabel,
            'market_code': s.marketCode,
            'market_label': s.marketLabel,
            'odds': s.odds,
            'is_live': s.isLive,
            'is_virtual': s.isVirtual,
          }).toList();
      final res = await Supabase.instance.client.rpc(
        'place_bet',
        params: {
          'p_bet_type': betType,
          'p_stake': stake,
          'p_selections': payload,
          'p_request_id': requestId,
        },
      );
      if (res is! Map) {
        return const BetResult.fail(
            error: 'Réponse serveur inattendue', code: 'BAD_RESPONSE');
      }
      final m = res.cast<String, dynamic>();
      return BetResult.ok(
        betId: m['bet_id']?.toString(),
        newBalance: (m['new_balance'] as num?)?.toInt(),
        potentialPayout: (m['potential_payout'] as num?)?.toInt(),
        totalOdds: (m['total_odds'] as num?)?.toDouble(),
      );
    } on PostgrestException catch (e) {
      return BetResult.fail(
        error: _humanizeError(e.message),
        code: e.code,
      );
    } catch (e) {
      return BetResult.fail(error: '$e', code: 'UNKNOWN');
    }
  }

  String _humanizeError(String raw) {
    if (raw.contains('WALLET_INSUFFICIENT')) {
      return 'Solde insuffisant pour cette mise.';
    }
    if (raw.contains('PLACE_BET_INVALID_STAKE')) {
      return 'Mise invalide (entre 100 et 1 000 000 FCFA).';
    }
    if (raw.contains('PLACE_BET_TOO_MANY_SELECTIONS')) {
      return 'Trop de sélections (max 20).';
    }
    if (raw.contains('PLACE_BET_AUTH_REQUIRED')) {
      return 'Connecte-toi pour parier.';
    }
    if (raw.contains('PLACE_BET_INVALID_ODDS')) {
      return 'Cote invalide. Rafraîchis et réessaie.';
    }
    return 'Erreur : $raw';
  }
}
