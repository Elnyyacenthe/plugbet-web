// ============================================================
// Plugbet – Barre de navigation en relief
// ============================================================
// Remplace le BottomNavigationBar plat (aplat noir + filet 0.5 px).
//
// La barre est une plaque de métal brossé éclairée en diagonale, dont
// l'arête supérieure capte la lumière et projette son ombre vers le
// haut, sur le contenu. L'onglet actif repose dans une pastille
// surélevée qui rayonne : l'icône passe en graisse Fill, le libellé
// s'épaissit.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_theme.dart';

class ReliefNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int? tabIndex;
  final VoidCallback? onTap;
  final bool prominent;

  /// Compteur affiché en pastille rouge (messages non lus).
  final int badgeCount;

  const ReliefNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.tabIndex,
    this.onTap,
    this.prominent = false,
    this.badgeCount = 0,
  });
}

class ReliefBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<ReliefNavItem> items;
  final Color? accent;

  const ReliefBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent ?? AppColors.primary;

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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SafeArea(
              top: false,
              child: SizedBox(
                height: 76,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _NavSlot(
                          item: items[i],
                          selected: items[i].tabIndex == currentIndex,
                          accent: a,
                          onTap: () {
                            final item = items[i];
                            if (item.onTap != null) {
                              item.onTap!();
                              return;
                            }
                            final tabIndex = item.tabIndex;
                            if (tabIndex != null) onTap(tabIndex);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final ReliefNavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _NavSlot({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (item.prominent) {
      return _ProminentNavSlot(item: item, accent: accent, onTap: onTap);
    }

    final fg = selected ? accent : AppColors.bottomNavInactive;

    Widget icon = Icon(
      selected ? item.activeIcon : item.icon,
      size: 21,
      color: fg,
    );

    if (item.badgeCount > 0) {
      icon = Badge(
        label: Text(
          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.bottomNavBadge,
        child: icon,
      );
    }

    return InkWell(
      onTap: onTap,
      splashColor: accent.withValues(alpha: 0.10),
      highlightColor: AppColors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 25, child: Center(child: icon)),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              letterSpacing: 0.4,
              color: fg,
            ),
            child: Text(
              item.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 5),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 18 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProminentNavSlot extends StatelessWidget {
  final ReliefNavItem item;
  final Color accent;
  final VoidCallback onTap;

  const _ProminentNavSlot({
    required this.item,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppSurfaces.inkOn(accent);

    return InkWell(
      onTap: onTap,
      splashColor: accent.withValues(alpha: 0.10),
      highlightColor: AppColors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: const Offset(0, -11),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppSurfaces.dome(accent),
                    border: Border.all(
                      color: AppColors.bottomNavBackground,
                      width: 4,
                    ),
                    boxShadow: AppSurfaces.glowOnly(accent, strength: 0.8),
                  ),
                  child: Icon(item.activeIcon, color: ink, size: 24),
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
                        color: AppColors.bottomNavBadge,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.bottomNavBackground,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          style: TextStyle(
                            color: AppColors.gamesOnAccent,
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
            offset: const Offset(0, -7),
            child: Column(
              children: [
                Text(
                  item.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
