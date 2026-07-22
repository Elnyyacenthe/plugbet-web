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
//
// >>> DESIGN PREMIUM <<<
// Cette version enrichit uniquement le rendu visuel (gradients,
// glow neon, bezel glassmorphism, ombres portees, degrades sur les
// segments). AUCUNE logique d'animation, de timing ou de calcul
// d'angle n'a ete modifiee.
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
        // --- Halo ambiant "respirant" (purement decoratif, ne touche
        // pas a la logique de rotation, se contente de lire _idleCtrl
        // pour une pulsation douce) ---
        AnimatedBuilder(
          animation: _idleCtrl,
          builder: (_, __) {
            final pulse = 0.35 + 0.15 * math.sin(_idleCtrl.value * 2 * math.pi);
            return Container(
              width: widget.size * 1.06,
              height: widget.size * 1.06,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD600).withValues(alpha: pulse),
                    blurRadius: 42,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFF6F00).withValues(alpha: pulse * 0.5),
                    blurRadius: 60,
                    spreadRadius: -4,
                  ),
                ],
              ),
            );
          },
        ),
        // --- Ombre portee statique sous la roue (profondeur) ---
        Container(
          width: widget.size * 0.94,
          height: widget.size * 0.94,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
        ),
        // Roue (rotation — logique inchangee)
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
        // --- Jante metallique 3D + ampoules casino (couche fixe) ---
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _idleCtrl,
            builder: (_, __) => CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _WheelRimPainter(_idleCtrl.value),
            ),
          ),
        ),
        // --- Bezel glassmorphism fixe (ne tourne pas avec la roue) ---
        IgnorePointer(
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.2,
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Container(
            width: widget.size * 0.985,
            height: widget.size * 0.985,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.20),
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.12, 0.5, 1.0],
              ),
              border: Border.all(color: Colors.transparent, width: 0),
            ),
          ),
        ),
        // Centre (logo PLUGBET stylise)
        _PlugbetCenter(size: widget.size * 0.34),
        // Pointeur (en haut)
        Positioned(
          top: -6,
          child: CustomPaint(
            size: const Size(26, 30),
            painter: _PointerPainter(),
          ),
        ),
      ]),
    );
  }
}

class _WheelPainter extends CustomPainter {
  static const _palette = [
    Color(0xFF1E7FE0), // bleu neon
    Color(0xFFE0303F), // rouge neon
    Color(0xFF19B562), // vert neon
    Color(0xFFFF9F1C), // orange neon
    Color(0xFF9A2FD6), // violet neon
    Color(0xFFF2C40C), // jaune neon
  ];

  // Couleurs speciales par tuile
  static const Color _gold = Color(0xFFFFD600);
  static const Color _silver = Color(0xFFD7DEE4);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    const segmentAngle = 2 * math.pi / kWheelSegments;

    // Anneau exterieur (fond) — degrade or profond pour effet 3D
    final outerRingPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF3A2400),
          Color(0xFFB07A00),
          Color(0xFF3A2400),
          Color(0xFFB07A00),
          Color(0xFF3A2400),
        ],
        stops: const [0, 0.25, 0.5, 0.75, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    for (int i = 0; i < kWheelSegments; i++) {
      final startAngle = -math.pi / 2 + i * segmentAngle;
      final type = segmentType(i);
      final tileValue = segmentToTileValue(i);

      // Couleur de base du segment
      final Color baseColor;
      switch (type) {
        case SegmentType.multiplier2x:
          baseColor = const Color(0xFFEC1E63); // rose vif neon
          break;
        case SegmentType.multiplier7x:
          baseColor = const Color(0xFF7C1FD6); // violet profond neon
          break;
        case SegmentType.money:
          if (tileValue == 40) {
            baseColor = _gold;
          } else if (tileValue == 20) {
            baseColor = _silver;
          } else {
            baseColor = _palette[i % _palette.length];
          }
      }

      final rect = Rect.fromCircle(center: center, radius: radius);

      // Degrade radial (centre plus clair / bord plus profond) pour un
      // rendu "glossy" premium au lieu d'une teinte plate.
      final lightShade = Color.lerp(baseColor, Colors.white, 0.30)!;
      final darkShade = Color.lerp(baseColor, Colors.black, 0.35)!;
      final segPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.15),
          radius: 1.05,
          colors: [lightShade, baseColor, darkShade],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, startAngle, segmentAngle, true, segPaint);

      // Halo interne pour la tuile 40 (or) et les segments speciaux
      final bool isFeature = tileValue == 40 ||
          type == SegmentType.multiplier2x ||
          type == SegmentType.multiplier7x;
      if (isFeature) {
        final glowPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - 6),
          startAngle,
          segmentAngle,
          true,
          glowPaint,
        );
      }

      // Separateur neon fin entre segments
      final dividerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke;
      final edge = Offset(
        center.dx + radius * math.cos(startAngle),
        center.dy + radius * math.sin(startAngle),
      );
      canvas.drawLine(center, edge, dividerPaint);

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
            shadows: [
              const Shadow(color: Colors.black87, blurRadius: 2),
              Shadow(color: baseColor.withValues(alpha: 0.9), blurRadius: 6),
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

    // Anneau exterieur degrade
    canvas.drawCircle(center, radius - 2, outerRingPaint);

    // Liseret neon dore fin
    canvas.drawCircle(
      center,
      radius - 12,
      Paint()
        ..color = const Color(0xFFFFD600)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      radius - 12,
      Paint()
        ..color = const Color(0xFFFFD600).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Petits points dores (decoration) avec leger glow
    final dotGlowPaint = Paint()
      ..color = const Color(0xFFFFE082).withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final dotPaint = Paint()..color = const Color(0xFFFFF3C4);
    for (int i = 0; i < 24; i++) {
      final a = -math.pi / 2 + (i * 2 * math.pi / 24);
      final r = radius - 6;
      final pos = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      canvas.drawCircle(pos, 3.5, dotGlowPaint);
      canvas.drawCircle(pos, 2.2, dotPaint);
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
            color: const Color(0xFFFFD600).withValues(alpha: 0.65),
            blurRadius: 22,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Reflet vitre en haut du disque (glassmorphism subtil)
          Positioned(
            top: size * 0.06,
            child: Container(
              width: size * 0.62,
              height: size * 0.24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Column(
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
                    color: const Color(0xFFFF1744).withValues(alpha: 0.85),
                    blurRadius: 8,
                  ),
                  const Shadow(color: Colors.black, blurRadius: 2),
                ],
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)   // pointe en bas
      ..lineTo(0, size.height * 0.14)
      ..quadraticBezierTo(0, 0, size.width * 0.18, 0)
      ..lineTo(size.width * 0.82, 0)
      ..quadraticBezierTo(size.width, 0, size.width, size.height * 0.14)
      ..close();

    // Glow neon derriere le pointeur
    final glow = Paint()
      ..color = AppColors.neonRed.withValues(alpha: 0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, glow);

    // Corps degrade
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(AppColors.neonRed, Colors.white, 0.25)!,
          AppColors.neonRed,
          Color.lerp(AppColors.neonRed, Colors.black, 0.35)!,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, bodyPaint);

    // Bord blanc fin (liseret glass)
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Reflet vitre en haut du pointeur
    final highlight = Path()
      ..moveTo(size.width * 0.22, size.height * 0.06)
      ..lineTo(size.width * 0.78, size.height * 0.06)
      ..lineTo(size.width * 0.6, size.height * 0.42)
      ..lineTo(size.width * 0.4, size.height * 0.42)
      ..close();
    canvas.drawPath(
      highlight,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Jante metallique doree biseautee (relief 3D) + couronne d'ampoules
/// casino qui scintillent en chenillard. Purement decoratif : ne tourne
/// pas avec la roue, ne capte aucun geste.
class _WheelRimPainter extends CustomPainter {
  final double t; // 0..1 phase du chenillard
  _WheelRimPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final rimOuter = r - 1;
    final rimInner = r * 0.865;
    final rimW = rimOuter - rimInner;
    final rimMid = (rimOuter + rimInner) / 2;
    final rect = Rect.fromCircle(center: center, radius: rimMid);

    // Corps de la jante : degrade vertical (lumiere haut / ombre bas) → 3D
    canvas.drawCircle(
      center,
      rimMid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF3C4),
            Color(0xFFFFC94D),
            Color(0xFFB07A00),
            Color(0xFF5A3800),
          ],
          stops: [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
    // Aretes sombres interne + externe (separation nette)
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF3A2400);
    canvas.drawCircle(center, rimOuter, edge);
    canvas.drawCircle(center, rimInner, edge);
    // Reflet metallique haut
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: rimMid),
      -math.pi * 0.85,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW * 0.35
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Couronne d'ampoules
    const n = 24;
    for (int i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      final pos = Offset(
        center.dx + rimMid * math.cos(a),
        center.dy + rimMid * math.sin(a),
      );
      // Chenillard : luminosite qui defile
      final phase = ((i / n) + t * 2) % 1.0;
      final bright = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
      final warm = i.isEven;
      final core = warm ? const Color(0xFFFFF7D6) : const Color(0xFFFFE0A3);
      final glow = warm ? const Color(0xFFFFD600) : const Color(0xFFFF8A00);
      // Halo
      canvas.drawCircle(
        pos,
        4.5,
        Paint()
          ..color = glow.withValues(alpha: 0.55 * bright)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Culot sombre
      canvas.drawCircle(pos, 3.1, Paint()..color = const Color(0xFF2A1B00));
      // Ampoule
      canvas.drawCircle(
        pos,
        2.4,
        Paint()..color = Color.lerp(const Color(0xFF7A5A00), core, bright)!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelRimPainter old) => old.t != t;
}
