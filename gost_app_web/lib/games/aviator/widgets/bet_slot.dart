// ============================================================
// BetSlot — Widget d'une mise Aviator (saisie + miser + cashout)
// Extrait d'aviator_game_screen.dart
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../models/aviator_models.dart';
import '../providers/aviator_provider.dart';
import 'auto_cash_out_picker.dart';

class BetSlot extends StatefulWidget {
  final AviatorBet bet;
  final AviatorProvider provider;
  final VoidCallback onCashOut;

  const BetSlot({
    super.key,
    required this.bet,
    required this.provider,
    required this.onCashOut,
  });

  @override
  State<BetSlot> createState() => _BetSlotState();
}

class _BetSlotState extends State<BetSlot> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.bet.amount}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _applyAmount(String v) {
    final n = int.tryParse(v);
    if (n != null && n >= 90) {
      widget.provider.setBetAmount(widget.bet, n);
    } else if (n != null && n < 90) {
      widget.provider.setBetAmount(widget.bet, 90);
      _ctrl.text = '90';
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final bet = widget.bet;
    final provider = widget.provider;
    final phase = provider.phase;
    final canBet = !bet.placed && phase == AviatorPhase.waiting;
    final canCashOut =
        bet.placed && !bet.cashedOut && phase == AviatorPhase.flying;
    final isWaiting = phase == AviatorPhase.waiting;

    if (!_editing && _ctrl.text != '${bet.amount}') {
      _ctrl.text = '${bet.amount}';
    }

    String? resultText;
    Color? resultColor;
    if (bet.placed && phase == AviatorPhase.crashed) {
      if (bet.cashedOut && bet.profit != null) {
        resultText = bet.profit! > 0
            ? '+${bet.profit} coins à x${bet.cashMultiplier!.toStringAsFixed(2)}'
            : '${bet.profit} coins';
        resultColor = bet.profit! > 0 ? AppColors.neonGreen : AppColors.neonRed;
      } else if (!bet.cashedOut) {
        resultText = '-${bet.amount} coins';
        resultColor = AppColors.neonRed;
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: canCashOut
              ? const Color(0xFFF97316).withValues(alpha: 0.6)
              : AppColors.divider.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.aviatorSlot('${bet.slot}'),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _ctrl,
                        enabled: canBet,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onTap: () => setState(() => _editing = true),
                        onSubmitted: _applyAmount,
                        onEditingComplete: () => _applyAmount(_ctrl.text),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          hintText: 'coins',
                          hintStyle: const TextStyle(
                              color: Colors.white38, fontSize: 13),
                          suffixText: 'coins',
                          suffixStyle: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                          filled: true,
                          fillColor: canBet
                              ? const Color(0xFF1E1E2E)
                              : const Color(0xFF14141E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: AppColors.divider.withValues(alpha: 0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: AppColors.divider.withValues(alpha: 0.4)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFFF97316), width: 1.5),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: AppColors.divider.withValues(alpha: 0.2)),
                          ),
                        ),
                        style: TextStyle(
                          color: canBet ? Colors.white : Colors.white60,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        cursorColor: const Color(0xFFF97316),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!bet.placed)
                AutoCashOutPicker(
                  value: bet.autoCashOut,
                  onChanged: (v) => provider.setAutoCashOut(bet, v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildActionButton(resultText, resultColor, canBet, canCashOut,
              isWaiting, phase, provider, bet),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String? resultText,
    Color? resultColor,
    bool canBet,
    bool canCashOut,
    bool isWaiting,
    AviatorPhase phase,
    AviatorProvider provider,
    AviatorBet bet,
  ) {
    if (resultText != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: resultColor!.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: resultColor.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Text(
            resultText,
            style: TextStyle(
              color: resultColor,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    if (canCashOut) {
      final delta =
          (bet.amount * provider.multiplier).floor() - bet.amount;
      return GestureDetector(
        onTap: widget.onCashOut,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.neonGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.7)),
          ),
          child: Center(
            child: Text(
              '${AppLocalizations.of(context)!.aviatorCashout}  x${provider.multiplier.toStringAsFixed(2)}  '
              '(${delta >= 0 ? '+' : ''}$delta coins)',
              style: TextStyle(
                color: AppColors.neonGreen,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    if (bet.placed && !bet.cashedOut && isWaiting) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.neonYellow.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.neonYellow.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Text(
            '✓ ${AppLocalizations.of(context)!.aviatorBetPlaced} · ${bet.amount} coins',
            style: TextStyle(
              color: AppColors.neonYellow,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    if (bet.placed && !bet.cashedOut) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF97316).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFFF97316).withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.aviatorInFlight,
            style: const TextStyle(
              color: Color(0xFFF97316),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    if (!bet.placed && phase == AviatorPhase.flying) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.aviatorBetBeforeTakeoff,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    // Bouton MISER
    return GestureDetector(
      onTap: canBet
          ? () async {
              final ok = await provider.placeBet(bet);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.aviatorInsufficientBalance),
                    backgroundColor: AppColors.neonRed,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: canBet
              ? const Color(0xFFF97316).withValues(alpha: 0.15)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: canBet
                ? const Color(0xFFF97316).withValues(alpha: 0.7)
                : AppColors.divider.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: Text(
            '${AppLocalizations.of(context)!.aviatorBetButton}  ${bet.amount} COINS',
            style: TextStyle(
              color: canBet
                  ? const Color(0xFFF97316)
                  : AppColors.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
