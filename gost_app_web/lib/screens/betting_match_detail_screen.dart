// ============================================================
// BettingMatchDetailScreen — Detail match avec tous les marches
// ============================================================
// Affiche pour 1 match :
//   1X2         (3 cotes)
//   Double Chance (3 cotes, calculees depuis 1X2)
//   Over/Under 2.5 (2 cotes)
//   Both Teams To Score (2 cotes)
//   1X2 mi-temps (3 cotes, si dispo)
//   Over/Under 1.5 mi-temps (2 cotes, si dispo)
//
// Interactions :
// - Tap simple sur une cote -> pari simple
// - Long press sur une cote -> ajoute au combine (haptic)
//
// Charge les cotes a l'ouverture (getMatchOdds) si non dispo.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';
import '../services/derived_markets_service.dart';
import '../state/bet_slip_controller.dart';
import '../widgets/bet_slip.dart';
import '../widgets/bet_team_crest.dart';
import '../widgets/team_profile_sheet.dart';
import '../utils/bet_slip_feedback.dart';
import '../utils/market_labels.dart';

class BettingMatchDetailScreen extends StatefulWidget {
  final BettingMatch match;
  const BettingMatchDetailScreen({super.key, required this.match});

  @override
  State<BettingMatchDetailScreen> createState() =>
      _BettingMatchDetailScreenState();
}

class _BettingMatchDetailScreenState extends State<BettingMatchDetailScreen> {
  late BettingMatch _match;
  bool _loadingOdds = false;
  LeagueStanding? _standing;
  bool _loadingStanding = false;

  // Marchés dérivés (moteur Goals Model), chargés en arrière-plan.
  final _derivedService = DerivedMarketsService();
  List<DerivedMarket> _derived = const [];

  @override
  void initState() {
    super.initState();
    _match = widget.match;
    if (_match.odds == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadOdds());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStanding());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDerived());
  }

  Future<void> _loadDerived() async {
    // Marchés dérivés uniquement pré-match (le moteur ne couvre pas le live).
    if (_match.isLive) return;
    final list = await _derivedService.getActive(_match.id);
    if (!mounted || list.isEmpty) return;
    setState(() => _derived = list);
  }

  Future<void> _loadStanding() async {
    final leagueId = _match.leagueId;
    if (leagueId == null || leagueId.isEmpty || leagueId == 'virt') return;
    setState(() => _loadingStanding = true);
    try {
      final s = await StatpalService.instance
          .getLeagueStanding(leagueId, sport: _match.sport);
      if (!mounted) return;
      setState(() {
        _standing = s;
        _loadingStanding = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStanding = false);
    }
  }

  Future<void> _loadOdds() async {
    setState(() => _loadingOdds = true);
    try {
      final odds = await StatpalService.instance.getMatchOdds(
        _match.id,
        isLive: _match.isLive,
        sport: _match.sport,
      );
      if (!mounted) return;
      setState(() {
        if (odds != null) _match = _match.copyWith(odds: odds);
        _loadingOdds = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOdds = false);
    }
  }

  BetSelection _buildSelection(String code, double odds) {
    final o = _match.odds;
    double? line;
    if (code == 'over25' || code == 'under25') {
      line = o?.mainOuLine;
    } else if (code == 'spread_home') {
      line = o?.spreadHomeLine;
    } else if (code == 'spread_away') {
      line = o?.spreadAwayLine;
    }
    return BetSelection(
      matchId: _match.id,
      matchLabel: '${_match.homeName} vs ${_match.awayName}',
      marketCode: code,
      marketLabel: MarketLabels.selectionLabel(
        code,
        _match.sport,
        homeName: _match.homeName,
        awayName: _match.awayName,
        line: line,
      ),
      odds: odds,
      kickoff: _match.startTime,
      isLive: _match.isLive,
    );
  }

  void _onTapOdd(String code, double value) {
    showSingleBetSheet(context, _buildSelection(code, value));
  }

  void _onLongPressOdd(String code, double value) {
    HapticFeedback.mediumImpact();
    final sel = _buildSelection(code, value);
    final r = BetSlipController.instance.toggle(sel);
    BetSlipFeedback.show(context, r, sel);
  }

  // ── Marchés dérivés (Goals Model) ──
  BetSelection _buildDerivedSelection(DerivedMarket dm) {
    return BetSelection(
      matchId: _match.id,
      matchLabel: '${_match.homeName} vs ${_match.awayName}',
      marketCode: dm.code,
      marketLabel: dm.label,
      odds: dm.odds,
      kickoff: _match.startTime,
      isLive: _match.isLive,
      competition: _match.league,
      sportName: _match.sport.name,
      sport: 'football',
      leagueKey: _match.leagueId,
    );
  }

  void _onTapDerived(DerivedMarket dm) {
    showSingleBetSheet(context, _buildDerivedSelection(dm));
  }

  void _longDerived(DerivedMarket dm) {
    HapticFeedback.mediumImpact();
    final s = _buildDerivedSelection(dm);
    final r = BetSlipController.instance.toggle(s);
    BetSlipFeedback.show(context, r, s);
  }

  DerivedMarket? _derivedByCode(String code) {
    for (final m in _derived) {
      if (m.code == code) return m;
    }
    return null;
  }

  List<DerivedMarket> _derivedFamily(String fam) =>
      _derived.where((m) => m.family == fam).toList();

  // ── Total buts : fusion de la ligne native (2.5) + lignes dérivées ──
  List<_TotalsLine> _totalsLines() {
    final o = _match.odds;
    final map = <String, _TotalsLine>{};
    for (final dm in _derived.where((m) => m.isTotal)) {
      final line = dm.totalLine;
      if (line == null) continue;
      final k = line.toStringAsFixed(1);
      final cur = map[k] ?? _TotalsLine(line);
      if (dm.isOver) {
        cur.overOdds = dm.odds;
        cur.overCode = dm.code;
        cur.overDerived = true;
      } else {
        cur.underOdds = dm.odds;
        cur.underCode = dm.code;
        cur.underDerived = true;
      }
      map[k] = cur;
    }
    // La ligne native (cotes bookmaker) est prioritaire sur un dérivé identique.
    if (o != null && (o.over25 != null || o.under25 != null)) {
      final line = o.mainOuLine ?? 2.5;
      final k = line.toStringAsFixed(1);
      final cur = map[k] ?? _TotalsLine(line);
      cur.isMain = true;
      if (o.over25 != null) {
        cur.overOdds = o.over25;
        cur.overCode = 'over25';
        cur.overDerived = false;
      }
      if (o.under25 != null) {
        cur.underOdds = o.under25;
        cur.underCode = 'under25';
        cur.underDerived = false;
      }
      map[k] = cur;
    }
    final list = map.values
        .where((t) => t.overOdds != null || t.underOdds != null)
        .toList()
      ..sort((a, b) => a.line.compareTo(b.line));
    return list;
  }

  void _tapTotals(String code, double odds, bool derived) {
    if (derived) {
      final dm = _derivedByCode(code);
      if (dm != null) _onTapDerived(dm);
    } else {
      _onTapOdd(code, odds);
    }
  }

  void _longTotals(String code, double odds, bool derived) {
    if (derived) {
      final dm = _derivedByCode(code);
      if (dm != null) _longDerived(dm);
    } else {
      _onLongPressOdd(code, odds);
    }
  }

  // ── Cartes dérivées (chaque famille dans sa propre carte, look natif) ──
  Widget _bttsDerivedCard(List<DerivedMarket> btts) {
    final ordered = [
      ...btts.where((m) => m.code == 'btts_yes'),
      ...btts.where((m) => m.code == 'btts_no'),
    ];
    return _goalsCardShell(
      title: 'Les deux équipes marquent',
      subtitle: 'BTTS — Oui / Non',
      child: _derivedGrid(
          ordered, (m) => m.code == 'btts_yes' ? 'Oui' : 'Non',
          cols: 2),
    );
  }

  Widget _resultTotalCard(List<DerivedMarket> rt) {
    const order = [
      'rt_1_o25', 'rt_1_u25', 'rt_x_o25', 'rt_x_u25', 'rt_2_o25', 'rt_2_u25'
    ];
    final byCode = {for (final m in rt) m.code: m};
    final ordered = <DerivedMarket>[
      for (final c in order)
        if (byCode[c] != null) byCode[c]!,
      for (final m in rt)
        if (!order.contains(m.code)) m,
    ];
    return _goalsCardShell(
      title: 'Résultat + Total 2.5',
      subtitle: 'Issue du match combinée au nombre de buts',
      child: _derivedGrid(ordered, _rtLabel, cols: 3),
    );
  }

  Widget _correctScoreCard(List<DerivedMarket> cs) {
    final top = ([...cs]..sort((a, b) => a.odds.compareTo(b.odds))).take(12).toList();
    return _goalsCardShell(
      title: 'Score exact',
      subtitle: 'Scores les plus probables',
      child: _derivedGrid(top, _csLabel, cols: 3),
    );
  }

  Widget _derivedGrid(List<DerivedMarket> items, String Function(DerivedMarket) label,
      {int cols = 3}) {
    final rows = (items.length / cols).ceil();
    return Column(children: [
      for (var r = 0; r < rows; r++) ...[
        if (r > 0) const SizedBox(height: 6),
        Row(children: [
          for (var c = 0; c < cols; c++) ...[
            if (c > 0) const SizedBox(width: 6),
            Expanded(
              child: (r * cols + c) < items.length
                  ? _derivedGridTile(items[r * cols + c],
                      label(items[r * cols + c]))
                  : const SizedBox.shrink(),
            ),
          ],
        ]),
      ],
    ]);
  }

  Widget _derivedGridTile(DerivedMarket dm, String label) {
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (_, __) {
        final sel = BetSlipController.instance.marketFor(_match.id) == dm.code;
        return GestureDetector(
          onTap: () => _onTapDerived(dm),
          onLongPress: () => _longDerived(dm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: sel
                  ? AppColors.primaryInk.withValues(alpha: 0.18)
                  : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel
                    ? AppColors.primaryInk
                    : AppColors.divider.withValues(alpha: 0.4),
                width: sel ? 1.4 : 0.6,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: sel ? AppColors.primaryInk : AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  )),
              const SizedBox(height: 4),
              Text(dm.odds.toStringAsFixed(2),
                  style: TextStyle(
                    color: sel ? AppColors.primaryInk : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  )),
            ]),
          ),
        );
      },
    );
  }

  String _csLabel(DerivedMarket dm) {
    final p = dm.code.split('_');
    return p.length >= 3 ? '${p[1]}-${p[2]}' : dm.label;
  }

  String _rtLabel(DerivedMarket dm) {
    final m = RegExp(r'^rt_([12x])_([ou])(\d+)$').firstMatch(dm.code);
    if (m == null) return dm.label;
    final res = m.group(1) == '1' ? '1' : (m.group(1) == '2' ? '2' : 'N');
    final ou = m.group(2) == 'o' ? '+' : '−';
    final line = (int.parse(m.group(3)!) / 10).toStringAsFixed(1);
    return '$res · $ou$line';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: ReliefAppBar(
        title: _match.league,
        accent: _match.isLive ? AppColors.neonRed : AppColors.primaryInk,
      ),
      body: SafeArea(
        child: Stack(children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _matchHeader(),
              const SizedBox(height: 16),
              if (_loadingOdds)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primaryInk),
                  ),
                )
              else if (_match.odds == null || !_match.odds!.hasAny)
                _noOddsView()
              else
                ..._buildMarkets(),
              if (_standing != null) ...[
                const SizedBox(height: 16),
                _StandingsCard(
                  standing: _standing!,
                  homeTeamId: null,
                  awayTeamId: null,
                  homeName: _match.homeName,
                  awayName: _match.awayName,
                ),
              ] else if (_loadingStanding) ...[
                const SizedBox(height: 16),
                _StandingsLoadingPlaceholder(),
              ],
              const SizedBox(height: 24),
              _legendHint(),
              if (_derived.isNotEmpty) ...[
                const SizedBox(height: 10),
                _derivedDisclaimer(),
              ],
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BetSlipPill(
              onTap: () => showBetSlipSheet(context),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _matchHeader() {
    final isLive = _match.isLive;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive
              ? AppColors.neonRed.withValues(alpha: 0.35)
              : AppColors.divider.withValues(alpha: 0.5),
          width: isLive ? 1 : 0.5,
        ),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (isLive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonRed,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(AppIcons.dot, size: 6, color: Colors.white),
                const SizedBox(width: 3),
                Text("LIVE ${_match.minute ?? 0}'",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    )),
              ]),
            ),
          ] else
            Text('Coup d\'envoi ${_formatTime(_match.startTime)}',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _teamColumn(_match.homeName,
                  logoUrl: _match.homeLogo, teamId: _match.homeTeamId)),
          _scoreOrVs(),
          Expanded(
              child: _teamColumn(_match.awayName,
                  logoUrl: _match.awayLogo, teamId: _match.awayTeamId)),
        ]),
        if (isLive) ...[
          const SizedBox(height: 10),
          Text(
            _statusLabel(_match.minute ?? 0),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _teamColumn(String name, {String? logoUrl, String? teamId}) {
    // Soccer uniquement : tap sur logo -> fiche equipe (endpoint /soccer/teams/{id})
    final tappable =
        teamId != null && teamId.isNotEmpty && _match.sport == Sport.soccer;
    return Column(children: [
      InkWell(
        onTap: tappable
            ? () => showTeamProfileSheet(context, teamId, fallbackName: name)
            : null,
        borderRadius: BorderRadius.circular(28),
        child: BetTeamCrest(
            name: name, logoUrl: logoUrl, sport: _match.sport, size: 56),
      ),
      const SizedBox(height: 8),
      Text(name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          )),
    ]);
  }

  Widget _scoreOrVs() {
    if (_match.isLive && _match.homeScore != null && _match.awayScore != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('${_match.homeScore} — ${_match.awayScore}',
            style: TextStyle(
              color: AppColors.neonYellow,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            )),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('VS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          )),
    );
  }

  /// Construit les sections de marche sport-aware via MarketLabels.
  /// Chaque section affiche : titre, sous-titre, et tiles cliquables.
  /// Les marches non-pertinents pour le sport courant sont automatiquement
  /// masques (BTTS / Mi-temps soccer-only ; Double Chance soccer-only).
  List<Widget> _buildMarkets() {
    final o = _match.odds!;
    final hasDraw = _match.hasDrawMarket;
    final isSoccer = _match.sport == Sport.soccer;
    final widgets = <Widget>[];

    void addSection(String anyCode, List<String> codes, List<double?> values) {
      widgets.add(_marketSectionFor(anyCode, codes, values));
    }

    // ── 1X2 / Moneyline (universel) ──
    if (o.home != null || o.draw != null || o.away != null) {
      addSection(
        'home',
        hasDraw ? ['home', 'draw', 'away'] : ['home', 'away'],
        hasDraw ? [o.home, o.draw, o.away] : [o.home, o.away],
      );
    }

    // ── Double Chance (soccer uniquement, calcule depuis 1X2) ──
    if (hasDraw && o.home != null && o.draw != null && o.away != null) {
      widgets.add(const SizedBox(height: 10));
      addSection(
          'dc_1x', ['dc_1x', 'dc_12', 'dc_x2'], [o.dc1X, o.dc12, o.dcX2]);
    }

    // ── Spread / Handicap (sports sans nul principalement) ──
    if (!isSoccer && (o.spreadHomeOdds != null || o.spreadAwayOdds != null)) {
      widgets.add(const SizedBox(height: 10));
      addSection(
        'spread_home',
        ['spread_home', 'spread_away'],
        [o.spreadHomeOdds, o.spreadAwayOdds],
      );
    }

    // ── Total buts (fusion : ligne native 2.5 + lignes dérivées) ──
    final totalsLines = isSoccer ? _totalsLines() : const <_TotalsLine>[];
    if (totalsLines.length > 1) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(_GoalsTotalsSection(
        lines: totalsLines,
        matchId: _match.id,
        bookmaker: o.ouBookmaker ?? o.bookmaker,
        onTap: _tapTotals,
        onLong: _longTotals,
      ));
    } else if (o.over25 != null || o.under25 != null) {
      widgets.add(const SizedBox(height: 10));
      addSection('over25', ['over25', 'under25'], [o.over25, o.under25]);
    }

    // ── Marches soccer-only ──
    if (isSoccer) {
      // BTTS : natif s'il existe, sinon dérivé (The Odds API ne fournit pas BTTS).
      if (o.bttsYes != null || o.bttsNo != null) {
        widgets.add(const SizedBox(height: 10));
        addSection('btts_yes', ['btts_yes', 'btts_no'], [o.bttsYes, o.bttsNo]);
      } else {
        final btts = _derivedFamily('BTTS');
        if (btts.isNotEmpty) {
          widgets.add(const SizedBox(height: 10));
          widgets.add(_bttsDerivedCard(btts));
        }
      }

      if (o.htHome != null || o.htDraw != null || o.htAway != null) {
        widgets.add(const SizedBox(height: 10));
        addSection(
          'ht_home',
          ['ht_home', 'ht_draw', 'ht_away'],
          [o.htHome, o.htDraw, o.htAway],
        );
      }

      if (o.htOver15 != null || o.htUnder15 != null) {
        widgets.add(const SizedBox(height: 10));
        addSection(
          'ht_over15',
          ['ht_over15', 'ht_under15'],
          [o.htOver15, o.htUnder15],
        );
      }

      // ── Handicap asiatique (soccer only, multi-lines) ──
      if (o.asianHandicap.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_AsianHandicapSection(
          lines: o.asianHandicap,
          homeName: _match.homeName,
          awayName: _match.awayName,
          bookmaker: o.ahBookmaker ?? o.bookmaker,
          matchId: _match.id,
          onTapOdd: _onTapOdd,
          onLongPressOdd: _onLongPressOdd,
        ));
      }

      // ── Handicap européen (dérivé Goals Model, multi-lignes) ──
      final eh = _derivedFamily('Handicap');
      if (eh.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_GoalsHandicapSection(
          markets: eh,
          matchId: _match.id,
          onTap: _onTapDerived,
          onLong: _longDerived,
        ));
      }
    }

    // ── Sports sans nul : Handicap multi-lines (idem soccer) ──
    if (!isSoccer && o.asianHandicap.isNotEmpty) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(_AsianHandicapSection(
        lines: o.asianHandicap,
        homeName: _match.homeName,
        awayName: _match.awayName,
        bookmaker: o.ahBookmaker ?? o.bookmaker,
        matchId: _match.id,
        onTapOdd: _onTapOdd,
        onLongPressOdd: _onLongPressOdd,
      ));
    }

    // ── Marches additionnels generiques (Correct Score, HT/FT, Race, etc.) ──
    for (final extra in o.extraMarkets) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(_ExtraMarketSection(
        market: extra,
        matchId: _match.id,
        matchLabel: '${_match.homeName} vs ${_match.awayName}',
        homeName: _match.homeName,
        awayName: _match.awayName,
        kickoff: _match.startTime,
        isLive: _match.isLive,
      ));
    }

    // ── Marchés dérivés restants (Résultat+Total, Score exact) ──
    if (isSoccer) {
      final rt = _derivedFamily('Résultat + Total');
      if (rt.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_resultTotalCard(rt));
      }
      final cs = _derivedFamily('Score exact');
      if (cs.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_correctScoreCard(cs));
      }
    }

    return widgets;
  }

  Widget _marketSectionFor(
    String firstCode,
    List<String> codes,
    List<double?> values,
  ) {
    assert(codes.length == values.length);
    final o = _match.odds;
    // Ligne pertinente selon le marche
    double? sectionLine;
    if (firstCode == 'over25') {
      sectionLine = o?.mainOuLine;
    } else if (firstCode == 'spread_home') {
      sectionLine = o?.spreadHomeLine;
    }

    // Source bookmaker selon la section (peut differer par marche)
    String? bm;
    if (firstCode == 'home' ||
        firstCode == 'draw' ||
        firstCode == 'away' ||
        firstCode.startsWith('dc_') ||
        firstCode.startsWith('ht_')) {
      bm = o?.mlBookmaker ?? o?.bookmaker;
    } else if (firstCode == 'over25' || firstCode == 'under25') {
      bm = o?.ouBookmaker ?? o?.bookmaker;
    } else if (firstCode == 'spread_home' || firstCode == 'spread_away') {
      bm = o?.spreadBookmaker ?? o?.bookmaker;
    }

    return _marketSection(
      title:
          MarketLabels.sectionTitle(firstCode, _match.sport, line: sectionLine),
      subtitle: MarketLabels.sectionSubtitle(firstCode, _match.sport),
      bookmaker: bm,
      tiles: [
        for (var i = 0; i < codes.length; i++)
          _MarketTile(
            MarketLabels.tileShort(codes[i], _match.sport,
                line: _tileLineFor(codes[i])),
            MarketLabels.tileLong(codes[i], _match.sport,
                homeName: _match.homeName,
                awayName: _match.awayName,
                line: _tileLineFor(codes[i])),
            codes[i],
            values[i],
          ),
      ],
    );
  }

  /// True si on affiche labelLong (nom equipe) sous le bouton.
  /// Cache pour OU + BTTS (deja redondant avec le label court).
  bool _shouldShowTileLong(String code) {
    return code == 'home' ||
        code == 'draw' ||
        code == 'away' ||
        code.startsWith('dc_') ||
        code == 'spread_home' ||
        code == 'spread_away' ||
        code == 'ht_home' ||
        code == 'ht_draw' ||
        code == 'ht_away';
  }

  double? _tileLineFor(String code) {
    final o = _match.odds;
    if (o == null) return null;
    if (code == 'over25' || code == 'under25') return o.mainOuLine;
    if (code == 'spread_home') return o.spreadHomeLine;
    if (code == 'spread_away') return o.spreadAwayLine;
    return null;
  }

  Widget _marketSection({
    required String title,
    required String subtitle,
    required List<_MarketTile> tiles,
    String? bookmaker,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primaryInk,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    )),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
          if (bookmaker != null && bookmaker.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.5),
                    width: 0.5),
              ),
              child: Text(bookmaker,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
            ),
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _buildTile(tiles[i])),
            ],
          ],
        ),
      ]),
    );
  }

  Widget _buildTile(_MarketTile t) {
    final disabled = t.value == null;
    final selected = BetSlipController.instance.marketFor(_match.id) == t.code;
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (context, _) {
        final currentSelected =
            BetSlipController.instance.marketFor(_match.id) == t.code;
        return GestureDetector(
          onTap: disabled ? null : () => _onTapOdd(t.code, t.value!),
          onLongPress:
              disabled ? null : () => _onLongPressOdd(t.code, t.value!),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: disabled
                  ? AppColors.bgElevated.withValues(alpha: 0.4)
                  : (currentSelected || selected)
                      ? AppColors.primaryInk.withValues(alpha: 0.18)
                      : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: disabled
                    ? AppColors.divider.withValues(alpha: 0.3)
                    : (currentSelected || selected)
                        ? AppColors.primaryInk
                        : AppColors.divider.withValues(alpha: 0.4),
                width: (currentSelected || selected) ? 1.4 : 0.6,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: (currentSelected || selected)
                        ? AppColors.primaryInk
                        : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
              // Description (nom equipe pour moneyline/spread,
              // omise pour OU car redondante avec t.label)
              if (_shouldShowTileLong(t.code) && t.labelLong != t.label) ...[
                const SizedBox(height: 2),
                Text(t.labelLong,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (currentSelected || selected)
                          ? AppColors.primaryInk.withValues(alpha: 0.8)
                          : AppColors.textPrimary.withValues(alpha: 0.8),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    )),
              ],
              const SizedBox(height: 6),
              Text(
                disabled ? '-' : t.value!.toStringAsFixed(2),
                style: TextStyle(
                  color: disabled
                      ? AppColors.textMuted
                      : (currentSelected || selected)
                          ? AppColors.primaryInk
                          : AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _noOddsView() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(children: [
        Icon(AppIcons.calendarOff, size: 40, color: AppColors.textMuted),
        const SizedBox(height: 10),
        Text('Cotes indisponibles',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            )),
        const SizedBox(height: 4),
        Text(
          'Les cotes pour ce match ne sont pas encore publiées.\n'
          'Reviens plus tard.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }

  Widget _legendHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(children: [
        Icon(AppIcons.info, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Tape une cote = pari simple.\nMaintiens une cote = ajout au combiné.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _derivedDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(children: [
        Icon(AppIcons.info, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Certaines cotes sont calculées par Plugbet à partir du marché pour '
            'élargir l\'offre. Elles sont validées à la pose et réglées '
            'automatiquement au score final.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ]),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _statusLabel(int m) {
    switch (_match.sport) {
      case Sport.soccer:
        return _statusSoccer(m);
      case Sport.basketball:
        return _statusBasketball(m);
      case Sport.americanFootball:
      case Sport.baseball:
      case Sport.tennis:
      case Sport.iceHockey:
      case Sport.rugby:
      case Sport.handball:
        return 'En direct';
    }
  }

  String _statusSoccer(int m) {
    if (m <= 0) return 'Coup d\'envoi';
    if (m <= 45) return '1ère mi-temps';
    if (m <= 60) return 'Mi-temps';
    if (m <= 90) return '2e mi-temps';
    return 'Prolongations';
  }

  String _statusBasketball(int m) {
    if (m <= 0) return 'Début';
    if (m <= 12) return '1er quart-temps';
    if (m <= 24) return '2e quart-temps';
    if (m <= 36) return '3e quart-temps';
    if (m <= 48) return '4e quart-temps';
    return 'Prolongations';
  }
}

class _MarketTile {
  final String label; // texte court affiche (1, X, 2, +2.5, etc.)
  final String labelLong; // pour le pari
  final String code; // code interne
  final double? value;
  _MarketTile(this.label, this.labelLong, this.code, this.value);
}

// ============================================================
// _StandingsCard — Classement de la ligue (highlight 2 equipes du match)
// ============================================================
class _StandingsCard extends StatelessWidget {
  final LeagueStanding standing;
  final String? homeTeamId;
  final String? awayTeamId;
  final String homeName;
  final String awayName;

  const _StandingsCard({
    required this.standing,
    required this.homeName,
    required this.awayName,
    this.homeTeamId,
    this.awayTeamId,
  });

  bool _isHighlighted(TeamStanding t) {
    // Match par id si dispo, sinon par nom (case-insensitive contains)
    if (homeTeamId != null && t.teamId == homeTeamId) return true;
    if (awayTeamId != null && t.teamId == awayTeamId) return true;
    final n = t.teamName.toLowerCase();
    return n.contains(homeName.toLowerCase()) ||
        n.contains(awayName.toLowerCase()) ||
        homeName.toLowerCase().contains(n) ||
        awayName.toLowerCase().contains(n);
  }

  @override
  Widget build(BuildContext context) {
    final teams = standing.teams;
    if (teams.isEmpty) return const SizedBox.shrink();
    // On affiche : top 5 + les 2 equipes du match si pas dans le top + 5 derniers
    final hl = teams.where(_isHighlighted).toList();
    final shown = <TeamStanding>{
      ...teams.take(5),
      ...hl,
      ...teams.skip(teams.length > 5 ? teams.length - 3 : 0),
    }.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primaryInk,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Classement',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    )),
                const SizedBox(height: 1),
                Text('${standing.leagueName} • ${standing.season}',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _headerRow(),
        const SizedBox(height: 4),
        Container(height: 0.5, color: AppColors.divider.withValues(alpha: 0.5)),
        for (final t in shown) ...[
          if (shown.indexOf(t) > 0 &&
              shown[shown.indexOf(t) - 1].position + 1 != t.position)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Center(
                child: Text('. . .',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 2,
                    )),
              ),
            ),
          _teamRow(t, _isHighlighted(t)),
        ],
      ]),
    );
  }

  Widget _headerRow() {
    final muted = TextStyle(
      color: AppColors.textMuted,
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 24, child: Text('#', style: muted)),
        Expanded(flex: 4, child: Text('EQUIPE', style: muted)),
        Expanded(child: Text('J', style: muted, textAlign: TextAlign.center)),
        Expanded(child: Text('V', style: muted, textAlign: TextAlign.center)),
        Expanded(child: Text('N', style: muted, textAlign: TextAlign.center)),
        Expanded(child: Text('D', style: muted, textAlign: TextAlign.center)),
        Expanded(
            flex: 2,
            child: Text('PTS', style: muted, textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _teamRow(TeamStanding t, bool hl) {
    final color = hl ? AppColors.primaryInk : AppColors.textPrimary;
    final bg = hl ? AppColors.primaryInk.withValues(alpha: 0.10) : null;
    final cell = TextStyle(
      color: hl ? AppColors.primaryInk : AppColors.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
            width: 24,
            child: Text('${t.position}',
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w900))),
        Expanded(
            flex: 4,
            child: Text(t.teamName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700))),
        Expanded(
            child:
                Text('${t.played}', style: cell, textAlign: TextAlign.center)),
        Expanded(
            child: Text('${t.wins}', style: cell, textAlign: TextAlign.center)),
        Expanded(
            child:
                Text('${t.draws}', style: cell, textAlign: TextAlign.center)),
        Expanded(
            child:
                Text('${t.losses}', style: cell, textAlign: TextAlign.center)),
        Expanded(
            flex: 2,
            child: Text('${t.points}',
                style: TextStyle(
                    color: hl ? AppColors.primaryInk : AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900),
                textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _StandingsLoadingPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Center(
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(
              color: AppColors.primaryInk, strokeWidth: 2),
        ),
      ),
    );
  }
}

// ============================================================
// _ExtraMarketSection — Section generique pour ExtraMarket
// ============================================================
// Affiche n'importe quel marche additionnel (Correct Score, HT/FT,
// Odd/Even, Race To X, etc.) en respectant le layout hint (row2 / row3
// / grid / chips). Chaque tile branche directement BetSlipController
// via _placeBet().
//
// Theme : reutilise AppColors + meme look qu'une section standard
// (bandeau vert + sous-titre + tiles).
// ============================================================
class _ExtraMarketSection extends StatelessWidget {
  final ExtraMarket market;
  final String matchId;
  final String matchLabel;
  final String homeName;
  final String awayName;
  final DateTime kickoff;
  final bool isLive;

  const _ExtraMarketSection({
    required this.market,
    required this.matchId,
    required this.matchLabel,
    required this.homeName,
    required this.awayName,
    required this.kickoff,
    required this.isLive,
  });

  /// Traduit les labels EN -> FR + remplace Home/Away par nom equipe.
  String _humanize(String raw) {
    var s = raw.trim();
    // Substitutions courantes EN -> FR
    final subs = <String, String>{
      'Home/Home': '$homeName / $homeName',
      'Home/Away': '$homeName / $awayName',
      'Home/Draw': '$homeName / Nul',
      'Draw/Home': 'Nul / $homeName',
      'Draw/Draw': 'Nul / Nul',
      'Draw/Away': 'Nul / $awayName',
      'Away/Home': '$awayName / $homeName',
      'Away/Draw': '$awayName / Nul',
      'Away/Away': '$awayName / $awayName',
      'Home': homeName,
      'Away': awayName,
      'Draw': 'Nul',
      'Yes': 'Oui',
      'No': 'Non',
      'Over': 'Plus de',
      'Under': 'Moins de',
      '1st Half': '1ere MT',
      '2nd Half': '2e MT',
      'Neither': 'Aucune',
      'Both': 'Les deux',
      'Equal': 'Egalite',
    };
    subs.forEach((en, fr) {
      if (s == en) s = fr;
    });
    return s;
  }

  void _placeBet(BuildContext context, ExtraOdd odd) {
    final sel = BetSelection(
      matchId: matchId,
      matchLabel: matchLabel,
      marketCode: odd.code,
      marketLabel: '${market.displayName} — ${_humanize(odd.name)}',
      odds: odd.value,
      kickoff: kickoff,
      isLive: isLive,
    );
    showSingleBetSheet(context, sel);
  }

  void _toggleCombine(BuildContext context, ExtraOdd odd) {
    HapticFeedback.mediumImpact();
    final sel = BetSelection(
      matchId: matchId,
      matchLabel: matchLabel,
      marketCode: odd.code,
      marketLabel: '${market.displayName} — ${_humanize(odd.name)}',
      odds: odd.value,
      kickoff: kickoff,
      isLive: isLive,
    );
    final r = BetSlipController.instance.toggle(sel);
    BetSlipFeedback.show(context, r, sel);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primaryInk,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(market.displayName,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    )),
                if (market.subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(market.subtitle!,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ],
            ),
          ),
          if (market.bookmaker != null && market.bookmaker!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.5),
                    width: 0.5),
              ),
              child: Text(market.bookmaker!,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
            ),
        ]),
        const SizedBox(height: 12),
        _buildBody(context),
      ]),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (market.layout) {
      case ExtraMarketLayout.row2:
      case ExtraMarketLayout.row3:
        final cnt = market.layout == ExtraMarketLayout.row2 ? 2 : 3;
        final cells = market.odds.take(cnt).toList();
        return Row(children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _tile(context, cells[i])),
          ],
        ]);
      case ExtraMarketLayout.chips:
        return SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: market.odds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) =>
                SizedBox(width: 92, child: _tile(context, market.odds[i])),
          ),
        );
      case ExtraMarketLayout.grid:
        // 3 colonnes pour les grilles (Correct Score, HT/FT, etc.)
        const cols = 3;
        final rows = (market.odds.length / cols).ceil();
        return Column(children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: 6),
            Row(children: [
              for (var c = 0; c < cols; c++) ...[
                if (c > 0) const SizedBox(width: 6),
                Expanded(
                  child: (r * cols + c) < market.odds.length
                      ? _tile(context, market.odds[r * cols + c])
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
          ],
        ]);
    }
  }

  Widget _tile(BuildContext context, ExtraOdd odd) {
    final label = _humanize(odd.name);
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (context, _) {
        final current = BetSlipController.instance.marketFor(matchId);
        final isSel = current == odd.code;
        return GestureDetector(
          onTap: () => _placeBet(context, odd),
          onLongPress: () => _toggleCombine(context, odd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: isSel
                  ? AppColors.primaryInk.withValues(alpha: 0.18)
                  : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSel
                    ? AppColors.primaryInk
                    : AppColors.divider.withValues(alpha: 0.4),
                width: isSel ? 1.4 : 0.6,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSel ? AppColors.primaryInk : AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  )),
              const SizedBox(height: 4),
              Text(odd.value.toStringAsFixed(2),
                  style: TextStyle(
                    color: isSel ? AppColors.primaryInk : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  )),
            ]),
          ),
        );
      },
    );
  }
}

// ============================================================
// _AsianHandicapSection — Section Handicap asiatique (multi-lines)
// ============================================================
// Specifique : 1 marche = N lignes. On affiche un chip-selector des
// lignes disponibles + 2 tiles Home/Away dont les cotes changent selon
// la ligne selectionnee. Initialise sur la 1ere ligne `isMain=true`.
//
// market_code emis vers BetSlip : "ah_home@-1.5" (parse via
// MarketLabels.parseLine cote settlement).
// ============================================================
class _AsianHandicapSection extends StatefulWidget {
  final List<AsianHandicapLine> lines;
  final String homeName;
  final String awayName;
  final String? bookmaker;
  final String matchId;
  final void Function(String code, double value) onTapOdd;
  final void Function(String code, double value) onLongPressOdd;

  const _AsianHandicapSection({
    required this.lines,
    required this.homeName,
    required this.awayName,
    required this.bookmaker,
    required this.matchId,
    required this.onTapOdd,
    required this.onLongPressOdd,
  });

  @override
  State<_AsianHandicapSection> createState() => _AsianHandicapSectionState();
}

class _AsianHandicapSectionState extends State<_AsianHandicapSection> {
  int _selectedIdx = 0;

  String _fmtSigned(double v) {
    if (v == 0) return '0';
    final abs = v.abs();
    final s = abs == abs.roundToDouble()
        ? abs.toInt().toString()
        : abs.toStringAsFixed(1).replaceAll('.', ',');
    return v > 0 ? '+$s' : '-$s';
  }

  String _codeFor(String side, double line) {
    // Encode la ligne home cote settlement : "ah_home@-1.5" (home perd 1.5
    // buts). Pour away on inverse pour stocker la ligne CONTRE laquelle
    // away parie : si home est -1.5, away est +1.5.
    final stored = side == 'ah_home' ? line : -line;
    final s = stored == stored.roundToDouble()
        ? stored.toInt().toString()
        : stored
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
    final prefix = stored > 0 ? '+' : '';
    return '$side@$prefix$s';
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.lines[_selectedIdx];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primaryInk,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Handicap asiatique',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    )),
                const SizedBox(height: 1),
                Text('Handicap virtuel appliqué au score final',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
          if (widget.bookmaker != null && widget.bookmaker!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.5),
                    width: 0.5),
              ),
              child: Text(widget.bookmaker!,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
            ),
        ]),
        const SizedBox(height: 12),
        // ── Chips de lignes ──
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.lines.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final l = widget.lines[i];
              final isSel = i == _selectedIdx;
              return GestureDetector(
                onTap: () => setState(() => _selectedIdx = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.primaryInk.withValues(alpha: 0.18)
                        : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel
                          ? AppColors.primaryInk
                          : AppColors.divider.withValues(alpha: 0.4),
                      width: isSel ? 1.2 : 0.6,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_fmtSigned(l.line),
                        style: TextStyle(
                          color: isSel
                              ? AppColors.primaryInk
                              : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        )),
                    if (l.isMain) ...[
                      const SizedBox(width: 4),
                      Icon(AppIcons.starFilled,
                          size: 10,
                          color: isSel
                              ? AppColors.primaryInk
                              : AppColors.neonYellow),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // ── Tiles Home / Away ──
        Row(children: [
          Expanded(
              child: _ahTile(
            side: 'ah_home',
            team: widget.homeName,
            signedLine: selected.line,
            value: selected.homeOdds,
          )),
          const SizedBox(width: 6),
          Expanded(
              child: _ahTile(
            side: 'ah_away',
            team: widget.awayName,
            signedLine: -selected.line,
            value: selected.awayOdds,
          )),
        ]),
      ]),
    );
  }

  Widget _ahTile({
    required String side,
    required String team,
    required double signedLine,
    required double value,
  }) {
    final code = _codeFor(side, widget.lines[_selectedIdx].line);
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (context, _) {
        final current = BetSlipController.instance.marketFor(widget.matchId);
        // Selection active uniquement si MEME side + MEME line (compare le code complet)
        final isSel = current == code;
        return GestureDetector(
          onTap: () => widget.onTapOdd(code, value),
          onLongPress: () => widget.onLongPressOdd(code, value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isSel
                  ? AppColors.primaryInk.withValues(alpha: 0.18)
                  : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSel
                    ? AppColors.primaryInk
                    : AppColors.divider.withValues(alpha: 0.4),
                width: isSel ? 1.4 : 0.6,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                '${side == 'ah_home' ? '1' : '2'} (${_fmtSigned(signedLine)})',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSel ? AppColors.primaryInk : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(team,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSel
                        ? AppColors.primaryInk.withValues(alpha: 0.8)
                        : AppColors.textPrimary.withValues(alpha: 0.8),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 6),
              Text(value.toStringAsFixed(2),
                  style: TextStyle(
                    color: isSel ? AppColors.primaryInk : AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  )),
            ]),
          ),
        );
      },
    );
  }
}

// ============================================================
// Marchés dérivés (Goals Model) — aides + sections multi-lignes
// ============================================================

/// Carte standard (même look que les sections natives).
Widget _goalsCardShell({
  required String title,
  required String subtitle,
  required Widget child,
  Widget? trailing,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.primaryInk,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  )),
              const SizedBox(height: 1),
              Text(subtitle,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ]),
      const SizedBox(height: 12),
      child,
    ]),
  );
}

/// Badge bookmaker (même look que les sections natives).
Widget _bookieBadge(String name) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
    ),
    child: Text(name,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        )),
  );
}

/// Une ligne de Total buts (native ou dérivée, chaque côté indépendant).
class _TotalsLine {
  final double line;
  bool isMain = false;
  double? overOdds;
  double? underOdds;
  String? overCode;
  String? underCode;
  bool overDerived = false;
  bool underDerived = false;
  _TotalsLine(this.line);
}

// ============================================================
// _GoalsTotalsSection — Total buts multi-lignes (natif 2.5 + dérivés)
// ============================================================
class _GoalsTotalsSection extends StatefulWidget {
  final List<_TotalsLine> lines;
  final String matchId;
  final String? bookmaker;
  final void Function(String code, double odds, bool derived) onTap;
  final void Function(String code, double odds, bool derived) onLong;

  const _GoalsTotalsSection({
    required this.lines,
    required this.matchId,
    required this.bookmaker,
    required this.onTap,
    required this.onLong,
  });

  @override
  State<_GoalsTotalsSection> createState() => _GoalsTotalsSectionState();
}

class _GoalsTotalsSectionState extends State<_GoalsTotalsSection> {
  late int _idx;

  @override
  void initState() {
    super.initState();
    _idx = widget.lines.indexWhere((l) => l.isMain);
    if (_idx < 0) _idx = 0;
  }

  String _fmt(double v) => v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final sel = widget.lines[_idx];
    final Widget? trailing = sel.isMain &&
            widget.bookmaker != null &&
            widget.bookmaker!.isNotEmpty
        ? _bookieBadge(widget.bookmaker!)
        : null;
    return _goalsCardShell(
      title: 'Total buts',
      subtitle: 'Plus / Moins — plusieurs lignes',
      trailing: trailing,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.lines.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final l = widget.lines[i];
              final isSel = i == _idx;
              return GestureDetector(
                onTap: () => setState(() => _idx = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.primaryInk.withValues(alpha: 0.18)
                        : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel
                          ? AppColors.primaryInk
                          : AppColors.divider.withValues(alpha: 0.4),
                      width: isSel ? 1.2 : 0.6,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_fmt(l.line),
                        style: TextStyle(
                          color: isSel
                              ? AppColors.primaryInk
                              : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        )),
                    if (l.isMain) ...[
                      const SizedBox(width: 4),
                      Icon(AppIcons.starFilled,
                          size: 10,
                          color: isSel
                              ? AppColors.primaryInk
                              : AppColors.neonYellow),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _ouTile(sel, over: true)),
          const SizedBox(width: 6),
          Expanded(child: _ouTile(sel, over: false)),
        ]),
      ]),
    );
  }

  Widget _ouTile(_TotalsLine l, {required bool over}) {
    final odds = over ? l.overOdds : l.underOdds;
    final code = over ? l.overCode : l.underCode;
    final derived = over ? l.overDerived : l.underDerived;
    final label = over ? 'Plus de ${_fmt(l.line)}' : 'Moins de ${_fmt(l.line)}';
    final disabled = odds == null || code == null;
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (_, __) {
        final isSel = !disabled &&
            BetSlipController.instance.marketFor(widget.matchId) == code;
        return GestureDetector(
          onTap: disabled ? null : () => widget.onTap(code, odds, derived),
          onLongPress:
              disabled ? null : () => widget.onLong(code, odds, derived),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: disabled
                  ? AppColors.bgElevated.withValues(alpha: 0.4)
                  : isSel
                      ? AppColors.primaryInk.withValues(alpha: 0.18)
                      : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: disabled
                    ? AppColors.divider.withValues(alpha: 0.3)
                    : isSel
                        ? AppColors.primaryInk
                        : AppColors.divider.withValues(alpha: 0.4),
                width: isSel ? 1.4 : 0.6,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSel ? AppColors.primaryInk : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
              const SizedBox(height: 6),
              Text(disabled ? '-' : odds.toStringAsFixed(2),
                  style: TextStyle(
                    color: disabled
                        ? AppColors.textMuted
                        : isSel
                            ? AppColors.primaryInk
                            : AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  )),
            ]),
          ),
        );
      },
    );
  }
}

// ============================================================
// _GoalsHandicapSection — Handicap européen dérivé (multi-lignes, 1/N/2)
// ============================================================
class _GoalsHandicapSection extends StatefulWidget {
  final List<DerivedMarket> markets;
  final String matchId;
  final void Function(DerivedMarket) onTap;
  final void Function(DerivedMarket) onLong;

  const _GoalsHandicapSection({
    required this.markets,
    required this.matchId,
    required this.onTap,
    required this.onLong,
  });

  @override
  State<_GoalsHandicapSection> createState() => _GoalsHandicapSectionState();
}

class _GoalsHandicapSectionState extends State<_GoalsHandicapSection> {
  final Map<int, Map<String, DerivedMarket>> _byHcap = {};
  List<int> _handicaps = const [];
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    final re = RegExp(r'^eh_(home|draw|away)_([mp])(\d+)$');
    for (final m in widget.markets) {
      final g = re.firstMatch(m.code);
      if (g == null) continue;
      final side = g.group(1)!;
      final h = (g.group(2) == 'm' ? -1 : 1) * int.parse(g.group(3)!);
      (_byHcap[h] ??= {})[side] = m;
    }
    _handicaps = _byHcap.keys.toList()..sort();
    // Défaut : handicap le plus proche de 0.
    for (var i = 1; i < _handicaps.length; i++) {
      if (_handicaps[i].abs() < _handicaps[_idx].abs()) _idx = i;
    }
  }

  String _fmtH(int h) => h > 0 ? '+$h' : '$h';

  @override
  Widget build(BuildContext context) {
    if (_handicaps.isEmpty) return const SizedBox.shrink();
    final trio = _byHcap[_handicaps[_idx]]!;
    return _goalsCardShell(
      title: 'Handicap européen',
      subtitle: 'Handicap appliqué au domicile (score final)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _handicaps.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final isSel = i == _idx;
              return GestureDetector(
                onTap: () => setState(() => _idx = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.primaryInk.withValues(alpha: 0.18)
                        : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel
                          ? AppColors.primaryInk
                          : AppColors.divider.withValues(alpha: 0.4),
                      width: isSel ? 1.2 : 0.6,
                    ),
                  ),
                  child: Text('Dom ${_fmtH(_handicaps[i])}',
                      style: TextStyle(
                        color: isSel
                            ? AppColors.primaryInk
                            : AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      )),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _hTile(trio['home'], '1')),
          const SizedBox(width: 6),
          Expanded(child: _hTile(trio['draw'], 'N')),
          const SizedBox(width: 6),
          Expanded(child: _hTile(trio['away'], '2')),
        ]),
      ]),
    );
  }

  Widget _hTile(DerivedMarket? dm, String label) {
    final disabled = dm == null;
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (_, __) {
        final isSel = !disabled &&
            BetSlipController.instance.marketFor(widget.matchId) == dm.code;
        return GestureDetector(
          onTap: disabled ? null : () => widget.onTap(dm),
          onLongPress: disabled ? null : () => widget.onLong(dm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: disabled
                  ? AppColors.bgElevated.withValues(alpha: 0.4)
                  : isSel
                      ? AppColors.primaryInk.withValues(alpha: 0.18)
                      : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: disabled
                    ? AppColors.divider.withValues(alpha: 0.3)
                    : isSel
                        ? AppColors.primaryInk
                        : AppColors.divider.withValues(alpha: 0.4),
                width: isSel ? 1.4 : 0.6,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                    color: isSel ? AppColors.primaryInk : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
              const SizedBox(height: 6),
              Text(disabled ? '-' : dm.odds.toStringAsFixed(2),
                  style: TextStyle(
                    color: disabled
                        ? AppColors.textMuted
                        : isSel
                            ? AppColors.primaryInk
                            : AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  )),
            ]),
          ),
        );
      },
    );
  }
}
