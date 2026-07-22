// ============================================================
// PlaneWidget + StarField — Elements visuels du jeu Aviator
// (premium redesign : jet vectoriel metallique + traînée comète)
// ============================================================
// >>> DESIGN <<<
// L'avion n'est plus un emoji : c'est un jet dessine au CustomPainter
// (fuselage degrade rouge metal, verriere, ailes, reacteur enflamme,
// traînee lumineuse). Au crash, un panache de fumee + eclat. AUCUNE
// logique de position/rotation/progress n'a change.
// ============================================================
import 'dart:math';
import 'package:flutter/material.dart';
import 'multiplier_curve_painter.dart';

/// Avion anime qui suit la courbe de multiplicateur.
class PlaneWidget extends StatelessWidget {
  final double progress;
  final double multiplier;
  final bool crashed;

  const PlaneWidget({
    super.key,
    required this.progress,
    required this.multiplier,
    required this.crashed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pos =
            MultiplierCurvePainter.planePosition(size, progress, multiplier);

        // -45° au depart (x0), tend vers -10° en altitude
        final yRatio =
            (log(1.0 + multiplier.clamp(0.0, 9999)) / log(51)).clamp(0.0, 1.0);
        final angle = crashed
            ? pi / 4 // tombe → tourne vers le bas
            : -pi / 4 + yRatio * pi / 6;

        // Boîte de dessin : plane centre, traînee vers l'arriere (gauche).
        const boxW = 116.0;
        const boxH = 72.0;

        return Stack(
          children: [
            Positioned(
              left: pos.dx - boxW / 2,
              top: pos.dy - boxH / 2,
              child: Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  size: const Size(boxW, boxH),
                  painter: _JetPainter(crashed: crashed),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Peintre du jet Aviator (oriente vers la droite = sens du vol).
class _JetPainter extends CustomPainter {
  final bool crashed;
  _JetPainter({required this.crashed});

  // Palette
  static const _redLight = Color(0xFFFF7A7A);
  static const _red = Color(0xFFEF4444);
  static const _redDark = Color(0xFF9B1C1C);
  static const _orange = Color(0xFFF97316);
  static const _amber = Color(0xFFFFC44D);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    if (crashed) {
      _paintExplosion(canvas, Offset(cx, cy));
      return;
    }

    // ── Traînée comète (derriere l'avion, vers la gauche) ──
    final trailRect = Rect.fromLTWH(0, cy - 9, cx + 6, 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trailRect, const Radius.circular(9)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x66F97316), Color(0x00F97316)],
        ).createShader(trailRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Coeur clair de la traînee
    final coreRect = Rect.fromLTWH(cx - 34, cy - 2.5, 40, 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(coreRect, const Radius.circular(3)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0xCCFFD9A0), Color(0x00FFD9A0)],
        ).createShader(coreRect),
    );

    // ── Halo doux autour de l'avion ──
    canvas.drawCircle(
      Offset(cx + 8, cy),
      30,
      Paint()
        ..color = _orange.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // ── Ailes (dessinees avant le fuselage pour passer dessous) ──
    final wingPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_redDark, Color(0xFF6E1212)],
      ).createShader(Rect.fromLTWH(cx - 18, cy - 20, 40, 40));
    // Aile basse (avant, plus grande)
    final lowerWing = Path()
      ..moveTo(cx + 8, cy + 2)
      ..lineTo(cx - 18, cy + 22)
      ..lineTo(cx - 2, cy + 6)
      ..close();
    canvas.drawShadow(lowerWing, Colors.black.withValues(alpha: 0.6), 3, false);
    canvas.drawPath(lowerWing, wingPaint);
    // Aile haute (arriere, en perspective)
    final upperWing = Path()
      ..moveTo(cx + 6, cy - 2)
      ..lineTo(cx - 14, cy - 16)
      ..lineTo(cx, cy - 4)
      ..close();
    canvas.drawPath(
        upperWing,
        Paint()
          ..color = const Color(0xFF7E1616));

    // ── Empennage (queue) ──
    final tail = Path()
      ..moveTo(cx - 26, cy - 1)
      ..lineTo(cx - 40, cy - 15)
      ..lineTo(cx - 30, cy - 15)
      ..lineTo(cx - 18, cy - 2)
      ..close();
    canvas.drawPath(tail, wingPaint);

    // ── Reacteur enflamme (a l'arriere du fuselage) ──
    final flame = Path()
      ..moveTo(cx - 30, cy - 3.5)
      ..lineTo(cx - 48, cy)
      ..lineTo(cx - 30, cy + 3.5)
      ..close();
    canvas.drawPath(
      flame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [_amber, _orange, Color(0x00F97316)],
        ).createShader(Rect.fromLTWH(cx - 48, cy - 4, 20, 8))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );

    // ── Fuselage (corps metallique degrade) ──
    final bodyRect = Rect.fromLTWH(cx - 30, cy - 8, 74, 16);
    final fuselage = Path()
      ..moveTo(cx - 30, cy) // arriere
      ..lineTo(cx - 24, cy - 6)
      ..quadraticBezierTo(cx + 8, cy - 9, cx + 40, cy - 3) // dos jusqu'au nez
      ..quadraticBezierTo(cx + 46, cy, cx + 40, cy + 3) // pointe du nez
      ..quadraticBezierTo(cx + 8, cy + 9, cx - 24, cy + 6) // ventre
      ..close();
    canvas.drawShadow(fuselage, Colors.black.withValues(alpha: 0.7), 4, false);
    canvas.drawPath(
      fuselage,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_redLight, _red, _redDark],
          stops: [0.0, 0.45, 1.0],
        ).createShader(bodyRect),
    );
    // Reflet metallique sur le dos
    final shine = Path()
      ..moveTo(cx - 20, cy - 4.5)
      ..quadraticBezierTo(cx + 8, cy - 6.5, cx + 34, cy - 2.2)
      ..quadraticBezierTo(cx + 8, cy - 3.5, cx - 20, cy - 2.5)
      ..close();
    canvas.drawPath(
        shine, Paint()..color = Colors.white.withValues(alpha: 0.45));

    // ── Verriere (cockpit) ──
    final canopy = Path()
      ..moveTo(cx + 18, cy - 5)
      ..quadraticBezierTo(cx + 30, cy - 7, cx + 33, cy - 1)
      ..lineTo(cx + 20, cy - 1)
      ..close();
    canvas.drawPath(
      canopy,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBFF3FF), Color(0xFF2A6E8A)],
        ).createShader(Rect.fromLTWH(cx + 18, cy - 7, 16, 8)),
    );

    // Liseret sombre sous le fuselage (contact/ombre propre)
    canvas.drawPath(
      Path()
        ..moveTo(cx - 22, cy + 5.5)
        ..quadraticBezierTo(cx + 8, cy + 8, cx + 36, cy + 2.6),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintExplosion(Canvas canvas, Offset c) {
    // Panache : halo, boule de feu, eclats et fumee.
    canvas.drawCircle(
      c,
      26,
      Paint()
        ..color = _orange.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Etoile d'eclat (8 branches)
    final burst = Path();
    for (int i = 0; i < 8; i++) {
      final a = i * pi / 4;
      final outer = i.isEven ? 24.0 : 14.0;
      final p = Offset(c.dx + cos(a) * outer, c.dy + sin(a) * outer);
      final a2 = a + pi / 8;
      final inner = Offset(c.dx + cos(a2) * 7, c.dy + sin(a2) * 7);
      if (i == 0) burst.moveTo(p.dx, p.dy);
      burst.lineTo(inner.dx, inner.dy);
      burst.lineTo(p.dx, p.dy);
    }
    burst.close();
    canvas.drawPath(
      burst,
      Paint()
        ..shader = const RadialGradient(
          colors: [_amber, _red, _redDark],
        ).createShader(Rect.fromCircle(center: c, radius: 24)),
    );
    // Coeur blanc-jaune
    canvas.drawCircle(
        c, 9, Paint()..color = const Color(0xFFFFF3C4).withValues(alpha: 0.95));
    canvas.drawCircle(c, 4.5, Paint()..color = Colors.white);
    // Quelques debris
    final debris = Paint()..color = _redDark;
    for (int i = 0; i < 5; i++) {
      final a = i * 1.3 + 0.4;
      final d = 20.0 + i * 3;
      canvas.drawCircle(
          Offset(c.dx + cos(a) * d, c.dy + sin(a) * d), 2.2, debris);
    }
  }

  @override
  bool shouldRepaint(_JetPainter old) => old.crashed != crashed;
}

/// Fond etoile (60 points aleatoires stables) avec scintillement doux.
class StarField extends StatefulWidget {
  const StarField({super.key});

  @override
  State<StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<StarField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return CustomPaint(
          painter: _StarPainter(_ctrl.value),
          child: Container(),
        );
      },
    );
  }
}

class _StarPainter extends CustomPainter {
  final double t;
  _StarPainter(this.t);

  static final _stars = List.generate(60, (i) {
    final r = Random(i * 31 + 7);
    return Offset(r.nextDouble(), r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      // Scintillement : phase propre à chaque étoile pour un effet organique.
      final phase = (t + (i * 0.073)) % 1.0;
      final twinkle = 0.15 + (0.20 * (0.5 + 0.5 * sin(phase * 2 * pi)));
      final paint = Paint()..color = Colors.white.withValues(alpha: twinkle);
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.t != t;
}
