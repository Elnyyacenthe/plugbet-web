// ============================================================
// AVIATOR - Live Winnings Panel (right side)
// Feed temps reel des cashouts reussis (dernières minutes).
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../models/aviator_models.dart';
import '../providers/aviator_provider.dart';

class LiveWinningsPanel extends StatelessWidget {
  final double width;
  const LiveWinningsPanel({super.key, this.width = 180});

  @override
  Widget build(BuildContext context) {
    return Consumer<AviatorProvider>(
      builder: (ctx, prov, _) {
        final wins = prov.recentWinnings;
        return Container(
          width: width,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1510),
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                color: const Color(0xFF0F2015),
                child: Row(
                  children: [
                    const Icon(Icons.bolt,
                        color: Color(0xFF00E676), size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'GAINS LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: wins.isEmpty
                    ? Center(
                        child: Text(
                          'Aucun gain\npour l\'instant',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 10,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: wins.length,
                        itemBuilder: (_, i) => _WinRow(win: wins[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WinRow extends StatelessWidget {
  final LiveBet win;
  const _WinRow({required this.win});

  @override
  Widget build(BuildContext context) {
    final mult = win.cashedOutAt ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: AppColors.neonGreen.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _avatarColor(win.username),
            ),
            alignment: Alignment.center,
            child: Text(
              win.username.isNotEmpty ? win.username[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _maskUsername(win.username),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'x${mult.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${win.winAmount ?? 0}',
            style: TextStyle(
              color: AppColors.neonYellow,
              fontSize: 11,
              fontWeight: FontWeight.w800,
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
