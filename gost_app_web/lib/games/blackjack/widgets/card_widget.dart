// ============================================================
// BLACKJACK — Widget carte
// ============================================================

import 'package:flutter/material.dart';
import '../models/blackjack_models.dart';

class BJCardWidget extends StatelessWidget {
  final BJCard? card; // null = carte cachée
  final double width;

  const BJCardWidget({super.key, this.card, this.width = 55});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.45;

    if (card == null) {
      return Container(
        width: width, height: h,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(2, 2))],
        ),
        child: Center(
          child: Text('?', style: TextStyle(color: Colors.white54, fontSize: width * 0.4, fontWeight: FontWeight.w900)),
        ),
      );
    }

    final c = card!;
    final color = c.isRed ? Colors.red : Colors.black;

    return Container(
      width: width, height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(2, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(c.rank, style: TextStyle(color: color, fontSize: width * 0.32, fontWeight: FontWeight.w900)),
          Text(
            {'hearts': '♥', 'diamonds': '♦', 'clubs': '♣', 'spades': '♠'}[c.suit] ?? '',
            style: TextStyle(color: color, fontSize: width * 0.28),
          ),
        ],
      ),
    );
  }
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
    if (cards.isEmpty) return SizedBox.shrink();
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
