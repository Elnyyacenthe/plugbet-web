// ============================================================
// FANTASY MODULE – Écran Accueil Fantasy
// Deadline GW, pitch compact, quick actions, live top, IA
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../providers/fpl_provider.dart';
import '../models/fpl_models.dart';
import '../widgets/fpl_player_card.dart';
import '../widgets/fantasy_inapp_pitch.dart';
import 'fantasy_my_team_screen.dart';
import 'fantasy_transfers_screen.dart';
import 'fantasy_player_screen.dart';
import 'fantasy_leagues_screen.dart';
import '../services/fantasy_service.dart';

class FantasyHomeScreen extends StatefulWidget {
  const FantasyHomeScreen({super.key});

  @override
  State<FantasyHomeScreen> createState() => _FantasyHomeScreenState();
}

class _FantasyHomeScreenState extends State<FantasyHomeScreen> {
  Timer? _deadlineTimer;
  Duration? _timeToDeadline;
  Map<String, dynamic>? _myTeamData;
  List<Map<String, dynamic>> _myPicks = [];
  bool _teamLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  void _init() async {
    final p = context.read<FplProvider>();
    if (p.state == FplLoadState.idle) {
      p.loadBootstrap();
    }
    _startDeadlineTimer();

    // Attendre que l'auth soit prête avant de charger l'équipe
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      // Écouter le premier événement auth (signIn anonyme en cours)
      final completer = Completer<void>();
      late final StreamSubscription sub;
      sub = client.auth.onAuthStateChange.listen((data) {
        if (data.session != null && !completer.isCompleted) {
          completer.complete();
          sub.cancel();
        }
      });
      // Timeout 5s max pour ne pas bloquer indéfiniment
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => sub.cancel(),
      );
    }
    if (!mounted) return;
    _loadMyTeam();
  }

  Future<void> _loadMyTeam() async {
    if (!mounted) return;
    setState(() => _teamLoading = true);
    try {
      final team = await FantasyService.instance.getMyTeam();
      if (team != null) {
        final picks = await FantasyService.instance.getPicks(team['id'] as String);
        debugPrint('[FANTASY] Loaded team: ${team['team_name']} with ${picks.length} picks');
        if (mounted) setState(() { _myTeamData = team; _myPicks = picks; });
      } else {
        debugPrint('[FANTASY] No team found');
        if (mounted) setState(() { _myTeamData = null; _myPicks = []; });
      }
    } catch (e) {
      debugPrint('[FANTASY] _loadMyTeam error: $e');
      if (mounted) setState(() { _myTeamData = null; _myPicks = []; });
    }
    if (mounted) setState(() => _teamLoading = false);
  }

  Future<void> _createTeam() async {
    final ctrl = TextEditingController(text: 'Mon Équipe');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(AppLocalizations.of(context)!.fantasyCreateTeam,
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Nom de l\'équipe',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel, style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.gameCreate, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final team = await FantasyService.instance.createTeam(
        teamName: ctrl.text.trim().isEmpty ? 'Mon Équipe' : ctrl.text.trim(),
        initialBudget: 10000,
      );
      if (!mounted) return;
      setState(() {
        _myTeamData = team;
        _myPicks = [];
        _teamLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.fantasyTeamCreated),
          backgroundColor: AppColors.neonGreen,
          duration: Duration(seconds: 3),
        ),
      );
    } on FantasyException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Icon(Icons.warning_amber, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text(e.message)),
          ]),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.fantasyUnexpectedError),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startDeadlineTimer() {
    _deadlineTimer?.cancel();
    _deadlineTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final gw = context.read<FplProvider>().bootstrap?.currentEvent;
      if (!mounted) return;
      setState(() => _timeToDeadline = gw?.timeToDeadline);
    });
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Consumer<FplProvider>(
        builder: (context, fpl, _) {
          return Container(
            decoration: BoxDecoration(gradient: AppColors.bgGradient),
            child: CustomScrollView(
              slivers: [
                _buildAppBar(fpl),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SizedBox(height: 12),
                      _buildGwBanner(fpl),
                      SizedBox(height: 16),
                      if (_teamLoading)
                        _shimmerBox(80)
                      else if (_myTeamData != null) ...[
                        _buildMyTeamSection(fpl),
                        SizedBox(height: 16),
                        _buildQuickActions(fpl),
                        SizedBox(height: 16),
                      ] else ...[
                        _buildCreateTeamBanner(),
                        SizedBox(height: 16),
                      ],
                      _buildTopPerformers(fpl),
                      SizedBox(height: 16),
                      _buildValuePicks(fpl),
                      SizedBox(height: 16),
                      _buildAiSection(fpl),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────

  Widget _buildAppBar(FplProvider fpl) {
    return SliverAppBar(
      backgroundColor: AppColors.bgBlueNight,
      expandedHeight: 60,
      floating: true,
      snap: true,
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.emoji_events, color: AppColors.neonGreen, size: 20),
          ),
          SizedBox(width: 10),
          Text(
            'Fantasy PL',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          if (fpl.state == FplLoadState.loading)
            SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.neonGreen,
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.refresh, color: AppColors.textSecondary),
          onPressed: () => context.read<FplProvider>().loadBootstrap(force: true),
        ),
      ],
    );
  }

  // ─── GW Banner ────────────────────────────────────────────

  Widget _buildGwBanner(FplProvider fpl) {
    final gw = fpl.bootstrap?.currentEvent;
    if (gw == null) {
      return _shimmerBox(80);
    }

    final isLive = gw.isLive;
    final bannerColor = isLive ? AppColors.neonGreen : AppColors.neonOrange;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            bannerColor.withValues(alpha: 0.15),
            AppColors.bgCard,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bannerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isLive)
                    Container(
                      margin: EdgeInsets.only(right: 8),
                      padding: EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.neonGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'LIVE',
                        style: TextStyle(
                          color: AppColors.neonGreen,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  Text(
                    gw.name.toUpperCase(),
                    style: TextStyle(
                      color: bannerColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              if (_timeToDeadline != null && !isLive)
                Text(
                  'Deadline : ${_formatDuration(_timeToDeadline!)}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                )
              else if (gw.finished)
                Text(
                  'Terminé · Moy. ${gw.averageEntryScore} pts',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (isLive && _myTeamData != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${fpl.myLivePoints}',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'pts live',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ─── My Team (pitch compact) ──────────────────────────────

  Widget _buildMyTeamSection(FplProvider fpl) {
    final teamName = _myTeamData?['team_name'] as String? ?? 'Mon Équipe';
    final totalPoints = _myTeamData?['total_points'] as int? ?? 0;
    final budget = _myTeamData?['budget'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(teamName, Icons.sports_soccer),
        SizedBox(height: 10),
        if (_myPicks.isNotEmpty && fpl.bootstrap != null)
          FantasyInAppPitch(
            picks: _myPicks,
            bootstrap: fpl.bootstrap!,
            formation: _myTeamData?['formation'] as String? ?? '4-4-2',
            compact: true,
            onPlayerTap: (el, pick) => _openPlayer(el),
          )
        else if (_myPicks.isNotEmpty && fpl.bootstrap == null)
          Container(
            height: 160,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.neonGreen),
                SizedBox(height: 8),
                Text(AppLocalizations.of(context)!.fantasyLoadingPlayers,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          )
        else
          Container(
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, color: AppColors.textMuted, size: 40),
                SizedBox(height: 8),
                Text(AppLocalizations.of(context)!.fantasyNoPlayerSelected,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                SizedBox(height: 4),
                TextButton(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(context,
                        MaterialPageRoute(builder: (_) => const FantasyTransfersScreen()));
                    if (result == true && mounted) _loadMyTeam();
                  },
                  child: Text('${AppLocalizations.of(context)!.fantasyAddPlayers} →',
                      style: TextStyle(color: AppColors.neonGreen, fontSize: 12)),
                ),
              ],
            ),
          ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _infoChip(Icons.account_balance_wallet, 'Budget: $budget FCFA', AppColors.neonGreen),
            _infoChip(Icons.trending_up, '$totalPoints pts total', AppColors.neonBlue),
          ],
        ),
      ],
    );
  }

  // ─── Quick Actions ────────────────────────────────────────

  Widget _buildQuickActions(FplProvider fpl) {
    return Column(
      children: [
        // Ligne 1 : Transferts · Compo · Captain
        Row(
          children: [
            Expanded(
              child: _actionButton(
                Icons.swap_horiz,
                'Transferts',
                AppColors.neonOrange,
                () async {
                  await Navigator.push<bool>(context,
                      MaterialPageRoute(builder: (_) => const FantasyTransfersScreen()));
                  if (mounted) _loadMyTeam();
                },
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                Icons.sports_soccer,
                'Compo',
                AppColors.neonGreen,
                () async {
                  if (_myTeamData == null || _myPicks.isEmpty) return;
                  final updated = await Navigator.push<List<Map<String, dynamic>>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FantasyMyTeamScreen(
                        team: _myTeamData!,
                        picks: _myPicks,
                      ),
                    ),
                  );
                  if (updated != null && mounted) {
                    setState(() => _myPicks = updated);
                  }
                },
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                Icons.star,
                'Captain',
                AppColors.neonYellow,
                () => _showCaptainPicker(fpl),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        // Ligne 2 : Ligues · Rejoindre
        Row(
          children: [
            Expanded(
              child: _actionButton(
                Icons.emoji_events,
                'Créer Ligue',
                AppColors.neonBlue,
                () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FantasyLeaguesScreen()));
                },
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                Icons.group_add,
                'Rejoindre',
                const Color(0xFF9C27B0),
                _showJoinLeagueDialog,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                Icons.leaderboard,
                'Mes Ligues',
                AppColors.neonGreen,
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FantasyLeaguesScreen())),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showJoinLeagueDialog() async {
    final codeCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(AppLocalizations.of(context)!.fantasyJoinLeague,
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: AppColors.textPrimary, letterSpacing: 3, fontSize: 18),
          maxLength: 6,
          decoration: InputDecoration(
            hintText: 'CODE',
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
            child: Text(AppLocalizations.of(context)!.commonCancel, style: TextStyle(color: AppColors.textSecondary)),
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

  // ─── Create Team Banner ───────────────────────────────────

  Widget _buildCreateTeamBanner() {
    return GestureDetector(
      onTap: _createTeam,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.neonGreen.withValues(alpha: 0.08),
              AppColors.neonBlue.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, color: AppColors.neonGreen, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Créer mon équipe Fantasy',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Budget de départ 10 000 FCFA · Gérez vos picks et ligues dans l\'app',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  // ─── Top Performers ───────────────────────────────────────

  Widget _buildTopPerformers(FplProvider fpl) {
    final tops = fpl.topLive(limit: 5);
    if (tops.isEmpty) {
      final gw = fpl.bootstrap?.currentEvent;
      if (gw == null || !gw.isLive) return const SizedBox.shrink();
      return _shimmerBox(200);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Top Performers Live', Icons.local_fire_department),
        SizedBox(height: 10),
        ...tops.map((entry) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: FplPlayerCard(
                player: entry.key,
                team: fpl.bootstrap?.teamById(entry.key.teamId),
                livePoints: entry.value,
                showPrice: false,
                onTap: () => _openPlayer(entry.key),
              ),
            )),
      ],
    );
  }

  // ─── Value Picks ──────────────────────────────────────────

  Widget _buildValuePicks(FplProvider fpl) {
    if (fpl.bootstrap == null) return const SizedBox.shrink();
    final picks = fpl.valuePicks(maxCoins: 600, limit: 4);
    if (picks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Value Picks <£6m', Icons.trending_up),
        SizedBox(height: 10),
        ...picks.map((el) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: FplPlayerCard(
                player: el,
                team: fpl.bootstrap?.teamById(el.teamId),
                showForm: true,
                showOwnership: true,
                onTap: () => _openPlayer(el),
              ),
            )),
      ],
    );
  }

  // ─── IA Section ───────────────────────────────────────────

  Widget _buildAiSection(FplProvider fpl) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.neonPurple.withValues(alpha: 0.08),
            AppColors.bgCard,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.neonPurple.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.neonPurple, size: 18),
              SizedBox(width: 8),
              Text(
                'Suggestions IA',
                style: TextStyle(
                  color: AppColors.neonPurple,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (fpl.aiLoading)
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.neonPurple,
                  ),
                )
              else
                TextButton(
                  onPressed: () => context.read<FplProvider>().fetchAiSuggestion(),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                  ),
                  child: Text(
                    'Actualiser',
                    style: TextStyle(
                      color: AppColors.neonPurple,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 10),
          if (fpl.aiSuggestion.isNotEmpty)
            Text(
              fpl.aiSuggestion,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            )
          else
            Text(
              'Appuyez sur "Actualiser" pour obtenir des conseils personnalisés sur les transfers, le captain et les value picks de cette semaine.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.neonGreen, size: 18),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _shimmerBox(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2, color: AppColors.neonGreen,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}j ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }

  void _openPlayer(FplElement el) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FantasyPlayerScreen(elementId: el.id),
      ),
    );
  }

  void _showCaptainPicker(FplProvider fpl) {
    final team = _myTeamData;
    if (team == null || fpl.bootstrap == null || _myPicks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.fantasyAddPlayersFirst),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Captain et VC actuels depuis les picks Supabase
    final capId = _myPicks
        .where((p) => p['is_captain'] == true)
        .map((p) => p['element_id'] as int)
        .firstOrNull;
    final vcId = _myPicks
        .where((p) => p['is_vice_captain'] == true)
        .map((p) => p['element_id'] as int)
        .firstOrNull;

    // Joueurs sélectionnés avec leurs infos FPL
    final players = _myPicks
        .map((p) => fpl.bootstrap!.elementById(p['element_id'] as int))
        .whereType<FplElement>()
        .toList()
      ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Choisir le Captain (C) / Vice-Captain (V)',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  ...players.map((el) {
                    final isCap = el.id == capId;
                    final isVc = el.id == vcId;
                    return ListTile(
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: isCap
                              ? AppColors.neonYellow.withValues(alpha: 0.3)
                              : isVc
                                  ? AppColors.neonBlue.withValues(alpha: 0.2)
                                  : AppColors.bgCard,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCap
                                ? AppColors.neonYellow
                                : isVc
                                    ? AppColors.neonBlue
                                    : AppColors.divider,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            isCap ? 'C' : isVc ? 'V' : el.positionLabel,
                            style: TextStyle(
                              color: isCap
                                  ? AppColors.neonYellow
                                  : isVc
                                      ? AppColors.neonBlue
                                      : AppColors.textSecondary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(el.webName,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${el.totalPoints} pts · forme ${el.form}',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                      trailing: PopupMenuButton<String>(
                        color: AppColors.bgCard,
                        icon: Icon(Icons.more_vert,
                            color: AppColors.textMuted),
                        onSelected: (choice) async {
                          Navigator.pop(ctx);
                          HapticFeedback.lightImpact();
                          // Trouver un VC par défaut (2e joueur par pts)
                          final otherId = players
                              .where((p) => p.id != el.id)
                              .firstOrNull
                              ?.id ?? el.id;
                          final newCapId =
                              choice == 'cap' ? el.id : (capId ?? otherId);
                          final newVcId =
                              choice == 'vc' ? el.id : (vcId ?? otherId);
                          try {
                            await FantasyService.instance.setCaptain(
                              teamId: team['id'] as String,
                              captainElementId: newCapId,
                              vcElementId: newVcId,
                            );
                            await _loadMyTeam();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(choice == 'cap'
                                    ? '${el.webName} désigné Captain !'
                                    : '${el.webName} désigné Vice-Captain !'),
                                backgroundColor: choice == 'cap'
                                    ? AppColors.neonYellow
                                    : AppColors.neonBlue,
                              ));
                            }
                          } on FantasyException catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message),
                                      backgroundColor: Colors.red));
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'cap',
                              child: Text('Définir comme Captain (C)',
                                  style: TextStyle(color: AppColors.neonYellow))),
                          PopupMenuItem(
                              value: 'vc',
                              child: Text('Définir comme Vice-Captain (V)',
                                  style: TextStyle(color: AppColors.neonBlue))),
                        ],
                      ),
                    );
                  }),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
