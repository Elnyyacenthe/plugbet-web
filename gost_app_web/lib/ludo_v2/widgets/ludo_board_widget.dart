// ============================================================
// LUDO V2 — Board Widget (plateau + pions animés, premium redesign)
// ============================================================

import 'package:flutter/material.dart';
import '../engine/ludo_board.dart';
import '../engine/ludo_engine.dart';
import '../models/ludo_models.dart';
import '../painters/board_painter.dart';

class LudoV2BoardWidget extends StatelessWidget {
  final LudoV2Game game;
  final LudoV2Game? previousGame;
  final String myId;
  final List<PawnMove> playableMoves;
  final void Function(int pawnIndex)? onPawnTap;

  const LudoV2BoardWidget({
    super.key,
    required this.game,
    this.previousGame,
    required this.myId,
    this.playableMoves = const [],
    this.onPawnTap,
  });

  static const _pawnColors = [
    Color(0xFFE53935), // Red
    Color(0xFF43A047), // Green
    Color(0xFF1E88E5), // Blue
    Color(0xFFFDD835), // Yellow
  ];

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final boardSize = constraints.maxWidth;
          final cell = boardSize / 15;

          return Stack(
            children: [
              // Plateau de fond
              CustomPaint(
                size: Size(boardSize, boardSize),
                painter: LudoBoardPainter(),
              ),

              // Pions de tous les joueurs
              ...game.pawns.entries.expand((entry) {
                final uid = entry.key;
                final pawns = entry.value;
                final colorIdx = game.colorMap[uid] ?? 0;
                final isMe = uid == myId;
                return List.generate(4, (i) {
                  final step = pawns[i];
                  final gridPos = LudoBoard.stepToGrid(step, colorIdx, pawnIndex: i);
                  final isPlayable = isMe && playableMoves.any((m) => m.pawnIndex == i);

                  // Stacking : offset si plusieurs pions sur la même case
                  final sameCell = _countSameCell(pawns, step, colorIdx, i, game);
                  final stackOffset = _stackOffset(sameCell.index, sameCell.total, cell);

                  return _AnimatedPawn(
                    key: ValueKey('$uid-$i'),
                    row: gridPos[0],
                    col: gridPos[1],
                    cell: cell,
                    color: _pawnColors[colorIdx],
                    isPlayable: isPlayable,
                    isActive: game.isMyTurn(uid),
                    stackOffset: stackOffset,
                    onTap: isPlayable ? () => onPawnTap?.call(i) : null,
                  );
                });
              }),
            ],
          );
        },
      ),
    );
  }

  /// Compte combien de pions sont sur la même case visuelle
  _SameCellInfo _countSameCell(List<int> myPawns, int step, int myColor, int pawnIdx, LudoV2Game game) {
    if (step <= 0 || step >= 58) {
      // En base ou au centre, offset par index directement
      return _SameCellInfo(pawnIdx, 4);
    }

    // Compter tous les pions de tous les joueurs sur la même case absolue
    int myAbs = LudoBoard.toAbsolute(step, myColor);
    if (step >= 52) myAbs = -step; // Home stretch : unique par couleur

    int total = 0;
    int myIndex = 0;

    for (final entry in game.pawns.entries) {
      final uid = entry.key;
      final color = game.colorMap[uid] ?? 0;
      for (int i = 0; i < entry.value.length; i++) {
        final s = entry.value[i];
        int abs = s >= 52 ? -s : (s >= 1 ? LudoBoard.toAbsolute(s, color) : -100 - i);
        if (abs == myAbs) {
          if (uid == game.pawns.keys.toList()[game.colorMap.keys.toList().indexOf(game.colorMap.keys.firstWhere((k) => game.colorMap[k] == myColor))] && i == pawnIdx) {
            myIndex = total;
          }
          total++;
        }
      }
    }

    return _SameCellInfo(myIndex, total > 1 ? total : 1);
  }

  Offset _stackOffset(int index, int total, double cell) {
    if (total <= 1) return Offset.zero;
    // Disposer en grille 2x2 si 2-4 pions sur la même case
    const offsets = [
      Offset(-0.15, -0.15),
      Offset(0.15, -0.15),
      Offset(-0.15, 0.15),
      Offset(0.15, 0.15),
    ];
    return offsets[index.clamp(0, 3)] * cell;
  }
}

class _SameCellInfo {
  final int index;
  final int total;
  const _SameCellInfo(this.index, this.total);
}

/// Pion animé avec position, couleur, tap et highlight.
/// Ajoute une pulsation néon douce quand le pion est jouable, pour un
/// rendu "premium" façon plateforme de paris haut de gamme.
class _AnimatedPawn extends StatefulWidget {
  final int row;
  final int col;
  final double cell;
  final Color color;
  final bool isPlayable;
  final bool isActive;
  final Offset stackOffset;
  final VoidCallback? onTap;

  const _AnimatedPawn({
    super.key,
    required this.row,
    required this.col,
    required this.cell,
    required this.color,
    required this.isPlayable,
    required this.isActive,
    required this.stackOffset,
    this.onTap,
  });

  @override
  State<_AnimatedPawn> createState() => _AnimatedPawnState();
}

class _AnimatedPawnState extends State<_AnimatedPawn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlayable) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AnimatedPawn old) {
    super.didUpdateWidget(old);
    if (widget.isPlayable != old.isPlayable) {
      if (widget.isPlayable) {
        _pulseCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.col * widget.cell + widget.stackOffset.dx;
    final y = widget.row * widget.cell + widget.stackOffset.dy;
    final size = widget.cell * 0.75;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      left: x + (widget.cell - size) / 2,
      top: y + (widget.cell - size) / 2,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) {
            final pulse = widget.isPlayable ? _pulseCtrl.value : 0.0;
            return Transform.scale(
              scale: 1.0 + (pulse * 0.10),
              child: child,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.35),
                colors: [
                  Color.lerp(widget.color, Colors.white, 0.35)!,
                  widget.color,
                  Color.lerp(widget.color, Colors.black, 0.25)!,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              border: Border.all(
                color: widget.isPlayable ? Colors.white : widget.color.withValues(alpha: 0.5),
                width: widget.isPlayable ? 3 : 1.5,
              ),
              boxShadow: [
                if (widget.isPlayable) ...[
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.55),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ] else if (widget.isActive)
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.35),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              // Cabochon surélevé (dôme + reflet spéculaire) → vrai jeton 3D
              child: Container(
                width: size * 0.5,
                height: size * 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.4),
                    colors: [
                      Colors.white.withValues(alpha: 0.85),
                      Color.lerp(widget.color, Colors.white, 0.25)!,
                      widget.color,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                  border: Border.all(
                      color: Colors.black.withValues(alpha: 0.15), width: 0.8),
                ),
                child: Align(
                  alignment: const Alignment(-0.35, -0.4),
                  child: FractionallySizedBox(
                    widthFactor: 0.32,
                    heightFactor: 0.32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
