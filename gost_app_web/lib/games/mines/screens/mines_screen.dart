// ============================================================
// MinesScreen — Ecran principal du jeu Mines
// Grille 5x5, sélection du nombre de mines, reveal + cashout
// ============================================================
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../services/audio_service.dart';
import '../models/mines_models.dart';
import '../services/mines_service.dart';
import '../../../widgets/network_lost_overlay.dart';

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
    _initAudio();
    _tryRecoverSession();
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('mines');
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void dispose() {
    AudioService.instance.stopBackgroundMusic();
    super.dispose();
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
      AudioService.instance.playExplosion();
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
      AudioService.instance.playSafe();
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
        AudioService.instance.playWin();
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

    AudioService.instance.playWin();
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
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Mines',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
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
            padding: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
            child: _coinPill('${wallet.coins}'),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Fond dégradé profond + halos néon d'ambiance
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(gradient: AppColors.bgGradient),
            ),
          ),
          _ambientGlow(
            top: -60,
            left: -50,
            color: AppColors.neonRed,
            size: 240,
          ),
          _ambientGlow(
            bottom: 40,
            right: -60,
            color: AppColors.neonGreen,
            size: 260,
          ),
          SafeArea(
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
                _isPlaying
                    ? _buildPlayingPanel()
                    : _buildSetupPanel(wallet.coins),
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

  // ─── Halo néon flou d'ambiance ───────────────────────────
  Widget _ambientGlow({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required Color color,
    required double size,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.20),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Pastille de solde (glassy) ──────────────────────────
  Widget _coinPill(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            AppColors.neonYellow.withValues(alpha: 0.18),
            AppColors.neonYellow.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonYellow.withValues(alpha: 0.20),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 17),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: AppColors.neonYellow,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBar() {
    final s = _session!;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard.withValues(alpha: 0.55),
            border: Border(
              bottom:
                  BorderSide(color: AppColors.neonGreen.withValues(alpha: 0.15)),
            ),
          ),
          child: Row(
            children: [
              _infoChip('💣', '${s.minesCount}', 'mines'),
              const SizedBox(width: 10),
              _infoChip('💎', '${s.safeRevealedCount}', 'reveles'),
              const SizedBox(width: 10),
              _infoChip(
                  '⚡', 'x${s.currentMultiplier.toStringAsFixed(2)}', 'mult'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppColors.neonYellow.withValues(alpha: 0.22),
                    AppColors.neonYellow.withValues(alpha: 0.10),
                  ]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.neonYellow.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 15),
                    const SizedBox(width: 4),
                    Text(
                      '${s.currentPotentialWin}',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    // Palette et contenu par état de la case
    List<Color> gradColors;
    Color glowColor;
    Color borderColor;
    double borderWidth;
    Widget child;
    bool glow = false;

    if (isRevealedMine) {
      gradColors = const [Color(0xFFE53935), Color(0xFF8B0000)];
      glowColor = AppColors.neonRed;
      borderColor = AppColors.neonRed.withValues(alpha: 0.8);
      borderWidth = 1.5;
      glow = true;
      child = const SizedBox(
          width: 30, height: 30, child: CustomPaint(painter: _BombPainter()));
    } else if (isRevealedSafe) {
      gradColors = const [Color(0xFF00E676), Color(0xFF1B5E20)];
      glowColor = AppColors.neonGreen;
      borderColor = AppColors.neonGreen.withValues(alpha: 0.8);
      borderWidth = 1.5;
      glow = true;
      child = const SizedBox(
          width: 30, height: 30, child: CustomPaint(painter: _GemPainter()));
    } else if (isOtherMine) {
      gradColors = const [Color(0xFF5A1414), Color(0xFF2A0808)];
      glowColor = AppColors.neonRed;
      borderColor = AppColors.neonRed.withValues(alpha: 0.3);
      borderWidth = 1;
      child = const Opacity(
        opacity: 0.55,
        child: SizedBox(
            width: 26, height: 26, child: CustomPaint(painter: _BombPainter())),
      );
    } else {
      // Case cachée : verre sombre bleuté
      gradColors = const [Color(0xFF1B2C48), Color(0xFF0C1526)];
      glowColor = AppColors.neonGreen;
      borderColor = canTap
          ? AppColors.neonGreen.withValues(alpha: 0.45)
          : Colors.white.withValues(alpha: 0.06);
      borderWidth = canTap ? 1.4 : 1;
      child = Icon(
        Icons.diamond_outlined,
        color: canTap
            ? AppColors.neonGreen.withValues(alpha: 0.35)
            : const Color(0xFF3A4A63),
        size: 20,
      );
    }

    return GestureDetector(
      onTap: canTap ? () => _onTileTap(index) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradColors,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Center(
          child: AnimatedScale(
            scale: (isRevealedSafe || isRevealedMine) ? 1.0 : 0.98,
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildSetupPanel(int coins) {
    return _bottomShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge mode fixe : 15 mines (Extreme)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.neonRed.withValues(alpha: 0.28),
                  AppColors.neonOrange.withValues(alpha: 0.16),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.neonRed.withValues(alpha: 0.55),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonRed.withValues(alpha: 0.25),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_fire_department,
                    color: AppColors.neonRed, size: 19),
                const SizedBox(width: 8),
                Text('MODE EXTREME',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonRed,
                      letterSpacing: 1.4,
                    )),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withValues(alpha: 0.25),
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
          const SizedBox(height: 14),

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.neonYellow.withValues(alpha: 0.14),
                      AppColors.neonYellow.withValues(alpha: 0.05),
                    ]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.neonYellow.withValues(alpha: 0.4)),
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
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bouton COMMENCER
          _neonButton(
            enabled: !(_loading || _betAmount > coins || _betAmount <= 0),
            loading: _loading,
            baseColor: AppColors.neonGreen,
            height: 52,
            label: _betAmount > coins ? 'Solde insuffisant' : 'COMMENCER',
            onTap: _startGame,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: isSelected
              ? LinearGradient(colors: [
                  AppColors.neonYellow.withValues(alpha: 0.22),
                  AppColors.neonYellow.withValues(alpha: 0.08),
                ])
              : null,
          color: isSelected ? null : AppColors.bgCard.withValues(alpha: 0.6),
          border: Border.all(
            color: isSelected
                ? AppColors.neonYellow.withValues(alpha: 0.6)
                : AppColors.divider,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.neonYellow.withValues(alpha: 0.25),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Text(
          '$amount',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isSelected ? AppColors.neonYellow : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayingPanel() {
    final s = _session!;
    return _bottomShell(
      child: _neonButton(
        enabled: s.canCashOut && !_loading,
        loading: _loading,
        baseColor: AppColors.neonYellow,
        foreground: Colors.black,
        height: 58,
        label: s.canCashOut
            ? 'CASH OUT ${s.currentPotentialWin} FCFA'
            : 'Revelez au moins 1 case',
        onTap: _doCashOut,
      ),
    );
  }

  // Coque en bas d'écran (glassmorphism sombre)
  Widget _bottomShell({required Widget child}) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0B1726).withValues(alpha: 0.85),
                const Color(0xFF040810).withValues(alpha: 0.95),
              ],
            ),
            border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06), width: 1),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  // Bouton néon générique (gradient + glow + micro-scale)
  Widget _neonButton({
    required bool enabled,
    required bool loading,
    required Color baseColor,
    required String label,
    required VoidCallback onTap,
    Color foreground = Colors.black,
    double height = 52,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled && !loading ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      baseColor,
                      baseColor.withValues(alpha: 0.75),
                    ],
                  )
                : null,
            color: enabled ? null : AppColors.textMuted.withValues(alpha: 0.25),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foreground,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: enabled ? foreground : AppColors.textMuted,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    final color = _resultIsWin ? AppColors.neonGreen : AppColors.neonRed;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0E1A2E).withValues(alpha: 0.92),
                      _resultIsWin
                          ? const Color(0xFF0A2010).withValues(alpha: 0.92)
                          : const Color(0xFF200A0A).withValues(alpha: 0.92),
                    ],
                  ),
                  border:
                      Border.all(color: color.withValues(alpha: 0.55), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 34,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_resultIsWin ? '🎉' : '💥',
                        style: const TextStyle(fontSize: 58)),
                    const SizedBox(height: 12),
                    Text(
                      _resultIsWin ? 'CASH OUT !' : 'BOOM !',
                      style: TextStyle(
                        color: color,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                              color: color.withValues(alpha: 0.6),
                              blurRadius: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_resultIsWin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: color.withValues(alpha: 0.18),
                          border:
                              Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'x${_resultMultiplier.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.monetization_on,
                            color: AppColors.neonYellow, size: 26),
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
                    const SizedBox(height: 22),
                    _neonButton(
                      enabled: true,
                      loading: false,
                      baseColor: color,
                      height: 50,
                      label: _resultIsWin ? 'CONTINUER' : 'REJOUER',
                      onTap: _dismissResult,
                    ),
                  ],
                ),
              ),
            ),
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
            child: Text(AppLocalizations.of(context)!.gameQuit,
                style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Gemme facettee (diamant) — remplace l'emoji 💎
// ════════════════════════════════════════════════════════════
class _GemPainter extends CustomPainter {
  const _GemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);

    // Contour du diamant (rhombus a facettes)
    final outline = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.88, h * 0.42)
      ..lineTo(w * 0.5, h * 0.95)
      ..lineTo(w * 0.12, h * 0.42)
      ..close();

    // Ombre portee du gem
    canvas.drawShadow(outline, Colors.black.withValues(alpha: 0.6), 3, false);

    // Corps degrade (blanc → cyan → teal profond)
    canvas.drawPath(
      outline,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.5),
          radius: 1.1,
          colors: [Color(0xFFECFFFC), Color(0xFF4DE1C4), Color(0xFF0E8F79)],
          stops: [0, 0.5, 1],
        ).createShader(Offset.zero & size),
    );

    // Facettes (lignes depuis le centre-haut vers les aretes)
    final facet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.white.withValues(alpha: 0.5);
    final girdle = h * 0.42;
    // Table (arete horizontale)
    canvas.drawLine(p(0.12, 0.42), p(0.88, 0.42), facet);
    // Rayons vers la pointe
    canvas.drawLine(p(0.12, 0.42), p(0.5, 0.95), facet);
    canvas.drawLine(p(0.88, 0.42), p(0.5, 0.95), facet);
    canvas.drawLine(p(0.5, girdle / h), p(0.5, 0.95), facet);
    // Couronne
    canvas.drawLine(p(0.5, 0.06), p(0.32, 0.42), facet);
    canvas.drawLine(p(0.5, 0.06), p(0.68, 0.42), facet);

    // Facette claire (reflet haut-gauche)
    final glint = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.32, h * 0.42)
      ..lineTo(w * 0.12, h * 0.42)
      ..close();
    canvas.drawPath(
        glint, Paint()..color = Colors.white.withValues(alpha: 0.35));

    // Etincelle
    canvas.drawCircle(
        p(0.35, 0.24), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _GemPainter old) => false;
}

// ════════════════════════════════════════════════════════════
// Bombe (sphere metal + meche + etincelle) — remplace l'emoji 💣
// ════════════════════════════════════════════════════════════
class _BombPainter extends CustomPainter {
  const _BombPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * 0.47, h * 0.6);
    final r = w * 0.34;

    // Ombre au sol
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx, h * 0.95), width: r * 1.8, height: r * 0.5),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );

    // Corps sphere (degrade radial : reflet haut-gauche → noir)
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.5),
          colors: const [Color(0xFF5A5A68), Color(0xFF23232E), Color(0xFF0C0C12)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Liseret sombre
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.5),
    );
    // Reflet vitre
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx - r * 0.35, c.dy - r * 0.4),
          width: r * 0.7,
          height: r * 0.45),
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );

    // Culot de meche (petit cylindre sur le dessus)
    final capRect = Rect.fromLTWH(c.dx - r * 0.22, c.dy - r - r * 0.28, r * 0.44, r * 0.34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(capRect, const Radius.circular(1.5)),
      Paint()..color = const Color(0xFF6E5A2A),
    );

    // Meche (courbe vers le haut-droite)
    final fuse = Path()
      ..moveTo(c.dx, c.dy - r - r * 0.2)
      ..quadraticBezierTo(
          c.dx + r * 0.5, c.dy - r - r * 0.7, c.dx + r * 0.35, c.dy - r - r * 1.05);
    canvas.drawPath(
      fuse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB98A3A),
    );

    // Etincelle (halo + coeur)
    final spark = Offset(c.dx + r * 0.35, c.dy - r - r * 1.05);
    canvas.drawCircle(
      spark,
      r * 0.38,
      Paint()
        ..color = const Color(0xFFFF9100).withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(spark, r * 0.16, Paint()..color = const Color(0xFFFFF3C4));
  }

  @override
  bool shouldRepaint(covariant _BombPainter old) => false;
}
