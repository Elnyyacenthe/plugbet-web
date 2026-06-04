// ============================================================
// BetSelector — Mise libre + chips de raccourci
// ============================================================
// 2 zones :
//   1. Quick-pick chips (10/50/100/500/1000 FCFA) : tap = bet direct
//   2. Champ libre 'Personnalise' : taper n'importe quel entier
//      dans [kMinBet, kMaxBet] (10..1000 FCFA).
//
// La valeur tapee remplace la selection chip des qu'elle est valide.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../models/slot_models.dart';

class BetSelector extends StatefulWidget {
  final int current;
  final bool disabled;
  final ValueChanged<int> onChanged;

  const BetSelector({
    super.key,
    required this.current,
    required this.onChanged,
    this.disabled = false,
  });

  @override
  State<BetSelector> createState() => _BetSelectorState();
}

class _BetSelectorState extends State<BetSelector> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.current}');
  }

  @override
  void didUpdateWidget(covariant BetSelector old) {
    super.didUpdateWidget(old);
    // Si le parent change la mise (chip tap) et que le champ n'est
    // pas focus, on resync le texte.
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
    if (!isValidBet(n)) {
      setState(() => _error = 'Mise entre $kMinBet et $kMaxBet FCFA');
      return;
    }
    setState(() => _error = null);
    widget.onChanged(n);
  }

  void _pick(int b) {
    if (widget.disabled) return;
    _ctrl.text = '$b';
    setState(() => _error = null);
    widget.onChanged(b);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Quick-pick chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: kQuickBetLevels.map((b) {
            final selected = b == widget.current;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _pick(b),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.neonGreen
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppColors.neonGreen
                          : Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: AppColors.neonGreen.withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: Text('$b FCFA',
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      )),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 10),
      // Champ libre
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: !widget.disabled,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Mise libre ($kMinBet-$kMaxBet)',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                errorText: _error,
                errorStyle: TextStyle(
                  color: AppColors.neonRed,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                suffixText: 'FCFA',
                suffixStyle: TextStyle(
                  color: AppColors.neonYellow,
                  fontSize: 11,
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
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.neonRed, width: 1.5),
                ),
              ),
              onChanged: _onTextChanged,
            ),
          ),
        ]),
      ),
    ]);
  }
}
