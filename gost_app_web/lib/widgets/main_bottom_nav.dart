// ============================================================
// Plugbet – Barre de navigation principale (globale)
// ============================================================
// 5 onglets égaux sur fond bleu-nuit (#0B1120). L'onglet ACTIF affiche
// son icône en blanc dans une pastille circulaire verte pleine ; les
// onglets inactifs sont en trait fin gris, sans remplissage. Un libellé
// sous chaque icône (blanc pour l'actif, gris pour l'inactif).
//
//  Populaire (flamme) · Favoris (étoile) · Coupon (ticket, au centre)
//  · Historique (horloge+flèche) · Menu (grille 2×2)
//
// L'icône « Coupon » est un ticket dessiné à la main (encoches semi-
// circulaires + pointillé vertical central) — voir [_TicketPainter].
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'plugbet_wordmark.dart' show kPlugbetGreen;

/// Un item de la barre de navigation principale.
class MainNavItem {
  final IconData? icon;

  /// Dessin custom de l'icône (utilisé pour le ticket « Coupon »).
  /// Reçoit la couleur cible et l'état actif.
  final Widget Function(Color color, bool active)? iconBuilder;
  final String label;

  /// Compteur en pastille rouge (ex. nb de sélections du coupon).
  final int badgeCount;

  /// Item central surélevé, toujours affiché avec la couleur d'accent
  /// (pastille verte pleine) même lorsqu'il n'est pas sélectionné.
  final bool prominent;

  const MainNavItem({
    this.icon,
    this.iconBuilder,
    required this.label,
    this.badgeCount = 0,
    this.prominent = false,
  }) : assert(icon != null || iconBuilder != null,
            'icon ou iconBuilder requis');
}

class MainBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<MainNavItem> items;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bottomNavBackground,
        border: Border(top: BorderSide(color: AppColors.bottomNavBorder)),
        boxShadow: [
          BoxShadow(
            color: AppColors.bottomNavShadow,
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Material(
        color: AppColors.bottomNavBackground,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 74,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavSlot(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final MainNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavSlot({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (item.prominent) {
      return _ProminentSlot(item: item, selected: selected, onTap: onTap);
    }

    // Onglet actif : on colore simplement l'icône + le libellé en vert
    // (pas de pastille pleine, réservée au bouton central).
    final iconColor = selected ? kPlugbetGreen : AppColors.bottomNavInactive;

    Widget glyph = item.iconBuilder != null
        ? item.iconBuilder!(iconColor, selected)
        : Icon(item.icon, size: 24, color: iconColor);

    if (item.badgeCount > 0) {
      glyph = Stack(
        clipBehavior: Clip.none,
        children: [
          glyph,
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.bottomNavBackground, width: 2),
              ),
              child: Center(
                child: Text(
                  item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: onTap,
      splashColor: kPlugbetGreen.withValues(alpha: 0.10),
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 30, child: Center(child: glyph)),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.2,
              color: iconColor,
            ),
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Item central surélevé, toujours en pastille verte pleine (accent),
/// que l'onglet soit sélectionné ou non. Sélectionné = halo plus fort.
class _ProminentSlot extends StatelessWidget {
  final MainNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _ProminentSlot({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget glyph = item.iconBuilder != null
        ? item.iconBuilder!(Colors.white, true)
        : Icon(item.icon, size: 26, color: Colors.white);

    return InkWell(
      onTap: onTap,
      splashColor: kPlugbetGreen.withValues(alpha: 0.10),
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: const Offset(0, -16),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kPlugbetGreen,
                    border:
                        Border.all(color: AppColors.bottomNavBackground, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: kPlugbetGreen
                            .withValues(alpha: selected ? 0.60 : 0.40),
                        blurRadius: selected ? 20 : 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(child: glyph),
                ),
                if (item.badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      constraints: const BoxConstraints(minWidth: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.bottomNavBackground, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -10),
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: selected ? Colors.white : kPlugbetGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icône « ticket / coupon » : rectangle arrondi avec deux encoches
/// semi-circulaires sur les bords gauche/droit et un pointillé vertical
/// central. Toujours en trait (outline), la couleur portant l'état.
class TicketIcon extends StatelessWidget {
  final double size;
  final Color color;

  const TicketIcon({super.key, this.size = 23, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TicketPainter(color: color, stroke: size * 0.085),
      ),
    );
  }
}

class _TicketPainter extends CustomPainter {
  final Color color;
  final double stroke;

  _TicketPainter({required this.color, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Corps du ticket : centré verticalement, plus large que haut.
    final ticketH = h * 0.60;
    final top = (h - ticketH) / 2;
    final inset = stroke; // marge pour ne pas rogner le trait
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, top, w - inset * 2, ticketH),
      Radius.circular(ticketH * 0.24),
    );

    final notchR = ticketH * 0.22;
    final cy = top + ticketH / 2;

    final body = Path()..addRRect(rect);
    final leftNotch = Path()
      ..addOval(Rect.fromCircle(center: Offset(inset, cy), radius: notchR));
    final rightNotch = Path()
      ..addOval(Rect.fromCircle(center: Offset(w - inset, cy), radius: notchR));

    var outline = Path.combine(PathOperation.difference, body, leftNotch);
    outline = Path.combine(PathOperation.difference, outline, rightNotch);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(outline, paint);

    // Pointillé vertical central.
    final cx = w / 2;
    final dashPaint = Paint()
      ..color = color
      ..strokeWidth = stroke * 0.9
      ..strokeCap = StrokeCap.round;
    const dash = 2.0;
    const gap = 2.0;
    double y = top + notchR * 0.7;
    final endY = top + ticketH - notchR * 0.7;
    while (y < endY) {
      final y2 = (y + dash) > endY ? endY : (y + dash);
      canvas.drawLine(Offset(cx, y), Offset(cx, y2), dashPaint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TicketPainter old) =>
      old.color != color || old.stroke != stroke;
}
