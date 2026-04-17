// ============================================================
// AutoCashOutPicker — Dropdown de cash out automatique
// (Manuel, x1.5, x2.0, x3.0, x5.0, x10.0)
// ============================================================
import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/app_theme.dart';

class AutoCashOutPicker extends StatelessWidget {
  final double? value;
  final void Function(double?) onChanged;

  const AutoCashOutPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final options = <double?>[null, 1.5, 2.0, 3.0, 5.0, 10.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          t.aviatorAuto,
          style: TextStyle(color: AppColors.textMuted, fontSize: 9),
        ),
        const SizedBox(height: 4),
        DropdownButton<double?>(
          value: value,
          isDense: true,
          dropdownColor: const Color(0xFF1A1A2E),
          underline: const SizedBox(),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          items: options
              .map(
                (v) => DropdownMenuItem<double?>(
                  value: v,
                  child: Text(
                    v == null ? t.aviatorManual : 'x${v.toStringAsFixed(1)}',
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
