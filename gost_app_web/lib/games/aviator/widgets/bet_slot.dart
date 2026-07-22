// ============================================================
// BetSlot — Widget d'une mise Aviator (saisie + miser + cashout)
// Extrait d'aviator_game_screen.dart — premium redesign
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../models/aviator_models.dart';
import '../providers/aviator_provider.dart';
import 'auto_cash_out_picker.dart';

const _kAviatorOrange = Color(0xFFF97316);

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
            ? '+${bet.profit} FCFA à x${bet.cashMultiplier!.toStringAsFixed(2)}'
            : '${bet.profit} FCFA';
        resultColor = bet.profit! > 0 ? AppColors.neonGreen : AppColors.neonRed;
      } else if (!bet.cashedOut) {
        resultText = '-${bet.amount} FCFA';
        resultColor = AppColors.neonRed;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF171727),
            const Color(0xFF0D0D18),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: canCashOut
              ? _kAviatorOrange.withValues(alpha: 0.7)
              : AppColors.divider.withValues(alpha: 0.3),
          width: canCashOut ? 1.3 : 1,
        ),
        boxShadow: canCashOut
            ? [
                BoxShadow(
                  color: _kAviatorOrange.withValues(alpha: 0.28),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
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
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
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
                              horizontal: 12, vertical: 10),
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
                              ? const Color(0xFF20202F)
                              : const Color(0xFF14141E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: AppColors.divider.withValues(alpha: 0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: AppColors.divider.withValues(alpha: 0.4)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: _kAviatorOrange, width: 1.5),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: AppColors.divider.withValues(alpha: 0.2)),
                          ),
                        ),
                        style: TextStyle(
                          color: canBet ? Colors.white : Colors.white60,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        cursorColor: _kAviatorOrange,
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
          const SizedBox(height: 10),
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
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              resultColor!.withValues(alpha: 0.18),
              resultColor.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: resultColor.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: resultColor.withValues(alpha: 0.2),
              blurRadius: 10,
              spreadRadius: 0.5,
            ),
          ],
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
      return _PremiumTapButton(
        onTap: widget.onCashOut,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.neonGreen.withValues(alpha: 0.28),
                AppColors.neonGreen.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.8), width: 1.3),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonGreen.withValues(alpha: 0.35),
                blurRadius: 14,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${AppLocalizations.of(context)!.aviatorCashout}  x${provider.multiplier.toStringAsFixed(2)}  '
              '(${delta >= 0 ? '+' : ''}$delta FCFA)',
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
          gradient: LinearGradient(
            colors: [
              AppColors.neonYellow.withValues(alpha: 0.16),
              AppColors.neonYellow.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.neonYellow.withValues(alpha: 0.45)),
        ),
        child: Center(
          child: Text(
            '✓ ${AppLocalizations.of(context)!.aviatorBetPlaced} · ${bet.amount} FCFA',
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
          color: _kAviatorOrange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _kAviatorOrange.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.aviatorInFlight,
            style: const TextStyle(
              color: _kAviatorOrange,
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
          borderRadius: BorderRadius.circular(12),
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
    return _PremiumTapButton(
      onTap: canBet
          ? () async {
              // [FIX MISE] Committer le montant saisi AVANT de miser.
              // Sans ça, si le joueur tape un montant puis appuie
              // directement sur MISER (sans valider le clavier),
              // onSubmitted/onEditingComplete ne se déclenchent pas et
              // c'est l'ANCIENNE valeur (90 par défaut) qui est misée.
              _applyAmount(_ctrl.text);
              final ok = await provider.placeBet(bet);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.aviatorInsufficientBalance),
                    backgroundColor: AppColors.neonRed,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: canBet
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _kAviatorOrange.withValues(alpha: 0.9),
                    Color.lerp(_kAviatorOrange, Colors.black, 0.2)!,
                  ],
                )
              : null,
          color: canBet ? null : AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canBet
                ? _kAviatorOrange.withValues(alpha: 0.9)
                : AppColors.divider.withValues(alpha: 0.3),
          ),
          boxShadow: canBet
              ? [
                  BoxShadow(
                    color: _kAviatorOrange.withValues(alpha: 0.4),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            '${AppLocalizations.of(context)!.aviatorBetButton}  ${bet.amount} FCFA',
            style: TextStyle(
              color: canBet ? Colors.white : AppColors.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit wrapper qui ajoute un retour visuel (scale) au tap, sans changer
/// la sémantique du callback fourni (même déclenchement, même conditions).
class _PremiumTapButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _PremiumTapButton({required this.onTap, required this.child});

  @override
  State<_PremiumTapButton> createState() => _PremiumTapButtonState();
}

class _PremiumTapButtonState extends State<_PremiumTapButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.onTap != null ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
