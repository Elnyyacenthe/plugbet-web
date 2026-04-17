// ============================================================
// ChatComboBadge — Badge combo dans le header de chat
// Affiche un embleme (bronze/argent/or/trophee/couronne) + compteur
// ============================================================
import 'package:flutter/material.dart';

class ChatComboBadge extends StatelessWidget {
  final int combo;
  const ChatComboBadge({super.key, required this.combo});

  (String, Color, Color) get _tier {
    if (combo >= 100) {
      return ('👑', const Color(0xFFFFD700), const Color(0xFFFFB300));
    }
    if (combo >= 50) {
      return ('🏆', const Color(0xFFFF7043), const Color(0xFFD84315));
    }
    if (combo >= 25) {
      return ('🥇', const Color(0xFFFFCA28), const Color(0xFFF9A825));
    }
    if (combo >= 10) {
      return ('🥈', const Color(0xFFB0BEC5), const Color(0xFF78909C));
    }
    return ('🥉', const Color(0xFFBF8970), const Color(0xFF8D5524));
  }

  @override
  Widget build(BuildContext context) {
    final (emoji, c1, c2) = _tier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: c1.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            '$combo',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.3,
              shadows: [
                Shadow(
                  color: Colors.black38,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
