// ============================================================
// LUDO MODULE - Widget De anime 3D
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';

class LudoDiceWidget extends StatefulWidget {
  final int? value;
  final bool isRolling;
  final bool enabled;
  final VoidCallback? onTap;

  const LudoDiceWidget({
    super.key,
    this.value,
    this.isRolling = false,
    this.enabled = true,
    this.onTap,
  });

  @override
  State<LudoDiceWidget> createState() => _LudoDiceWidgetState();
}

class _LudoDiceWidgetState extends State<LudoDiceWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _flipController;
  late Animation<double> _scale;
  late Animation<double> _rotX;
  late Animation<double> _rotY;
  int _displayValue = 1;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.85), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.1), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _rotX = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeOut),
    );
    _rotY = Tween<double>(begin: 0, end: pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeOut),
    );

    _controller.addListener(() {
      if (_controller.isAnimating) {
        setState(() {
          _displayValue = _random.nextInt(6) + 1;
        });
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.value != null) {
        setState(() {
          _displayValue = widget.value!;
        });
      }
    });

    if (widget.value != null) {
      _displayValue = widget.value!;
    }
  }

  @override
  void didUpdateWidget(LudoDiceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRolling && !oldWidget.isRolling) {
      _controller.forward(from: 0);
      _flipController.forward(from: 0);
    }
    if (!widget.isRolling && widget.value != null) {
      _displayValue = widget.value!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedBuilder(
        listenable: Listenable.merge([_controller, _flipController]),
        builder: (context, child) {
          final isAnimating = _controller.isAnimating;
          return Transform.scale(
            scale: isAnimating ? _scale.value : 1.0,
            child: Transform(
              alignment: Alignment.center,
              transform: isAnimating
                  ? (Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(_rotX.value * 0.5)
                    ..rotateY(_rotY.value * 0.3))
                  : Matrix4.identity(),
              child: child,
            ),
          );
        },
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: widget.enabled ? Colors.white : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.enabled
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(2, 5),
              ),
              if (widget.enabled)
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.15),
                  blurRadius: 2,
                  offset: const Offset(-1, -1),
                ),
            ],
            border: Border.all(
              color: widget.enabled
                  ? const Color(0xFF263238)
                  : Colors.grey.shade400,
              width: 2,
            ),
            gradient: widget.enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFAFAFA), Color(0xFFE8E8E8)],
                  )
                : null,
          ),
          child: _buildDiceFace(_displayValue),
        ),
      ),
    );
  }

  Widget _buildDiceFace(int value) {
    final dotColor = widget.enabled ? const Color(0xFF263238) : Colors.grey;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: _getDotLayout(value, dotColor),
    );
  }

  Widget _getDotLayout(int value, Color dotColor) {
    switch (value) {
      case 1:
        return Center(child: _dot(dotColor, 14));
      case 2:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Align(alignment: Alignment.topRight, child: _dot(dotColor, 10)),
            Align(alignment: Alignment.bottomLeft, child: _dot(dotColor, 10)),
          ],
        );
      case 3:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Align(alignment: Alignment.topRight, child: _dot(dotColor, 10)),
            Center(child: _dot(dotColor, 10)),
            Align(alignment: Alignment.bottomLeft, child: _dot(dotColor, 10)),
          ],
        );
      case 4:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_dot(dotColor, 10), _dot(dotColor, 10)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_dot(dotColor, 10), _dot(dotColor, 10)],
            ),
          ],
        );
      case 5:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_dot(dotColor, 9), _dot(dotColor, 9)],
            ),
            Center(child: _dot(dotColor, 9)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_dot(dotColor, 9), _dot(dotColor, 9)],
            ),
          ],
        );
      case 6:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_dot(dotColor, 9), _dot(dotColor, 9)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_dot(dotColor, 9), _dot(dotColor, 9)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_dot(dotColor, 9), _dot(dotColor, 9)],
            ),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  Widget _dot(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
