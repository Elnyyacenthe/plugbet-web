// ============================================================
// Plugbet – Détail d'un match
// Événements · Statistiques · Compositions
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/football_models.dart';
import '../providers/matches_provider.dart';
import '../providers/favorites_provider.dart';
import '../widgets/score_display.dart';
import '../widgets/team_crest.dart';

class MatchDetailScreen extends StatefulWidget {
  final int matchId;
  const MatchDetailScreen({super.key, required this.matchId});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  MatchDetailData? _detail;
  bool _loadingDetail = true;
  bool _fetchError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() { _loadingDetail = true; _fetchError = false; });
    try {
      final data = await context.read<MatchesProvider>().fetchMatchDetailFull(widget.matchId);
      if (mounted) setState(() { _detail = data; _loadingDetail = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingDetail = false; _fetchError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Consumer<MatchesProvider>(
          builder: (context, provider, _) {
            final match = provider.getMatchById(widget.matchId);
            if (match == null) {
              return Center(
                child: Text(AppLocalizations.of(context)!.matchNotFound,
                    style: TextStyle(color: AppColors.textSecondary)),
              );
            }
            return SafeArea(
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(child: _buildAppBar(match)),
                  SliverToBoxAdapter(child: _buildMatchHeader(match)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(tabController: _tabController),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildEventsTab(match),
                    _buildStatsTab(match),
                    _buildLineupsTab(match),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // APP BAR
  // ────────────────────────────────────────────────────────────
  Widget _buildAppBar(FootballMatch match) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Text(match.competition.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ),
        Consumer<FavoritesProvider>(
          builder: (context, favProvider, _) {
            final isFav = favProvider.isFavorite(match.homeTeam.id) ||
                favProvider.isFavorite(match.awayTeam.id);
            return IconButton(
              icon: Icon(
                isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFav ? AppColors.neonYellow : AppColors.textMuted,
                size: 24,
              ),
              onPressed: () => favProvider.toggleFavorite(match.homeTeam.id),
            );
          },
        ),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────
  // EN-TÊTE MATCH
  // ────────────────────────────────────────────────────────────
  Widget _buildMatchHeader(FootballMatch match) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(children: [
        if (match.matchday != null)
          Text(AppLocalizations.of(context)!.matchMatchday('${match.matchday}'),
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Expanded(
            flex: 3,
            child: Column(children: [
              TeamCrest(team: match.homeTeam, size: 52),
              SizedBox(height: 8),
              Text(match.homeTeam.shortName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Column(children: [
              if (match.status.isUpcoming)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${match.dateTime.hour.toString().padLeft(2, '0')}:${match.dateTime.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        fontSize: 38, fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ScoreDisplay(
                      match: match, isLarge: true, animated: match.status.isLive),
                ),
              SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: MatchStatusBadge(match: match, showMinute: true),
              ),
            ]),
          ),
          Expanded(
            flex: 3,
            child: Column(children: [
              TeamCrest(team: match.awayTeam, size: 52),
              SizedBox(height: 8),
              Text(match.awayTeam.shortName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        if (match.score.homeHalfTime != null)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'MT : ${match.score.homeHalfTime} - ${match.score.awayHalfTime}',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────
  // ONGLET ÉVÉNEMENTS
  // ────────────────────────────────────────────────────────────
  Widget _buildEventsTab(FootballMatch match) {
    if (_loadingDetail) return _loadingWidget();
    if (_fetchError) return _retryWidget();
    final events = _detail?.events ?? [];
    if (events.isEmpty) {
      return _emptyTab(
        icon: Icons.timeline_rounded,
        message: match.status.isUpcoming
            ? 'Les événements seront affichés une fois le match commencé.'
            : 'Aucun événement disponible pour ce match.',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 12),
      itemCount: events.length,
      itemBuilder: (context, i) => _EventTile(
        event: events[i],
        homeTeamName: match.homeTeam.shortName,
        awayTeamName: match.awayTeam.shortName,
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // ONGLET STATISTIQUES
  // ────────────────────────────────────────────────────────────
  Widget _buildStatsTab(FootballMatch match) {
    if (_loadingDetail) return _loadingWidget();
    if (_fetchError) return _retryWidget();

    final stats = _detail?.stats;
    final hasStats = _detail?.hasStats ?? false;

    if (!hasStats) {
      // Afficher au moins le résumé du score
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          _scoreSummaryCard(match),
          SizedBox(height: 16),
          _emptyTabInline(
            icon: Icons.bar_chart_rounded,
            message: 'Statistiques détaillées non disponibles\npour ce match.',
          ),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(children: [
        _scoreSummaryCard(match),
        SizedBox(height: 16),
        _statsCard(match, stats!),
      ]),
    );
  }

  Widget _scoreSummaryCard(FootballMatch match) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _statPill(match.homeTeam.shortName, match.score.homeFullTime?.toString() ?? '-'),
        Column(children: [
          Text(AppLocalizations.of(context)!.matchScore, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          SizedBox(height: 4),
          if (match.score.homeHalfTime != null)
            Text('${AppLocalizations.of(context)!.matchHalfTime} ${match.score.homeHalfTime}-${match.score.awayHalfTime}',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        _statPill(match.awayTeam.shortName, match.score.awayFullTime?.toString() ?? '-'),
      ]),
    );
  }

  Widget _statPill(String label, String value) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]);
  }

  Widget _statsCard(FootballMatch match, MatchStats stats) {
    final rows = <_StatRow>[];
    if (stats.homePossession != null && stats.awayPossession != null) {
      rows.add(_StatRow('Possession',
          '${stats.homePossession}%', '${stats.awayPossession}%',
          stats.homePossession! / 100));
    }
    if (stats.homeShots != null && stats.awayShots != null) {
      final total = (stats.homeShots! + stats.awayShots!);
      rows.add(_StatRow('Tirs', '${stats.homeShots}', '${stats.awayShots}',
          total > 0 ? stats.homeShots! / total : 0.5));
    }
    if (stats.homeShotsOnTarget != null && stats.awayShotsOnTarget != null) {
      final total = (stats.homeShotsOnTarget! + stats.awayShotsOnTarget!);
      rows.add(_StatRow('Tirs cadrés', '${stats.homeShotsOnTarget}', '${stats.awayShotsOnTarget}',
          total > 0 ? stats.homeShotsOnTarget! / total : 0.5));
    }
    if (stats.homeCorners != null && stats.awayCorners != null) {
      final total = (stats.homeCorners! + stats.awayCorners!);
      rows.add(_StatRow('Corners', '${stats.homeCorners}', '${stats.awayCorners}',
          total > 0 ? stats.homeCorners! / total : 0.5));
    }
    if (stats.homeFouls != null && stats.awayFouls != null) {
      final total = (stats.homeFouls! + stats.awayFouls!);
      rows.add(_StatRow('Fautes', '${stats.homeFouls}', '${stats.awayFouls}',
          total > 0 ? stats.homeFouls! / total : 0.5));
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(children: [
        // Header équipes
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(match.homeTeam.shortName,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.neonGreen)),
          Text(match.awayTeam.shortName,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.neonBlue)),
        ]),
        SizedBox(height: 16),
        ...rows.map((r) => _StatRowWidget(row: r)),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────
  // ONGLET COMPOSITIONS
  // ────────────────────────────────────────────────────────────
  Widget _buildLineupsTab(FootballMatch match) {
    if (_loadingDetail) return _loadingWidget();
    if (_fetchError) return _retryWidget();

    final hasLineups = _detail?.hasLineups ?? false;
    if (!hasLineups) {
      return _emptyTab(
        icon: Icons.people_outline_rounded,
        message: match.status.isUpcoming
            ? 'Compositions non disponibles.\nElles apparaissent ~1h avant le coup d\'envoi.'
            : 'Compositions non disponibles pour ce match.',
      );
    }

    final hl = _detail!.homeLineup;
    final al = _detail!.awayLineup;

    return SingleChildScrollView(
      padding: EdgeInsets.all(12),
      child: Column(children: [
        // Formations
        if (hl?.formation != null || al?.formation != null)
          Container(
            margin: EdgeInsets.only(bottom: 12),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider, width: 0.5),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(hl?.formation ?? '?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: AppColors.neonGreen)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('vs',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
              Text(al?.formation ?? '?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: AppColors.neonBlue)),
            ]),
          ),

        // Tableau joueurs côte-à-côte
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _TeamLineupColumn(lineup: hl, color: AppColors.neonGreen,
              teamName: match.homeTeam.shortName)),
          SizedBox(width: 8),
          Expanded(child: _TeamLineupColumn(lineup: al, color: AppColors.neonBlue,
              teamName: match.awayTeam.shortName)),
        ]),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────
  // WIDGETS HELPERS
  // ────────────────────────────────────────────────────────────
  Widget _loadingWidget() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: AppColors.neonGreen, strokeWidth: 2),
        SizedBox(height: 12),
        Text(AppLocalizations.of(context)!.commonLoading, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }

  Widget _retryWidget() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off, size: 40, color: AppColors.textMuted),
        SizedBox(height: 12),
        Text(AppLocalizations.of(context)!.matchCannotLoadData,
            style: TextStyle(color: AppColors.textMuted)),
        SizedBox(height: 16),
        TextButton.icon(
          onPressed: _loadDetail,
          icon: Icon(Icons.refresh, color: AppColors.neonGreen),
          label: Text(AppLocalizations.of(context)!.commonRetry, style: TextStyle(color: AppColors.neonGreen)),
        ),
      ]),
    );
  }

  Widget _emptyTab({required IconData icon, required String message}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.textMuted.withValues(alpha: 0.3)),
          SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        ]),
      ),
    );
  }

  Widget _emptyTabInline({required IconData icon, required String message}) {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 36, color: AppColors.textMuted.withValues(alpha: 0.3)),
        SizedBox(height: 10),
        Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}

// ============================================================
// Tile d'un événement
// ============================================================
class _EventTile extends StatelessWidget {
  final MatchEvent event;
  final String homeTeamName;
  final String awayTeamName;

  const _EventTile({
    required this.event,
    required this.homeTeamName,
    required this.awayTeamName,
  });

  @override
  Widget build(BuildContext context) {
    final isHome = event.isHomeTeam;
    final type = event.eventType;

    IconData icon;
    Color color;
    switch (type) {
      case EventType.goal:
        icon = Icons.sports_soccer; color = AppColors.neonGreen;
      case EventType.ownGoal:
        icon = Icons.sports_soccer; color = AppColors.neonRed;
      case EventType.penalty:
        icon = Icons.sports_soccer; color = AppColors.neonYellow;
      case EventType.yellowCard:
        icon = Icons.square_rounded; color = AppColors.neonYellow;
      case EventType.redCard:
        icon = Icons.square_rounded; color = AppColors.neonRed;
      case EventType.substitution:
        icon = Icons.swap_horiz; color = AppColors.neonBlue;
      case EventType.varDecision:
        icon = Icons.monitor; color = AppColors.neonPurple;
      default:
        icon = Icons.circle; color = AppColors.textMuted;
    }

    final minuteWidget = Container(
      width: 36,
      alignment: Alignment.center,
      child: Text("${event.minute}'",
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
    );

    final iconWidget = Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: color),
    );

    final playerWidget = Column(
      crossAxisAlignment: isHome ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (event.playerName != null && event.playerName!.isNotEmpty)
          Text(event.playerName!,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        if (type == EventType.substitution && event.assistPlayerName != null)
          Text('↓ ${event.assistPlayerName}',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        if ((type == EventType.goal || type == EventType.penalty) &&
            event.assistPlayerName != null && event.assistPlayerName!.isNotEmpty)
          Text('${AppLocalizations.of(context)!.matchAssist}: ${event.assistPlayerName}',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        Text(isHome ? homeTeamName : awayTeamName,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: isHome
          ? Row(children: [
              Expanded(child: playerWidget),
              SizedBox(width: 8),
              iconWidget,
              SizedBox(width: 6),
              minuteWidget,
              SizedBox(width: 6),
              SizedBox(width: iconWidget.constraints?.minWidth ?? 32),
              const Expanded(child: SizedBox()),
            ])
          : Row(children: [
              const Expanded(child: SizedBox()),
              SizedBox(width: iconWidget.constraints?.minWidth ?? 32),
              SizedBox(width: 6),
              minuteWidget,
              SizedBox(width: 6),
              iconWidget,
              SizedBox(width: 8),
              Expanded(child: playerWidget),
            ]),
    );
  }
}

// Données d'une ligne de stat
class _StatRow {
  final String label;
  final String homeVal;
  final String awayVal;
  final double homeRatio; // 0.0 à 1.0
  const _StatRow(this.label, this.homeVal, this.awayVal, this.homeRatio);
}

class _StatRowWidget extends StatelessWidget {
  final _StatRow row;
  const _StatRowWidget({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(row.homeVal,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.neonGreen)),
          Text(row.label,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          Text(row.awayVal,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.neonBlue)),
        ]),
        SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 5,
            child: Row(children: [
              Expanded(
                flex: (row.homeRatio * 100).round(),
                child: Container(color: AppColors.neonGreen),
              ),
              Expanded(
                flex: ((1 - row.homeRatio) * 100).round(),
                child: Container(color: AppColors.neonBlue),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ============================================================
// Colonne lineup d'une équipe
// ============================================================
class _TeamLineupColumn extends StatelessWidget {
  final Lineup? lineup;
  final Color color;
  final String teamName;

  const _TeamLineupColumn({required this.lineup, required this.color, required this.teamName});

  @override
  Widget build(BuildContext context) {
    if (lineup == null) {
      return Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Center(
          child: Text(teamName,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête équipe
        Text(teamName,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        if (lineup!.coach != null) ...[
          SizedBox(height: 2),
          Text('🧑‍💼 ${lineup!.coach}',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        SizedBox(height: 10),

        // Titulaires
        const _LineupSectionHeader('Titulaires'),
        SizedBox(height: 4),
        ...lineup!.startingXI.map((p) => _PlayerRow(player: p, color: color)),

        // Remplaçants
        if (lineup!.substitutes.isNotEmpty) ...[
          SizedBox(height: 10),
          const _LineupSectionHeader('Remplaçants'),
          SizedBox(height: 4),
          ...lineup!.substitutes.map((p) => _PlayerRow(player: p, color: AppColors.textMuted)),
        ],
      ]),
    );
  }
}

class _LineupSectionHeader extends StatelessWidget {
  final String title;
  const _LineupSectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Text(
    title.toUpperCase(),
    style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w700,
        color: AppColors.textMuted, letterSpacing: 1),
  );
}

class _PlayerRow extends StatelessWidget {
  final Player player;
  final Color color;
  const _PlayerRow({required this.player, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        if (player.shirtNumber != null)
          SizedBox(
            width: 20,
            child: Text('${player.shirtNumber}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ),
        Expanded(
          child: Text(player.name,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

// ============================================================
// TabBar persistant
// ============================================================
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  _TabBarDelegate({required this.tabController});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.bgDark,
      child: TabBar(
        controller: tabController,
        indicatorColor: AppColors.neonGreen,
        indicatorWeight: 2.5,
        labelColor: AppColors.neonGreen,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Événements'),
          Tab(text: 'Statistiques'),
          Tab(text: 'Compositions'),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 48;
  @override
  double get minExtent => 48;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}
