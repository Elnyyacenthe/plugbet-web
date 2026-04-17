// ============================================================
// FinishedSection — Section repliable des matchs termines
// Extrait de home_screen.dart.
// ============================================================
import 'package:flutter/material.dart';

import '../../models/football_models.dart';
import '../../theme/app_theme.dart';
import 'league_row.dart';

class FinishedSection extends StatefulWidget {
  final List<MapEntry<Competition, List<FootballMatch>>> groups;
  final void Function(int matchId) onMatchTap;

  const FinishedSection({
    super.key,
    required this.groups,
    required this.onMatchTap,
  });

  @override
  State<FinishedSection> createState() => _FinishedSectionState();
}

class _FinishedSectionState extends State<FinishedSection> {
  bool _isExpanded = false;

  int get _totalCount =>
      widget.groups.fold(0, (sum, g) => sum + g.value.length);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  'TERMINES',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_totalCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down,
                      size: 20, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: widget.groups.map((entry) {
              return LeagueRow(
                competition: entry.key,
                matches: entry.value,
                onMatchTap: widget.onMatchTap,
              );
            }).toList(),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _isExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}
