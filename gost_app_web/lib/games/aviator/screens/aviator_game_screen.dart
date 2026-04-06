// ============================================================
// AVIATOR – Écran de jeu principal
// Courbe multiplicateur + avion animé + 2 mises + chat
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../models/aviator_models.dart';
import '../providers/aviator_provider.dart';
import '../widgets/multiplier_curve_painter.dart';

class AviatorGameScreen extends StatelessWidget {
  final bool demoMode;
  const AviatorGameScreen({super.key, this.demoMode = false});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AviatorProvider()..isDemoMode = demoMode,
      child: const _AviatorBody(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _AviatorBody extends StatefulWidget {
  const _AviatorBody();
  @override
  State<_AviatorBody> createState() => _AviatorBodyState();
}

class _AviatorBodyState extends State<_AviatorBody>
    with TickerProviderStateMixin {
  // Animation du multiplicateur (texte pulse)
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Animation crash (shake)
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onPhaseCrashed() {
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
  }

  void _onCashOut(AviatorProvider prov, AviatorBet bet) {
    HapticFeedback.mediumImpact();
    prov.cashOut(bet);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Consumer<AviatorProvider>(
      builder: (ctx, prov, _) {
        // Détecter crash pour animation
        if (prov.phase == AviatorPhase.crashed &&
            _shakeCtrl.status == AnimationStatus.dismissed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _onPhaseCrashed());
        }

        return Scaffold(
          backgroundColor: const Color(0xFF090912),
          appBar: _buildAppBar(prov, wallet),
          body: Column(
            children: [
              // ── Historique crashes ──────────────────────
              _buildCrashHistory(prov),

              // ── Zone de jeu principale ──────────────────
              Expanded(child: _buildGameArea(prov)),

              // ── Panneau mises ───────────────────────────
              _buildBetPanel(prov),
            ],
          ),
        );
      },
    );
  }

  // ─── AppBar ──────────────────────────────────────────────
  AppBar _buildAppBar(AviatorProvider prov, WalletProvider wallet) {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D1A),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Text('✈ ', style: TextStyle(fontSize: 16)),
          Text('Aviator',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          if (prov.isDemoMode) ...[
            SizedBox(width: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.5)),
              ),
              child: Text('DÉMO',
                  style: TextStyle(
                      color: AppColors.neonBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
      actions: [
        // Solde coins
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Icon(Icons.monetization_on,
                  color: AppColors.neonYellow, size: 16),
              SizedBox(width: 4),
              Text(
                prov.isDemoMode ? '∞' : '${wallet.coins}',
                style: TextStyle(
                    color: AppColors.neonYellow,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ],
          ),
        ),
        // Toggle demo
        IconButton(
          icon: Icon(
            prov.isDemoMode ? Icons.money_off : Icons.play_circle,
            color: AppColors.textMuted,
            size: 20,
          ),
          tooltip: prov.isDemoMode ? 'Quitter démo' : 'Mode démo',
          onPressed: prov.toggleDemo,
        ),
      ],
    );
  }

  // ─── Historique crashes ──────────────────────────────────
  Widget _buildCrashHistory(AviatorProvider prov) {
    final history = prov.crashHistory;
    return Container(
      height: 36,
      color: const Color(0xFF0D0D1A),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: history.length,
        itemBuilder: (_, i) {
          final r = history[i];
          final color = r.isEarly
              ? const Color(0xFFEF4444)
              : r.isMid
                  ? AppColors.neonOrange
                  : AppColors.neonGreen;
          return Container(
            margin: EdgeInsets.only(right: 6),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              'x${r.crashPoint.toStringAsFixed(2)}',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          );
        },
      ),
    );
  }

  // ─── Zone de jeu ─────────────────────────────────────────
  Widget _buildGameArea(AviatorProvider prov) {
    // Progress de la courbe : log scale depuis 0
    // mult=0 → 0.0 | mult=1 → 0.14 | mult=5 → 0.41 | mult=50 → 0.95
    final progress = prov.phase == AviatorPhase.waiting
        ? 0.0
        : (log(1.0 + prov.multiplier.clamp(0.0, 9999)) / log(51))
            .clamp(0.0, 0.95);

    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (ctx, child) {
        final shake = prov.phase == AviatorPhase.crashed
            ? sin(_shakeAnim.value * pi) * 6
            : 0.0;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: child,
        );
      },
      child: Stack(
        children: [
          // Fond étoilé
          _StarField(),

          // Courbe multiplicateur
          Positioned.fill(
            child: CustomPaint(
              painter: MultiplierCurvePainter(
                progress: progress,
                multiplier: prov.multiplier,
                crashed: prov.phase == AviatorPhase.crashed,
                waiting: prov.phase == AviatorPhase.waiting,
              ),
            ),
          ),

          // ── Avion ──────────────────────────────────────
          if (prov.phase != AviatorPhase.waiting)
            _PlaneWidget(
              progress: progress,
              multiplier: prov.multiplier,
              crashed: prov.phase == AviatorPhase.crashed,
            ),

          // ── Multiplicateur central ─────────────────────
          Center(
            child: _buildMultiplierDisplay(prov),
          ),

          // ── Seeds provably fair (après crash) ──────────
          if (prov.phase == AviatorPhase.crashed)
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: _buildProvablyFair(prov),
            ),
        ],
      ),
    );
  }

  Widget _buildMultiplierDisplay(AviatorProvider prov) {
    if (prov.phase == AviatorPhase.waiting) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PROCHAIN VOL DANS',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1)),
          SizedBox(height: 6),
          Text(
            '${prov.countdownSecs}s',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 52,
                fontWeight: FontWeight.w900),
          ),
        ],
      );
    }

    if (prov.phase == AviatorPhase.crashed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CRASHÉ !',
              style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          SizedBox(height: 4),
          Text(
            'x${prov.multiplier.toStringAsFixed(2)}',
            style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 56,
                fontWeight: FontWeight.w900),
          ),
        ],
      );
    }

    // Phase flying
    return ScaleTransition(
      scale: _pulseAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'x${prov.multiplier.toStringAsFixed(2)}',
            style: TextStyle(
              color: prov.multiplier >= 10
                  ? AppColors.neonGreen
                  : const Color(0xFFF97316),
              fontSize: 58,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: (prov.multiplier >= 10
                          ? AppColors.neonGreen
                          : const Color(0xFFF97316))
                      .withValues(alpha: 0.5),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
          if (prov.bet1.autoCashOut != null || prov.bet2.autoCashOut != null)
            Text(
              'Auto: x${(prov.bet1.autoCashOut ?? prov.bet2.autoCashOut)!.toStringAsFixed(2)}',
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildProvablyFair(AviatorProvider prov) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔒 Provably Fair',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          _seedRow('Server', prov.serverSeed),
          _seedRow('Client', prov.clientSeed),
          _seedRow('Hash', prov.roundHash),
        ],
      ),
    );
  }

  Widget _seedRow(String label, String value) {
    return Row(
      children: [
        Text('$label: ',
            style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
                fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  // ─── Panneau mises ───────────────────────────────────────
  Widget _buildBetPanel(AviatorProvider prov) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(
            top: BorderSide(
                color: AppColors.divider.withValues(alpha: 0.3))),
      ),
      child: Column(
        children: [
          // Mise 1 (toujours visible)
          _BetSlot(
            bet: prov.bet1,
            provider: prov,
            onCashOut: () => _onCashOut(prov, prov.bet1),
          ),

          // Mise 2 (optionnelle)
          if (prov.showBet2) ...[
            SizedBox(height: 8),
            _BetSlot(
              bet: prov.bet2,
              provider: prov,
              onCashOut: () => _onCashOut(prov, prov.bet2),
            ),
          ],

          SizedBox(height: 8),

          // Bouton toggle 2ème mise
          GestureDetector(
            onTap: prov.toggleBet2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  prov.showBet2 ? Icons.remove_circle_outline : Icons.add_circle_outline,
                  color: AppColors.textMuted,
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  prov.showBet2 ? 'Retirer 2ème mise' : '+ Ajouter 2ème mise',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────
// Widget : Slot de mise (saisie libre + mise/cashout)
// ─────────────────────────────────────────────────────────────
class _BetSlot extends StatefulWidget {
  final AviatorBet bet;
  final AviatorProvider provider;
  final VoidCallback onCashOut;

  const _BetSlot({
    required this.bet,
    required this.provider,
    required this.onCashOut,
  });

  @override
  State<_BetSlot> createState() => _BetSlotState();
}

class _BetSlotState extends State<_BetSlot> {
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
      // Ramener au minimum si trop bas
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
    // Mises UNIQUEMENT pendant le countdown (avant décollage)
    final canBet = !bet.placed && phase == AviatorPhase.waiting;
    final canCashOut =
        bet.placed && !bet.cashedOut && phase == AviatorPhase.flying;
    final isWaiting = phase == AviatorPhase.waiting;

    // Sync input when bet resets between rounds
    if (!_editing && _ctrl.text != '${bet.amount}') {
      _ctrl.text = '${bet.amount}';
    }

    // Résultat affiché après le round
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
      padding: EdgeInsets.all(10),
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
              // ── Montant (saisie libre) ────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MISE ${bet.slot}',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    SizedBox(height: 6),
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
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          hintText: 'coins',
                          hintStyle: TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                          suffixText: 'coins',
                          suffixStyle: TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
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
                          color: canBet
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(width: 8),

              // ── Auto cash out ─────────────────────────
              if (!bet.placed)
                _AutoCashOutPicker(
                  value: bet.autoCashOut,
                  onChanged: (v) => provider.setAutoCashOut(bet, v),
                ),
            ],
          ),

          SizedBox(height: 8),

          // ── Bouton principal ──────────────────────────
          if (resultText != null)
            // Affichage résultat
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 10),
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
                      fontSize: 14),
                ),
              ),
            )
          else if (canCashOut)
            // Bouton CASHOUT (vert pulsant)
            GestureDetector(
              onTap: widget.onCashOut,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.neonGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.neonGreen.withValues(alpha: 0.7)),
                ),
                child: Center(
                  child: Text(
                    'CASHOUT  x${provider.multiplier.toStringAsFixed(2)}  '
                    '(${((bet.amount * provider.multiplier).floor() - bet.amount) >= 0 ? '+' : ''}${(bet.amount * provider.multiplier).floor() - bet.amount} coins)',
                    style: TextStyle(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 13),
                  ),
                ),
              ),
            )
          else if (bet.placed && !bet.cashedOut && isWaiting)
            // Mise placée, attend décollage
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.neonYellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.neonYellow.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(
                  '✓ Mise placée · ${bet.amount} coins',
                  style: TextStyle(
                      color: AppColors.neonYellow,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            )
          else if (bet.placed && !bet.cashedOut)
            // En vol, pas encore cashout
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFF97316).withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  'EN VOL...',
                  style: TextStyle(
                      color: Color(0xFFF97316),
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            )
          else if (!bet.placed && phase == AviatorPhase.flying)
            // Avion en vol, plus possible de miser
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  '✈  Misez avant le prochain décollage',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic),
                ),
              ),
            )
          else
            // Bouton MISER (actif uniquement pendant countdown)
            GestureDetector(
              onTap: canBet
                  ? () async {
                      final ok = await provider.placeBet(bet);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Solde insuffisant ou mise invalide.'),
                            backgroundColor: AppColors.neonRed,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  : null,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 12),
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
                    'MISER  ${bet.amount} COINS',
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
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Widget : Sélecteur auto cash out
// ─────────────────────────────────────────────────────────────
class _AutoCashOutPicker extends StatelessWidget {
  final double? value;
  final void Function(double?) onChanged;

  const _AutoCashOutPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [null, 1.5, 2.0, 3.0, 5.0, 10.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Auto',
            style:
                TextStyle(color: AppColors.textMuted, fontSize: 9)),
        SizedBox(height: 4),
        DropdownButton<double?>(
          value: value,
          isDense: true,
          dropdownColor: const Color(0xFF1A1A2E),
          underline: SizedBox(),
          style:
              TextStyle(color: AppColors.textSecondary, fontSize: 11),
          items: options
              .map((v) => DropdownMenuItem<double?>(
                    value: v,
                    child: Text(v == null ? 'Manuel' : 'x${v.toStringAsFixed(1)}'),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Widget : Avion animé
// ─────────────────────────────────────────────────────────────
class _PlaneWidget extends StatelessWidget {
  final double progress;
  final double multiplier;
  final bool crashed;

  const _PlaneWidget({
    required this.progress,
    required this.multiplier,
    required this.crashed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pos = MultiplierCurvePainter.planePosition(size, progress, multiplier);

        // Angle : -45° au départ (x0), tend vers -10° en altitude
        final yRatio = (log(1.0 + multiplier.clamp(0.0, 9999)) / log(51)).clamp(0.0, 1.0);
        final angle = crashed
            ? pi / 4  // tombé → tourne vers le bas
            : -pi / 4 + yRatio * pi / 6; // -45° → -15° en montant

        return Stack(
          children: [
            Positioned(
              left: pos.dx - 20,
              top: pos.dy - 20,
              child: Transform.rotate(
                angle: angle,
                child: Text(
                  crashed ? '💥' : '✈',
                  style: TextStyle(
                    fontSize: crashed ? 28 : 24,
                    shadows: [
                      Shadow(
                        color: crashed
                            ? const Color(0xFFEF4444)
                            : const Color(0xFFF97316),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Widget : Fond étoilé
// ─────────────────────────────────────────────────────────────
class _StarField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarPainter(),
      child: Container(),
    );
  }
}

class _StarPainter extends CustomPainter {
  static final _stars = List.generate(60, (i) {
    final r = Random(i * 31 + 7);
    return Offset(r.nextDouble(), r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.25);
    for (final s in _stars) {
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}
