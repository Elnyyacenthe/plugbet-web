// ============================================================
// Plugbet - Ecran des jeux
// Header custom + carousel + recherche + filtres + grille 3 colonnes.
// La navigation de chaque jeu reste portee par les builders existants.
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../providers/wallet_provider.dart';
import '../games/games_catalog.dart';
import '../widgets/game_rules_dialog.dart';
import '../widgets/players_leaderboard.dart';
import '../providers/promo_provider.dart';
import '../models/promo_item.dart';
import 'promotions/promo_detail_screen.dart';

class _FilterOption {
  final String label;
  final IconData icon;
  final GameCategory? tag;

  const _FilterOption({
    required this.label,
    required this.icon,
    required this.tag,
  });
}

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final _searchController = TextEditingController();
  final _carouselController = PageController(viewportFraction: 0.85);
  GameCategory? _selectedTag;
  String _query = '';

  static const _filters = <_FilterOption>[
    _FilterOption(label: 'Tous', icon: Icons.apps_rounded, tag: null),
    _FilterOption(
      label: 'Classiques',
      icon: Icons.extension_rounded,
      tag: GameCategory.classic,
    ),
    _FilterOption(
      label: 'Casino',
      icon: Icons.casino_rounded,
      tag: GameCategory.casino,
    ),
    _FilterOption(
      label: 'Multijoueur',
      icon: Icons.groups_rounded,
      tag: GameCategory.multiplayer,
    ),
    _FilterOption(
      label: 'Arcade',
      icon: Icons.sports_esports_rounded,
      tag: GameCategory.arcade,
    ),
  ];


  @override
  void dispose() {
    _searchController.dispose();
    _carouselController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final games = kGamesCatalog.where((g) => g.matches(_query, _selectedTag)).toList();

    return Scaffold(
      backgroundColor: AppColors.gamesBackground,
      appBar: _GamesHeader(balance: wallet.coins),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 4),
          _PromoCarousel(controller: _carouselController),
          _SearchBar(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          _GameFilters(
            filters: _filters,
            selectedTag: _selectedTag,
            onSelected: (tag) => setState(() => _selectedTag = tag),
          ),
          _GamesSectionHeader(count: games.length),
          if (games.isEmpty)
            const _EmptyGamesState()
          else
            _GamesGrid(
              games: games,
              onOpen: _openGame,
              onRules: _showRules,
            ),
          const SizedBox(height: 18),
          const PlayersLeaderboard(),
        ],
      ),
    );
  }

  void _openGame(GameEntry game) {
    Navigator.push(context, MaterialPageRoute(builder: game.builder));
  }

  void _showRules(GameEntry game) {
    final rules = game.rules;
    if (rules == null) return;
    GameRulesDialog.show(context, rules);
  }
}

class _GamesHeader extends StatelessWidget implements PreferredSizeWidget {
  final int balance;

  const _GamesHeader({required this.balance});

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    final localizedTitle = AppLocalizations.of(context)?.tabGames ?? 'Games';

    return SafeArea(
      bottom: false,
      child: Container(
        height: preferredSize.height,
        color: AppColors.gamesBackground,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  label: localizedTitle,
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.gamesTextPrimary,
                        AppColors.gamesTextPrimary,
                        AppColors.gamesAccent,
                      ],
                      stops: const [0, 0.42, 1],
                    ).createShader(bounds),
                    child: Text(
                      'Games',
                      style: TextStyle(
                        fontSize: 31,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'ARCADE & CASINO',
                  style: TextStyle(
                    color: AppColors.gamesAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: AppColors.gamesSurfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.gamesBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gamesSoftShadow,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.attach_money_rounded,
                    color: AppColors.gamesYellow,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$balance',
                    style: TextStyle(
                      color: AppColors.gamesTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
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
}

class _PromoCarousel extends StatelessWidget {
  final PageController controller;

  const _PromoCarousel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PromoProvider>();
    final promos = provider.promotions;

    if (promos.isEmpty) {
      // En cours de chargement (ou aucune promo) : on reserve la hauteur
      // pour eviter un saut de layout, sans rien afficher d'intrusif.
      return const SizedBox(height: 204);
    }

    return SizedBox(
      height: 204,
      child: PageView.builder(
        controller: controller,
        padEnds: false,
        itemCount: promos.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 16 : 6,
              right: 6,
              top: 2,
              bottom: 10,
            ),
            child: _PromoCard(promo: promos[index]),
          );
        },
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final PromoItem promo;

  const _PromoCard({required this.promo});

  void _open(BuildContext context) {
    // Détail de CETTE promo (avant : ouvrait la page globale des promos).
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PromoDetailScreen(promoId: promo.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.gamesSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gamesBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.gamesCardShadow,
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                promo.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              ),
              // Voile bas pour lisibilite du titre.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0.35, 0.6, 1],
                    ),
                  ),
                ),
              ),
              // Badge "PROMO".
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.gamesAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'PROMO',
                    style: TextStyle(
                      color: AppColors.gamesOnAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              // Titre + CTA en bas.
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            promo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (promo.highlightedReward != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              promo.highlightedReward!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.gamesAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.gamesAccent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Voir',
                            style: TextStyle(
                              color: AppColors.gamesOnAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: AppColors.gamesOnAccent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gamesAccent.withValues(alpha: 0.85),
            AppColors.gamesAccent.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.card_giftcard_rounded,
          size: 56,
          color: AppColors.gamesOnAccent.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.gamesSurfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gamesBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.gamesSoftShadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        cursorColor: AppColors.gamesAccent,
        style: TextStyle(
          color: AppColors.gamesTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.gamesMutedIcon,
            size: 21,
          ),
          hintText: 'Rechercher un jeu...',
          hintStyle: TextStyle(
            color: AppColors.gamesTextSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

class _GameFilters extends StatelessWidget {
  final List<_FilterOption> filters;
  final GameCategory? selectedTag;
  final ValueChanged<GameCategory?> onSelected;

  const _GameFilters({
    required this.filters,
    required this.selectedTag,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final active = filter.tag == selectedTag;
          return _FilterChip(
            option: filter,
            active: active,
            onTap: () => onSelected(filter.tag),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final _FilterOption option;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.option,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.gamesOnAccent : AppColors.gamesTextSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color:
              active ? AppColors.gamesAccent : AppColors.gamesSurfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppColors.gamesAccent : AppColors.gamesBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: active ? AppColors.transparent : AppColors.gamesSoftShadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(option.icon, size: 16, color: fg),
            const SizedBox(width: 7),
            Text(
              option.label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GamesSectionHeader extends StatelessWidget {
  final int count;

  const _GamesSectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final counterText =
        AppColors.isDark ? AppColors.gamesAccent : AppColors.gamesAccentDeep;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 13),
      child: Row(
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: AppColors.gamesOrange,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            'TOUS LES JEUX',
            style: TextStyle(
              color: AppColors.gamesTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gamesAccentSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: counterText,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GamesGrid extends StatelessWidget {
  final List<GameEntry> games;
  final ValueChanged<GameEntry> onOpen;
  final ValueChanged<GameEntry> onRules;

  const _GamesGrid({
    required this.games,
    required this.onOpen,
    required this.onRules,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.88,
      ),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];
        return _GameTile(
          game: game,
          onTap: () => onOpen(game),
          onRules: () => onRules(game),
        );
      },
    );
  }
}

class _GameTile extends StatelessWidget {
  final GameEntry game;
  final VoidCallback onTap;
  final VoidCallback onRules;

  const _GameTile({
    required this.game,
    required this.onTap,
    required this.onRules,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _GameImage(
              asset: game.imageAsset,
              icon: game.icon,
              cacheWidth: 320,
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.gamesImageOverlayClear,
                      AppColors.gamesImageOverlaySoft,
                      AppColors.gamesImageOverlayStrong,
                    ],
                    stops: const [0.35, 0.72, 1],
                  ),
                ),
              ),
            ),
            if (game.hot)
              const Positioned(
                top: 7,
                left: 7,
                child: _HotBadge(),
              ),
            Positioned(
              top: 7,
              right: 7,
              child: GestureDetector(
                onTap: onRules,
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gamesImageControlBg,
                  ),
                  child: Icon(
                    Icons.question_mark_rounded,
                    color: AppColors.gamesImageText,
                    size: 15,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 8,
              bottom: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    game.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.gamesImageText,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.gamesAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${game.onlineCount} en ligne',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.gamesImageTextMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotBadge extends StatelessWidget {
  const _HotBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gamesOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: AppColors.gamesOnAccent,
            size: 10,
          ),
          const SizedBox(width: 2),
          Text(
            'HOT',
            style: TextStyle(
              color: AppColors.gamesOnAccent,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameImage extends StatelessWidget {
  final String asset;
  final IconData icon;
  final int cacheWidth;

  const _GameImage({
    required this.asset,
    required this.icon,
    required this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.gamesImageFallbackStart,
              AppColors.gamesImageFallbackEnd,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 44,
            color: AppColors.gamesImageFallbackIcon,
          ),
        ),
      ),
    );
  }
}

class _EmptyGamesState extends StatelessWidget {
  const _EmptyGamesState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            color: AppColors.gamesMutedIcon,
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            'Aucun jeu trouvé',
            style: TextStyle(
              color: AppColors.gamesTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Essaie une autre recherche ou un autre filtre.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.gamesTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
