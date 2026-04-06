// ============================================================
// LIVE MATCH WRAPPER - Ajoute animations aux matchs live
// Enveloppe le MatchCard existant avec des effets visuels
// ============================================================

import 'package:flutter/material.dart';
import '../models/football_models.dart';
import 'match_card.dart';

class LiveMatchWrapper extends StatefulWidget {
  final FootballMatch match;
  final VoidCallback? onTap;
  final int animationIndex;

  const LiveMatchWrapper({
    super.key,
    required this.match,
    this.onTap,
    this.animationIndex = 0,
  });

  @override
  State<LiveMatchWrapper> createState() => _LiveMatchWrapperState();
}

class _LiveMatchWrapperState extends State<LiveMatchWrapper>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulseController;
  int? _previousHomeScore;
  int? _previousAwayScore;
  bool _showGoalAnimation = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    if (widget.match.status.isLive) {
      _pulseController.repeat();
    }

    _previousHomeScore = widget.match.score.homeFullTime;
    _previousAwayScore = widget.match.score.awayFullTime;
  }

  @override
  void didUpdateWidget(LiveMatchWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Détecter nouveau but pour animation
    final currentHomeScore = widget.match.score.homeFullTime ?? 0;
    final currentAwayScore = widget.match.score.awayFullTime ?? 0;
    final oldHomeScore = _previousHomeScore ?? 0;
    final oldAwayScore = _previousAwayScore ?? 0;

    if (currentHomeScore > oldHomeScore || currentAwayScore > oldAwayScore) {
      _triggerGoalAnimation();
    }

    _previousHomeScore = currentHomeScore;
    _previousAwayScore = currentAwayScore;

    // Gérer l'animation pulse pour les matchs live
    if (widget.match.status.isLive && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!widget.match.status.isLive && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  void _triggerGoalAnimation() {
    setState(() => _showGoalAnimation = true);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showGoalAnimation = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      transform: Matrix4.identity()
        ..scale(_showGoalAnimation ? 1.05 : 1.0),
      child: Stack(
        children: [
          // Animation goal en arrière-plan
          if (_showGoalAnimation)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.green.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

          // Card du match
          MatchCard(
            match: widget.match,
            onTap: widget.onTap,
            animationIndex: widget.animationIndex,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
}
