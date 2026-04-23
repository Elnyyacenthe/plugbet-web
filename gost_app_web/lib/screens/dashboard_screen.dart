// ============================================================
// Dashboard – Profil joueur, stats, rang, historique, rewards
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/player_models.dart';
import '../providers/player_provider.dart';
import '../providers/wallet_provider.dart';
import 'leaderboard_screen.dart';
import 'friends_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Consumer2<PlayerProvider, WalletProvider>(
            builder: (context, player, wallet, _) {
              return ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  // Header
                  _buildHeader(context),
                  SizedBox(height: 16),
                  // Rang + XP
                  _buildRankCard(player),
                  SizedBox(height: 14),
                  // Coins
                  _buildCoinsCard(wallet, player),
                  SizedBox(height: 14),
                  // Daily reward
                  _buildDailyReward(player, wallet),
                  SizedBox(height: 14),
                  // Quick stats
                  _buildQuickStats(player),
                  SizedBox(height: 14),
                  // Stats par jeu
                  _buildGameStats(player),
                  SizedBox(height: 14),
                  // Achievements
                  _buildAchievements(player),
                  SizedBox(height: 14),
                  // Historique récent
                  _buildHistory(player),
                  SizedBox(height: 14),
                  // Liens rapides
                  _buildQuickLinks(context),
                  SizedBox(height: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        Text(
          'Mon Profil',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ── Carte Rang ────────────────────────────────────────────
  Widget _buildRankCard(PlayerProvider player) {
    final rank = player.rank;
    final xp = player.xp;
    final progress = player.progress;
    final nextRank = rank.next;

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            rank.color.withValues(alpha: 0.2),
            AppColors.bgCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rank.color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Badge de rang
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: rank.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: rank.color.withValues(alpha: 0.5)),
                ),
                child: Icon(rank.icon, color: rank.color, size: 32),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rank.label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: rank.color,
                      ),
                    ),
                    Text(
                      '$xp XP',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Streak
              if (player.winStreak > 0)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.neonOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department,
                          color: AppColors.neonOrange, size: 16),
                      SizedBox(width: 4),
                      Text(
                        '${player.winStreak}',
                        style: TextStyle(
                          color: AppColors.neonOrange,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          // Barre de progression
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rank.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: rank.color,
                    ),
                  ),
                  if (nextRank != null)
                    Text(
                      nextRank.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: nextRank.color.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 6),
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            rank.color,
                            (nextRank?.color ?? rank.color)
                                .withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              if (nextRank != null)
                Text(
                  '${nextRank.minXp - xp} XP restants pour ${nextRank.label}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Carte Coins ───────────────────────────────────────────
  Widget _buildCoinsCard(WalletProvider wallet, PlayerProvider player) {
    final total = player.totalStats;
    final net = total.coinsWon - total.coinsLost;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          // Solde
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solde',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 24),
                    SizedBox(width: 8),
                    Text(
                      '${wallet.coins}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.neonYellow,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Gains / Pertes
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_upward,
                      size: 14,
                      color: AppColors.neonGreen.withValues(alpha: 0.8)),
                  Text(
                    ' +${total.coinsWon}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neonGreen,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_downward,
                      size: 14,
                      color: AppColors.neonRed.withValues(alpha: 0.8)),
                  Text(
                    ' -${total.coinsLost}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neonRed,
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              Text(
                'Net: ${net >= 0 ? '+' : ''}$net',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: net >= 0 ? AppColors.neonGreen : AppColors.neonRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Daily Reward ──────────────────────────────────────────
  Widget _buildDailyReward(PlayerProvider player, WalletProvider wallet) {
    final canClaim = player.canClaimDaily;
    final streak = player.dailyStreak;
    final dayIndex = streak % dailyRewardCoins.length;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: canClaim
              ? [
                  AppColors.neonGreen.withValues(alpha: 0.12),
                  AppColors.bgCard,
                ]
              : [AppColors.bgCard, AppColors.bgCard],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: canClaim
              ? AppColors.neonGreen.withValues(alpha: 0.4)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          // Icône calendrier
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (canClaim ? AppColors.neonGreen : AppColors.textMuted)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.card_giftcard,
              color: canClaim ? AppColors.neonGreen : AppColors.textMuted,
              size: 24,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canClaim ? 'Récompense quotidienne !' : 'Reviens demain !',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: canClaim
                        ? AppColors.neonGreen
                        : AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  canClaim
                      ? 'Jour ${dayIndex + 1} : +${dailyRewardCoins[dayIndex]} FCFA'
                      : 'Série de $streak jours',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (canClaim)
            ElevatedButton(
              onPressed: () async {
                final coins = await player.claimDailyReward();
                if (coins > 0) {
                  await wallet.refresh();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('+$coins FCFA récupérés !'),
                        backgroundColor: AppColors.neonGreen,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Réclamer',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  // ── Stats rapides ─────────────────────────────────────────
  Widget _buildQuickStats(PlayerProvider player) {
    final total = player.totalStats;
    return Row(
      children: [
        _StatMini(
          icon: Icons.sports_esports,
          label: 'Parties',
          value: '${total.gamesPlayed}',
          color: AppColors.neonBlue,
        ),
        SizedBox(width: 10),
        _StatMini(
          icon: Icons.emoji_events,
          label: 'Victoires',
          value: '${total.wins}',
          color: AppColors.neonGreen,
        ),
        SizedBox(width: 10),
        _StatMini(
          icon: Icons.percent,
          label: 'Taux',
          value: '${total.winRate.toStringAsFixed(0)}%',
          color: AppColors.neonYellow,
        ),
        SizedBox(width: 10),
        _StatMini(
          icon: Icons.local_fire_department,
          label: 'Record',
          value: '${player.bestWinStreak}',
          color: AppColors.neonOrange,
        ),
      ],
    );
  }

  // ── Stats par jeu ─────────────────────────────────────────
  Widget _buildGameStats(PlayerProvider player) {
    final games = [
      ('Dames', 'checkers', '♟️', const Color(0xFF8D6E63)),
      ('Solitaire', 'solitaire', '🃏', const Color(0xFF9C27B0)),
      ('Cora Dice', 'cora', '🎲', AppColors.neonBlue),
      ('Ludo', 'ludo', '🎯', AppColors.neonGreen),
    ];

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 16, color: AppColors.neonBlue),
              SizedBox(width: 8),
              Text(
                'Statistiques par jeu',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          ...games.map((g) {
            final stats = player.statsFor(g.$2);
            if (stats.gamesPlayed == 0) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(g.$3, style: TextStyle(fontSize: 18)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.$1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '${stats.wins}V / ${stats.losses}D / ${stats.draws}N • ${stats.winRate.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  // Mini barre
                  SizedBox(
                    width: 60,
                    height: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: stats.winRate / 100,
                        backgroundColor: AppColors.bgElevated,
                        color: g.$4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Achievements ──────────────────────────────────────────
  Widget _buildAchievements(PlayerProvider player) {
    final unlocked = player.unlockedAchievements;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium,
                  size: 16, color: AppColors.neonYellow),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Achievements',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${unlocked.length} / ${allAchievements.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allAchievements.map((a) {
              final isUnlocked = unlocked.contains(a.id);
              return Tooltip(
                message: '${a.title}\n${a.description}',
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isUnlocked
                        ? a.color.withValues(alpha: 0.15)
                        : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isUnlocked
                          ? a.color.withValues(alpha: 0.5)
                          : AppColors.divider,
                    ),
                  ),
                  child: Icon(
                    a.icon,
                    color: isUnlocked
                        ? a.color
                        : AppColors.textMuted.withValues(alpha: 0.3),
                    size: 22,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Historique récent ─────────────────────────────────────
  Widget _buildHistory(PlayerProvider player) {
    final history = player.history.take(10).toList();
    if (history.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Aucune partie jouée',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded,
                  size: 16, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text(
                'Historique récent',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ...history.map((h) => _HistoryRow(entry: h)),
        ],
      ),
    );
  }

  // ── Liens rapides ─────────────────────────────────────────
  Widget _buildQuickLinks(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickLinkBtn(
            icon: Icons.leaderboard_rounded,
            label: 'Classement',
            color: AppColors.neonYellow,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const LeaderboardScreen()),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _QuickLinkBtn(
            icon: Icons.people_alt_rounded,
            label: 'Amis',
            color: AppColors.neonBlue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FriendsScreen()),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Widgets helpers ─────────────────────────────────────────

class _StatMini extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatMini({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final GameHistoryEntry entry;
  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isWin = entry.result == 'win';
    final isDraw = entry.result == 'draw';
    final resultColor =
        isWin ? AppColors.neonGreen : (isDraw ? AppColors.neonYellow : AppColors.neonRed);
    final resultLabel = isWin ? 'Victoire' : (isDraw ? 'Nul' : 'Défaite');

    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(entry.gameEmoji, style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.gameLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (entry.opponentName != null)
                  Text(
                    'vs ${entry.opponentName}',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  resultLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: resultColor,
                  ),
                ),
              ),
              SizedBox(height: 3),
              Text(
                '${entry.coinsChange >= 0 ? '+' : ''}${entry.coinsChange} • +${entry.xpGained} XP',
                style: TextStyle(
                    fontSize: 10, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickLinkBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickLinkBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
