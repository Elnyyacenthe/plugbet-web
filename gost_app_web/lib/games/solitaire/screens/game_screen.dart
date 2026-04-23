// ============================================================
// Solitaire – Écran de jeu Klondike (UI améliorée)
// ============================================================
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/matches_provider.dart';
import '../../../services/live_score_manager.dart';
import '../models/solitaire_models.dart';
import '../game/solitaire_logic.dart';
import '../services/solitaire_service.dart';

class SolitaireGameScreen extends StatefulWidget {
  final bool isPractice;
  const SolitaireGameScreen({super.key, this.isPractice = false});
  @override
  State<SolitaireGameScreen> createState() => _SolitaireGameScreenState();
}

class _SolitaireGameScreenState extends State<SolitaireGameScreen>
    with TickerProviderStateMixin {
  final SolitaireService _service = SolitaireService();
  late SolitaireState _state;
  Timer? _timer;
  int _elapsed = 0;
  bool _gameEnded = false;
  // Timer d'inactivité : 8s par coup
  static const int _inactivitySeconds = 8;
  int _inactivityCountdown = _inactivitySeconds;
  Timer? _inactivityTimer;
  int _consecutiveAutoMoves = 0;
  static const int _bet = 200;
  static const int _maxSec = 600;

  // Animation pour le score
  late AnimationController _scoreAnimCtrl;
  late Animation<double> _scoreScale;

  bool get _isPractice => widget.isPractice;

  @override
  void initState() {
    super.initState();
    _state = SolitaireState.initial();
    if (!_isPractice) _deductBet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MatchesProvider>().pausePolling();
        context.read<LiveScoreManager>().pauseTracking();
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _maxSec && !_gameEnded) _end(won: false);
    });

    _scoreAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scoreScale = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _scoreAnimCtrl, curve: Curves.elasticOut),
    );
    _startInactivityTimer();
  }

  Future<void> _deductBet() async {
    final ok = await _service.deductCoins(_bet);
    if (!ok && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.gameInsufficientFunds)));
    }
  }

  void _confirmExit() {
    if (_gameEnded) {
      Navigator.pop(context);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.gameLeaveQuestion,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          _isPractice
              ? 'Abandonner la partie en cours ?'
              : 'Cette action sera considérée comme un forfait et tu perdras ta mise de $_bet FCFA.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel,
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _end(won: false);
            },
            child: Text(AppLocalizations.of(context)!.gameForfeit,
                style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_gameEnded || !mounted) return;
    setState(() => _inactivityCountdown = _inactivitySeconds);
    _inactivityTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _gameEnded) { t.cancel(); return; }
      setState(() => _inactivityCountdown--);
      if (_inactivityCountdown <= 0) {
        t.cancel();
        _onInactivityTimeout();
      }
    });
  }

  void _onInactivityTimeout() {
    if (_gameEnded) return;
    _consecutiveAutoMoves++;
    if (_consecutiveAutoMoves >= 4) {
      _inactivityTimer?.cancel();
      _end(won: false);
      return;
    }
    _tryAutoMove();
  }

  void _tryAutoMove() {
    final rng = Random();

    // Catégoriser les coups disponibles
    SolitaireState? foundationMove; // bon coup
    SolitaireState? tableauMove;    // coup neutre
    final SolitaireState stockMove = SolitaireLogic.drawFromStock(_state); // mauvais coup

    foundationMove = SolitaireLogic.moveWasteToFoundation(_state);
    if (foundationMove == null) {
      for (int c = 0; c < 7; c++) {
        foundationMove = SolitaireLogic.moveTableauToFoundation(_state, c);
        if (foundationMove != null) break;
      }
    }
    for (int c = 0; c < 7; c++) {
      tableauMove = SolitaireLogic.moveWasteToTableau(_state, c);
      if (tableauMove != null) break;
    }

    final rand = rng.nextDouble();
    if (rand < 0.35 && foundationMove != null) {
      // 35% : bon coup (fondation)
      _act(foundationMove);
    } else if (rand < 0.65 && tableauMove != null) {
      // 30% : coup neutre (tableau)
      _act(tableauMove);
    } else if (rand < 0.85) {
      // 20% : mauvais coup (pioche)
      _act(stockMove);
    } else if (foundationMove != null) {
      _act(foundationMove);
    } else if (tableauMove != null) {
      _act(tableauMove);
    } else {
      _act(stockMove);
    }
  }

  void _end({required bool won}) {
    if (_gameEnded) return;
    _gameEnded = true;
    _timer?.cancel();
    if (won && !_isPractice) {
      _service.addCoins(_bet * 2);
      _service.saveBestScore(_state.score);
    }
    context.read<PlayerProvider>().recordGameResult(
      gameType: 'solitaire',
      result: won ? 'win' : 'loss',
      coinsChange:
          won && !_isPractice ? _bet * 2 : (_isPractice ? 0 : -_bet),
      score: _state.score,
      isPractice: _isPractice,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EndDialog(
        won: won,
        score: _state.score,
        prize: won && !_isPractice ? _bet * 2 : 0,
        isPractice: _isPractice,
        onClose: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _act(SolitaireState? s) {
    if (s == null || _gameEnded) return;
    _consecutiveAutoMoves = 0; // reset on any move
    final prevScore = _state.score;
    setState(() => _state = s);
    _startInactivityTimer(); // restart 8s timer after each move
    if (s.score > prevScore) {
      _scoreAnimCtrl.forward(from: 0);
    }
    if (s.isWon) _end(won: true);
  }

  String get _timeStr {
    final rem = _maxSec - _elapsed;
    final m = (rem < 0 ? 0 : rem) ~/ 60;
    final s = (rem < 0 ? 0 : rem) % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _isLowTime => _elapsed > _maxSec * 0.8;

  @override
  void dispose() {
    _timer?.cancel();
    _inactivityTimer?.cancel();
    _scoreAnimCtrl.dispose();
    context.read<MatchesProvider>().resumePolling();
    context.read<LiveScoreManager>().resumeTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(child: _board()),
        ]),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────
  Widget _topBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 10, 12, 10),
      decoration: BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155), width: 0.8),
        ),
      ),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70, size: 18),
          onPressed: () => _confirmExit(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        SizedBox(width: 4),
        Text(
          'SOLITAIRE',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 2.5,
          ),
        ),
        if (_isPractice) ...[
          SizedBox(width: 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.neonBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.neonBlue.withValues(alpha: 0.3)),
            ),
            child: Text('ENTRAÎN.',
                style: TextStyle(
                    color: AppColors.neonBlue,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ),
        ],
        const Spacer(),
        // Badge Score
        ScaleTransition(
          scale: _scoreScale,
          child: _InfoChip(
            icon: Icons.star_rounded,
            label: '${_state.score}',
            color: const Color(0xFFF59E0B),
          ),
        ),
        SizedBox(width: 8),
        // Badge Timer
        _InfoChip(
          icon: Icons.timer_outlined,
          label: _timeStr,
          color: _isLowTime ? AppColors.neonRed : AppColors.neonGreen,
          pulse: _isLowTime,
        ),
        SizedBox(width: 8),
        // Badge inactivité
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (_inactivityCountdown <= 3
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF64748B))
                .withValues(alpha: 0.18),
            border: Border.all(
              color: (_inactivityCountdown <= 3
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF64748B))
                  .withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
          child: Center(
            child: Text(
              '$_inactivityCountdown',
              style: TextStyle(
                color: _inactivityCountdown <= 3
                    ? const Color(0xFFEF4444)
                    : Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Plateau ────────────────────────────────────────────────
  Widget _board() {
    return LayoutBuilder(builder: (ctx, box) {
      final cw = (box.maxWidth - 32) / 7;
      final ch = cw * 1.48;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(8, 14, 8, 16),
        child: Column(children: [
          // Ligne supérieure
          SizedBox(
            height: ch,
            child: Row(children: [
              _stock(cw, ch),
              SizedBox(width: 6),
              _waste(cw, ch),
              const Spacer(),
              for (int i = 0; i < 4; i++) ...[
                SizedBox(width: 6),
                _foundation(i, cw, ch),
              ],
            ]),
          ),
          SizedBox(height: 14),
          // Tableau 7 colonnes
          SizedBox(
            height: box.maxHeight - ch - 42,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                7,
                (col) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3),
                    child: _tableauCol(col, cw, ch),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }

  // ── Stock ──────────────────────────────────────────────────
  Widget _stock(double w, double h) => GestureDetector(
        onTap: () => _act(SolitaireLogic.drawFromStock(_state)),
        child: _slot(
          w, h,
          child: _state.stock.isNotEmpty
              ? _back(w, h)
              : Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Center(
                    child: Icon(Icons.refresh_rounded,
                        color: Colors.white38, size: 26),
                  ),
                ),
        ),
      );

  // ── Talon ──────────────────────────────────────────────────
  Widget _waste(double w, double h) => _slot(
        w, h,
        child: _state.waste.isNotEmpty
            ? _face(_state.waste.last, w, h,
                onTap: () =>
                    _act(SolitaireLogic.moveWasteToFoundation(_state)))
            : null,
      );

  // ── Fondation ──────────────────────────────────────────────
  Widget _foundation(int idx, double w, double h) {
    final f = _state.foundations[idx];
    final suit = CardSuit.values[idx];
    return GestureDetector(
      onTap: () => _act(SolitaireLogic.moveWasteToFoundation(_state)),
      child: _slot(
        w, h,
        border: const Color(0xFF22C55E).withValues(alpha: 0.4),
        child: f.isNotEmpty
            ? _face(f.last, w, h)
            : Center(
                child: Text(
                  suit.symbol,
                  style: TextStyle(
                    color: suit.isRed
                        ? Colors.red.shade300.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.2),
                    fontSize: w * 0.38,
                  ),
                ),
              ),
      ),
    );
  }

  // ── Colonne tableau ────────────────────────────────────────
  Widget _tableauCol(int col, double w, double h) {
    final cards = _state.tableau[col];
    if (cards.isEmpty) {
      return GestureDetector(
        onTap: () => _act(SolitaireLogic.moveWasteToTableau(_state, col)),
        child: _slot(w, h),
      );
    }
    final overlap = h * 0.30;
    return SizedBox(
      height: h + overlap * (cards.length - 1),
      child: Stack(
        children: List.generate(cards.length, (i) {
          final card = cards[i];
          return Positioned(
            top: i * overlap,
            left: 0,
            right: 0,
            child: card.faceUp
                ? _face(card, w, h, onTap: () {
                    if (i == cards.length - 1) {
                      final r = SolitaireLogic.moveTableauToFoundation(
                          _state, col);
                      if (r != null) {
                        _act(r);
                        return;
                      }
                    }
                    for (int d = 0; d < 7; d++) {
                      if (d == col) continue;
                      final r = SolitaireLogic.moveTableauToTableau(
                          _state, col, i, d);
                      if (r != null) {
                        _act(r);
                        return;
                      }
                    }
                  })
                : _back(w, h),
          );
        }),
      ),
    );
  }

  // ── Slot vide ──────────────────────────────────────────────
  Widget _slot(double w, double h,
      {Widget? child, Color? border}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: border ?? Colors.white.withValues(alpha: 0.10),
          width: 1.2,
        ),
      ),
      child: child,
    );
  }

  // ── Carte face ─────────────────────────────────────────────
  Widget _face(PlayingCard card, double w, double h,
      {VoidCallback? onTap}) {
    final isRed = card.isRed;
    final textColor =
        isRed ? const Color(0xFFDC2626) : const Color(0xFF1E293B);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
          border: Border.all(
              color: Colors.black.withValues(alpha: 0.08), width: 0.5),
        ),
        child: Stack(children: [
          Positioned(
            top: 3,
            left: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  card.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: w * 0.26,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                Text(
                  card.suit.symbol,
                  style: TextStyle(
                    color: textColor,
                    fontSize: w * 0.22,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Text(
              card.suit.symbol,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.08),
                fontSize: w * 0.52,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Dos de carte ───────────────────────────────────────────
  Widget _back(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1D4ED8), Color(0xFF6D28D9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 5,
              offset: Offset(0, 3),
            ),
          ],
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.15), width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CustomPaint(painter: _CardBackPainter()),
        ),
      );
}

// ── Peintre motif dos de carte ─────────────────────────────
class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    const step = 10.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        if ((x ~/ step + y ~/ step) % 2 == 0) {
          canvas.drawRect(
              Rect.fromLTWH(x, y, step, step), paint);
        }
      }
    }

    // Bordure intérieure
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
        const Radius.circular(7),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Info chip (timer / score) ──────────────────────────────
class _InfoChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  @override
  State<_InfoChip> createState() => _InfoChipState();
}

class _InfoChipState extends State<_InfoChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_InfoChip old) {
    super.didUpdateWidget(old);
    if (widget.pulse && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      )..repeat(reverse: true);
    } else if (!widget.pulse) {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget chip = Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 14, color: widget.color),
          SizedBox(width: 5),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );

    if (_pulse != null) {
      return AnimatedBuilder(
        animation: _pulse!,
        builder: (_, child) => Opacity(
          opacity: 0.5 + _pulse!.value * 0.5,
          child: child,
        ),
        child: chip,
      );
    }
    return chip;
  }
}

// ── Dialog fin de partie ────────────────────────────────────
class _EndDialog extends StatelessWidget {
  final bool won;
  final int score, prize;
  final bool isPractice;
  final VoidCallback onClose;

  const _EndDialog({
    required this.won,
    required this.score,
    required this.prize,
    this.isPractice = false,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final accent = won ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(won ? '🎉' : '😔', style: TextStyle(fontSize: 54)),
        SizedBox(height: 12),
        Text(
          won ? 'Félicitations !' : 'Partie terminée',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: accent),
        ),
        SizedBox(height: 10),
        Container(
          padding:
              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Score : $score pts',
            style: TextStyle(
                color: Colors.white70, fontSize: 16),
          ),
        ),
        if (won && prize > 0) ...[
          SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.monetization_on_rounded,
                color: Color(0xFFF59E0B), size: 22),
            SizedBox(width: 6),
            Text(
              '+$prize FCFA',
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ]),
        ],
        SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 4,
            ),
            child: Text('RETOUR',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1)),
          ),
        ),
      ]),
    );
  }
}
