// ============================================================
// AmountInput — Selection du montant a deposer sur une tuile
// ============================================================
// Pattern aligne avec Penalty/Slots : champ texte libre + 4 chips
// raccourcis. La valeur saisie devient le "montant a deposer". Le
// joueur tap ensuite une tuile (1/2/5/10/20/40) pour deposer le
// montant courant dessus.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../models/wheel_models.dart';

class AmountInput extends StatefulWidget {
  final int current;
  final bool disabled;
  final ValueChanged<int> onChanged;

  const AmountInput({
    super.key,
    required this.current,
    required this.onChanged,
    this.disabled = false,
  });

  @override
  State<AmountInput> createState() => _AmountInputState();
}

class _AmountInputState extends State<AmountInput> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.current}');
  }

  @override
  void didUpdateWidget(covariant AmountInput old) {
    super.didUpdateWidget(old);
    if (widget.current != old.current && !_focus.hasFocus) {
      _ctrl.text = '${widget.current}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged(String v) {
    final n = int.tryParse(v.trim());
    if (n == null) {
      setState(() => _error = null);
      return;
    }
    if (n < kMinBetPerTile || n > kMaxBetPerTile) {
      setState(() =>
          _error = 'Mise $kMinBetPerTile – $kMaxBetPerTile FCFA');
      return;
    }
    setState(() => _error = null);
    widget.onChanged(n);
  }

  void _pickQuick(int amount) {
    if (widget.disabled) return;
    _ctrl.text = '$amount';
    setState(() => _error = null);
    widget.onChanged(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Quick-pick chips
      SizedBox(
        height: 32,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: kQuickAmounts.length,
          itemBuilder: (_, i) {
            final amount = kQuickAmounts[i];
            final isSelected = amount == widget.current;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: widget.disabled ? null : () => _pickQuick(amount),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.neonGreen
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.neonGreen
                          : Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Text('$amount',
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      )),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      // Champ libre
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          enabled: !widget.disabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText:
                'Mise libre ($kMinBetPerTile-$kMaxBetPerTile)',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            errorText: _error,
            errorStyle: TextStyle(
              color: AppColors.neonRed,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            suffixText: 'FCFA',
            suffixStyle: TextStyle(
              color: AppColors.neonYellow,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppColors.neonGreen, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.neonRed, width: 1),
            ),
          ),
          onChanged: _onTextChanged,
        ),
      ),
    ]);
  }
}
