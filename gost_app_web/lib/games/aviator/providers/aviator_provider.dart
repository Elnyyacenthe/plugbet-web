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
const int _kCountdownMs = 10000; // 10s de countdown (mises autorisees)
const int _kMaxFlyMs    = 20000; // 20s max de vol
const int _kRoundMs     = _kCountdownMs + _kMaxFlyMs; // 30s par round

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

  // ─── Init ─────────────────────────────────────────────
  Future<void> _init() async {
    crashHistory = await _svc.getRecentRounds();
    chatMessages = await _svc.getRecentChat();
    _subscribeRealtime();
    _syncToGlobalTime(); // Synchronisation initiale
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

    final now  = DateTime.now().millisecondsSinceEpoch;
    final roundNum     = now ~/ _kRoundMs;
    final posInRound   = now % _kRoundMs;

    // ── Générer le crash point depuis le roundNum ─────
    // Identique sur tous les appareils pour ce round
    serverSeed     = _hashRoundNum(roundNum);
    clientSeed     = _svc.generateClientSeed(); // device-specific, juste pour affichage
    roundHash      = _svc.computeHash(serverSeed, clientSeed);
    crashPoint     = _svc.generateCrashPoint(serverSeed, '');
    currentRoundId = roundNum.toString();

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

    for (final bet in [bet1, bet2]) {
      if (bet.placed && !bet.cashedOut) {
        bet.profit = -bet.amount;
        totalLost += bet.amount;
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

    // Calculer le temps restant jusqu'au prochain round
    final now        = DateTime.now().millisecondsSinceEpoch;
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

  // ─── Hash déterministe du numéro de round ─────────────
  // Identique sur tous les appareils → même crash point mondial
  String _hashRoundNum(int roundNum) {
    var h = 5381;
    for (final c in roundNum.toString().codeUnits) {
      h = ((h << 5) + h) ^ c;
      h &= 0x7FFFFFFF;
    }
    return h.abs().toRadixString(16).padLeft(16, '0');
  }

  // ─── Actions utilisateur ──────────────────────────────

  Future<bool> placeBet(AviatorBet bet) async {
    // Mises UNIQUEMENT pendant le countdown
    if (phase != AviatorPhase.waiting) return false;
    if (bet.placed) return false;
    if (bet.amount < 90) return false;

    if (!isDemoMode) {
      final ok = await _svc.deductBet(bet.amount);
      if (!ok) return false;
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
      _svc.addWinnings(payout);
      _svc.getUsername().then((username) {
        _svc.sendCashOutMessage(
          username:   username,
          multiplier: multiplier,
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
