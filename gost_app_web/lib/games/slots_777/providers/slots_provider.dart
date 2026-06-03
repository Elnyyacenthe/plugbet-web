// ============================================================
// SlotsProvider — State management (Phase 1 sans Provider/Riverpod)
// ============================================================
// ChangeNotifier simple. L'ecran s'enregistre comme listener via
// AnimatedBuilder/ListenableBuilder. Pas de Provider package requis
// (cf le projet utilise deja Provider, on peut migrer plus tard).
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/slot_models.dart';
import '../services/slots_service.dart';

class SlotsProvider extends ChangeNotifier {
  final SlotsService _svc = SlotsService.instance;

  int _currentBet = kBetLevels[2]; // 100 par defaut
  int get currentBet => _currentBet;

  bool _spinning = false;
  bool get spinning => _spinning;

  SpinResult? _lastResult;
  SpinResult? get lastResult => _lastResult;

  int get balance => _svc.demoBalance;
  List<SpinResult> get history => _svc.history;

  void setBet(int bet) {
    if (!kBetLevels.contains(bet)) return;
    if (_spinning) return;
    _currentBet = bet;
    notifyListeners();
  }

  Future<SpinResult?> spin() async {
    if (_spinning) return null;
    if (balance < _currentBet) return null;

    _spinning = true;
    notifyListeners();
    try {
      final r = await _svc.spin(bet: _currentBet);
      _lastResult = r;
      return r;
    } catch (_) {
      return null;
    } finally {
      _spinning = false;
      notifyListeners();
    }
  }

  void refillDemo() {
    _svc.refillDemo();
    notifyListeners();
  }
}
