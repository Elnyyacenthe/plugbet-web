// ============================================================
// BettingScreen — Onglet "Paris" (anciennement Match)
// ============================================================
// 2 sections : "En direct" (avec polling 10s) puis "Aujourd'hui".
// Bouton "Parier" -> bottom sheet "Bientot disponible" Phase 1.
//
// Phase 2 (StatPal Pro) : remplacer le snackbar 'soon' par une
// vraie navigation vers MatchDetailScreen + ticket de pari.
//
// Etats geres : loading initial, error, empty (aucun match), data.
// Pull-to-refresh : refetch live + today simultanement.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';
import '../widgets/betting_match_card.dart';

class BettingScreen extends StatefulWidget {
  const BettingScreen({super.key});

  @override
  State<BettingScreen> createState() => _BettingScreenState();
}

class _BettingScreenState extends State<BettingScreen>
    with WidgetsBindingObserver {
  final _svc = StatpalService.instance;

  List<BettingMatch> _live = const [];
  List<BettingMatch> _today = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  static const _pollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialLoad();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLive();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
    }
  }

  Future<void> _initialLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _svc.getLiveMatches(),
        _svc.getTodayMatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _live = results[0];
        _today = results[1];
        _loading = false;
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshLive());
  }

  Future<void> _refreshLive() async {
    try {
      final live = await _svc.getLiveMatches();
      if (!mounted) return;
      setState(() => _live = live);
    } catch (_) {/* silencieux : on garde l'ancien snapshot */}
  }

  Future<void> _refreshAll() async {
    try {
      final results = await Future.wait([
        _svc.getLiveMatches(),
        _svc.getTodayMatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _live = results[0];
        _today = results[1];
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _onBet(BettingMatch m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 18),
          Icon(Icons.bolt, size: 42, color: AppColors.neonYellow),
          const SizedBox(height: 12),
          Text('Bientôt disponible',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 8),
          Text(
            'Les paris sportifs arrivent prochainement. '
            'Tu pourras parier sur ${m.homeName} vs ${m.awayName} '
            'dès la mise en ligne des cotes officielles.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('OK',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.neonGreen),
      );
    }
    if (_error != null && _live.isEmpty && _today.isEmpty) {
      return _errorView();
    }
    return RefreshIndicator(
      color: AppColors.neonGreen,
      backgroundColor: AppColors.bgCard,
      onRefresh: _refreshAll,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _header()),
        if (_live.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionTitle('En direct', _live.length)),
          SliverList.builder(
            itemCount: _live.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child:
                  BettingMatchCard(match: _live[i], onBet: () => _onBet(_live[i])),
            ),
          ),
        ],
        if (_today.isNotEmpty) ...[
          SliverToBoxAdapter(
              child: _sectionTitle("Aujourd'hui", _today.length)),
          SliverList.builder(
            itemCount: _today.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: BettingMatchCard(
                  match: _today[i], onBet: () => _onBet(_today[i])),
            ),
          ),
        ],
        if (_live.isEmpty && _today.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _emptyView()),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ]),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(children: [
        Icon(Icons.bolt, color: AppColors.neonYellow, size: 26),
        const SizedBox(width: 8),
        Text('Paris',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            )),
        const Spacer(),
        if (_live.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neonRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.neonRed.withValues(alpha: 0.4), width: 0.6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                    color: AppColors.neonRed, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('${_live.length} live',
                  style: TextStyle(
                    color: AppColors.neonRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  )),
            ]),
          ),
      ]),
    );
  }

  Widget _sectionTitle(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(children: [
        Text(label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$count',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              )),
        ),
      ]),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.sports_soccer, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Aucun match disponible',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 6),
          Text('Reviens plus tard pour voir les matchs du jour.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, size: 56, color: AppColors.neonRed),
          const SizedBox(height: 12),
          Text('Erreur de chargement',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 6),
          Text(_error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initialLoad,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reessayer',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
  }
}
