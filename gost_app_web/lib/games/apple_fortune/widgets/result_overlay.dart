// ============================================================
// Apple of Fortune – Result overlay (win / loss)
// ============================================================
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class ResultOverlay extends StatefulWidget {
  final bool isWin;
  final int amount; // winnings or lost bet
  final double multiplier;
  final VoidCallback onDismiss;

  const ResultOverlay({
    super.key,
    required this.isWin,
    required this.amount,
    required this.multiplier,
    required this.onDismiss,
  });

  @override
  State<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<ResultOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller, curve: const Interval(0, 0.3, curve: Curves.easeIn)),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: Center(
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: _buildCard(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard() {
    final color = widget.isWin ? AppColors.neonGreen : AppColors.neonRed;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0E1A2E),
            widget.isWin ? const Color(0xFF0A2010) : const Color(0xFF200A0A),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Text(
            widget.isWin ? '🎉' : '💥',
            style: const TextStyle(fontSize: 56),
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            widget.isWin ? 'CASH OUT !' : 'PERDU !',
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),

          // Multiplier
          if (widget.isWin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: color.withValues(alpha: 0.15),
              ),
              child: Text(
                'x${widget.multiplier.toStringAsFixed(2)}',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.monetization_on,
                  color: AppColors.neonYellow, size: 24),
              const SizedBox(width: 6),
              Text(
                widget.isWin ? '+${widget.amount}' : '-${widget.amount}',
                style: TextStyle(
                  color: widget.isWin ? AppColors.neonYellow : AppColors.neonRed,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Dismiss button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: widget.onDismiss,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                widget.isWin ? 'CONTINUER' : 'REJOUER',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
