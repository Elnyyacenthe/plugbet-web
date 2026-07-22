// ============================================================
// SlotReel — Un rouleau (vertical scrolling band)
// ============================================================
// Spin = animation Y rapide (random symboles defilent), puis arret
// sur le symbole final fourni. Decelration via Curves.easeOutCubic.
// Les 3 rouleaux s'arretent en cascade (delais 0ms / 250ms / 500ms)
// gere par l'ecran parent.
//
// >>> DESIGN PREMIUM <<<
// Seul l'habillage visuel a ete retravaille (cadre glass/neon, glow,
// fondu haut/bas type "cinema reel", tuiles plus percutantes).
// AUCUNE logique d'animation, de generation de bande ou de timing
// n'a ete modifiee.
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
      // Nouveau spin : regenerer le band + relancer l'anim
      _band = _generateBand(widget.target);
      _ctrl.reset();
      _start();
    } else if (widget.target != old.target) {
      // Le parent a recu un nouveau resultat -> remplace le DERNIER tile
      // du band avec le nouveau target. Sans ce remplacement, le scroll
      // se termine sur l'ancien target et l'utilisateur voit un symbole
      // qui ne correspond pas au resultat du serveur.
      if (_band.isNotEmpty) {
        final newBand = List<SlotSymbol>.from(_band);
        newBand[newBand.length - 1] = widget.target;
        _band = newBand;
      }
      if (!widget.spinning) {
        // Spin termine : force la position finale.
        _ctrl.value = 1.0;
        setState(() {});
      }
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
    return Container(
      // Halo neon autour du rouleau (purement decoratif)
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD600).withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Container(
              width: widget.width,
              height: widget.tileHeight,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF3C4), // dore tres clair (reflet haut)
                    Color(0xFFFFD54A), // dore clair
                    Color(0xFFFFB300), // dore profond (centre, payline)
                    Color(0xFFFFD54A), // dore clair
                    Color(0xFFFFF3C4), // reflet bas
                  ],
                  stops: [0, 0.22, 0.5, 0.78, 1],
                ),
                border: Border.all(
                  color: const Color(0xFF7A4F00).withValues(alpha: 0.9),
                  width: 2,
                ),
              ),
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, __) {
                  // offset Y : a anim=0, dy=0 -> tile 0 (random) visible en haut.
                  // A anim=1, dy=-totalDist -> Column remontee de totalDist, le
                  // DERNIER tile (target en position _spinTiles) est visible.
                  final totalDist = _spinTiles * widget.tileHeight;
                  final dy = -totalDist * _anim.value;

                  // Pas en cours d'animation : affiche directement le target
                  // (couvre le cas initial avant tout spin).
                  if (!widget.spinning && _ctrl.value == 0) {
                    return _tile(widget.target);
                  }
                  return Transform.translate(
                    offset: Offset(0, dy),
                    child: Column(
                      children: _band.map(_tile).toList(),
                    ),
                  );
                },
              ),
            ),
            // Fondu "cinema reel" en haut et en bas — effet purement
            // decoratif via IgnorePointer, ne capte aucun geste et ne
            // change rien a la logique de defilement.
            IgnorePointer(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    height: widget.tileHeight * 0.28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.38),
                          Colors.black.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    height: widget.tileHeight * 0.28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.38),
                          Colors.black.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Liseret payline central fin (indique la ligne de gain)
            IgnorePointer(
              child: Center(
                child: Container(
                  height: 1.4,
                  width: widget.width,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
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
              color: AppColors.neonRed.withValues(alpha: 0.75),
              blurRadius: 16,
            ),
            const Shadow(color: Colors.black45, blurRadius: 3),
          ],
          height: 1,
        ),
      );
    } else if (isBar) {
      child = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B1B1B), Colors.black],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFFD600), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD600).withValues(alpha: 0.45),
              blurRadius: 8,
            ),
          ],
        ),
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [Color(0xFFFFF59D), Color(0xFFFFD600)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect),
          child: const Text('BAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 1,
              )),
        ),
      );
    } else {
      // Symbole pose sur un medaillon embosse (relief premium)
      final d = widget.tileHeight * 0.66;
      child = Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.3, -0.4),
            radius: 0.95,
            colors: [Color(0xFF3A2A5E), Color(0xFF1B0E33), Color(0xFF0B0620)],
            stops: [0, 0.6, 1],
          ),
          border: Border.all(
              color: const Color(0xFFFFD54A).withValues(alpha: 0.85),
              width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: const Color(0xFFFFD600).withValues(alpha: 0.18),
              blurRadius: 8,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          s.emoji,
          style: TextStyle(
            fontSize: widget.tileHeight * 0.4,
            height: 1,
            shadows: const [
              Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
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
