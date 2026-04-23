// ============================================================
// Leaderboard – Classement global et par jeu
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/player_models.dart';
import '../providers/player_provider.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<LeaderboardEntry> _entries = [];
  bool _loading = true;

  final _tabs = const ['Global', 'Dames', 'Solitaire', 'Cora', 'Ludo'];
  final _gameTypes = const [null, 'checkers', 'solitaire', 'cora', 'ludo'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadData();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final provider = context.read<PlayerProvider>();
    final gameType = _gameTypes[_tabController.index];
    final data = await provider.fetchLeaderboard(gameType: gameType);
    if (mounted) {
      setState(() {
        _entries = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Icon(Icons.leaderboard_rounded,
                        color: AppColors.neonYellow, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Classement',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Tabs
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.neonYellow.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.neonYellow.withValues(alpha: 0.4)),
                  ),
                  labelColor: AppColors.neonYellow,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                  tabAlignment: TabAlignment.start,
                  dividerHeight: 0,
                ),
              ),
              // Content
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppColors.neonYellow))
                    : _entries.isEmpty
                        ? _buildEmpty()
                        : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.leaderboard_rounded,
              size: 48, color: AppColors.textMuted.withValues(alpha: 0.4)),
          SizedBox(height: 12),
          Text(
            'Aucun joueur classé',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          SizedBox(height: 8),
          Text(
            'Les classements apparaîtront quand\ndes joueurs auront joué.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      color: AppColors.neonYellow,
      backgroundColor: AppColors.bgCard,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final position = index + 1;
          return _LeaderboardTile(
            entry: entry,
            position: position,
            onAddFriend: () => _sendFriendRequest(entry),
          );
        },
      ),
    );
  }

  Future<void> _sendFriendRequest(LeaderboardEntry entry) async {
    if (entry.isCurrentUser) return;
    final provider = context.read<PlayerProvider>();
    final ok = await provider.sendFriendRequest(entry.oddsId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Demande d\'ami envoyée à ${entry.username}'
              : 'Impossible d\'envoyer la demande'),
          backgroundColor: ok ? AppColors.neonGreen : AppColors.neonRed,
        ),
      );
    }
  }
}

class _LeaderboardTile extends StatelessWidget {
  final LeaderboardEntry entry;
  final int position;
  final VoidCallback onAddFriend;

  const _LeaderboardTile({
    required this.entry,
    required this.position,
    required this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    final isTop3 = position <= 3;
    final medal = position == 1
        ? '🥇'
        : position == 2
            ? '🥈'
            : position == 3
                ? '🥉'
                : null;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: entry.isCurrentUser
            ? AppColors.neonGreen.withValues(alpha: 0.08)
            : AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.isCurrentUser
              ? AppColors.neonGreen.withValues(alpha: 0.4)
              : isTop3
                  ? entry.rank.color.withValues(alpha: 0.3)
                  : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          // Position
          SizedBox(
            width: 36,
            child: medal != null
                ? Text(medal, style: TextStyle(fontSize: 22))
                : Text(
                    '#$position',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
          ),
          SizedBox(width: 8),
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: entry.rank.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border:
                  Border.all(color: entry.rank.color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                entry.username.isNotEmpty
                    ? entry.username[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: entry.rank.color,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.username,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: entry.isCurrentUser
                              ? AppColors.neonGreen
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (entry.isCurrentUser) ...[
                      SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'TOI',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.neonGreen,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(entry.rank.icon, size: 12, color: entry.rank.color),
                    SizedBox(width: 4),
                    Text(
                      entry.rank.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: entry.rank.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      entry.xp > 0 ? '${entry.xp} XP' : '${entry.coins} FCFA',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Coins / Victories
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.monetization_on, size: 14, color: AppColors.neonYellow),
                  SizedBox(width: 3),
                  Text(
                    '${entry.coins}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.neonYellow,
                    ),
                  ),
                ],
              ),
              if (entry.wins > 0)
                Text(
                  '${entry.wins} victoires',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
            ],
          ),
          // Add friend button
          if (!entry.isCurrentUser) ...[
            SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.person_add_alt_1_rounded,
                  size: 18, color: AppColors.neonBlue),
              onPressed: onAddFriend,
              tooltip: 'Ajouter en ami',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}
