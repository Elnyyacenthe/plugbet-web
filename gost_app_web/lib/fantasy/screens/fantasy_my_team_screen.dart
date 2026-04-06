// ============================================================
// FANTASY MODULE – Gestion Mon Équipe
// Formation · Tactiques · Remplaçants · Captain · VC
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../providers/fpl_provider.dart';
import '../services/fantasy_service.dart';
import '../widgets/fantasy_inapp_pitch.dart';

// ─── Formations disponibles ────────────────────────────────
class Formation {
  final String name;
  final List<int> lines;
  final String label;
  const Formation(this.name, this.lines, this.label);
  int get defCount => lines[0];
  int get midCount => lines.length == 3 ? lines[1] : lines[1] + lines[2];
  int get fwdCount => lines.last;
}

const kFormations = [
  Formation('4-4-2',   [4, 4, 2],   'Classique'),
  Formation('4-3-3',   [4, 3, 3],   'Offensif'),
  Formation('3-5-2',   [3, 5, 2],   'Milieu fort'),
  Formation('3-4-3',   [3, 4, 3],   'Ultra offensif'),
  Formation('5-3-2',   [5, 3, 2],   'Défensif'),
  Formation('5-4-1',   [5, 4, 1],   'Ultra défensif'),
  Formation('4-5-1',   [4, 5, 1],   'Milieu dense'),
  Formation('4-2-3-1', [4, 2, 3, 1], 'Moderne'),
  Formation('4-1-4-1', [4, 1, 4, 1], 'Double rideau'),
  Formation('3-4-1-2', [3, 4, 1, 2], 'Meneur de jeu'),
];

Formation formationByName(String name) =>
    kFormations.firstWhere((f) => f.name == name, orElse: () => kFormations[0]);

// ─── Options tactiques ─────────────────────────────────────
class TacticOption {
  final String id;
  final String label;
  final IconData icon;
  const TacticOption(this.id, this.label, this.icon);
}

const kPlayStyles = [
  TacticOption('possession',    'Possession',      Icons.rotate_right),
  TacticOption('counter',       'Contre-attaque',  Icons.flash_on),
  TacticOption('direct',        'Jeu direct',      Icons.arrow_upward),
  TacticOption('balanced',      'Équilibré',       Icons.balance),
  TacticOption('tiki_taka',     'Tiki-Taka',       Icons.bubble_chart),
];

const kMentalities = [
  TacticOption('ultra_def',  'Ultra Défensif',  Icons.shield),
  TacticOption('defensive',  'Défensif',        Icons.security),
  TacticOption('balanced',   'Équilibré',       Icons.drag_handle),
  TacticOption('attacking',  'Offensif',        Icons.sports_soccer),
  TacticOption('ultra_att',  'Ultra Offensif',  Icons.local_fire_department),
];

const kPressings = [
  TacticOption('low',     'Bloc bas',          Icons.download),
  TacticOption('medium',  'Pressing moyen',    Icons.horizontal_rule),
  TacticOption('high',    'Pressing haut',     Icons.upload),
  TacticOption('gegen',   'Gegenpressing',     Icons.speed),
];

const kTempos = [
  TacticOption('slow',    'Lent / Patient',    Icons.hourglass_top),
  TacticOption('normal',  'Normal',            Icons.timer),
  TacticOption('fast',    'Rapide / Direct',   Icons.bolt),
];

const kWidths = [
  TacticOption('narrow',  'Étroit',   Icons.compress),
  TacticOption('normal',  'Normal',   Icons.open_in_full),
  TacticOption('wide',    'Large',    Icons.unfold_more),
];

// ─── Screen ────────────────────────────────────────────────

class FantasyMyTeamScreen extends StatefulWidget {
  final Map<String, dynamic> team;
  final List<Map<String, dynamic>> picks;

  const FantasyMyTeamScreen({
    super.key,
    required this.team,
    required this.picks,
  });

  @override
  State<FantasyMyTeamScreen> createState() => _FantasyMyTeamScreenState();
}

class _FantasyMyTeamScreenState extends State<FantasyMyTeamScreen>
    with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _picks;
  late Formation _formation;
  bool _saving = false;

  // Tactiques
  late String _playStyle;
  late String _mentality;
  late String _pressing;
  late String _tempo;
  late String _width;

  // Ordre remplaçants (bench_order: 1,2,3,4)
  late List<Map<String, dynamic>> _benchOrder;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _picks = widget.picks.map((p) => Map<String, dynamic>.from(p)).toList();
    for (final p in _picks) {
      p['is_starter'] ??= (p['position'] as int? ?? 0) <= 11;
    }
    _formation = formationByName(
        widget.team['formation'] as String? ?? '4-4-2');

    // Charger tactiques depuis team data (ou défauts)
    final tactics = widget.team['tactics'] as Map<String, dynamic>? ?? {};
    _playStyle = tactics['play_style'] as String? ?? 'balanced';
    _mentality = tactics['mentality'] as String? ?? 'balanced';
    _pressing  = tactics['pressing'] as String? ?? 'medium';
    _tempo     = tactics['tempo'] as String? ?? 'normal';
    _width     = tactics['width'] as String? ?? 'normal';

    _rebuildBenchOrder();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _rebuildBenchOrder() {
    _benchOrder = _picks
        .where((p) => p['is_starter'] != true)
        .toList()
      ..sort((a, b) =>
          (a['bench_order'] as int? ?? 99)
              .compareTo(b['bench_order'] as int? ?? 99));
    for (int i = 0; i < _benchOrder.length; i++) {
      _benchOrder[i]['bench_order'] = i + 1;
    }
  }

  // ── Validation : juste 11 starters requis ──────────────
  bool _isValidFormation() {
    final starters = _picks.where((p) => p['is_starter'] == true).toList();
    return starters.length == 11;
  }

  int _outOfPositionCount() {
    final fpl = context.read<FplProvider>();
    final starters = _picks.where((p) => p['is_starter'] == true).toList();
    // Trier par type de position pour simuler la répartition
    starters.sort((a, b) {
      final ea = fpl.bootstrap?.elementById(a['element_id'] as int);
      final eb = fpl.bootstrap?.elementById(b['element_id'] as int);
      return (ea?.elementType ?? 0).compareTo(eb?.elementType ?? 0);
    });
    final parts = _formation.name.split('-').map((s) => int.tryParse(s) ?? 0).toList();
    final lineSizes = [1, ...parts];
    final totalLines = lineSizes.length;
    int outCount = 0;
    int cursor = 0;
    for (int i = 0; i < totalLines; i++) {
      final size = lineSizes[i];
      final end = (cursor + size).clamp(0, starters.length);
      final expectedType = FantasyInAppPitch.expectedPosType(i, totalLines);
      for (int j = cursor; j < end; j++) {
        final el = fpl.bootstrap?.elementById(starters[j]['element_id'] as int);
        if (el != null && el.elementType != expectedType) outCount++;
      }
      cursor = end;
    }
    return outCount;
  }

  String _formationStatus() {
    final starters = _picks.where((p) => p['is_starter'] == true).toList();
    if (starters.length != 11) {
      return '${_formation.name} · ${starters.length}/11 titulaires';
    }
    final outCount = _outOfPositionCount();
    if (outCount == 0) return '${_formation.name} · Formation parfaite';
    return '${_formation.name} · $outCount joueur${outCount > 1 ? 's' : ''} hors-position';
  }

  // ── Sélecteur de formation ────────────────────────────────
  void _pickFormation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text('Choisir la formation',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ),
              ...kFormations.map((f) {
                final selected = f.name == _formation.name;
                return ListTile(
                  leading: Container(
                    width: 50, height: 32,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.neonGreen.withValues(alpha: 0.2)
                          : AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected ? AppColors.neonGreen : AppColors.divider),
                    ),
                    child: Center(
                      child: Text(f.name,
                          style: TextStyle(
                              color: selected ? AppColors.neonGreen : AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  title: Text(f.label,
                      style: TextStyle(
                          color: selected ? AppColors.neonGreen : AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '1 GK · ${f.defCount} DEF · ${f.midCount} MID · ${f.fwdCount} FWD',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: AppColors.neonGreen, size: 20)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _formation = f);
                  },
                );
              }),
              SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ── Swap starters / bench ─────────────────────────────────
  void _toggleStarter(Map<String, dynamic> pick) {
    final isStarter = pick['is_starter'] == true;
    final starterCount = _picks.where((p) => p['is_starter'] == true).length;
    if (isStarter) {
      if (starterCount <= 11) _swapWithBench(pick);
    } else {
      if (starterCount >= 11) {
        _showSwapDialog(pick);
      } else {
        setState(() {
          pick['is_starter'] = true;
          _rebuildBenchOrder();
        });
      }
    }
  }

  void _swapWithBench(Map<String, dynamic> starter) {
    // Tous les remplaçants sont proposés (pas de filtre par position)
    final benchers = _picks
        .where((p) => p['is_starter'] == false)
        .toList();
    if (benchers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Aucun remplaçant disponible.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    _showPickerSheet('Choisir le remplaçant', benchers, (b) {
      setState(() {
        starter['is_starter'] = false;
        b['is_starter'] = true;
        _rebuildBenchOrder();
      });
    });
  }

  void _showSwapDialog(Map<String, dynamic> bencher) {
    // Tous les titulaires sont proposés pour le swap
    final starters = _picks
        .where((p) => p['is_starter'] == true)
        .toList();
    if (starters.isEmpty) {
      setState(() {
        bencher['is_starter'] = true;
        _rebuildBenchOrder();
      });
      return;
    }
    _showPickerSheet('Qui mettre au banc ?', starters, (s) {
      setState(() {
        s['is_starter'] = false;
        bencher['is_starter'] = true;
        _rebuildBenchOrder();
      });
    });
  }

  void _showPickerSheet(String title, List<Map<String, dynamic>> items,
      void Function(Map<String, dynamic>) onPick) {
    final fpl = context.read<FplProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(title,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
              ...items.map((p) {
                final el = fpl.bootstrap?.elementById(p['element_id'] as int);
                if (el == null) return const SizedBox.shrink();
                return ListTile(
                  leading: _posIcon(el.elementType),
                  title: Text(el.webName,
                      style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text('${el.coinsValue} coins · ${el.totalPoints} pts',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onPick(p);
                  },
                );
              }),
              SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ── Sauvegarde complète ───────────────────────────────────
  Future<void> _saveAll() async {
    if (!_isValidFormation()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Il faut exactement 11 titulaires pour sauvegarder.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _saving = true);
    final teamId = widget.team['id'] as String;
    try {
      await FantasyService.instance.saveLineup(
        teamId: teamId,
        picks: _picks,
      );
      await FantasyService.instance.saveFormation(teamId, _formation.name);
      await FantasyService.instance.saveTactics(
        teamId: teamId,
        playStyle: _playStyle,
        mentality: _mentality,
        pressing: _pressing,
        tempo: _tempo,
        width: _width,
      );
      await FantasyService.instance.saveBenchOrder(
        teamId: teamId,
        benchPicks: _benchOrder,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_formation.name} · Tactiques sauvegardées !'),
          backgroundColor: AppColors.neonGreen,
        ));
        Navigator.pop(context, _picks);
      }
    } on FantasyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final fpl = context.watch<FplProvider>();
    final valid = _isValidFormation();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text('Coach · Mon Équipe'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_saving)
            Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.neonGreen)),
            )
          else
            TextButton.icon(
              onPressed: valid ? _saveAll : null,
              icon: Icon(Icons.save,
                  size: 16,
                  color: valid ? AppColors.neonGreen : AppColors.textMuted),
              label: Text('Sauver',
                  style: TextStyle(
                      color: valid ? AppColors.neonGreen : AppColors.textMuted,
                      fontWeight: FontWeight.w700)),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.neonGreen,
          labelColor: AppColors.neonGreen,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'COMPO', icon: Icon(Icons.sports_soccer, size: 16)),
            Tab(text: 'TACTIQUE', icon: Icon(Icons.psychology, size: 16)),
            Tab(text: 'BANC', icon: Icon(Icons.swap_vert, size: 16)),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildCompoTab(fpl, valid),
            _buildTacticsTab(),
            _buildBenchTab(fpl),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 1 : COMPOSITION
  // ═══════════════════════════════════════════════════════════
  Widget _buildCompoTab(FplProvider fpl, bool valid) {
    return Column(
      children: [
        // Sélecteur formation
        GestureDetector(
          onTap: _pickFormation,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.bgBlueNight,
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.neonGreen.withValues(alpha: 0.3),
                      AppColors.neonGreen.withValues(alpha: 0.1),
                    ]),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_soccer, size: 14, color: AppColors.neonGreen),
                      SizedBox(width: 6),
                      Text(_formation.name,
                          style: TextStyle(
                              color: AppColors.neonGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(_formation.label,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ),
                Icon(Icons.swap_horiz, size: 18, color: AppColors.neonGreen),
                SizedBox(width: 4),
                Text('Changer',
                    style: TextStyle(
                        color: AppColors.neonGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        // Status bar
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: AppColors.bgBlueNight.withValues(alpha: 0.5),
          child: Builder(builder: (_) {
            final outCount = valid ? _outOfPositionCount() : 0;
            final perfect = valid && outCount == 0;
            final statusColor = !valid
                ? AppColors.neonOrange
                : outCount > 0
                    ? AppColors.neonOrange
                    : AppColors.neonGreen;
            return Row(
              children: [
                Icon(perfect ? Icons.check_circle : Icons.info_outline,
                    color: statusColor, size: 14),
                SizedBox(width: 8),
                Expanded(
                  child: Text(_formationStatus(),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                Text('Tap = permuter',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
              ],
            );
          }),
        ),
        // Pitch
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: fpl.bootstrap == null
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.neonGreen))
                : FantasyInAppPitch(
                    picks: _picks,
                    bootstrap: fpl.bootstrap!,
                    formation: _formation.name,
                    compact: false,
                    onPlayerTap: (el, pick) {
                      HapticFeedback.lightImpact();
                      _toggleStarter(pick);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 2 : TACTIQUES
  // ═══════════════════════════════════════════════════════════
  Widget _buildTacticsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tacticSection('Style de jeu', Icons.sports, kPlayStyles, _playStyle,
              (v) => setState(() => _playStyle = v)),
          SizedBox(height: 16),
          _tacticSection('Mentalité', Icons.psychology, kMentalities, _mentality,
              (v) => setState(() => _mentality = v)),
          SizedBox(height: 16),
          _tacticSection('Pressing', Icons.compress, kPressings, _pressing,
              (v) => setState(() => _pressing = v)),
          SizedBox(height: 16),
          _tacticSection('Tempo', Icons.speed, kTempos, _tempo,
              (v) => setState(() => _tempo = v)),
          SizedBox(height: 16),
          _tacticSection('Largeur', Icons.open_in_full, kWidths, _width,
              (v) => setState(() => _width = v)),
          SizedBox(height: 24),

          // Résumé tactique
          _tacticSummary(),

          SizedBox(height: 24),

          // ── Chips ──
          _buildChipsSection(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CHIPS SECTION
  // ═══════════════════════════════════════════════════════════

  List<String> _chipsUsed = [];
  bool _chipsLoaded = false;

  Future<void> _loadChips() async {
    if (_chipsLoaded || widget.team['id'] == null) return;
    try {
      final used = await FantasyService.instance
          .getChipsUsed(widget.team['id'] as String);
      if (mounted) setState(() { _chipsUsed = used; _chipsLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _chipsLoaded = true);
    }
  }

  Widget _buildChipsSection() {
    if (!_chipsLoaded) {
      _loadChips();
      return Center(
          child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(color: AppColors.neonGreen),
      ));
    }

    const chips = [
      ('wildcard', 'Wildcard', 'Transferts illimités sans pénalité ce GW', Icons.all_inclusive, Color(0xFFE91E63)),
      ('bench_boost', 'Bench Boost', 'Points des remplaçants comptent ce GW', Icons.airline_seat_recline_extra, Color(0xFF2196F3)),
      ('triple_captain', 'Triple Captain', 'Le capitaine rapporte ×3 ce GW', Icons.star, Color(0xFFFF9800)),
      ('free_hit', 'Free Hit', 'Équipe temporaire pour 1 GW, revient après', Icons.flash_on, Color(0xFF9C27B0)),
    ];

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.neonYellow),
              SizedBox(width: 8),
              Text('CHIPS',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          SizedBox(height: 4),
          Text('1 seul chip actif par GW. Chaque chip ne peut être utilisé qu\'une fois.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          SizedBox(height: 12),
          ...chips.map((c) {
            final used = _chipsUsed.contains(c.$1);
            return Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: used ? null : () => _activateChip(c.$1, c.$2),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: used
                        ? AppColors.bgElevated.withValues(alpha: 0.5)
                        : c.$5.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: used
                          ? AppColors.divider.withValues(alpha: 0.3)
                          : c.$5.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: used
                              ? AppColors.bgCard
                              : c.$5.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(c.$4,
                            color: used ? AppColors.textMuted : c.$5,
                            size: 18),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.$2,
                                style: TextStyle(
                                    color: used
                                        ? AppColors.textMuted
                                        : AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    decoration: used
                                        ? TextDecoration.lineThrough
                                        : null)),
                            SizedBox(height: 2),
                            Text(c.$3,
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10)),
                          ],
                        ),
                      ),
                      if (used)
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.textMuted.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('UTILISÉ',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        )
                      else
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: c.$5.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.$5.withValues(alpha: 0.5)),
                          ),
                          child: Text('ACTIVER',
                              style: TextStyle(
                                  color: c.$5,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _activateChip(String chipId, String chipName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Activer $chipName ?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(
            'Ce chip ne peut être utilisé qu\'une seule fois dans toute la saison. '
            'Êtes-vous sûr de vouloir l\'activer pour ce GW ?',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Activer',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await FantasyService.instance.activateChip(
        teamId: widget.team['id'] as String,
        chipName: chipId,
      );
      setState(() => _chipsUsed.add(chipId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$chipName activé !'),
          backgroundColor: AppColors.neonGreen,
        ));
      }
    } on FantasyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      }
    }
  }

  Widget _tacticSection(String title, IconData titleIcon,
      List<TacticOption> options, String current, ValueChanged<String> onChanged) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, size: 16, color: AppColors.neonGreen),
              SizedBox(width: 8),
              Text(title.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final selected = opt.id == current;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(opt.id);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.neonGreen.withValues(alpha: 0.2)
                        : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppColors.neonGreen
                          : AppColors.divider.withValues(alpha: 0.5),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(opt.icon,
                          size: 14,
                          color: selected
                              ? AppColors.neonGreen
                              : AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text(opt.label,
                          style: TextStyle(
                              color: selected
                                  ? AppColors.neonGreen
                                  : AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _tacticSummary() {
    String findLabel(List<TacticOption> list, String id) =>
        list.firstWhere((o) => o.id == id, orElse: () => list.first).label;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.neonGreen.withValues(alpha: 0.1),
          AppColors.neonGreen.withValues(alpha: 0.03),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize, size: 16, color: AppColors.neonGreen),
              SizedBox(width: 8),
              Text('RÉSUMÉ TACTIQUE',
                  style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          SizedBox(height: 12),
          _summaryRow('Formation', _formation.name),
          _summaryRow('Style', findLabel(kPlayStyles, _playStyle)),
          _summaryRow('Mentalité', findLabel(kMentalities, _mentality)),
          _summaryRow('Pressing', findLabel(kPressings, _pressing)),
          _summaryRow('Tempo', findLabel(kTempos, _tempo)),
          _summaryRow('Largeur', findLabel(kWidths, _width)),
        ],
      ),
    );
  }

  Widget _summaryRow(String key, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(key,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 3 : ORDRE DES REMPLAÇANTS
  // ═══════════════════════════════════════════════════════════
  Widget _buildBenchTab(FplProvider fpl) {
    if (fpl.bootstrap == null) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen));
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(14),
          color: AppColors.bgBlueNight,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: AppColors.neonOrange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Définissez l\'ordre de priorité des remplaçants. '
                  'Si un titulaire ne joue pas, le remplaçant n°1 entre en premier.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _benchOrder.isEmpty
              ? Center(
                  child: Text('Aucun remplaçant',
                      style: TextStyle(color: AppColors.textMuted)),
                )
              : ReorderableListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _benchOrder.length,
                  onReorder: (oldIdx, newIdx) {
                    setState(() {
                      if (newIdx > oldIdx) newIdx--;
                      final item = _benchOrder.removeAt(oldIdx);
                      _benchOrder.insert(newIdx, item);
                      for (int i = 0; i < _benchOrder.length; i++) {
                        _benchOrder[i]['bench_order'] = i + 1;
                      }
                    });
                  },
                  itemBuilder: (ctx, i) {
                    final pick = _benchOrder[i];
                    final el = fpl.bootstrap!
                        .elementById(pick['element_id'] as int);
                    if (el == null) {
                      return SizedBox.shrink(key: ValueKey(pick['element_id']));
                    }
                    return _benchCard(i, el, pick);
                  },
                ),
        ),
      ],
    );
  }

  Widget _benchCard(int index, dynamic el, Map<String, dynamic> pick) {
    final posColor = _posColorByType(el.elementType as int);
    final posLabel = el.elementType == 1
        ? 'GK'
        : el.elementType == 2
            ? 'DEF'
            : el.elementType == 3
                ? 'MID'
                : 'FWD';

    return Container(
      key: ValueKey(pick['element_id']),
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Numéro de priorité
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: index == 0
                  ? AppColors.neonGreen.withValues(alpha: 0.2)
                  : AppColors.bgElevated,
              shape: BoxShape.circle,
              border: Border.all(
                  color: index == 0
                      ? AppColors.neonGreen
                      : AppColors.divider),
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: index == 0
                          ? AppColors.neonGreen
                          : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ),
          ),
          SizedBox(width: 12),
          // Position badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: posColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: posColor.withValues(alpha: 0.4)),
            ),
            child: Text(posLabel,
                style: TextStyle(
                    color: posColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800)),
          ),
          SizedBox(width: 10),
          // Nom joueur
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(el.webName as String,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text('${el.coinsValue} coins · ${el.totalPoints} pts',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          // Handle
          Icon(Icons.drag_handle, color: AppColors.textMuted, size: 20),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────
  Color _posColorByType(int t) {
    switch (t) {
      case 1: return AppColors.neonYellow;
      case 2: return AppColors.neonBlue;
      case 3: return AppColors.neonGreen;
      case 4: return AppColors.neonOrange;
      default: return AppColors.textSecondary;
    }
  }

  Widget _posIcon(int type) {
    final color = _posColorByType(type);
    final label =
        type == 1 ? 'GK' : type == 2 ? 'DEF' : type == 3 ? 'MID' : 'FWD';
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Center(
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w800))),
    );
  }
}
