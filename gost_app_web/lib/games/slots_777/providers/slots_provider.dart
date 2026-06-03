// ============================================================
// SlotsProvider — State management Phase 2 (real money)
// ============================================================
// Plus de demoBalance : le solde affiche vient de WalletProvider.
// L'ecran injecte WalletProvider via constructeur ; apres chaque
// spin, on appelle wallet.refresh() pour resync.
// ============================================================

import 'package:flutter/foundation.dart';
import '../../../providers/wallet_provider.dart';
import '../models/slot_models.dart';
import '../services/slots_service.dart';

class SlotsProvider extends ChangeNotifier {
  final WalletProvider wallet;
  final SlotsService _svc = SlotsService.instance;

  SlotsProvider({required this.wallet});

  int _currentBet = kBetLevels[2]; // 100 par defaut
  int get currentBet => _currentBet;

  bool _spinning = false;
  bool get spinning => _spinning;

  SpinResult? _lastResult;
  SpinResult? get lastResult => _lastResult;

  String? _error;
  String? get error => _error;

  int get balance => wallet.coins;
  List<SpinResult> get history => _svc.history;

  void setBet(int bet) {
    if (!kBetLevels.contains(bet)) return;
    if (_spinning) return;
    _currentBet = bet;
    notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  /// Lance un spin. Retourne le SpinResult ou null si echec.
  /// Stocke un message d'erreur dans [error] pour affichage UI.
  Future<SpinResult?> spin() async {
    if (_spinning) return null;
    if (balance < _currentBet) {
      _error = 'Solde insuffisant';
      notifyListeners();
      return null;
    }

    _spinning = true;
    _error = null;
    notifyListeners();

    try {
      // generateRequestId() est dans le try : si elle throw (cas edge web),
      // le finally remet spinning a false au lieu de bloquer le bouton.
      final reqId = _svc.generateRequestId();
      final r = await _svc.spin(bet: _currentBet, requestId: reqId);
      _lastResult = r;
      // Resync le wallet provider (le RPC a deja modifie le ledger)
      await wallet.refresh();
      return r;
    } on StateError catch (e) {
      switch (e.message) {
        case 'INSUFFICIENT_FUNDS':
          _error = 'Solde insuffisant';
          break;
        case 'RATE_LIMIT':
          _error = 'Patiente une seconde...';
          break;
        case 'NOT_AUTH':
          _error = 'Connecte-toi pour jouer';
          break;
        case 'RPC_NOT_DEPLOYED':
          _error = 'Slots indisponible (migration SQL a executer)';
          break;
        case 'TIMEOUT':
          _error = 'Reseau trop lent, reessaie';
          break;
        default:
          _error = 'Erreur : ${e.message}';
      }
      return null;
    } catch (e) {
      _error = 'Erreur reseau';
      return null;
    } finally {
      _spinning = false;
      notifyListeners();
    }
  }
}
