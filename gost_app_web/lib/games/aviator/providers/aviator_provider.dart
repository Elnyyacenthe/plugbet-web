// ============================================================
// AVIATOR – Provider synchronisé sur l'horloge mondiale
//
// Principe :
//   • Un "round global" dure 25 secondes exactement
//   • Tous les clients calculent le même numéro de round
//     à partir de DateTime.now().millisecondsSinceEpoch
//   • Le crash point est dérivé du numéro de round → identique
//     sur tous les appareils en même temps
//   • Phase 0–5s  : countdown (mises autorisées)
//   • Phase 5–25s : vol (cashout uniquement)
//   • Quand mult ≥ crashPoint → crash
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/aviator_models.dart';
import '../services/aviator_service.dart';

// Durees fixes du round (en ms)
// NOTE: si tu changes ces valeurs, MAJ aussi aviator_multiplayer.sql
// (les RPC aviator_place_bet / aviator_cashout ont les memes constantes hardcodees)
const int _kCountdownMs = 5000;  // 5s de countdown (mises autorisees)
const int _kMaxFlyMs    = 10000; // 10s max de vol
const int _kRoundMs     = _kCountdownMs + _kMaxFlyMs; // 15s par round

class AviatorProvider extends ChangeNotifier {
  AviatorProvider() {
    _init();
  }

  final _svc = AviatorService.instance;

  // ─── État du jeu ─────────────────────────────────────
  AviatorPhase phase = AviatorPhase.waiting;
  double multiplier = 0.00;
  double crashPoint = 2.00;
  int countdownSecs = 5;

  // Seeds provably fair (affichés après crash pour vérif)
  String serverSeed = '';
  String clientSeed = '';
  String roundHash  = '';
  String currentRoundId = '';

  // ─── Mode démo ───────────────────────────────────────
  bool isDemoMode = false;

  // ─── Mises ───────────────────────────────────────────
  final bet1 = AviatorBet(slot: 1);
  final bet2 = AviatorBet(slot: 2);
  bool showBet2 = false;

  // ─── Historique & chat ───────────────────────────────
  List<CrashRound> crashHistory = [];
  List<AviatorChatMessage> chatMessages = [];

  // ─── Paris multijoueur temps reel ────────────────────
  /// Tous les paris actifs du round courant (tous les joueurs confondus)
  List<LiveBet> liveBets = [];
  /// Gains recents pour le feed de droite
  List<LiveBet> recentWinnings = [];

  // ─── Stats perso ─────────────────────────────────────
  double bestMultiplier = 0.0;
  int totalWon  = 0;
  int totalLost = 0;

  // ─── Internes ────────────────────────────────────────
  Timer? _ticker;
  Timer? _syncTimer;
  int _elapsedMs = 0;
  RealtimeChannel? _channel;
  bool _disposed = false;

  /// Numero du round actuellement affiche (identique sur tous les appareils).
  int _currentRoundNum = 0;
  int get currentRoundNum => _currentRoundNum;

  /// Offset (ms) entre horloge locale et horloge serveur Supabase.
  /// Mis a jour au demarrage via un RPC server_epoch_ms().
  int _serverClockOffset = 0;
  int _serverNowMs() =>
      DateTime.now().millisecondsSinceEpoch + _serverClockOffset;

  // ─── Init ─────────────────────────────────────────────
  Future<void> _init() async {
    // Mesure l'offset horloge serveur AVANT toute logique de round
    // pour que _syncToGlobalTime() voie le bon roundNum.
    _serverClockOffset = await _svc.measureServerClockOffset();
    crashHistory = await _svc.getRecentRounds();
    chatMessages = await _svc.getRecentChat();
    _subscribeRealtime();
    _syncToGlobalTime();
    _notify();
  }

  void _subscribeRealtime() {
    _channel = _svc.subscribeLive(
      onMessage: (msg) {
        chatMessages.add(msg);
        if (chatMessages.length > 100) chatMessages.removeAt(0);
        _notify();
      },
      onRound: (round) {
        if (!crashHistory.any((r) => r.roundId == round.roundId)) {
          crashHistory.insert(0, round);
          if (crashHistory.length > 20) crashHistory.removeLast();
          _notify();
        }
      },
      onBetPlaced: (bet) {
        // Ne pas dupliquer (si c'est le notre deja ajoute en local)
        if (bet.roundNum != _currentRoundNum) return;
        if (liveBets.any((b) => b.id == bet.id)) return;
        liveBets.add(bet);
        _notify();
      },
      onBetUpdated: (bet) {
        final idx = liveBets.indexWhere((b) => b.id == bet.id);
        if (idx >= 0) {
          liveBets[idx] = bet;
        }
        // Si cashout reussi : push dans le feed des gains
        if (bet.cashedOutAt != null &&
            !recentWinnings.any((w) => w.id == bet.id)) {
          recentWinnings.insert(0, bet);
          if (recentWinnings.length > 30) recentWinnings.removeLast();
        }
        _notify();
      },
    );
  }

  // ─── Synchronisation horloge mondiale ─────────────────
  //
  // Tous les appareils du monde calculent :
  //   roundNum = epoch ~/ 25000
  //   posInRound = epoch % 25000
  //
  // → Même roundNum = même crash point = même round partout.

  void _syncToGlobalTime() {
    _ticker?.cancel();
    _syncTimer?.cancel();

    // Utilise l'horloge SERVEUR (locale + offset mesure) pour que tous les
    // clients voient le meme roundNum, meme si leur horloge locale est decalee.
    final now  = _serverNowMs();
    final roundNum     = now ~/ _kRoundMs;
    final posInRound   = now % _kRoundMs;

    // ── Générer le crash point depuis le roundNum ─────
    // Identique sur tous les appareils pour ce round
    serverSeed     = _hashRoundNum(roundNum);
    clientSeed     = _svc.generateClientSeed(); // device-specific, juste pour affichage
    roundHash      = _svc.computeHash(serverSeed, clientSeed);
    crashPoint     = _svc.generateCrashPoint(serverSeed, '');
    currentRoundId = roundNum.toString();

    // Si on a change de round → reset les paris live + charger ceux de la DB
    if (roundNum != _currentRoundNum) {
      _currentRoundNum = roundNum;
      liveBets = [];
      // Charge async les bets du round courant + les gains recents
      _svc.getCurrentRoundBets(roundNum).then((bets) {
        if (_disposed || _currentRoundNum != roundNum) return;
        liveBets = bets;
        _notify();
      });
      if (recentWinnings.isEmpty) {
        _svc.getRecentWinnings(limit: 30).then((wins) {
          if (_disposed) return;
          recentWinnings = wins;
          _notify();
        });
      }
    }

    if (posInRound < _kCountdownMs) {
      // ── Phase countdown ──────────────────────────
      _enterCountdown(posInRound);
    } else {
      // ── Phase vol (ou déjà crashé) ───────────────
      _elapsedMs = posInRound - _kCountdownMs;
      multiplier  = _svc.computeMultiplier(_elapsedMs);

      if (multiplier >= crashPoint || _elapsedMs >= _kMaxFlyMs) {
        // Déjà crashé quand on arrive
        phase      = AviatorPhase.crashed;
        multiplier = crashPoint;
        _notify();
        _scheduleNextRound(posInRound);
      } else {
        // Round en cours → rejoindre le vol (pas de mise possible)
        _enterFlying(startElapsed: _elapsedMs);
      }
    }
  }

  void _enterCountdown(int posInRound) {
    phase         = AviatorPhase.waiting;
    multiplier    = 0.00;
    _elapsedMs    = 0;
    bet1.reset();
    bet2.reset();
    countdownSecs = ((_kCountdownMs - posInRound) / 1000).ceil().clamp(1, 10);
    _notify();

    // Mettre à jour le countdown chaque seconde
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed) { t.cancel(); return; }
      countdownSecs--;
      _notify();
      if (countdownSecs <= 0) {
        t.cancel();
        _enterFlying(startElapsed: 0);
      }
    });
  }

  void _enterFlying({required int startElapsed}) {
    phase      = AviatorPhase.flying;
    _elapsedMs = startElapsed;
    _notify();

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_disposed) return;
      _elapsedMs += 100;
      multiplier  = _svc.computeMultiplier(_elapsedMs);

      // Auto cash out
      _checkAuto(bet1);
      _checkAuto(bet2);

      _notify();

      // Crash si multiplicateur atteint crashPoint ou timeout max
      if (multiplier >= crashPoint || _elapsedMs >= _kMaxFlyMs) {
        _ticker?.cancel();
        _doCrash();
      }
    });
  }

  void _checkAuto(AviatorBet bet) {
    if (!bet.placed || bet.cashedOut || bet.autoCashOut == null) return;
    if (multiplier >= bet.autoCashOut!) _executeCashOut(bet);
  }

  void _doCrash() {
    phase      = AviatorPhase.crashed;
    multiplier = double.parse(crashPoint.toStringAsFixed(2));

    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;

    for (final bet in [bet1, bet2]) {
      if (bet.placed && !bet.cashedOut) {
        bet.profit = -bet.amount;
        totalLost += bet.amount;
        // Mise perdue → va dans la caisse du jeu (10% house edge implicite)
        if (!isDemoMode) {
          supabase.rpc('game_treasury_collect_loss', params: {
            'p_amount': bet.amount,
            'p_game_type': 'aviator',
            'p_user_id': uid,
            'p_description': 'Aviator: crash @x${crashPoint.toStringAsFixed(2)}',
          }).then((_) {}, onError: (_) {});
          // Marque la ligne aviator_bets comme perdue (win_amount = 0)
          // → permet aux stats / feed de distinguer perdu vs en cours
          _svc.settleLossRpc(
            roundNum: _currentRoundNum,
            slot: bet.slot,
          );
        }
      }
    }

    _notify();

    // Sauvegarder le round (hors démo, 1 seule fois)
    if (!isDemoMode) {
      _svc.saveRound(CrashRound(
        roundId:    currentRoundId,
        crashPoint: crashPoint,
        serverSeed: serverSeed,
        clientSeed: clientSeed,
        time:       DateTime.now(),
      ));
    }

    // Calculer le temps restant jusqu'au prochain round (horloge serveur)
    final now        = _serverNowMs();
    final posInRound = now % _kRoundMs;
    _scheduleNextRound(posInRound);
  }

  void _scheduleNextRound(int posInRound) {
    // Attendre la fin du round en cours, puis re-synchroniser
    final msRemaining = _kRoundMs - posInRound;
    final delay = msRemaining.clamp(2000, _kRoundMs);
    Future.delayed(Duration(milliseconds: delay), () {
      if (!_disposed) _syncToGlobalTime();
    });
  }

  // ─── Hash deterministe du numero de round ─────────────
  // Identique sur tous les appareils -> meme crash point mondial.
  // Applique un avalanche XorShift pour decorreler les roundNums consecutifs
  // (DJB2 seul laisse les bits hauts correles -> crash points repetitifs).
  String _hashRoundNum(int roundNum) {
    var h = 5381;
    for (final c in roundNum.toString().codeUnits) {
      h = ((h << 5) + h) ^ c;
      h &= 0x7FFFFFFF;
    }
    // Avalanche XorShift (2 passes) pour bien melanger les bits
    h ^= (h << 13) & 0x7FFFFFFF;
    h ^= h >> 17;
    h ^= (h << 5) & 0x7FFFFFFF;
    h &= 0x7FFFFFFF;
    h ^= (h << 13) & 0x7FFFFFFF;
    h ^= h >> 17;
    h ^= (h << 5) & 0x7FFFFFFF;
    h &= 0x7FFFFFFF;
    return h.abs().toRadixString(16).padLeft(16, '0');
  }

  // ─── Actions utilisateur ──────────────────────────────

  Future<bool> placeBet(AviatorBet bet) async {
    // Mises UNIQUEMENT pendant le countdown
    if (phase != AviatorPhase.waiting) return false;
    if (bet.placed) return false;
    if (bet.amount < 90) return false;

    if (!isDemoMode) {
      // RPC atomique : deduit les coins + insert dans aviator_bets
      // → tous les autres joueurs voient la mise apparaitre en temps reel
      final username = await _svc.getUsername();
      final err = await _svc.placeBetRpc(
        roundNum: _currentRoundNum,
        slot: bet.slot,
        amount: bet.amount,
        username: username,
      );
      if (err != null) return false;
    }

    bet.placed = true;
    _notify();
    return true;
  }

  Future<void> cashOut(AviatorBet bet) async {
    if (phase != AviatorPhase.flying) return;
    if (!bet.placed || bet.cashedOut) return;
    _executeCashOut(bet);
  }

  void _executeCashOut(AviatorBet bet) {
    bet.cashedOut      = true;
    bet.cashMultiplier = multiplier;
    final payout       = (bet.amount * multiplier).floor();
    bet.profit         = payout - bet.amount;

    if (payout > 0 && !isDemoMode) {
      if (multiplier > bestMultiplier) bestMultiplier = multiplier;
      if (bet.profit! > 0) totalWon += bet.profit!;

      // RPC atomique : update aviator_bets (cashed_out_at + win_amount) + credit coins
      // → broadcast realtime vers tous les autres joueurs (panneau gains live)
      final cashMult = multiplier;
      _svc.cashoutRpc(
        roundNum: _currentRoundNum,
        slot: bet.slot,
        mult: cashMult,
      );

      // Cashout : on paie depuis la caisse du jeu (comptabilite house)
      final uid = Supabase.instance.client.auth.currentUser?.id;
      Supabase.instance.client.rpc('game_treasury_pay_win', params: {
        'p_amount': payout,
        'p_game_type': 'aviator',
        'p_user_id': uid,
        'p_description': 'Aviator: cashout @x${cashMult.toStringAsFixed(2)}',
      }).then((_) {}, onError: (_) {});

      _svc.getUsername().then((username) {
        _svc.sendCashOutMessage(
          username:   username,
          multiplier: cashMult,
          profit:     bet.profit!,
        );
      });
    }

    _notify();
  }

  void setBetAmount(AviatorBet bet, int amount) {
    if (bet.placed) return;
    bet.amount = amount < 90 ? 90 : amount;
    _notify();
  }

  void setAutoCashOut(AviatorBet bet, double? value) {
    bet.autoCashOut = value;
    _notify();
  }

  void toggleBet2() {
    showBet2 = !showBet2;
    _notify();
  }

  void toggleDemo() {
    isDemoMode = !isDemoMode;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _syncTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}
