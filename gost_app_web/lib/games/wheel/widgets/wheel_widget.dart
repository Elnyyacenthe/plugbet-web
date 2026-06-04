// ============================================================
// WheelWidget — Roue animée 48 segments
// ============================================================
// CustomPainter dessine la roue avec les valeurs 1/2/5/10/20/40
// reparties sur 48 segments (cf segmentToTileValue dans models).
// Couleurs alternees + tuile 40 mise en valeur en or.
//
// L'animation : on tourne plusieurs tours complets puis on atterit
// pile sur le segment cible (passe par le parent via [targetSegment]
// quand le serveur a repondu).
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/wheel_models.dart';

class WheelWidget extends StatefulWidget {
  /// Segment cible apres le spin. null = au repos.
  final int? targetSegment;
  /// True = anime en continu (avant que le resultat serveur arrive).
  final bool spinning;
  /// Duree totale du spin a partir du moment ou targetSegment est connu.
  final Duration duration;
  final double size;

  const WheelWidget({
    super.key,
    required this.targetSegment,
    required this.spinning,
    this.duration = const Duration(milliseconds: 4200),
    this.size = 280,
  });

  @override
  State<WheelWidget> createState() => _WheelWidgetState();
}

class _WheelWidgetState extends State<WheelWidget>
    with TickerProviderStateMixin {
  late final AnimationController _idleCtrl;
  late final AnimationController _spinCtrl;
  late Animation<double> _spinAnim;
  double _idleAngle = 0;          // angle a freeze quand on lance le spin
  double _finalAngle = 0;         // angle apres atterrissage

  @override
  void initState() {
    super.initState();
    // Rotation lente quand au repos / en attente RPC
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _spinCtrl = AnimationController(vsync: this, duration: widget.duration);
    _spinAnim = CurvedAnimation(parent: _spinCtrl, curve: Curves.easeOutQuint);
  }

  @override
  void didUpdateWidget(covariant WheelWidget old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !old.spinning) {
      // Le joueur a clique SPIN -> on garde l'idle running. Quand le
      // serveur repond et target arrive, on switch sur _spinCtrl.
    }
    if (widget.targetSegment != null && old.targetSegment == null) {
      _launchToTarget(widget.targetSegment!);
    }
    if (widget.targetSegment == null && old.targetSegment != null) {
      // Reset visuel
      _spinCtrl.reset();
    }
  }

  void _launchToTarget(int segment) {
    // Capture l'angle idle courant
    _idleAngle = _currentIdleAngle();
    _idleCtrl.stop();

    // Angle cible : le segment doit etre sous le pointeur (12h = -π/2).
    // On veut que la rotation finale, modulo 2π, mette le centre du
    // segment au top. + 6 tours complets pour l'effet visuel.
    final segmentCenter = segmentToAngleRadians(segment);
    // Inverse car la roue tourne en sens horaire mais notre repere math
    // a y vers le bas. On veut que segment soit sous le pointeur (top).
    final aimAngle = -segmentCenter;
    const extraTurns = 6;
    _finalAngle = _idleAngle + extraTurns * 2 * math.pi + aimAngle - _idleAngle;
    // Normalise pour qu'on aille toujours vers l'avant (+)
    while (_finalAngle <= _idleAngle) {
      _finalAngle += 2 * math.pi;
    }

    _spinCtrl.reset();
    _spinCtrl.forward();
  }

  double _currentIdleAngle() {
    // 1 tour toutes les 20s -> 2π * elapsedSec / 20
    return _idleCtrl.value * 2 * math.pi;
  }

  @override
  void dispose() {
    _idleCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size, height: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        // Halo
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD600).withValues(alpha: 0.4),
                blurRadius: 30, spreadRadius: 4,
              ),
            ],
          ),
        ),
        // Roue
        AnimatedBuilder(
          animation: Listenable.merge([_idleCtrl, _spinCtrl]),
          builder: (_, __) {
            final double angle;
            if (_spinCtrl.isAnimating || _spinCtrl.isCompleted) {
              angle = _idleAngle + (_finalAngle - _idleAngle) * _spinAnim.value;
            } else {
              angle = _currentIdleAngle();
            }
            return Transform.rotate(
              angle: angle,
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _WheelPainter(),
              ),
            );
          },
        ),
        // Centre (logo PLUGBET stylise)
        _PlugbetCenter(size: widget.size * 0.34),
        // Pointeur (en haut)
        Positioned(
          top: -4,
          child: Container(
            width: 0, height: 0,
            decoration: const BoxDecoration(),
            child: CustomPaint(
              size: const Size(22, 26),
              painter: _PointerPainter(),
            ),
          ),
        ),
      ]),
    );
  }
}

class _WheelPainter extends CustomPainter {
  static const _palette = [
    Color(0xFF1976D2), // bleu
    Color(0xFFD32F2F), // rouge
    Color(0xFF388E3C), // vert
    Color(0xFFFFA000), // orange
    Color(0xFF7B1FA2), // violet
    Color(0xFFFFC107), // jaune
  ];

  // Couleurs speciales par tuile
  static const Color _gold = Color(0xFFFFD600);
  static const Color _silver = Color(0xFFB0BEC5);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    const segmentAngle = 2 * math.pi / kWheelSegments;

    final ringPaint = Paint()
      ..color = const Color(0xFF7A4F00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    for (int i = 0; i < kWheelSegments; i++) {
      final startAngle = -math.pi / 2 + i * segmentAngle;
      final type = segmentType(i);
      final tileValue = segmentToTileValue(i);

      // Couleur du segment
      final Color color;
      switch (type) {
        case SegmentType.multiplier2x:
          color = const Color(0xFFE91E63); // rose vif
          break;
        case SegmentType.multiplier7x:
          color = const Color(0xFF6A1B9A); // violet profond
          break;
        case SegmentType.money:
          if (tileValue == 40) {
            color = _gold;
          } else if (tileValue == 20) {
            color = _silver;
          } else {
            color = _palette[i % _palette.length];
          }
      }

      final paint = Paint()..color = color..style = PaintingStyle.fill;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, startAngle, segmentAngle, true, paint);

      // Texte du segment
      final String label;
      final Color textColor;
      final double textSize;
      switch (type) {
        case SegmentType.multiplier2x:
          label = '2x'; textColor = Colors.white; textSize = 12;
          break;
        case SegmentType.multiplier7x:
          label = '7x'; textColor = Colors.white; textSize = 12;
          break;
        case SegmentType.money:
          label = '$tileValue';
          textColor = tileValue == 40 ? Colors.black : Colors.white;
          textSize = 14;
      }

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: textColor,
            fontSize: textSize,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(color: Colors.black54, blurRadius: 1),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final mid = startAngle + segmentAngle / 2;
      final tr = radius * 0.72;
      final tx = center.dx + tr * math.cos(mid) - tp.width / 2;
      final ty = center.dy + tr * math.sin(mid) - tp.height / 2;
      canvas.save();
      canvas.translate(tx + tp.width / 2, ty + tp.height / 2);
      canvas.rotate(mid + math.pi / 2);
      canvas.translate(-tp.width / 2, -tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Anneau exterieur
    canvas.drawCircle(center, radius - 2, ringPaint);
    canvas.drawCircle(center, radius - 12,
        Paint()..color = const Color(0xFFFFD600)..style = PaintingStyle.stroke..strokeWidth = 2);

    // Petits points dores (decoration)
    final dotPaint = Paint()..color = const Color(0xFFFFE082);
    for (int i = 0; i < 24; i++) {
      final a = -math.pi / 2 + (i * 2 * math.pi / 24);
      final r = radius - 6;
      canvas.drawCircle(
        Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a)),
        2.5, dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Logo PLUGBET au centre de la roue. Effet "casino bling" :
///   - Anneau exterieur or fonce (profondeur 3D)
///   - Disque principal degrade or
///   - Texte PLUGBET avec degrade or vif + outline noire + ombre neon
///   - Sous-titre "WHEEL" en rouge neon
class _PlugbetCenter extends StatelessWidget {
  final double size;
  const _PlugbetCenter({required this.size});

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.18;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [
            Color(0xFFFFF8E1),  // brillance haute lumiere
            Color(0xFFFFE082),  // or clair
            Color(0xFFFFB300),  // or moyen
            Color(0xFF8B5A00),  // or fonce (profondeur)
          ],
          stops: [0, 0.25, 0.7, 1],
        ),
        border: Border.all(color: const Color(0xFF5A3800), width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD600).withValues(alpha: 0.6),
            blurRadius: 18,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 6, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // PLUGBET avec gradient + outline + glow
          Stack(alignment: Alignment.center, children: [
            // Outline noire (rendu 2 fois pour effet outline epaisse)
            Text('PLUGBET', style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.5
                ..color = Colors.black,
            )),
            // Texte avec gradient or vif
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFF59D),  // jaune lumineux haut
                  Color(0xFFFFD600),  // or vif
                  Color(0xFFFFA000),  // orange-or bas
                ],
                stops: [0, 0.5, 1],
              ).createShader(rect),
              child: Text('PLUGBET', style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                shadows: const [
                  Shadow(color: Color(0xFFFF6F00), blurRadius: 6),
                ],
              )),
            ),
          ]),
          SizedBox(height: size * 0.015),
          // Sous-titre WHEEL en rouge neon
          Text('WHEEL', style: TextStyle(
            color: const Color(0xFFFF1744),
            fontSize: fontSize * 0.55,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
            shadows: [
              Shadow(
                color: const Color(0xFFFF1744).withValues(alpha: 0.8),
                blurRadius: 6,
              ),
              const Shadow(color: Colors.black, blurRadius: 2),
            ],
          )),
        ],
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.neonRed;
    final path = Path()
      ..moveTo(size.width / 2, size.height)   // pointe en bas
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, p);
    // Bord blanc
    canvas.drawPath(
      path,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
