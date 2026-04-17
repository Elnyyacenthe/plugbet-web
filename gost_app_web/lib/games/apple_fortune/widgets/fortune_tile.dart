// ============================================================
// Apple of Fortune – Single tile widget
// ============================================================
import 'package:flutter/material.dart';

enum FortuneTileState {
  hidden,     // Not yet revealed, not active
  active,     // Current row, clickable
  revealedSafe,   // Was safe (green apple)
  revealedDanger, // Was danger (skull)
  chosenSafe,     // Player picked this & it was safe
  chosenDanger,   // Player picked this & it was danger
}

class FortuneTile extends StatefulWidget {
  final FortuneTileState state;
  final VoidCallback? onTap;
  final int rowIndex;
  final int colIndex;
  final bool animateReveal;

  const FortuneTile({
    super.key,
    required this.state,
    required this.rowIndex,
    required this.colIndex,
    this.onTap,
    this.animateReveal = false,
  });

  @override
  State<FortuneTile> createState() => _FortuneTileState();
}

class _FortuneTileState extends State<FortuneTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;


  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(FortuneTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateReveal &&
        oldWidget.state != widget.state &&
        (widget.state == FortuneTileState.revealedSafe ||
            widget.state == FortuneTileState.revealedDanger ||
            widget.state == FortuneTileState.chosenSafe ||
            widget.state == FortuneTileState.chosenDanger)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.animateReveal ? _scaleAnim.value : 1.0,
          child: _buildTile(),
        );
      },
    );
  }

  Widget _buildTile() {
    final bool isClickable = widget.state == FortuneTileState.active;

    return GestureDetector(
      onTap: isClickable ? widget.onTap : null,
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: _gradient,
          border: Border.all(
            color: _borderColor,
            width: widget.state == FortuneTileState.active ? 2.0 : 1.5,
          ),
          boxShadow: [
            if (widget.state == FortuneTileState.active)
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            if (widget.state == FortuneTileState.chosenSafe)
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.5),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            if (widget.state == FortuneTileState.chosenDanger)
              BoxShadow(
                color: const Color(0xFFFF1744).withValues(alpha: 0.5),
                blurRadius: 16,
                spreadRadius: 2,
              ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(child: _buildIcon(constraints.maxWidth));
          },
        ),
        ),
      ),
    );
  }

  LinearGradient get _gradient {
    switch (widget.state) {
      case FortuneTileState.hidden:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2740), Color(0xFF0F1B2D)],
        );
      case FortuneTileState.active:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A20), Color(0xFF0F2810)],
        );
      case FortuneTileState.revealedSafe:
      case FortuneTileState.chosenSafe:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        );
      case FortuneTileState.revealedDanger:
      case FortuneTileState.chosenDanger:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B0000), Color(0xFFB71C1C)],
        );
    }
  }

  Color get _borderColor {
    switch (widget.state) {
      case FortuneTileState.hidden:
        return const Color(0xFF2A3F5F);
      case FortuneTileState.active:
        return const Color(0xFF00E676).withValues(alpha: 0.6);
      case FortuneTileState.revealedSafe:
        return const Color(0xFF4CAF50);
      case FortuneTileState.chosenSafe:
        return const Color(0xFF00E676);
      case FortuneTileState.revealedDanger:
        return const Color(0xFFE53935);
      case FortuneTileState.chosenDanger:
        return const Color(0xFFFF1744);
    }
  }

  Widget _buildIcon(double s) {
    final iconSize = s * 0.42;
    final emojiSize = s * 0.44;
    final emojiBig = s * 0.48;

    switch (widget.state) {
      case FortuneTileState.hidden:
        return Icon(
          Icons.help_outline_rounded,
          color: const Color(0xFF4A5568),
          size: iconSize,
        );
      case FortuneTileState.active:
        return Icon(
          Icons.touch_app_rounded,
          color: const Color(0xFF00E676).withValues(alpha: 0.8),
          size: iconSize,
        );
      case FortuneTileState.revealedSafe:
        return Text('🍏', style: TextStyle(fontSize: emojiSize));
      case FortuneTileState.chosenSafe:
        return Text('🍏', style: TextStyle(fontSize: emojiBig));
      case FortuneTileState.revealedDanger:
        return Text('💀', style: TextStyle(fontSize: emojiSize));
      case FortuneTileState.chosenDanger:
        return Text('💣', style: TextStyle(fontSize: emojiBig));
    }
  }
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
