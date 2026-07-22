// ============================================================
// Apple of Fortune – Single tile widget
// ============================================================
import 'package:flutter/material.dart';

enum FortuneTileState {
  hidden,     // Not yet revealed, not active
  active,     // Current row, clickable
  revealedSafe,   // Was safe (green apple)
  revealedDanger, // Was danger (skull)
  chosenSafe,     // Player picked this & it was safe
  chosenDanger,   // Player picked this & it was danger
}

class FortuneTile extends StatefulWidget {
  final FortuneTileState state;
  final VoidCallback? onTap;
  final int rowIndex;
  final int colIndex;
  final bool animateReveal;

  const FortuneTile({
    super.key,
    required this.state,
    required this.rowIndex,
    required this.colIndex,
    this.onTap,
    this.animateReveal = false,
  });

  @override
  State<FortuneTile> createState() => _FortuneTileState();
}

class _FortuneTileState extends State<FortuneTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;


  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(FortuneTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateReveal &&
        oldWidget.state != widget.state &&
        (widget.state == FortuneTileState.revealedSafe ||
            widget.state == FortuneTileState.revealedDanger ||
            widget.state == FortuneTileState.chosenSafe ||
            widget.state == FortuneTileState.chosenDanger)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.animateReveal ? _scaleAnim.value : 1.0,
          child: _buildTile(),
        );
      },
    );
  }

  Widget _buildTile() {
    final bool isClickable = widget.state == FortuneTileState.active;

    return GestureDetector(
      onTap: isClickable ? widget.onTap : null,
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: _gradient,
            border: Border.all(
              color: _borderColor,
              width: widget.state == FortuneTileState.active ? 2.0 : 1.5,
            ),
            boxShadow: [
              // Ombre portée de profondeur (toujours présente)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
              if (widget.state == FortuneTileState.active)
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              if (widget.state == FortuneTileState.chosenSafe)
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              if (widget.state == FortuneTileState.chosenDanger)
                BoxShadow(
                  color: const Color(0xFFFF1744).withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Reflet glossy en haut (effet verre premium)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(child: _buildIcon(constraints.maxWidth));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  LinearGradient get _gradient {
    switch (widget.state) {
      case FortuneTileState.hidden:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2740), Color(0xFF0F1B2D)],
        );
      case FortuneTileState.active:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A20), Color(0xFF0F2810)],
        );
      case FortuneTileState.revealedSafe:
      case FortuneTileState.chosenSafe:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        );
      case FortuneTileState.revealedDanger:
      case FortuneTileState.chosenDanger:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B0000), Color(0xFFB71C1C)],
        );
    }
  }

  Color get _borderColor {
    switch (widget.state) {
      case FortuneTileState.hidden:
        return const Color(0xFF2A3F5F);
      case FortuneTileState.active:
        return const Color(0xFF00E676).withValues(alpha: 0.6);
      case FortuneTileState.revealedSafe:
        return const Color(0xFF4CAF50);
      case FortuneTileState.chosenSafe:
        return const Color(0xFF00E676);
      case FortuneTileState.revealedDanger:
        return const Color(0xFFE53935);
      case FortuneTileState.chosenDanger:
        return const Color(0xFFFF1744);
    }
  }

  Widget _buildIcon(double s) {
    final iconSize = s * 0.42;
    final emojiSize = s * 0.44;
    final emojiBig = s * 0.48;

    switch (widget.state) {
      case FortuneTileState.hidden:
        return Icon(
          Icons.help_outline_rounded,
          color: const Color(0xFF4A5568),
          size: iconSize,
        );
      case FortuneTileState.active:
        return Icon(
          Icons.touch_app_rounded,
          color: const Color(0xFF00E676).withValues(alpha: 0.8),
          size: iconSize,
        );
      case FortuneTileState.revealedSafe:
        return SizedBox(
            width: emojiSize + 6,
            height: emojiSize + 6,
            child: const CustomPaint(painter: _ApplePainter()));
      case FortuneTileState.chosenSafe:
        return SizedBox(
            width: emojiBig + 8,
            height: emojiBig + 8,
            child: const CustomPaint(painter: _ApplePainter()));
      case FortuneTileState.revealedDanger:
        return SizedBox(
            width: emojiSize + 6,
            height: emojiSize + 6,
            child: const CustomPaint(painter: _SkullPainter()));
      case FortuneTileState.chosenDanger:
        return SizedBox(
            width: emojiBig + 8,
            height: emojiBig + 8,
            child: const CustomPaint(painter: _SkullPainter()));
    }
  }
}

// ════════════════════════════════════════════════════════════
// Pomme vectorielle glossy (remplace l'emoji 🍏)
// ════════════════════════════════════════════════════════════
class _ApplePainter extends CustomPainter {
  const _ApplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Corps de la pomme (deux lobes via oval + creux haut)
    final body = Path()
      ..moveTo(w * 0.5, h * 0.30)
      ..cubicTo(w * 0.18, h * 0.14, w * 0.02, h * 0.55, w * 0.20, h * 0.82)
      ..cubicTo(w * 0.32, h * 0.99, w * 0.44, h * 0.95, w * 0.5, h * 0.90)
      ..cubicTo(w * 0.56, h * 0.95, w * 0.68, h * 0.99, w * 0.80, h * 0.82)
      ..cubicTo(w * 0.98, h * 0.55, w * 0.82, h * 0.14, w * 0.5, h * 0.30)
      ..close();

    canvas.drawShadow(body, Colors.black.withValues(alpha: 0.5), 2, false);
    canvas.drawPath(
      body,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.0,
          colors: [Color(0xFF7BE86B), Color(0xFF32C24E), Color(0xFF128A34)],
          stops: [0, 0.5, 1],
        ).createShader(Offset.zero & size),
    );

    // Reflet glossy haut-gauche
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.36, h * 0.42), width: w * 0.28, height: h * 0.18),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    // Tige
    canvas.drawLine(
      Offset(w * 0.5, h * 0.30),
      Offset(w * 0.56, h * 0.12),
      Paint()
        ..color = const Color(0xFF6E4A25)
        ..strokeWidth = w * 0.05
        ..strokeCap = StrokeCap.round,
    );
    // Feuille
    final leaf = Path()
      ..moveTo(w * 0.56, h * 0.16)
      ..quadraticBezierTo(w * 0.82, h * 0.06, w * 0.80, h * 0.28)
      ..quadraticBezierTo(w * 0.66, h * 0.26, w * 0.56, h * 0.16)
      ..close();
    canvas.drawPath(
      leaf,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF8BE58A), Color(0xFF2E9E3C)],
        ).createShader(Rect.fromLTWH(w * 0.56, h * 0.06, w * 0.26, h * 0.22)),
    );
  }

  @override
  bool shouldRepaint(covariant _ApplePainter old) => false;
}

// ════════════════════════════════════════════════════════════
// Tête de mort vectorielle (remplace l'emoji 💀)
// ════════════════════════════════════════════════════════════
class _SkullPainter extends CustomPainter {
  const _SkullPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bone = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF3EEE2), Color(0xFFC9BFA8)],
    ).createShader(Offset.zero & size);

    // Crâne
    final skull = Path()
      ..addOval(Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.42),
          width: w * 0.74,
          height: h * 0.70));
    // Mâchoire
    final jaw = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.74), width: w * 0.44, height: h * 0.28),
      Radius.circular(w * 0.12),
    );
    canvas.drawShadow(skull, Colors.black.withValues(alpha: 0.5), 2, false);
    canvas.drawRRect(jaw, Paint()..shader = bone);
    canvas.drawPath(skull, Paint()..shader = bone);

    // Orbites (yeux)
    final socket = Paint()..color = const Color(0xFF1A1A22);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.34, h * 0.42), width: w * 0.22, height: h * 0.24),
      socket,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.66, h * 0.42), width: w * 0.22, height: h * 0.24),
      socket,
    );
    // Lueur rouge au fond des orbites
    final spark = Paint()..color = const Color(0xFFFF1744).withValues(alpha: 0.8);
    canvas.drawCircle(Offset(w * 0.34, h * 0.44), w * 0.04, spark);
    canvas.drawCircle(Offset(w * 0.66, h * 0.44), w * 0.04, spark);
    // Nez
    final nose = Path()
      ..moveTo(w * 0.5, h * 0.48)
      ..lineTo(w * 0.44, h * 0.60)
      ..lineTo(w * 0.56, h * 0.60)
      ..close();
    canvas.drawPath(nose, socket);
    // Dents
    final tooth = Paint()..color = const Color(0xFF9C917A);
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(w * (0.4 + i * 0.067), h * 0.66),
        Offset(w * (0.4 + i * 0.067), h * 0.84),
        tooth..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkullPainter old) => false;
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
