// ============================================================
// Apple of Fortune – Game board (vertical grid)
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../models/apple_fortune_models.dart';
import 'fortune_tile.dart';

class FortuneBoard extends StatelessWidget {
  final AppleFortuneSession? session;
  final int columns;
  final int totalRows;
  final bool isPlaying;
  final bool loading;
  final List<double> multipliers;
  final ValueChanged<int>? onTileTap;

  const FortuneBoard({
    super.key,
    required this.session,
    required this.columns,
    required this.totalRows,
    required this.isPlaying,
    required this.loading,
    required this.multipliers,
    this.onTileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalRows, (i) {
        final rowIndex = totalRows - 1 - i;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildRow(rowIndex),
        );
      }),
    );
  }

  Widget _buildRow(int rowIndex) {
    final revealed = session?.revealedRows
        .where((r) => r.row == rowIndex)
        .toList();
    final revealedRow = (revealed != null && revealed.isNotEmpty)
        ? revealed.first
        : null;

    final isActiveRow = isPlaying &&
        session != null &&
        session!.isActive &&
        rowIndex == session!.currentRow;

    final isReached = session != null && rowIndex < (session!.currentRow);
    final isLostRow = session != null &&
        session!.isLost &&
        rowIndex == session!.currentRow;

    // Multiplier for this row (rowIndex is 0-based, multipliers[0] = row 1 success)
    final mult = rowIndex < multipliers.length ? multipliers[rowIndex] : 0.0;

    return Row(
      children: [
        // Multiplier label on left — capsule néon
        SizedBox(
          width: 54,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: isLostRow
                  ? LinearGradient(colors: [
                      AppColors.neonRed.withValues(alpha: 0.28),
                      AppColors.neonRed.withValues(alpha: 0.10),
                    ])
                  : isActiveRow
                      ? LinearGradient(colors: [
                          AppColors.neonGreen.withValues(alpha: 0.24),
                          AppColors.neonGreen.withValues(alpha: 0.08),
                        ])
                      : isReached
                          ? LinearGradient(colors: [
                              AppColors.neonGreen.withValues(alpha: 0.12),
                              AppColors.neonGreen.withValues(alpha: 0.04),
                            ])
                          : null,
              color: (isLostRow || isActiveRow || isReached)
                  ? null
                  : AppColors.bgCard.withValues(alpha: 0.4),
              border: Border.all(
                color: isLostRow
                    ? AppColors.neonRed.withValues(alpha: 0.55)
                    : isActiveRow
                        ? AppColors.neonGreen.withValues(alpha: 0.55)
                        : isReached
                            ? AppColors.neonGreen.withValues(alpha: 0.22)
                            : AppColors.divider.withValues(alpha: 0.25),
                width: isActiveRow ? 1.4 : 1,
              ),
              boxShadow: isActiveRow
                  ? [
                      BoxShadow(
                        color: AppColors.neonGreen.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ]
                  : isLostRow
                      ? [
                          BoxShadow(
                            color: AppColors.neonRed.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
            ),
            child: Text(
              'x${mult % 1 == 0 ? mult.toInt() : mult}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActiveRow ? FontWeight.w900 : FontWeight.w700,
                color: isLostRow
                    ? AppColors.neonRed
                    : isActiveRow
                        ? AppColors.neonGreen
                        : isReached
                            ? AppColors.neonGreen.withValues(alpha: 0.75)
                            : AppColors.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Tiles
        ...List.generate(columns, (colIndex) {
          FortuneTileState tileState;

          if (revealedRow != null) {
            final isSafe = revealedRow.safeTiles.contains(colIndex);
            final isChosen = revealedRow.chosenTile == colIndex;

            if (isChosen && isSafe) {
              tileState = FortuneTileState.chosenSafe;
            } else if (isChosen && !isSafe) {
              tileState = FortuneTileState.chosenDanger;
            } else if (isSafe) {
              tileState = FortuneTileState.revealedSafe;
            } else {
              tileState = FortuneTileState.revealedDanger;
            }
          } else if (isActiveRow) {
            tileState = FortuneTileState.active;
          } else {
            tileState = FortuneTileState.hidden;
          }

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FortuneTile(
                state: tileState,
                rowIndex: rowIndex,
                colIndex: colIndex,
                animateReveal: revealedRow != null,
                onTap: isActiveRow && !loading
                    ? () {
                        HapticFeedback.mediumImpact();
                        onTileTap?.call(colIndex);
                      }
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }
}
