// ============================================================
// FANTASY MODULE – Écran Transferts
// Liste joueurs filtrables + add/remove avec budget
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../models/fpl_models.dart';
import '../providers/fpl_provider.dart';
import '../services/fantasy_service.dart';
import '../widgets/fpl_player_card.dart';
import 'fantasy_player_screen.dart';

class FantasyTransfersScreen extends StatefulWidget {
  const FantasyTransfersScreen({super.key});

  @override
  State<FantasyTransfersScreen> createState() => _FantasyTransfersScreenState();
}

class _FantasyTransfersScreenState extends State<FantasyTransfersScreen> {
  int _posFilter = 0;
  String _search = '';
  String _sortBy = 'form';
  final _searchCtrl = TextEditingController();

  Map<String, dynamic>? _myTeam;
  Set<int> _myElementIds = {};
  bool _teamLoaded = false;

  static const _posLabels = ['Tous', 'GK', 'DEF', 'MID', 'ATT'];

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeam() async {
    final team = await FantasyService.instance.getMyTeam();
    if (team == null) {
      if (mounted) setState(() => _teamLoaded = true);
      return;
    }
    final picks = await FantasyService.instance.getPicks(team['id'] as String);
    if (mounted) {
      setState(() {
        _myTeam = team;
        _myElementIds = picks.map((p) => p['element_id'] as int).toSet();
        _teamLoaded = true;
      });
    }
  }

  List<FplElement> _filter(List<FplElement> all) {
    var list = all.where((e) {
      if (_posFilter > 0 && e.elementType != _posFilter) return false;
      if (_search.isNotEmpty &&
          !e.webName.toLowerCase().contains(_search.toLowerCase()) &&
          !e.secondName.toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    switch (_sortBy) {
      case 'form':
        list.sort((a, b) => double.parse(b.form).compareTo(double.parse(a.form)));
      case 'cost':
        list.sort((a, b) => b.nowCost.compareTo(a.nowCost));
      case 'pts':
        list.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
      case 'ownership':
        list.sort((a, b) => double.parse(b.selectedByPercent)
            .compareTo(double.parse(a.selectedByPercent)));
    }
    return list.take(50).toList();
  }

  Future<void> _addPlayer(FplElement el) async {
    final team = _myTeam;
    if (team == null) {
      _showSnack('Créez d\'abord une équipe Fantasy.', Colors.orange);
      return;
    }
    final budget = team['budget'] as int? ?? 0;
    if (el.coinsValue > budget) {
      _showSnack(
          'Budget insuffisant (${el.coinsValue} FCFA requis, $budget dispo).',
          Colors.red);
      return;
    }
    if (_myElementIds.length >= 15) {
      _showSnack('Équipe complète — retirez un joueur d\'abord.', Colors.orange);
      return;
    }
    try {
      await FantasyService.instance.addPlayer(
        teamId: team['id'] as String,
        elementId: el.id,
        position: _myElementIds.length + 1,
        coinsPrice: el.coinsValue,
        clubTeamId: el.teamId,
      );
      setState(() {
        _myElementIds.add(el.id);
        _myTeam = Map.from(team)..['budget'] = budget - el.coinsValue;
      });
      _showSnack('${el.webName} ajouté !', AppColors.neonGreen);
    } on FantasyException catch (e) {
      _showSnack(e.message, Colors.red);
    }
  }

  Future<void> _removePlayer(FplElement el) async {
    final team = _myTeam;
    if (team == null) return;
    final budget = team['budget'] as int? ?? 0;
    try {
      await FantasyService.instance.removePlayer(
        teamId: team['id'] as String,
        elementId: el.id,
        coinsRefund: el.coinsValue,
      );
      setState(() {
        _myElementIds.remove(el.id);
        _myTeam = Map.from(team)..['budget'] = budget + el.coinsValue;
      });
      _showSnack(
          '${el.webName} retiré · ${el.coinsValue} FCFA remboursés.',
          AppColors.neonOrange);
    } on FantasyException catch (e) {
      _showSnack(e.message, Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(AppLocalizations.of(context)!.fantasyTransfersTitle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _myElementIds.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: _myElementIds.length >= 11
                  ? AppColors.neonGreen
                  : AppColors.neonOrange,
              icon: Icon(Icons.check, color: Colors.black),
              label: Text(
                _myElementIds.length >= 15
                    ? 'Équipe complète · Valider'
                    : '${_myElementIds.length}/15 joueurs',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w800),
              ),
              onPressed: () => Navigator.pop(context, true),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Consumer<FplProvider>(
        builder: (context, fpl, _) {
          if (fpl.bootstrap == null) {
            return Center(
                child: CircularProgressIndicator(color: AppColors.neonGreen));
          }

          final filtered = _filter(fpl.bootstrap!.elements);
          final budget = _myTeam?['budget'] as int? ?? 0;
          final pickCount = _myElementIds.length;

          return Container(
            decoration: BoxDecoration(gradient: AppColors.bgGradient),
            child: Column(
              children: [
                // ── Budget + compteur ──
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: AppColors.bgBlueNight,
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          color: AppColors.neonGreen, size: 16),
                      SizedBox(width: 6),
                      Text('${AppLocalizations.of(context)!.fantasyBudget}: $budget FCFA',
                          style: TextStyle(
                              color: AppColors.neonGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      const Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (pickCount >= 15
                                  ? AppColors.neonGreen
                                  : AppColors.neonOrange)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$pickCount/15 joueurs',
                            style: TextStyle(
                              color: pickCount >= 15
                                  ? AppColors.neonGreen
                                  : AppColors.neonOrange,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    ],
                  ),
                ),

                // ── Recherche ──
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un joueur...',
                      hintStyle:
                          TextStyle(color: AppColors.textMuted),
                      prefixIcon:
                          Icon(Icons.search, color: AppColors.textMuted),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: AppColors.textMuted),
                              onPressed: () => setState(() {
                                _search = '';
                                _searchCtrl.clear();
                              }),
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.bgCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                // ── Filtre position ──
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: List.generate(_posLabels.length, (i) {
                      final active = _posFilter == i;
                      return GestureDetector(
                        onTap: () => setState(() => _posFilter = i),
                        child: Container(
                          margin: EdgeInsets.only(right: 8),
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.neonGreen.withValues(alpha: 0.2)
                                : AppColors.bgCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: active
                                    ? AppColors.neonGreen
                                    : AppColors.divider),
                          ),
                          child: Text(_posLabels[i],
                              style: TextStyle(
                                  color: active
                                      ? AppColors.neonGreen
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ),
                      );
                    }),
                  ),
                ),

                SizedBox(height: 8),

                // ── Tri ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('Trier: ',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      ...[
                        ('form', 'Forme'),
                        ('pts', 'Pts'),
                        ('cost', 'Prix'),
                        ('ownership', 'Sél.'),
                      ].map((s) {
                        final active = _sortBy == s.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _sortBy = s.$1),
                          child: Container(
                            margin: EdgeInsets.only(right: 6),
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.neonOrange.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: active
                                      ? AppColors.neonOrange
                                      : AppColors.divider),
                            ),
                            child: Text(s.$2,
                                style: TextStyle(
                                    color: active
                                        ? AppColors.neonOrange
                                        : AppColors.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                SizedBox(height: 8),

                // ── Liste joueurs ──
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final el = filtered[i];
                      final inTeam = _myElementIds.contains(el.id);
                      final canAfford = el.coinsValue <= budget;

                      return FplPlayerCard(
                        player: el,
                        team: fpl.bootstrap?.teamById(el.teamId),
                        showForm: true,
                        showOwnership: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  FantasyPlayerScreen(elementId: el.id)),
                        ),
                        actionWidget: _teamLoaded
                            ? _buildActionBtn(el, inTeam, canAfford)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionBtn(FplElement el, bool inTeam, bool canAfford) {
    if (inTeam) {
      return GestureDetector(
        onTap: () => _removePlayer(el),
        child: Container(
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.neonRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppColors.neonRed.withValues(alpha: 0.5)),
          ),
          child: Icon(Icons.remove, color: AppColors.neonRed, size: 18),
        ),
      );
    }
    return GestureDetector(
      onTap: canAfford ? () => _addPlayer(el) : null,
      child: Container(
        padding: EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: canAfford
              ? AppColors.neonGreen.withValues(alpha: 0.15)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: canAfford
                  ? AppColors.neonGreen.withValues(alpha: 0.5)
                  : AppColors.divider),
        ),
        child: Icon(Icons.add,
            color:
                canAfford ? AppColors.neonGreen : AppColors.textMuted,
            size: 18),
      ),
    );
  }
}
