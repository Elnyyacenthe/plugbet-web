// ============================================================
// SlotReel — Un rouleau (vertical scrolling band)
// ============================================================
// Spin = animation Y rapide (random symboles defilent), puis arret
// sur le symbole final fourni. Decelration via Curves.easeOutCubic.
// Les 3 rouleaux s'arretent en cascade (delais 0ms / 250ms / 500ms)
// gere par l'ecran parent.
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/slot_models.dart';

class SlotReel extends StatefulWidget {
  final SlotSymbol target;     // symbole final apres spin
  final bool spinning;         // true = en train de tourner
  final Duration duration;     // temps total du spin
  final double tileHeight;
  final double width;

  const SlotReel({
    super.key,
    required this.target,
    required this.spinning,
    this.duration = const Duration(milliseconds: 1800),
    this.tileHeight = 80,
    this.width = 80,
  });

  @override
  State<SlotReel> createState() => _SlotReelState();
}

class _SlotReelState extends State<SlotReel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  late List<SlotSymbol> _band; // bande de symboles affichee
  final _rng = Random();

  static const int _spinTiles = 24; // nb de tuiles avant l'arret

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _band = _generateBand(widget.target);
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() {});
    });
    if (widget.spinning) _start();
  }

  @override
  void didUpdateWidget(covariant SlotReel old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !old.spinning) {
      _band = _generateBand(widget.target);
      _ctrl.reset();
      _start();
    }
    if (widget.target != old.target && !widget.spinning) {
      // Si la cible change hors spin, juste re-affiche
      _band = _generateBand(widget.target);
      _ctrl.value = 1.0;
      setState(() {});
    }
  }

  void _start() => _ctrl.forward(from: 0);

  /// Genere une bande : [N tuiles aleatoires] + target en position N
  List<SlotSymbol> _generateBand(SlotSymbol target) {
    final list = <SlotSymbol>[];
    for (int i = 0; i < _spinTiles; i++) {
      list.add(SlotSymbol.values[_rng.nextInt(SlotSymbol.values.length - 1)]);
    }
    list.add(target);
    return list;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: widget.width,
        height: widget.tileHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFE082), // doré clair
              const Color(0xFFFFB300), // doré profond
              const Color(0xFFFFE082),
            ],
            stops: const [0, 0.5, 1],
          ),
          border: Border.all(color: const Color(0xFF7A4F00), width: 2),
        ),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            // offset Y : on commence en haut (offset negatif) et on glisse
            // jusqu'a target (position _spinTiles, donc -spinTiles * h)
            final totalDist = _spinTiles * widget.tileHeight;
            final dy = -totalDist * _anim.value;

            // Si pas spinning : affiche juste target
            if (!widget.spinning && _ctrl.value == 0) {
              return _tile(widget.target);
            }
            return Transform.translate(
              offset: Offset(0, dy + (_spinTiles * widget.tileHeight)),
              child: Column(
                children: _band.map(_tile).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tile(SlotSymbol s) {
    final isSeven = s.isSeven;
    final isBar = s.isWildBar;
    Widget child;
    if (isSeven) {
      child = Text(
        '7',
        style: TextStyle(
          fontSize: widget.tileHeight * 0.55,
          fontWeight: FontWeight.w900,
          color: AppColors.neonRed,
          shadows: [
            Shadow(
              color: AppColors.neonRed.withValues(alpha: 0.6),
              blurRadius: 12,
            ),
          ],
          height: 1,
        ),
      );
    } else if (isBar) {
      child = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFFD600), width: 1.5),
        ),
        child: const Text('BAR',
            style: TextStyle(
              color: Color(0xFFFFD600),
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1,
            )),
      );
    } else {
      child = Text(
        s.emoji,
        style: TextStyle(
          fontSize: widget.tileHeight * 0.5,
          height: 1,
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.tileHeight,
      child: Center(child: child),
    );
  }
}
