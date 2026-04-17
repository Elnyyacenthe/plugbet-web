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
        // Multiplier label on left
        SizedBox(
          width: 52,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isLostRow
                  ? AppColors.neonRed.withValues(alpha: 0.15)
                  : isActiveRow
                      ? AppColors.neonGreen.withValues(alpha: 0.12)
                      : isReached
                          ? AppColors.neonGreen.withValues(alpha: 0.06)
                          : Colors.transparent,
              border: Border.all(
                color: isLostRow
                    ? AppColors.neonRed.withValues(alpha: 0.4)
                    : isActiveRow
                        ? AppColors.neonGreen.withValues(alpha: 0.4)
                        : isReached
                            ? AppColors.neonGreen.withValues(alpha: 0.15)
                            : AppColors.divider.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              'x${mult % 1 == 0 ? mult.toInt() : mult}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActiveRow ? FontWeight.w800 : FontWeight.w600,
                color: isLostRow
                    ? AppColors.neonRed
                    : isActiveRow
                        ? AppColors.neonGreen
                        : isReached
                            ? AppColors.neonGreen.withValues(alpha: 0.7)
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
