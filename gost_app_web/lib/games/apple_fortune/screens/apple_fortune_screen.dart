// ============================================================
// Apple of Fortune – Main game screen
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/wallet_provider.dart';
import '../models/apple_fortune_models.dart';
import '../services/apple_fortune_service.dart';
import '../widgets/fortune_board.dart';

import '../widgets/bet_panel.dart';
import '../widgets/result_overlay.dart';

class AppleFortuneScreen extends StatefulWidget {
  const AppleFortuneScreen({super.key});

  @override
  State<AppleFortuneScreen> createState() => _AppleFortuneScreenState();
}

class _AppleFortuneScreenState extends State<AppleFortuneScreen> {
  final _svc = AppleFortuneService.instance;

  // ── Config ──
  int _betAmount = 100;
  static const _difficulty = AppleFortuneDifficulty.extreme;

  // ── State ──
  AppleFortuneSession? _session;
  bool _loading = false;
  bool _tileLoading = false; // Prevents double-tap on tiles

  // ── Result overlay ──
  bool _showResult = false;
  bool _resultIsWin = false;
  int _resultAmount = 0;
  double _resultMultiplier = 1.0;

  // ── Multiplier table (precomputed for display) ──
  List<double> _multipliers = [];

  @override
  void initState() {
    super.initState();
    _updateMultipliers();
    _tryRecoverSession();
  }

  void _updateMultipliers() {
    _multipliers = AppleFortuneMultipliers.buildTable(
      totalRows: _difficulty.totalRows,
      columns: _difficulty.columns,
      safeTiles: _difficulty.safeTiles,
    );
  }

  // ── Recover active session on screen open ──
  Future<void> _tryRecoverSession() async {
    final session = await _svc.getActiveSession();
    if (session != null && session.isActive && mounted) {
      setState(() {
        _session = session;
        _betAmount = session.betAmount;
        _updateMultipliers();
      });
    }
  }

  // ── Start new game ──
  Future<void> _startGame() async {
    if (_loading) return;
    setState(() => _loading = true);

    final session = await _svc.createSession(
      betAmount: _betAmount,
      difficulty: _difficulty,
    );

    if (session == null && mounted) {
      setState(() => _loading = false);
      _showError('Impossible de lancer la partie. Vérifiez votre solde.');
      return;
    }

    // Refresh wallet after deduction
    if (mounted) {
      context.read<WalletProvider>().refresh();
      setState(() {
        _session = session;
        _loading = false;
        _showResult = false;
      });
    }
  }

  // ── Reveal a tile ──
  Future<void> _onTileTap(int tileIndex) async {
    if (_tileLoading || _session == null || !_session!.isActive) return;
    setState(() => _tileLoading = true);

    final result = await _svc.revealTile(
      sessionId: _session!.id,
      tileIndex: tileIndex,
    );

    if (result == null && mounted) {
      setState(() => _tileLoading = false);
      _showError('Erreur réseau. Réessayez.');
      return;
    }

    if (!mounted) return;

    final isWin = result!['is_win'] as bool;
    final safeTiles = List<int>.from(result['safe_tiles'] as List);
    final newRow = AppleFortuneRevealedRow(
      row: _session!.currentRow,
      chosenTile: tileIndex,
      isWin: isWin,
      safeTiles: safeTiles,
    );

    if (isWin) {
      // Advance to next row
      final newMultiplier = (result['current_multiplier'] as num).toDouble();
      final newPotentialWin = result['current_potential_win'] as int;
      final nextRow = result['current_row'] as int;

      HapticFeedback.mediumImpact();

      setState(() {
        _session = AppleFortuneSession(
          id: _session!.id,
          userId: _session!.userId,
          betAmount: _session!.betAmount,
          status: nextRow >= _session!.totalRows
              ? AppleFortuneStatus.cashedOut
              : AppleFortuneStatus.active,
          currentRow: nextRow,
          currentMultiplier: newMultiplier,
          currentPotentialWin: newPotentialWin,
          columns: _session!.columns,
          safeTilesPerRow: _session!.safeTilesPerRow,
          totalRows: _session!.totalRows,
          revealedRows: [..._session!.revealedRows, newRow],
          createdAt: _session!.createdAt,
        );
        _tileLoading = false;
      });

      // Auto-win at top
      if (nextRow >= _session!.totalRows) {
        await Future.delayed(const Duration(milliseconds: 400));
        await _doCashOut(auto: true);
      }
    } else {
      // Lost
      HapticFeedback.heavyImpact();

      setState(() {
        _session = AppleFortuneSession(
          id: _session!.id,
          userId: _session!.userId,
          betAmount: _session!.betAmount,
          status: AppleFortuneStatus.lost,
          currentRow: _session!.currentRow,
          currentMultiplier: _session!.currentMultiplier,
          currentPotentialWin: 0,
          columns: _session!.columns,
          safeTilesPerRow: _session!.safeTilesPerRow,
          totalRows: _session!.totalRows,
          revealedRows: [..._session!.revealedRows, newRow],
          createdAt: _session!.createdAt,
        );
        _tileLoading = false;
      });

      // Show loss overlay after brief delay
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _showResult = true;
          _resultIsWin = false;
          _resultAmount = _session!.betAmount;
          _resultMultiplier = 0;
        });
      }
    }
  }

  // ── Cash out ──
  Future<void> _doCashOut({bool auto = false}) async {
    if (_loading || _session == null) return;
    if (!auto && !_session!.canCashOut) return;

    setState(() => _loading = true);

    final result = await _svc.cashOut(sessionId: _session!.id);

    if (mounted) {
      context.read<WalletProvider>().refresh();
    }

    if (result == null && mounted) {
      setState(() => _loading = false);
      _showError('Erreur lors du cash out.');
      return;
    }

    if (!mounted) return;

    final payout = result!['payout'] as int;
    final multiplier = (result['multiplier'] as num).toDouble();

    HapticFeedback.heavyImpact();

    setState(() {
      _loading = false;
      _showResult = true;
      _resultIsWin = true;
      _resultAmount = payout;
      _resultMultiplier = multiplier;
      _session = AppleFortuneSession(
        id: _session!.id,
        userId: _session!.userId,
        betAmount: _session!.betAmount,
        status: AppleFortuneStatus.cashedOut,
        currentRow: _session!.currentRow,
        currentMultiplier: multiplier,
        currentPotentialWin: payout,
        columns: _session!.columns,
        safeTilesPerRow: _session!.safeTilesPerRow,
        totalRows: _session!.totalRows,
        revealedRows: _session!.revealedRows,
        createdAt: _session!.createdAt,
      );
    });
  }

  // ── Dismiss result and reset ──
  void _dismissResult() {
    setState(() {
      _showResult = false;
      _session = null;
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.neonRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool get _isPlaying => _session != null && _session!.isActive;

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(
          'Apple of Fortune',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_isPlaying) {
              _showLeaveDialog();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(Icons.monetization_on,
                    color: AppColors.neonYellow, size: 18),
                const SizedBox(width: 4),
                Text(
                  '${wallet.coins}',
                  style: TextStyle(
                    color: AppColors.neonYellow,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          Container(
            decoration: BoxDecoration(gradient: AppColors.bgGradient),
            child: Column(
              children: [
                // Game area
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    child: FortuneBoard(
                      session: _session,
                      columns: _isPlaying
                          ? _session!.columns
                          : _difficulty.columns,
                      totalRows: _isPlaying
                          ? _session!.totalRows
                          : _difficulty.totalRows,
                      multipliers: _multipliers,
                      isPlaying: _isPlaying,
                      loading: _tileLoading,
                      onTileTap: _isPlaying ? _onTileTap : null,
                    ),
                  ),
                ),

                // Bet panel
                BetPanel(
                  coins: wallet.coins,
                  betAmount: _betAmount,
                  isPlaying: _isPlaying,
                  canCashOut: _session?.canCashOut ?? false,
                  currentPotentialWin:
                      _session?.currentPotentialWin ?? 0,
                  currentMultiplier:
                      _session?.currentMultiplier ?? 1.0,
                  loading: _loading,
                  onBetChanged: (v) => setState(() => _betAmount = v),
                  onStart: _startGame,
                  onCashOut: _doCashOut,
                ),
              ],
            ),
          ),

          // Result overlay
          if (_showResult)
            Positioned.fill(
              child: ResultOverlay(
                isWin: _resultIsWin,
                amount: _resultAmount,
                multiplier: _resultMultiplier,
                onDismiss: _dismissResult,
              ),
            ),
        ],
      ),
    );
  }

  void _showLeaveDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Partie en cours',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Vous avez une partie en cours. Vous pouvez la retrouver en revenant.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.gameStay,
                style: TextStyle(color: AppColors.neonGreen)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.gameQuit,
                style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }
}
