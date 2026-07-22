// ============================================================
// Plugbet – PromoCarouselBanner Widget
// Carousel interactif haut de gamme pour les promotions actives
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:math' as math;

import '../../../theme/app_theme.dart';
import '../../../theme/app_surfaces.dart' show AppRadius;
import '../../../theme/app_icons.dart';
import '../../../models/promo_item.dart';
import '../../../providers/promo_provider.dart';
import '../promo_detail_screen.dart';

class PromoCarouselBanner extends StatefulWidget {
  final Function(PromoItem)? onTap;

  const PromoCarouselBanner({super.key, this.onTap});

  @override
  State<PromoCarouselBanner> createState() => _PromoCarouselBannerState();
}

class _PromoCarouselBannerState extends State<PromoCarouselBanner> {
  late final PageController _pageController;
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  bool _isUserInteracting = false;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, viewportFraction: 0.93);
    _startAutoScroll();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _stopAutoScroll();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted || _isUserInteracting) return;
      final provider = context.read<PromoProvider>();
      final itemsCount = provider.activePromotions.length;
      if (itemsCount <= 1) return;

      final nextPage = (_currentPage + 1) % itemsCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _onInteractionStarted() {
    if (!_isUserInteracting) {
      setState(() {
        _isUserInteracting = true;
      });
      _stopAutoScroll();
    }
  }

  void _onInteractionEnded() {
    if (_isUserInteracting) {
      setState(() {
        _isUserInteracting = false;
      });
      // Attendre un peu avant de relancer pour éviter un saut brusque
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isUserInteracting) {
          _startAutoScroll();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PromoProvider>();

    if (provider.isLoading) {
      return _buildSkeletonShimmer(context);
    }

    final items = provider.activePromotions;

    if (items.isEmpty) {
      return _buildEmptyState(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(constraints.maxHeight, 350.0);
        return SizedBox(
          height: height,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Carousel (PageView)
                    Listener(
                      onPointerDown: (_) => _onInteractionStarted(),
                      onPointerUp: (_) => _onInteractionEnded(),
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: items.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentPage = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isHovered = _hoveredIndex == index;

                          return AnimatedScale(
                            scale: _currentPage == index ? (isHovered ? 1.02 : 1.0) : 0.92,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutBack,
                            child: GestureDetector(
                              onTapDown: (_) => setState(() => _hoveredIndex = index),
                              onTapCancel: () => setState(() => _hoveredIndex = null),
                              onTapUp: (_) => setState(() => _hoveredIndex = null),
                              onTap: () {
                                if (widget.onTap != null) {
                                  widget.onTap!(item);
                                } else {
                                  // Action par défaut : ouvrir le détail de CETTE promo
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PromoDetailScreen(promoId: item.id),
                                    ),
                                  );
                                }
                              },
                              child: _buildSlideCard(context, item),
                            ),
                          );
                        },
                      ),
                    ),

                    // Bouton Gauche (Glassmorphic)
                    if (items.length > 1)
                      Positioned(
                        left: 20,
                        child: _buildGlassNavigationButton(
                          icon: Icons.chevron_left_rounded,
                          onPressed: () {
                            _onInteractionStarted();
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                            );
                            _onInteractionEnded();
                          },
                        ),
                      ),

                    // Bouton Droite (Glassmorphic)
                    if (items.length > 1)
                      Positioned(
                        right: 20,
                        child: _buildGlassNavigationButton(
                          icon: Icons.chevron_right_rounded,
                          onPressed: () {
                            _onInteractionStarted();
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                            );
                            _onInteractionEnded();
                          },
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Indicateurs (dots) cliquables
              if (items.length > 1) _buildPageIndicators(items.length),
            ],
          ),
        );
      },
    );
  }

  // ── Bouton de navigation Glassmorphic ────────────────────────
  Widget _buildGlassNavigationButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipOval(
        child: Material(
          color: Colors.white.withValues(alpha: 0.08),
          child: InkWell(
            splashColor: AppColors.primary.withValues(alpha: 0.2),
            onTap: onPressed,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Fiche d'une promo (affiche paysage plein cadre) ─────────
  Widget _buildSlideCard(BuildContext context, PromoItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Couleur néon d'accent (cadre / ombre) selon le titre.
    Color neonAccent = AppColors.neonPurple;
    if (item.title.contains('GOLD') || item.title.contains('JAUNE')) {
      neonAccent = AppColors.neonYellow;
    } else if (item.title.contains('IPHONE') || item.title.contains('RED')) {
      neonAccent = AppColors.neonRed;
    } else if (item.title.contains('VIP') || item.title.contains('BLUE')) {
      neonAccent = AppColors.neonBlue;
    }

    // L'affiche paysage couvre toute la carte (repli portrait puis icône).
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: neonAccent.withValues(alpha: isDark ? 0.35 : 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: neonAccent.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.brLg,
        child: Image.asset(
          item.bannerImageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => Image.asset(
            item.imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.bgCard,
              alignment: Alignment.center,
              child: Icon(AppIcons.gift, size: 48, color: neonAccent),
            ),
          ),
        ),
      ),
    );
  }

  // ── Indicateurs de page (dots cliquables) ────────────────────
  Widget _buildPageIndicators(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = _currentPage == index;
        return GestureDetector(
          onTap: () {
            _onInteractionStarted();
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
            );
            _onInteractionEnded();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }

  // ── Skeleton Shimmer (loading state) ─────────────────────────
  Widget _buildSkeletonShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        height: 330,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F1B2D) : Colors.white,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: AppColors.divider, width: 1.5),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 24,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 180,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 110,
                  height: 25,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ──────────────────────────────────────────────
  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 300,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: AppColors.divider,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.gift,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Aucune promotion active',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Revenez plus tard pour de nouveaux gains !',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dessin d'arrière-plan de la carte ─────────────────────────
