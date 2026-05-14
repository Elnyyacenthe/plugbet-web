// ============================================================
// FANTASY MODULE – Écran Ligues
// Créer, rejoindre, classements
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/wallet_provider.dart';
import '../services/fantasy_service.dart';

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '$dd/$mm/${l.year}';
}

class FantasyLeaguesScreen extends StatefulWidget {
  const FantasyLeaguesScreen({super.key});

  @override
  State<FantasyLeaguesScreen> createState() => _FantasyLeaguesScreenState();
}

class _FantasyLeaguesScreenState extends State<FantasyLeaguesScreen> {
  List<Map<String, dynamic>> _myLeagues = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final leagues = await FantasyService.instance.getMyLeagues();
    if (mounted) setState(() { _myLeagues = leagues; _loading = false; });
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: '0');
    bool isPrivate = false;
    DateTime? endDate;
    // Presets de distribution du pot
    const distPresets = <String, List<int>>{
      '🥇 Winner takes all (100%)': [100],
      '🥇🥈 Top 2 (70/30)': [70, 30],
      '🥇🥈🥉 Top 3 (60/30/10)': [60, 30, 10],
      '🥇🥈🥉 Top 3 (50/30/20)': [50, 30, 20],
      '🏆 Top 4 (40/30/20/10)': [40, 30, 20, 10],
    };
    String distKey = '🥇🥈🥉 Top 3 (60/30/10)';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text(AppLocalizations.of(context)!.fantasyCreateLeague,
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Nom de la ligue',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.neonGreen),
                    ),
                  ),
                ),
                SizedBox(height: 14),
                TextField(
                  controller: feeCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Mise d\'entrée (coins)',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    helperText: '0 = ligue gratuite. Sinon, chaque membre paie cette mise et le pot est distribué aux meilleurs (-10% de commission par gain).',
                    helperMaxLines: 3,
                    helperStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    prefixIcon: Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 18),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.neonGreen),
                    ),
                  ),
                ),
                SizedBox(height: 14),
                // Date de fin (OBLIGATOIRE)
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: endDate ?? now.add(const Duration(days: 7)),
                      firstDate: now.add(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365)),
                      builder: (c, child) => Theme(
                        data: Theme.of(c).copyWith(
                          colorScheme: ColorScheme.dark(
                            primary: AppColors.neonGreen,
                            surface: AppColors.bgCard,
                            onPrimary: Colors.black,
                            onSurface: AppColors.textPrimary,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setLocal(() => endDate = DateTime(
                          picked.year, picked.month, picked.day, 23, 59));
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: endDate == null
                              ? Colors.redAccent.withValues(alpha: 0.5)
                              : AppColors.divider),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today,
                          color: endDate == null
                              ? Colors.redAccent
                              : AppColors.neonGreen,
                          size: 18),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          endDate == null
                              ? 'Date de fin (obligatoire) *'
                              : 'Fin : ${_fmtDate(endDate!)}',
                          style: TextStyle(
                              color: endDate == null
                                  ? Colors.redAccent
                                  : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.textMuted),
                    ]),
                  ),
                ),
                SizedBox(height: 14),
                // Sélecteur distribution du pot
                DropdownButtonFormField<String>(
                  initialValue: distKey,
                  isExpanded: true,
                  dropdownColor: AppColors.bgCard,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Répartition du pot',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: Icon(Icons.emoji_events_outlined,
                        color: AppColors.neonOrange, size: 18),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.neonGreen),
                    ),
                  ),
                  items: distPresets.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) => setLocal(() => distKey = v ?? distKey),
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    Switch(
                      value: isPrivate,
                      activeColor: AppColors.neonGreen,
                      onChanged: (v) => setLocal(() => isPrivate = v),
                    ),
                    SizedBox(width: 8),
                    Text(isPrivate ? 'Ligue privée (code)' : 'Ligue publique',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context)!.commonCancel, style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(context)!.gameCreate,
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    if (endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Vous devez choisir une date de fin'),
        backgroundColor: Colors.red));
      return;
    }
    final fee = int.tryParse(feeCtrl.text.trim()) ?? 0;
    // FPL = argent reel : minimum 100 FCFA d'entry fee
    if (fee < 100) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Mise minimum : 100 FCFA (argent reel obligatoire)'),
        backgroundColor: Colors.red));
      return;
    }
    final entryFee = fee;
    // Check solde avant de creer la ligue (l'entry fee est deduite cote serveur)
    final wallet = context.read<WalletProvider>();
    if (wallet.coins < entryFee) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Solde insuffisant : il vous faut $entryFee FCFA'),
        backgroundColor: Colors.red));
      return;
    }
    try {
      await FantasyService.instance.createLeague(
        name: nameCtrl.text.trim().isEmpty ? 'Ma Ligue' : nameCtrl.text.trim(),
        isPrivate: isPrivate,
        entryFee: entryFee,
        prizeDistribution: distPresets[distKey]!,
        endDate: endDate!,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.fantasyLeagueCreated), backgroundColor: AppColors.neonGreen),
        );
      }
    } on FantasyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showJoinDialog() async {
    final codeCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(AppLocalizations.of(context)!.fantasyJoinByCode,
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: AppColors.textPrimary, letterSpacing: 3, fontSize: 18),
          maxLength: 6,
          decoration: InputDecoration(
            hintText: 'XXXXXX',
            hintStyle: TextStyle(color: AppColors.textMuted),
            counterStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.neonBlue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonBlue),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.gameJoin,
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await FantasyService.instance.joinLeagueByCode(codeCtrl.text.trim());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.fantasyLeagueJoined), backgroundColor: AppColors.neonBlue),
        );
      }
    } on FantasyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openStandings(Map<String, dynamic> member) {
    final league = member['fantasy_leagues'] as Map<String, dynamic>?;
    if (league == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LeagueStandingsScreen(league: league),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(AppLocalizations.of(context)!.fantasyMyLeagues),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: _load,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Column(
          children: [
            // ── Boutons créer / rejoindre ──
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _actionBtn(
                      Icons.add_circle_outline,
                      'Créer une ligue',
                      AppColors.neonGreen,
                      _showCreateDialog,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _actionBtn(
                      Icons.vpn_key_outlined,
                      'Rejoindre (code)',
                      AppColors.neonBlue,
                      _showJoinDialog,
                    ),
                  ),
                ],
              ),
            ),

            // ── Liste ligues ──
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.neonGreen))
                  : _myLeagues.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 80),
                          itemCount: _myLeagues.length,
                          separatorBuilder: (_, __) => SizedBox(height: 10),
                          itemBuilder: (_, i) => _buildLeagueTile(_myLeagues[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeagueTile(Map<String, dynamic> member) {
    final league = member['fantasy_leagues'] as Map<String, dynamic>?;
    final name = league?['name'] as String? ?? 'Ligue';
    final isPrivate = league?['is_private'] as bool? ?? false;
    final code = league?['private_code'] as String?;
    final pts = member['total_points'] as int? ?? 0;

    return GestureDetector(
      onTap: () => _openStandings(member),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.neonOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPrivate ? Icons.lock_outline : Icons.public,
                color: AppColors.neonOrange,
                size: 20,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  SizedBox(height: 4),
                  if (isPrivate && code != null)
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(AppLocalizations.of(context)!.gameCodeCopied),
                              duration: Duration(seconds: 2)),
                        );
                      },
                      child: Row(
                        children: [
                          Text('Code: $code',
                              style: TextStyle(
                                  color: AppColors.neonBlue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(width: 4),
                          Icon(Icons.copy, color: AppColors.neonBlue, size: 12),
                        ],
                      ),
                    )
                  else
                    Text(AppLocalizations.of(context)!.fantasyPublicLeague,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$pts',
                    style: TextStyle(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w900,
                        fontSize: 22)),
                Text('pts',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined,
              color: AppColors.textMuted, size: 56),
          SizedBox(height: 16),
          Text(AppLocalizations.of(context)!.fantasyNoLeagues,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(AppLocalizations.of(context)!.fantasyNoLeaguesHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─── Classement d'une ligue ───────────────────────────────

class _LeagueStandingsScreen extends StatefulWidget {
  final Map<String, dynamic> league;

  const _LeagueStandingsScreen({required this.league});

  @override
  State<_LeagueStandingsScreen> createState() => _LeagueStandingsScreenState();
}

class _LeagueStandingsScreenState extends State<_LeagueStandingsScreen> {
  List<Map<String, dynamic>> _standings = [];
  Map<String, dynamic> _league = {};
  bool _loading = true;

  String get _leagueId => _league['id'] as String;
  String get _leagueName => _league['name'] as String? ?? 'Ligue';
  String? get _privateCode => _league['private_code'] as String?;
  String get _status => _league['status'] as String? ?? 'open';
  int get _pot => (_league['pot'] as num?)?.toInt() ?? 0;
  int get _entryFee => (_league['entry_fee'] as num?)?.toInt() ?? 0;
  String? get _creatorId => _league['creator_id'] as String?;
  String? get _winnerId => _league['winner_id'] as String?;

  DateTime? get _endDate {
    final raw = _league['end_date'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  bool get _canClose {
    final ed = _endDate;
    return ed != null && DateTime.now().isAfter(ed);
  }

  List<int> get _distribution {
    final raw = _league['prize_distribution'];
    if (raw is List) return raw.map((e) => (e as num).toInt()).toList();
    return const [60, 30, 10];
  }

  @override
  void initState() {
    super.initState();
    _league = Map<String, dynamic>.from(widget.league);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await FantasyService.instance.getLeagueStandings(_leagueId);
    // Recharger aussi les meta de la ligue (status/pot/winner peuvent avoir change)
    try {
      final fresh = await Supabase.instance.client
          .from('fantasy_leagues')
          .select()
          .eq('id', _leagueId)
          .maybeSingle();
      if (fresh != null) _league = Map<String, dynamic>.from(fresh);
    } catch (_) {}
    if (mounted) setState(() { _standings = s; _loading = false; });
  }

  bool get _isCreator =>
      Supabase.instance.client.auth.currentUser?.id == _creatorId;

  // _confirmAndClose retire : la cloture est AUTOMATIQUE via cron
  // (fantasy_auto_close_stale, toutes les 10 min).
  // Cf. supabase/migrations/security_fix_14_fantasy_auto_close.sql

  Widget _buildHeader() {
    final isFinished = _status == 'finished';
    final dist = _distribution;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isFinished
                ? AppColors.neonOrange.withValues(alpha: 0.4)
                : AppColors.neonGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                isFinished ? Icons.flag_circle : Icons.account_balance_wallet,
                color: isFinished ? AppColors.neonOrange : AppColors.neonYellow,
                size: 20),
            SizedBox(width: 8),
            Text(isFinished ? 'Ligue terminée' : 'Cagnotte',
                style: TextStyle(color: AppColors.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600)),
            Spacer(),
            Text('$_pot',
                style: TextStyle(color: AppColors.neonYellow,
                    fontWeight: FontWeight.w900, fontSize: 22)),
            SizedBox(width: 4),
            Text('coins',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
          if (_entryFee > 0) ...[
            SizedBox(height: 6),
            Text('Mise d\'entrée : $_entryFee coins / membre',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
          SizedBox(height: 6),
          Text('Distribution : ${dist.map((p) => '$p%').join(' / ')}  •  -10% caisse',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          if (_endDate != null) ...[
            SizedBox(height: 6),
            Row(children: [
              Icon(Icons.calendar_today, size: 12, color: AppColors.textMuted),
              SizedBox(width: 4),
              Text(
                isFinished
                    ? 'Terminée le ${_fmtDate(_endDate!)}'
                    : _canClose
                        ? 'Date de fin atteinte (${_fmtDate(_endDate!)})'
                        : 'Clôture possible le ${_fmtDate(_endDate!)}',
                style: TextStyle(
                    color: _canClose && !isFinished
                        ? AppColors.neonGreen
                        : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: _canClose && !isFinished
                        ? FontWeight.w600
                        : FontWeight.normal),
              ),
            ]),
          ],
          if (!isFinished && _endDate != null) ...[
            // FPL specialisee : la cloture est AUTOMATIQUE (cron toutes
            // les 10 min). Aucun bouton n'est affiche, on indique juste
            // quand le payout aura lieu.
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.divider.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Icons.auto_awesome, color: AppColors.neonYellow, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _canClose
                        ? 'Distribution automatique en cours... (le gagnant est crédité sous 10 min)'
                        : 'Distribution automatique le ${_fmtDate(_endDate!)}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(_leagueName),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_privateCode != null)
            IconButton(
              icon: Icon(Icons.copy, color: AppColors.neonBlue),
              tooltip: 'Copier le code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _privateCode!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Code $_privateCode copié !'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: AppColors.neonGreen))
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _standings.isEmpty
                        ? Center(
                            child: Text(AppLocalizations.of(context)!.fantasyNoMembers,
                                style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 80),
                            itemCount: _standings.length,
                            separatorBuilder: (_, __) => SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final m = _standings[i];
                              final profile = m['user_profiles'] as Map<String, dynamic>?;
                              final username =
                                  profile?['username'] as String? ?? m['team_name'] as String? ?? '—';
                              final pts = m['total_points'] as int? ?? 0;
                              final uid = m['user_id'] as String?;
                              final rank = i + 1;
                              final isWinner = _winnerId != null && uid == _winnerId;
                              final rankColor = rank == 1
                                  ? AppColors.neonYellow
                                  : rank == 2
                                      ? const Color(0xFFB0BEC5)
                                      : rank == 3
                                          ? const Color(0xFFCD7F32)
                                          : AppColors.textMuted;

                              return Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: rank <= 3
                                      ? rankColor.withValues(alpha: 0.07)
                                      : AppColors.bgCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: rank <= 3
                                          ? rankColor.withValues(alpha: 0.3)
                                          : AppColors.divider.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 32,
                                      child: Text('#$rank',
                                          style: TextStyle(
                                              color: rankColor,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16)),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Row(children: [
                                        Flexible(
                                          child: Text(username,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14)),
                                        ),
                                        if (isWinner) ...[
                                          SizedBox(width: 6),
                                          Icon(Icons.emoji_events,
                                              color: AppColors.neonYellow, size: 16),
                                        ],
                                      ]),
                                    ),
                                    Text('$pts pts',
                                        style: TextStyle(
                                            color: AppColors.neonGreen,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
