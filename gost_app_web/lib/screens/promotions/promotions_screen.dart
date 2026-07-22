// ============================================================
// Plugbet – PromotionsScreen
// Écran principal listant les promotions actives
// Style néon premium, glassmorphism et micro-animations
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_surfaces.dart';
import '../../theme/app_icons.dart';
import '../../models/promo_item.dart';
import '../../providers/promo_provider.dart';
import 'widgets/promo_carousel_banner.dart';
import 'widgets/gold_outline_text.dart';
import 'promo_detail_screen.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  Timer? _countdownTimer;
  Map<String, String> _remainingTime = {};

  @override
  void initState() {
    super.initState();
    // Animation pour le bouton néon pulsant
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Démarrer le countdown de la page
    _startCountdown();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final provider = context.read<PromoProvider>();
      final gp = provider.grandPrixPromo;
      if (gp != null && gp.endDate != null) {
        final remaining = gp.remainingTime;
        final days = remaining.inDays;
        final hours = remaining.inHours.remainder(24).toString().padLeft(2, '0');
        final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
        final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

        setState(() {
          _remainingTime = {
            'days': '$days',
            'hours': hours,
            'minutes': minutes,
            'seconds': seconds,
          };
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PromoProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primaryInk,
            backgroundColor: isDark ? AppColors.bgCard : Colors.white,
            onRefresh: () => provider.loadPromotions(forceRefresh: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
              children: [
                // Header personnalisé
                _buildHeader(context),
                const SizedBox(height: 16),

                // 1. Carousel des bannières de promotions
                const PromoCarouselBanner(),
                const SizedBox(height: 24),

                // 2. Section "Comment participer"
                _buildHowToSection(context),
                const SizedBox(height: 24),

                // 3. Bannière unique "Grand Prix"
                _buildGrandPrixBanner(context, provider.grandPrixPromo),
                const SizedBox(height: 28),

                // 5. Grid des promotions actives
                _buildGridSection(context, provider),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header custom ───────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      AppColors.textPrimary,
                      AppColors.neonYellow,
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'PROMOTIONS',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                Text(
                  'PARIEZ, JOUEZ ET GAGNEZ DES LOTS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // Icône cadeau scintillante
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.neonPurple.withValues(alpha: 0.15),
              border: Border.all(
                color: AppColors.neonPurple.withValues(alpha: 0.3),
              ),
              boxShadow: AppSurfaces.glowOnly(AppColors.neonPurple, strength: 0.6),
            ),
            child: Icon(
              AppIcons.gift,
              color: AppColors.neonPurple,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section "Comment participer" ────────────────────────────
  Widget _buildHowToSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre accrocheur
          const Text(
            'GAINS & RÉCOMPENSES',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Carte 1: Tickets Promo
              Expanded(
                child: _buildHowToCard(
                  context,
                  icon: AppIcons.receipt,
                  color: AppColors.neonGreen,
                  title: 'Tickets Promo',
                  desc: 'Obtenez 1 ticket de tirage pour chaque tranche de 5000 FCFA misés.',
                  onTap: () => _showHowToDetail(
                    context,
                    'Tickets Promo',
                    'Pour chaque pari sportif ou partie de jeu d\'une valeur minimale de 5 000 FCFA, vous recevez automatiquement un ticket de tombola. Plus vous cumulez de tickets, plus vos chances de remporter le prix sont élevées !',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Carte 2: Cartes de collection
              Expanded(
                child: _buildHowToCard(
                  context,
                  icon: AppIcons.starFilled,
                  color: AppColors.neonOrange,
                  title: 'Collections',
                  desc: 'Collectionnez les badges de jeux pour débloquer des multiplicateurs.',
                  onTap: () => _showHowToDetail(
                    context,
                    'Cartes de collection',
                    'En jouant à nos différents jeux (Ludo, Penalty, etc.), vous pouvez obtenir des cartes de collection rares. Compléter un album vous octroie des multiplicateurs de gains et des bonus directs crédités sur votre wallet !',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowToCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.95, end: 1.0),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brMd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        AppColors.bgCard.withValues(alpha: 0.6),
                        AppColors.bgCardLight.withValues(alpha: 0.4),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.8),
                        const Color(0xFFF2F5FC).withValues(alpha: 0.6),
                      ],
              ),
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: color.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.05),
                  blurRadius: 10,
                  spreadRadius: -2,
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon bombé
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bannière "Grand Prix" ──────────────────────────────────
  Widget _buildGrandPrixBanner(BuildContext context, PromoItem? gp) {
    if (gp == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF070E1A),
            AppColors.bgCardLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: AppColors.neonYellow.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonYellow.withValues(alpha: 0.2),
            blurRadius: 28,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.brLg,
        child: Stack(
          children: [
            // Background grid / decorative glowing lines
            Positioned.fill(
              child: CustomPaint(
                painter: _GrandPrixBgPainter(),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Ligne titre & Trophée stylisé
                  Row(
                    children: [
                      // Trophée en CustomPainter
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CustomPaint(
                          painter: _TrophyPainter(color: AppColors.neonYellow),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.neonRed.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.neonRed.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'ÉVÉNEMENT GRAND PRIX',
                                style: TextStyle(
                                  color: Color(0xFFFF5252),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              gp.title.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Montant en gros chiffres avec ShaderMask dégradé or
                  if (gp.highlightedReward != null)
                    Center(
                      child: GoldOutlineText(
                        text: gp.highlightedReward!,
                        fontSize: 42,
                        outlineWidth: 5,
                      ),
                    ),

                  const SizedBox(height: 6),

                  Center(
                    child: Text(
                      gp.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Countdown
                  if (_remainingTime.isNotEmpty) _buildCountdownSection(context),

                  const SizedBox(height: 20),

                  // Bouton CTA "Participer" néon pulsant
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Center(
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: AppSurfaces.glowOnly(AppColors.neonGreen, strength: 0.9),
                        ),
                        child: ElevatedButton(
                          onPressed: () => _handleParticiper(context, gp),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.neonGreen,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            elevation: 0,
                            side: const BorderSide(
                              color: Colors.white,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            gp.actionLabel ?? 'PARTICIPER MAINTENANT',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Color(0xFFFFB300), size: 16),
          const SizedBox(width: 8),
          Text(
            'FIN DANS : ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            '${_remainingTime['days']}J ${_remainingTime['hours']}H ${_remainingTime['minutes']}M ${_remainingTime['seconds']}S',
            style: const TextStyle(
              color: Color(0xFFFFD54F),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Grid des autres promotions actives ──────────────────────
  Widget _buildGridSection(BuildContext context, PromoProvider provider) {
    if (provider.isLoading) {
      return _buildGridSkeleton(context);
    }

    final otherPromos = provider.activePromotions.where((p) => !p.isGrandPrix).toList();

    if (otherPromos.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOUTES LES PROMOS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: otherPromos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.75,
            ),
            itemBuilder: (context, index) {
              final promo = otherPromos[index];
              return _buildGridCard(context, promo, isDark);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGridCard(BuildContext context, PromoItem promo, bool isDark) {
    Color cardColor = AppColors.neonPurple;
    if (promo.title.contains('GOLD') || promo.title.contains('PS5')) {
      cardColor = AppColors.neonYellow;
    } else if (promo.title.contains('IPHONE')) {
      cardColor = AppColors.neonRed;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.95, end: 1.0),
      duration: const Duration(milliseconds: 350),
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PromoDetailScreen(promoId: promo.id),
            ),
          ),
          borderRadius: AppRadius.brMd,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : Colors.white,
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: cardColor.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Affiche paysage en haut : couvre la largeur de la carte.
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        promo.bannerImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Image.asset(
                          promo.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(
                            color: cardColor.withValues(alpha: 0.12),
                            alignment: Alignment.center,
                            child: Icon(AppIcons.gift, size: 30, color: cardColor),
                          ),
                        ),
                      ),
                      // Ruban "N GAG." en haut a droite
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: cardColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            '${promo.winnersCount} GAG.',
                            style: TextStyle(
                              color: cardColor,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            promo.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              height: 1.3,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: cardColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Grid Skeleton Shimmer ──────────────────────────────────
  Widget _buildGridSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Shimmer.fromColors(
            baseColor: AppColors.shimmerBase,
            highlightColor: AppColors.shimmerHighlight,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.75,
              ),
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.brMd,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Méthodes utilitaires d'action ──────────────────────────
  void _handleParticiper(BuildContext context, PromoItem gp) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.neonGreen,
        content: Text(
          'Félicitations ! Votre participation à la promo "${gp.title}" a été prise en compte.',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
    );
    // Note : pas de pushNamed ici (aucune route nommée enregistrée dans
    // l'app). La confirmation snackbar suffit ; le détail est accessible via
    // la carte de la promo -> PromoDetailScreen.
  }

  void _showHowToDetail(BuildContext context, String title, String detailText) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(
            color: AppColors.divider,
            width: 1,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          detailText,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'FERMER',
              style: TextStyle(
                color: AppColors.primaryInk,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
        ],
      ),
    );
  }
}

// ── Dessin personnalisé du trophée néon ──────────────────────
class _TrophyPainter extends CustomPainter {
  final Color color;

  _TrophyPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Path du trophée
    final path = Path();
    // Coupe du haut
    path.moveTo(w * 0.25, h * 0.2);
    path.lineTo(w * 0.75, h * 0.2);
    path.lineTo(w * 0.7, h * 0.55);
    path.quadraticBezierTo(w * 0.5, h * 0.7, w * 0.3, h * 0.55);
    path.close();

    // Pied
    path.moveTo(w * 0.5, h * 0.68);
    path.lineTo(w * 0.5, h * 0.82);

    // Socle
    path.moveTo(w * 0.3, h * 0.82);
    path.lineTo(w * 0.7, h * 0.82);

    // Anse gauche
    path.moveTo(w * 0.25, h * 0.28);
    path.quadraticBezierTo(w * 0.1, h * 0.32, w * 0.27, h * 0.48);

    // Anse droite
    path.moveTo(w * 0.75, h * 0.28);
    path.quadraticBezierTo(w * 0.9, h * 0.32, w * 0.73, h * 0.48);

    // Dessiner le glow d'abord
    canvas.drawPath(path, glowPaint);
    // Puis la ligne nette
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Dessin d'arrière-plan de la bannière Grand Prix ──────────
class _GrandPrixBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    // Dessiner un dôme de lumière circulaire au centre droit
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.3),
      140,
      paint,
    );

    // Deux lignes géométriques diagonales subtiles
    final linePaint = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(size.width * 0.1, 0),
      Offset(size.width * 0.6, size.height),
      linePaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.2, 0),
      Offset(size.width * 0.7, size.height),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
