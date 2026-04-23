// ============================================================
// AVIATOR - Live Bets Panel (left side)
// Affiche tous les paris actifs du round courant en temps reel.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../models/aviator_models.dart';
import '../providers/aviator_provider.dart';

class LiveBetsPanel extends StatelessWidget {
  final double width;
  const LiveBetsPanel({super.key, this.width = 220});

  @override
  Widget build(BuildContext context) {
    return Consumer<AviatorProvider>(
      builder: (ctx, prov, _) {
        final bets = prov.liveBets;
        final totalWagered = bets.fold<int>(0, (a, b) => a + b.amount);
        return Container(
          width: width,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1510),
            border: Border(
              right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: const Color(0xFF0F2015),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'TOTAL BETS: ${bets.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      '$totalWagered',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.monetization_on,
                        color: Color(0xFFFFD600), size: 12),
                  ],
                ),
              ),

              // Column headers
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                color: Colors.black.withValues(alpha: 0.25),
                child: Row(
                  children: const [
                    _HeaderCell('User', flex: 3),
                    _HeaderCell('Bet', flex: 2),
                    _HeaderCell('Coef', flex: 2),
                    _HeaderCell('Win', flex: 2),
                  ],
                ),
              ),

              // List
              Expanded(
                child: bets.isEmpty
                    ? Center(
                        child: Text(
                          'En attente des mises...',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: bets.length,
                        itemBuilder: (_, i) => _BetRow(bet: bets[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  const _HeaderCell(this.label, {this.flex = 1});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _BetRow extends StatelessWidget {
  final LiveBet bet;
  const _BetRow({required this.bet});

  @override
  Widget build(BuildContext context) {
    final hasCashedOut = bet.cashedOutAt != null;
    final rowColor = hasCashedOut
        ? AppColors.neonGreen.withValues(alpha: 0.08)
        : Colors.transparent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(
          bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.03), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // User (avatar + masked pseudo)
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _avatarColor(bet.username),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    bet.username.isNotEmpty
                        ? bet.username[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _maskUsername(bet.username),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bet amount
          Expanded(
            flex: 2,
            child: Text(
              '${bet.amount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Coef
          Expanded(
            flex: 2,
            child: Text(
              hasCashedOut
                  ? 'x${bet.cashedOutAt!.toStringAsFixed(2)}'
                  : '-',
              style: TextStyle(
                color: hasCashedOut ? AppColors.neonGreen : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Win
          Expanded(
            flex: 2,
            child: Text(
              bet.winAmount != null ? '${bet.winAmount}' : '-',
              style: TextStyle(
                color: bet.winAmount != null && bet.winAmount! > 0
                    ? AppColors.neonGreen
                    : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _maskUsername(String u) {
    if (u.length <= 2) return u;
    return '${u[0]}***${u[u.length - 1]}';
  }

  Color _avatarColor(String name) {
    final palette = [
      const Color(0xFFEF4444),
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
    ];
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[hash % palette.length];
  }
}
