// ============================================================
// BLACKJACK — Widget carte
// ============================================================
// >>> DESIGN <<<
// Cartes "matière" : dos à guilloché (lattice) + médaillon doré et
// reflet ; faces avec double index (haut-gauche + bas-droite miroir),
// sheen diagonal et pip central en relief. La logique (card, cards,
// hideSecond, cardWidth) est strictement identique à l'original.
// ============================================================

import 'package:flutter/material.dart';
import '../models/blackjack_models.dart';

class BJCardWidget extends StatelessWidget {
  final BJCard? card; // null = carte cachée
  final double width;

  const BJCardWidget({super.key, this.card, this.width = 55});

  static const _gold = Color(0xFFE8C879);

  @override
  Widget build(BuildContext context) {
    final h = width * 1.45;
    final radius = width * 0.16;

    if (card == null) {
      // Dos de carte : bleu nuit + guilloché + médaillon doré.
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E4179), Color(0xFF0B1D3A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: _gold.withValues(alpha: 0.55), width: 1),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45, blurRadius: 7, offset: Offset(2, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Motif guilloché
              Positioned.fill(
                  child: CustomPaint(painter: _CardBackPainter(width))),
              // Médaillon central doré (relief)
              Container(
                width: width * 0.42,
                height: width * 0.42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    colors: [Color(0xFFFFF3C4), Color(0xFFE8C879), Color(0xFF9A7420)],
                    stops: [0, 0.55, 1],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: _gold.withValues(alpha: 0.5), blurRadius: 8),
                  ],
                ),
                child: Icon(Icons.diamond_rounded,
                    color: const Color(0xFF3A2B00).withValues(alpha: 0.8),
                    size: width * 0.24),
              ),
              // Reflet vitre diagonal
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.center,
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final c = card!;
    final color = c.isRed ? const Color(0xFFE53935) : const Color(0xFF1A2035);
    final suit =
        {'hearts': '♥', 'diamonds': '♦', 'clubs': '♣', 'spades': '♠'}[c.suit] ??
            '';

    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFE7EAF2)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 3)),
          const BoxShadow(
              color: Colors.black38, blurRadius: 5, offset: Offset(1, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Enseigne centrale en relief
            Center(
              child: Text(suit,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.92),
                      fontSize: width * 0.52,
                      shadows: [
                        Shadow(
                            color: color.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2)),
                      ])),
            ),
            // Index haut-gauche
            Positioned(
              top: width * 0.06,
              left: width * 0.09,
              child: _index(c.rank, suit, color),
            ),
            // Index bas-droite (miroir)
            Positioned(
              bottom: width * 0.06,
              right: width * 0.09,
              child: Transform.rotate(
                angle: 3.14159,
                child: _index(c.rank, suit, color),
              ),
            ),
            // Sheen diagonal (matière carte)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.32, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _index(String rank, String suit, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(rank,
            style: TextStyle(
                color: color,
                fontSize: width * 0.26,
                height: 1,
                fontWeight: FontWeight.w900)),
        Text(suit, style: TextStyle(color: color, fontSize: width * 0.2, height: 1)),
      ],
    );
  }
}

/// Motif guilloché du dos (lattice diagonal doré + liseret intérieur).
class _CardBackPainter extends CustomPainter {
  final double w;
  const _CardBackPainter(this.w);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFE8C879).withValues(alpha: 0.14)
      ..strokeWidth = 0.8;
    final step = w * 0.22;
    // Diagonales ↘
    for (double d = -size.height; d < size.width; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), line);
    }
    // Diagonales ↙ (croisement = losanges)
    for (double d = 0; d < size.width + size.height; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), line);
    }
    // Liseret intérieur doré
    final inset = Rect.fromLTWH(
        w * 0.10, w * 0.10, size.width - w * 0.20, size.height - w * 0.20);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, Radius.circular(w * 0.10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE8C879).withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(covariant _CardBackPainter old) => false;
}

class BJHandWidget extends StatelessWidget {
  final List<BJCard> cards;
  final bool hideSecond; // dealer cache la 2e carte
  final double cardWidth;

  const BJHandWidget({
    super.key,
    required this.cards,
    this.hideSecond = false,
    this.cardWidth = 50,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final overlap = cardWidth * 0.3;
    final totalWidth = cardWidth + (cards.length - 1) * (cardWidth - overlap);

    return SizedBox(
      width: totalWidth,
      height: cardWidth * 1.45,
      child: Stack(
        children: List.generate(cards.length, (i) {
          final show = !(hideSecond && i == 1);
          return Positioned(
            left: i * (cardWidth - overlap),
            child: BJCardWidget(
              card: show ? cards[i] : null,
              width: cardWidth,
            ),
          );
        }),
      ),
    );
  }
}
