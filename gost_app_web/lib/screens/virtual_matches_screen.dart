// ============================================================
// VirtualMatchesScreen — Liste des matchs virtuels
// ============================================================
// 100% genere client via VirtualMatchService :
// - Match toutes les 15s
// - Duree 30s reelles (90 min virtuelles)
// - Cotes 1X2 calculees depuis les ratings
//
// Reutilise BettingMatchCard via VirtualMatch.toBettingMatch().
// Pari simple / combine identiques aux vrais matchs, mais
// BetSelection.isVirtual=true -> badge violet "VIRT" dans le panier.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_theme.dart';
import '../services/virtual_match_service.dart';
import '../state/bet_slip_controller.dart';
import '../services/statpal_service.dart' show Sport;
import '../widgets/betting_match_card.dart';
import '../widgets/bet_slip.dart';
import '../utils/market_labels.dart';
import '../utils/bet_slip_feedback.dart';

class VirtualMatchesScreen extends StatefulWidget {
  const VirtualMatchesScreen({super.key});

  @override
  State<VirtualMatchesScreen> createState() => _VirtualMatchesScreenState();
}

class _VirtualMatchesScreenState extends State<VirtualMatchesScreen> {
  final _svc = VirtualMatchService.instance;
  Sport _selectedSport = Sport.soccer;

  @override
  void initState() {
    super.initState();
    _svc.start();
  }

  @override
  void dispose() {
    _svc.stop();
    super.dispose();
  }

  BetSelection _buildSelection(VirtualMatch v, String code) {
    final bm = v.toBettingMatch();
    final value = _oddsValue(bm, code);
    return BetSelection(
      matchId: v.id,
      matchLabel: '${v.homeName} vs ${v.awayName}',
      marketCode: code,
      marketLabel: MarketLabels.selectionLabel(
        code, Sport.soccer,
        homeName: v.homeName, awayName: v.awayName,
      ),
      odds: value ?? 1.0,
      kickoff: v.kickoff,
      isLive: v.isLive,
      isVirtual: true,
    );
  }

  double? _oddsValue(dynamic bm, String code) {
    final o = bm.odds;
    if (o == null) return null;
    switch (code) {
      case 'home': return o.home as double?;
      case 'draw': return o.draw as double?;
      case 'away': return o.away as double?;
    }
    return null;
  }

  void _onTapOdd(VirtualMatch v, String code) {
    if (v.state == VirtualState.finished) {
      _toast('Match terminé');
      return;
    }
    showSingleBetSheet(context, _buildSelection(v, code));
  }

  void _onLongPressOdd(VirtualMatch v, String code) {
    if (v.state == VirtualState.finished) return;
    HapticFeedback.mediumImpact();
    final sel = _buildSelection(v, code);
    final r = BetSlipController.instance.toggle(sel);
    BetSlipFeedback.show(context, r, sel);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.bgElevated,
        duration: const Duration(milliseconds: 1200),
        content: Text(msg,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: ReliefAppBar(
        accent: AppColors.neonPurple,
        titleWidget: Row(mainAxisSize: MainAxisSize.min, children: [
          DomeIcon(
              icon: AppIcons.bets, color: AppColors.neonPurple, size: 28),
          const SizedBox(width: 9),
          Text('Matchs Flash',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              )),
        ]),
      ),
      body: SafeArea(
        child: Stack(children: [
          AnimatedBuilder(
            animation: _svc,
            builder: (context, _) {
              final allMatches = _svc.matches;
              final matches = allMatches
                  .where((m) => m.sport == _selectedSport)
                  .toList();
              return Column(children: [
                _sportTabBar(allMatches),
                Expanded(
                  child: matches.isEmpty
                      ? _emptyView()
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: matches.length + 1,
                          itemBuilder: (_, i) {
                            if (i == 0) return _legend(matches);
                            return _virtualCard(matches[i - 1]);
                          },
                        ),
                ),
              ]);
            },
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: BetSlipPill(
              onTap: () => showBetSlipSheet(context),
            ),
          ),
        ]),
      ),
    );
  }

  /// Tab horizontal Football / Basket en haut de l'ecran.
  Widget _sportTabBar(List<VirtualMatch> allMatches) {
    final soccerN = allMatches.where((m) => m.sport == Sport.soccer).length;
    final basketN =
        allMatches.where((m) => m.sport == Sport.basketball).length;
    Widget tab(Sport s, IconData icon, String label, int count) {
      final active = _selectedSport == s;
      final fg = active
          ? AppSurfaces.inkOn(AppColors.neonPurple)
          : AppColors.textMuted;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _selectedSport = s),
          borderRadius: AppRadius.brXs,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: AppRadius.brXs,
              gradient: active
                  ? AppSurfaces.raisedGradient(AppColors.neonPurple)
                  : null,
              boxShadow: active
                  ? AppSurfaces.raised(
                      glow: AppColors.neonPurple, elevation: 0.55)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text('$label · $count',
                    style: TextStyle(
                      color: active ? fg : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: InsetPanel(
        radius: AppRadius.sm,
        padding: const EdgeInsets.all(3),
        baseColor: AppColors.bgDark,
        child: Row(children: [
          tab(Sport.soccer, AppIcons.football, 'Football', soccerN),
          tab(Sport.basketball, AppIcons.basketball, 'Basket', basketN),
        ]),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
              _selectedSport == Sport.basketball
                  ? AppIcons.basketball
                  : AppIcons.football,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Aucun match Flash en cours',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              )),
        ]),
      ),
    );
  }

  Widget _legend(List<VirtualMatch> matches) {
    final live = matches.where((m) => m.isLive).length;
    final upcoming = matches.where((m) => m.state == VirtualState.upcoming).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.neonPurple.withValues(alpha: 0.18),
            AppColors.bgCard,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.neonPurple.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.neonPurple,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('FLASH',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                )),
          ),
          const SizedBox(width: 8),
          Text('Pariez 24/7 · Résultat en 30s',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _stat('$live', 'en cours', AppColors.neonRed),
          const SizedBox(width: 18),
          _stat('$upcoming', 'à venir', AppColors.neonYellow),
        ]),
        const SizedBox(height: 8),
        Text(
          'Tape une cote = pari simple · Maintiens = ajout combiné',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Row(children: [
      Container(
        width: 6, height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          )),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          )),
    ]);
  }

  Widget _virtualCard(VirtualMatch v) {
    final bm = v.toBettingMatch();
    final isFinished = v.state == VirtualState.finished;

    return Stack(children: [
      AnimatedBuilder(
        animation: BetSlipController.instance,
        builder: (context, _) {
          final selectedMarket =
              BetSlipController.instance.marketFor(v.id);
          return BettingMatchCard(
            match: bm,
            selectedMarket: selectedMarket,
            onTapOdds: isFinished ? null : (mk) => _onTapOdd(v, mk),
            onLongPressOdds:
                isFinished ? null : (mk) => _onLongPressOdd(v, mk),
            showMoreHint: false,   // pas d'ecran detail sur virtuel
          );
        },
      ),
      if (isFinished)
        Positioned(
          top: 6, right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: AppColors.divider.withValues(alpha: 0.6),
                  width: 0.5),
            ),
            child: Text('TERMINÉ',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                )),
          ),
        ),
      if (v.state == VirtualState.upcoming) _upcomingOverlay(v),
    ]);
  }

  Widget _upcomingOverlay(VirtualMatch v) {
    final secs = v.kickoff.difference(DateTime.now()).inSeconds;
    return Positioned(
      top: 6, right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.neonYellow.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: AppColors.neonYellow.withValues(alpha: 0.6), width: 0.5),
        ),
        child: Text(
          secs > 0 ? 'Dans ${secs}s' : 'Coup d\'envoi…',
          style: TextStyle(
            color: AppColors.neonYellow,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
