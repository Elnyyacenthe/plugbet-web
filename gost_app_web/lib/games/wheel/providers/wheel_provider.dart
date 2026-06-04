// ============================================================
// WheelProvider — State management
// ============================================================
// Etat principal : chipsByTile (jetons deposes par tuile), spinning,
// lastResult, error. Lit le solde live via WalletProvider.
// ============================================================

import 'package:flutter/foundation.dart';
import '../../../providers/wallet_provider.dart';
import '../models/wheel_models.dart';
import '../services/wheel_service.dart';

class WheelProvider extends ChangeNotifier {
  final WalletProvider wallet;
  final WheelService _svc = WheelService.instance;

  WheelProvider({required this.wallet});

  /// Jeton selectionne (denomination en FCFA). Tap une tuile pour
  /// deposer ce jeton dessus.
  int _selectedChip = kChipDenominations[1]; // 100 par defaut
  int get selectedChip => _selectedChip;

  /// Mises courantes par tuile. Vide = aucun jeton pose.
  final Map<WheelTile, int> _chipsByTile = {};
  Map<WheelTile, int> get chipsByTile => Map.unmodifiable(_chipsByTile);

  bool _spinning = false;
  bool get spinning => _spinning;

  WheelSpinResult? _lastResult;
  WheelSpinResult? get lastResult => _lastResult;

  String? _error;
  String? get error => _error;

  int get balance => wallet.coins;
  List<WheelSpinResult> get history => _svc.history;

  int get totalBet => _chipsByTile.values.fold(0, (a, b) => a + b);

  bool get canSpin =>
      !_spinning &&
      totalBet >= kMinTotalBet &&
      totalBet <= kMaxTotalBet &&
      balance >= totalBet;

  void setSelectedChip(int chip) {
    if (!kChipDenominations.contains(chip)) return;
    _selectedChip = chip;
    notifyListeners();
  }

  /// Tap une tuile : depose le chip selectionne dessus si valide.
  void addChip(WheelTile tile) {
    if (_spinning) return;
    final current = _chipsByTile[tile] ?? 0;
    final next = current + _selectedChip;
    if (next > kMaxBetPerTile) {
      _error = 'Mise max $kMaxBetPerTile FCFA par tuile';
      notifyListeners();
      return;
    }
    if (totalBet + _selectedChip > kMaxTotalBet) {
      _error = 'Mise totale max $kMaxTotalBet FCFA';
      notifyListeners();
      return;
    }
    if (balance < totalBet + _selectedChip) {
      _error = 'Solde insuffisant';
      notifyListeners();
      return;
    }
    _chipsByTile[tile] = next;
    notifyListeners();
  }

  /// Long-press une tuile : retire tout le stack.
  void clearTile(WheelTile tile) {
    if (_spinning) return;
    _chipsByTile.remove(tile);
    notifyListeners();
  }

  /// Reset toutes les mises.
  void clearAll() {
    if (_spinning) return;
    _chipsByTile.clear();
    notifyListeners();
  }

  /// "Repeat" : remet les memes mises que le dernier spin.
  void repeatLastBets() {
    if (_spinning) return;
    final last = _lastResult;
    if (last == null) return;
    _chipsByTile.clear();
    for (final e in last.bets.entries) {
      _chipsByTile[WheelTile.fromValue(e.key)] = e.value;
    }
    notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  /// Lance le spin via RPC. Returns le resultat ou null si echec.
  Future<WheelSpinResult?> spin() async {
    if (_spinning) return null;
    if (!canSpin) {
      if (totalBet < kMinTotalBet) {
        _error = 'Mise min $kMinTotalBet FCFA';
      } else if (balance < totalBet) {
        _error = 'Solde insuffisant';
      }
      notifyListeners();
      return null;
    }

    _spinning = true;
    _error = null;
    notifyListeners();

    try {
      final reqId = _svc.generateRequestId();
      final r = await _svc.spin(chipsByTile: _chipsByTile, requestId: reqId);
      _lastResult = r;
      // Reset les mises apres le spin (le joueur replace pour le prochain)
      _chipsByTile.clear();
      await wallet.refresh();
      return r;
    } on StateError catch (e) {
      switch (e.message) {
        case 'INSUFFICIENT_FUNDS': _error = 'Solde insuffisant'; break;
        case 'RATE_LIMIT': _error = 'Patiente une seconde...'; break;
        case 'NOT_AUTH': _error = 'Connecte-toi pour jouer'; break;
        case 'TOTAL_BET_TOO_LOW': _error = 'Mise min $kMinTotalBet FCFA'; break;
        case 'TOTAL_BET_TOO_HIGH': _error = 'Mise max $kMaxTotalBet FCFA'; break;
        case 'BET_TOO_LOW_ON_TILE': _error = 'Mise min $kMinBetPerTile FCFA par tuile'; break;
        case 'BET_TOO_HIGH_ON_TILE': _error = 'Mise max $kMaxBetPerTile FCFA par tuile'; break;
        case 'TIMEOUT': _error = 'Reseau trop lent, reessaie'; break;
        case 'RPC_NOT_DEPLOYED': _error = 'Roue indisponible (migration SQL a executer)'; break;
        default:
          _error = e.message.startsWith('RPC_ERROR:')
              ? e.message.substring(11).trim()
              : 'Erreur : ${e.message}';
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
