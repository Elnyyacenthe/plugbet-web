// ============================================================
// FANTASY MODULE – Écran Ligues
// Créer, rejoindre, classements
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../services/fantasy_service.dart';

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
    bool isPrivate = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text('Créer une ligue',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          content: Column(
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
              SizedBox(height: 16),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Créer',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await FantasyService.instance.createLeague(
        name: nameCtrl.text.trim().isEmpty ? 'Ma Ligue' : nameCtrl.text.trim(),
        isPrivate: isPrivate,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ligue créée !'), backgroundColor: AppColors.neonGreen),
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
        title: Text('Rejoindre par code',
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
            child: Text('Rejoindre',
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
          SnackBar(content: Text('Ligue rejointe !'), backgroundColor: AppColors.neonBlue),
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
        builder: (_) => _LeagueStandingsScreen(
          leagueId: league['id'] as String,
          leagueName: league['name'] as String? ?? 'Ligue',
          privateCode: league['private_code'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text('Mes Ligues'),
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
                              content: Text('Code copié !'),
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
                    Text('Ligue publique',
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
          Text('Aucune ligue pour l\'instant',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('Créez ou rejoignez une ligue\npour affronter vos amis',
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
  final String leagueId;
  final String leagueName;
  final String? privateCode;

  const _LeagueStandingsScreen({
    required this.leagueId,
    required this.leagueName,
    this.privateCode,
  });

  @override
  State<_LeagueStandingsScreen> createState() => _LeagueStandingsScreenState();
}

class _LeagueStandingsScreenState extends State<_LeagueStandingsScreen> {
  List<Map<String, dynamic>> _standings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await FantasyService.instance.getLeagueStandings(widget.leagueId);
    if (mounted) setState(() { _standings = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(widget.leagueName),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.privateCode != null)
            IconButton(
              icon: Icon(Icons.copy, color: AppColors.neonBlue),
              tooltip: 'Copier le code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.privateCode!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Code ${widget.privateCode} copié !'),
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
            : _standings.isEmpty
                ? Center(
                    child: Text('Aucun membre dans cette ligue.',
                        style: TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _standings.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final m = _standings[i];
                      final profile = m['user_profiles'] as Map<String, dynamic>?;
                      final username =
                          profile?['username'] as String? ?? m['team_name'] as String? ?? '—';
                      final pts = m['total_points'] as int? ?? 0;
                      final rank = i + 1;
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
                              child: Text(username,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
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
    );
  }
}
