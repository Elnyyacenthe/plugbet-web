// ============================================================
// FANTASY MODULE – Fiche Joueur
// Stats saison, historique points, prochains matchs FDR
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../models/fpl_models.dart';
import '../providers/fpl_provider.dart';
import '../services/fpl_service.dart';

class FantasyPlayerScreen extends StatefulWidget {
  final int elementId;
  const FantasyPlayerScreen({super.key, required this.elementId});

  @override
  State<FantasyPlayerScreen> createState() => _FantasyPlayerScreenState();
}

class _FantasyPlayerScreenState extends State<FantasyPlayerScreen> {
  FplElementSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await FplService.instance.fetchElementSummary(widget.elementId);
    if (mounted) setState(() { _summary = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final fpl = context.read<FplProvider>();
    final el = fpl.bootstrap?.elementById(widget.elementId);
    final team = el != null ? fpl.bootstrap?.teamById(el.teamId) : null;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(el?.webName ?? 'Joueur'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: el == null
          ? Center(child: CircularProgressIndicator(color: AppColors.neonGreen))
          : Container(
              decoration: BoxDecoration(gradient: AppColors.bgGradient),
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: AppColors.neonGreen))
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(el, team),
                          SizedBox(height: 20),
                          _buildStats(el),
                          SizedBox(height: 20),
                          if (_summary != null) ...[
                            _buildHistory(_summary!),
                            SizedBox(height: 20),
                            _buildFixtures(el, _summary!, fpl),
                          ],
                          if (el.news != null && el.news!.isNotEmpty) ...[
                            SizedBox(height: 20),
                            _buildNews(el),
                          ],
                        ],
                      ),
                    ),
            ),
    );
  }

  Widget _buildHeader(FplElement el, FplTeam? team) {
    final posColor = _posColor(el.elementType);
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [posColor.withValues(alpha: 0.15), AppColors.bgCard],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: posColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: posColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: posColor, width: 2),
            ),
            child: Center(
              child: Text(el.positionLabel,
                  style: TextStyle(color: posColor, fontWeight: FontWeight.w900, fontSize: 18)),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${el.firstName} ${el.secondName}',
                    style: TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 4),
                Text(team?.name ?? '',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                SizedBox(height: 8),
                Row(children: [
                  _badge('${el.coinsValue} FCFA', AppColors.neonGreen),
                  SizedBox(width: 8),
                  _badge('${el.selectedByPercent}% sél.', AppColors.neonBlue),
                  if (el.chanceOfPlayingNextRound < 100) ...[
                    SizedBox(width: 8),
                    _badge('${el.chanceOfPlayingNextRound}%', AppColors.neonRed),
                  ],
                ]),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${el.totalPoints}',
                  style: TextStyle(color: AppColors.neonGreen,
                      fontWeight: FontWeight.w900, fontSize: 28)),
              Text('pts total',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats(FplElement el) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Statistiques saison'),
        SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            _statBox('Forme', el.form, AppColors.neonGreen),
            _statBox('Pts/match', el.pointsPerGame, AppColors.neonBlue),
            _statBox('Buts', '${el.goalsScored}', AppColors.neonYellow),
            _statBox('Passes D.', '${el.assists}', AppColors.neonOrange),
            _statBox('CS', '${el.cleanSheets}', AppColors.neonPurple),
            _statBox('Minutes', '${el.minutes}', AppColors.textSecondary),
          ],
        ),
      ],
    );
  }

  Widget _buildHistory(FplElementSummary summary) {
    if (summary.history.isEmpty) return const SizedBox.shrink();
    final last5 = summary.history.reversed.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('5 derniers matchs'),
        SizedBox(height: 12),
        ...last5.map((h) => Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Text('GW${h.round}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                SizedBox(width: 12),
                Expanded(child: Text('vs ${h.opponentShortTitle}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
                if (h.goals > 0) _miniStat('⚽', '${h.goals}', AppColors.neonYellow),
                if (h.assists > 0) _miniStat('🅰', '${h.assists}', AppColors.neonBlue),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (h.totalPoints >= 6 ? AppColors.neonGreen : AppColors.textMuted)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${h.totalPoints} pts',
                      style: TextStyle(
                        color: h.totalPoints >= 6 ? AppColors.neonGreen : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      )),
                ),
              ]),
            )),
      ],
    );
  }

  Widget _buildFixtures(FplElement el, FplElementSummary summary, FplProvider fpl) {
    if (summary.fixtures.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Prochains matchs'),
        SizedBox(height: 12),
        Row(
          children: summary.fixtures.take(5).map((f) {
            final opp = fpl.bootstrap?.teams
                .where((t) => t.id == (f.isHome ? f.teamA : f.teamH))
                .firstOrNull;
            final color = _fdrColor(f.difficulty);
            return Expanded(
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 3),
                padding: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Column(children: [
                  Text(opp?.shortName ?? '?',
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                  Text(f.isHome ? 'H' : 'A',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
                ]),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNews(FplElement el) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.neonRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: AppColors.neonRed, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(el.news!,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────

  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15));

  Widget _badge(String t, Color c) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _statBox(String label, String value, Color color) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
          SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ]),
      );

  Widget _miniStat(String icon, String val, Color c) => Padding(
        padding: EdgeInsets.only(right: 6),
        child: Text('$icon $val', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Color _posColor(int type) {
    switch (type) {
      case 1: return AppColors.neonYellow;
      case 2: return AppColors.neonBlue;
      case 3: return AppColors.neonGreen;
      case 4: return AppColors.neonOrange;
      default: return AppColors.textSecondary;
    }
  }

  Color _fdrColor(int d) {
    switch (d) {
      case 1: return AppColors.neonGreen;
      case 2: return const Color(0xFF66BB6A);
      case 3: return AppColors.neonYellow;
      case 4: return AppColors.neonOrange;
      case 5: return AppColors.neonRed;
      default: return AppColors.textMuted;
    }
  }
}
