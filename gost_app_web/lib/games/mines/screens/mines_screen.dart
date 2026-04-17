// ============================================================
// MinesScreen — Ecran principal du jeu Mines
// Grille 5x5, sélection du nombre de mines, reveal + cashout
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../models/mines_models.dart';
import '../services/mines_service.dart';

class MinesScreen extends StatefulWidget {
  const MinesScreen({super.key});

  @override
  State<MinesScreen> createState() => _MinesScreenState();
}

class _MinesScreenState extends State<MinesScreen> {
  final _svc = MinesService.instance;

  int _betAmount = 100;
  static const int _minesCount = 15; // Mode Extreme fixe

  MinesSession? _session;
  bool _loading = false;
  bool _tileLoading = false;

  bool _showResult = false;
  bool _resultIsWin = false;
  int _resultAmount = 0;
  double _resultMultiplier = 1.0;

  @override
  void initState() {
    super.initState();
    _tryRecoverSession();
  }

  Future<void> _tryRecoverSession() async {
    final session = await _svc.getActiveSession();
    if (session != null && session.isActive && mounted) {
      setState(() {
        _session = session;
        _betAmount = session.betAmount;
      });
    }
  }

  Future<void> _startGame() async {
    if (_loading) return;
    setState(() => _loading = true);

    final session = await _svc.createSession(
      betAmount: _betAmount,
      minesCount: _minesCount,
    );

    if (session == null && mounted) {
      setState(() => _loading = false);
      _snack('Impossible de demarrer. Verifiez votre solde.', isError: true);
      return;
    }

    if (mounted) {
      context.read<WalletProvider>().refresh();
      setState(() {
        _session = session;
        _loading = false;
        _showResult = false;
      });
    }
  }

  Future<void> _onTileTap(int position) async {
    if (_tileLoading || _session == null || !_session!.isActive) return;
    setState(() => _tileLoading = true);

    final result = await _svc.revealTile(
      sessionId: _session!.id,
      position: position,
    );

    if (result == null && mounted) {
      setState(() => _tileLoading = false);
      _snack('Erreur réseau. Réessayez.', isError: true);
      return;
    }

    if (!mounted) return;

    final isMine = result!['is_mine'] as bool;
    final newCell = MinesRevealedCell(position: position, isMine: isMine);

    if (isMine) {
      // LOST
      HapticFeedback.heavyImpact();
      final minePos = (result['mine_positions'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [];
      setState(() {
        _session = MinesSession(
          id: _session!.id,
          userId: _session!.userId,
          betAmount: _session!.betAmount,
          status: MinesStatus.lost,
          minesCount: _session!.minesCount,
          gridSize: _session!.gridSize,
          safeRevealedCount: _session!.safeRevealedCount,
          currentMultiplier: _session!.currentMultiplier,
          currentPotentialWin: 0,
          revealedCells: [..._session!.revealedCells, newCell],
          minePositions: minePos,
          createdAt: _session!.createdAt,
        );
        _tileLoading = false;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _showResult = true;
          _resultIsWin = false;
          _resultAmount = _session!.betAmount;
          _resultMultiplier = 0;
        });
      }
    } else {
      // SAFE
      HapticFeedback.mediumImpact();
      final newCount = (result['safe_revealed_count'] as num).toInt();
      final newMult = (result['current_multiplier'] as num).toDouble();
      final newWin = (result['current_potential_win'] as num).toInt();
      final finished = result['finished'] as bool? ?? false;

      setState(() {
        _session = MinesSession(
          id: _session!.id,
          userId: _session!.userId,
          betAmount: _session!.betAmount,
          status: finished ? MinesStatus.cashedOut : MinesStatus.active,
          minesCount: _session!.minesCount,
          gridSize: _session!.gridSize,
          safeRevealedCount: newCount,
          currentMultiplier: newMult,
          currentPotentialWin: newWin,
          revealedCells: [..._session!.revealedCells, newCell],
          minePositions: _session!.minePositions,
          createdAt: _session!.createdAt,
        );
        _tileLoading = false;
      });

      if (finished) {
        // Auto-win : tout revele
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          context.read<WalletProvider>().refresh();
          setState(() {
            _showResult = true;
            _resultIsWin = true;
            _resultAmount = newWin;
            _resultMultiplier = newMult;
          });
        }
      }
    }
  }

  Future<void> _doCashOut() async {
    if (_loading || _session == null || !_session!.canCashOut) return;
    setState(() => _loading = true);

    final result = await _svc.cashOut(sessionId: _session!.id);
    if (mounted) context.read<WalletProvider>().refresh();

    if (result == null && mounted) {
      setState(() => _loading = false);
      _snack('Erreur cash out.', isError: true);
      return;
    }

    if (!mounted) return;

    final payout = (result!['payout'] as num).toInt();
    final multiplier = (result['multiplier'] as num).toDouble();
    final minePos = (result['mine_positions'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [];

    HapticFeedback.heavyImpact();
    setState(() {
      _loading = false;
      _showResult = true;
      _resultIsWin = true;
      _resultAmount = payout;
      _resultMultiplier = multiplier;
      _session = MinesSession(
        id: _session!.id,
        userId: _session!.userId,
        betAmount: _session!.betAmount,
        status: MinesStatus.cashedOut,
        minesCount: _session!.minesCount,
        gridSize: _session!.gridSize,
        safeRevealedCount: _session!.safeRevealedCount,
        currentMultiplier: multiplier,
        currentPotentialWin: payout,
        revealedCells: _session!.revealedCells,
        minePositions: minePos,
        createdAt: _session!.createdAt,
      );
    });
  }

  void _dismissResult() {
    setState(() {
      _showResult = false;
      _session = null;
    });
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.neonRed : AppColors.neonGreen,
        behavior: SnackBarBehavior.floating,
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
          'Mines',
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
          Container(
            decoration: BoxDecoration(gradient: AppColors.bgGradient),
            child: Column(
              children: [
                // Info bar (mines + mult + potentialWin)
                if (_isPlaying) _buildInfoBar(),
                // Game area
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildGrid(),
                    ),
                  ),
                ),
                // Bottom panel
                _isPlaying ? _buildPlayingPanel() : _buildSetupPanel(wallet.coins),
              ],
            ),
          ),
          if (_showResult)
            Positioned.fill(
              child: _buildResultOverlay(),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoBar() {
    final s = _session!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(
          bottom: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          _infoChip('💣', '${s.minesCount}', 'mines'),
          const SizedBox(width: 10),
          _infoChip(
              '💎', '${s.safeRevealedCount}', 'reveles'),
          const SizedBox(width: 10),
          _infoChip('⚡',
              'x${s.currentMultiplier.toStringAsFixed(2)}', 'mult'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.neonYellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.neonYellow.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monetization_on,
                    color: AppColors.neonYellow, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${s.currentPotentialWin}',
                  style: TextStyle(
                    color: AppColors.neonYellow,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String emoji, String value, String label) {
    return Column(
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 3),
            Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(color: AppColors.textMuted, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    final gridSize = _session?.gridSize ?? 25;
    final revealed = _session?.revealedCells ?? [];
    final revealedMap = {
      for (final c in revealed) c.position: c,
    };
    final minePositions = _session?.minePositions;
    final isGameOver =
        _session?.isLost == true || _session?.isCashedOut == true;

    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: gridSize,
        itemBuilder: (context, index) {
          final cell = revealedMap[index];
          final isRevealedSafe = cell != null && !cell.isMine;
          final isRevealedMine = cell != null && cell.isMine;
          // Si game over + mines revelees → afficher les mines non revealed
          final isOtherMine = isGameOver &&
              cell == null &&
              (minePositions?.contains(index) ?? false);

          return _buildCell(
            index: index,
            isRevealedSafe: isRevealedSafe,
            isRevealedMine: isRevealedMine,
            isOtherMine: isOtherMine,
            canTap: _isPlaying && !_tileLoading && cell == null,
          );
        },
      ),
    );
  }

  Widget _buildCell({
    required int index,
    required bool isRevealedSafe,
    required bool isRevealedMine,
    required bool isOtherMine,
    required bool canTap,
  }) {
    Color bgColor;
    Widget child;

    if (isRevealedMine) {
      bgColor = const Color(0xFFB71C1C);
      child = const Text('💣', style: TextStyle(fontSize: 26));
    } else if (isRevealedSafe) {
      bgColor = const Color(0xFF1B5E20);
      child = const Text('💎', style: TextStyle(fontSize: 24));
    } else if (isOtherMine) {
      bgColor = const Color(0xFF8B0000);
      child = Text('💣',
          style:
              TextStyle(fontSize: 22, color: Colors.white.withValues(alpha: 0.6)));
    } else {
      bgColor = const Color(0xFF1A2740);
      child = Icon(
        Icons.help_outline_rounded,
        color: const Color(0xFF4A5568),
        size: 22,
      );
    }

    return GestureDetector(
      onTap: canTap ? () => _onTileTap(index) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgColor, bgColor.withValues(alpha: 0.7)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canTap
                ? AppColors.neonGreen.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
            width: canTap ? 1.5 : 1,
          ),
          boxShadow: isRevealedSafe || isRevealedMine
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildSetupPanel(int coins) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1726), Color(0xFF040810)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge mode fixe : 15 mines (Extreme)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.neonRed.withValues(alpha: 0.25),
                  AppColors.neonOrange.withValues(alpha: 0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.neonRed.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_fire_department, color: AppColors.neonRed, size: 18),
                const SizedBox(width: 8),
                Text('MODE EXTREME',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.neonRed,
                      letterSpacing: 1.2,
                    )),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('15 💣',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      )),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Bet buttons
          Row(
            children: [
              _quickBet(50),
              const SizedBox(width: 6),
              _quickBet(100),
              const SizedBox(width: 6),
              _quickBet(200),
              const SizedBox(width: 6),
              _quickBet(500),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.neonYellow.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.monetization_on,
                          color: AppColors.neonYellow, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$_betAmount',
                        style: TextStyle(
                          color: AppColors.neonYellow,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bouton COMMENCER
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading || _betAmount > coins || _betAmount <= 0
                  ? null
                  : _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    AppColors.textMuted.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      _betAmount > coins
                          ? 'Solde insuffisant'
                          : 'COMMENCER',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickBet(int amount) {
    final isSelected = _betAmount == amount;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _betAmount = amount);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppColors.neonYellow.withValues(alpha: 0.15)
              : AppColors.bgCard,
          border: Border.all(
            color: isSelected
                ? AppColors.neonYellow.withValues(alpha: 0.5)
                : AppColors.divider,
          ),
        ),
        child: Text(
          '$amount',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.neonYellow : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayingPanel() {
    final s = _session!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1726), Color(0xFF040810)],
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: s.canCashOut && !_loading ? _doCashOut : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD600),
            foregroundColor: Colors.black,
            disabledBackgroundColor: AppColors.textMuted.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: _loading
              ? const CircularProgressIndicator(color: Colors.black)
              : Text(
                  s.canCashOut
                      ? 'CASH OUT ${s.currentPotentialWin} coins'
                      : 'Revelez au moins 1 case',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    final color = _resultIsWin ? AppColors.neonGreen : AppColors.neonRed;
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0E1A2E),
                _resultIsWin
                    ? const Color(0xFF0A2010)
                    : const Color(0xFF200A0A),
              ],
            ),
            border: Border.all(
                color: color.withValues(alpha: 0.4), width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_resultIsWin ? '🎉' : '💥',
                  style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(
                _resultIsWin ? 'CASH OUT !' : 'BOOM !',
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              if (_resultIsWin)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: color.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    'x${_resultMultiplier.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monetization_on,
                      color: AppColors.neonYellow, size: 24),
                  const SizedBox(width: 6),
                  Text(
                    _resultIsWin ? '+$_resultAmount' : '-$_resultAmount',
                    style: TextStyle(
                      color: _resultIsWin
                          ? AppColors.neonYellow
                          : AppColors.neonRed,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _dismissResult,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _resultIsWin ? 'CONTINUER' : 'REJOUER',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLeaveDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.gameInProgress,
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          AppLocalizations.of(context)!.gameLeaveQuestion,
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
            child:
                Text(AppLocalizations.of(context)!.gameQuit, style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }
}
