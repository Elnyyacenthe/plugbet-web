// ============================================================
// Plugbet – Formes de cadre
// ============================================================
// TicketBorder : le contour signature des cartes de l'app. Un rectangle
// à coins arrondis dans lequel on a mordu deux arcs de cercle, à
// mi-hauteur des bords gauche et droit — la silhouette d'un ticket.
//
// C'est une vraie ShapeBorder et non un dessin posé par-dessus : la
// forme pilote donc aussi l'ombre portée (ShapeDecoration.shadows) et
// le rognage du contenu (ShapeBorderClipper).
//
// ── Géométrie ───────────────────────────────────────────────
// Le centre du cercle d'encoche est posé à [notchCenterInset] pixels
// EN DEHORS du bord. Un grand cercle dont le centre sort du bord ne
// creuse qu'une lentille large et peu profonde : on obtient une encoche
// visuellement généreuse sans manger la place du contenu.
//
//   profondeur de la morsure = notchRadius - notchCenterInset
//   demi-hauteur de l'arc    = √(notchRadius² - notchCenterInset²)
//
// ── Décalage vers l'intérieur ───────────────────────────────
// Attention : une courbe CONCAVE ne se décale pas comme une convexe.
// Pour obtenir une bande d'épaisseur constante `d` :
//   • les coins (convexes) rétrécissent   -> radius - d
//   • les encoches (concaves) GRANDISSENT -> notchRadius + d
//     et leur centre reste au même endroit -> notchCenterInset + d
// Rétrécir le rayon de l'encoche ferait au contraire se toucher les
// deux contours au fond du creux, et le cadre y disparaîtrait.
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

class TicketBorder extends OutlinedBorder {
  /// Rayon des quatre coins.
  final double radius;

  /// Rayon du cercle qui mord les bords latéraux. 0 = pas d'encoche.
  final double notchRadius;

  /// Distance dont le centre du cercle d'encoche déborde hors du bord.
  /// Doit rester inférieure à [notchRadius], sinon plus rien n'est mordu.
  final double notchCenterInset;

  /// Position verticale du centre des encoches, de 0 (haut) à 1 (bas).
  final double notchCenter;

  /// Épaisseur de cadre à prendre en compte dans le test de place.
  ///
  /// Le contour intérieur a des encoches plus grandes, donc plus hautes :
  /// il exige plus de hauteur que l'extérieur pour les loger. Sans ce
  /// champ, une carte de la mauvaise taille garderait son encoche
  /// extérieure et perdrait l'intérieure — la surface déborderait dans
  /// le creux. On évalue donc les deux contours sur le même critère.
  final double notchFitBand;

  const TicketBorder({
    super.side = BorderSide.none,
    this.radius = 20,
    this.notchRadius = 22,
    this.notchCenterInset = 10,
    this.notchCenter = 0.5,
    this.notchFitBand = 0,
  });

  /// Contour de la forme, rentré de [inset] vers l'intérieur.
  Path _build(Rect outer, double inset) {
    final rect = inset == 0 ? outer : outer.deflate(inset);
    if (rect.width <= 0 || rect.height <= 0) return Path();

    final r = math.min(
      math.max(0.0, radius - inset),
      math.min(rect.width, rect.height) / 2,
    );

    // Concave : le rayon grandit, le centre ne bouge pas.
    final n = notchRadius <= 0 ? 0.0 : notchRadius + inset;
    final ci = notchCenterInset + inset;

    final depth = n - ci;
    final dy = (n > ci) ? math.sqrt(n * n - ci * ci) : 0.0;

    // Le test de place se fait toujours sur la plus haute des deux
    // encoches (celle du contour intérieur), pour que les deux contours
    // gardent ou perdent leur creux ensemble.
    final fitN = n + notchFitBand;
    final fitCi = ci + notchFitBand;
    final fitDy = (fitN > fitCi) ? math.sqrt(fitN * fitN - fitCi * fitCi) : 0.0;

    // L'encoche doit tenir entre les deux coins du bord, et ne pas
    // dévorer la largeur. Sinon on la laisse tomber proprement.
    final hasNotch = depth > 0 &&
        dy > 0 &&
        fitDy <= rect.height / 2 - r &&
        depth < rect.width / 2;

    // Sans encoche, dy resterait grand et inverserait les bornes du clamp.
    final effDy = hasNotch ? dy : 0.0;
    final cy = (rect.top + rect.height * notchCenter)
        .clamp(rect.top + r + effDy, rect.bottom - r - effDy)
        .toDouble();

    final p = Path()..moveTo(rect.left + r, rect.top);

    // Bord haut → coin haut-droit
    p.lineTo(rect.right - r, rect.top);
    p.arcToPoint(Offset(rect.right, rect.top + r),
        radius: Radius.circular(r));

    // Bord droit, descendu. Le tracé global tourne dans le sens horaire :
    // un arc concave se parcourt donc à l'envers. largeArc reste faux, ce
    // qui garantit une flèche d'arc égale à `depth`.
    if (hasNotch) {
      p.lineTo(rect.right, cy - dy);
      p.arcToPoint(Offset(rect.right, cy + dy),
          radius: Radius.circular(n), clockwise: false);
    }
    p.lineTo(rect.right, rect.bottom - r);
    p.arcToPoint(Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r));

    // Bord bas → coin bas-gauche
    p.lineTo(rect.left + r, rect.bottom);
    p.arcToPoint(Offset(rect.left, rect.bottom - r),
        radius: Radius.circular(r));

    // Bord gauche, remonté, mordu par l'encoche symétrique.
    if (hasNotch) {
      p.lineTo(rect.left, cy + dy);
      p.arcToPoint(Offset(rect.left, cy - dy),
          radius: Radius.circular(n), clockwise: false);
    }
    p.lineTo(rect.left, rect.top + r);
    p.arcToPoint(Offset(rect.left + r, rect.top),
        radius: Radius.circular(r));

    return p..close();
  }

  /// Contour intérieur d'une bande d'épaisseur [d]. À utiliser pour la
  /// surface posée dans le cadre : c'est le seul décalage qui conserve
  /// une épaisseur constante, encoches comprises.
  TicketBorder inner(double d, {BorderSide side = BorderSide.none}) =>
      TicketBorder(
        side: side,
        radius: math.max(0.0, radius - d),
        notchRadius: notchRadius <= 0 ? 0 : notchRadius + d,
        notchCenterInset: notchCenterInset + d,
        notchCenter: notchCenter,
        // Le contour intérieur EST déjà le plus haut : il se teste sur
        // lui-même. C'est l'extérieur qui doit porter la bande.
        notchFitBand: 0,
      );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _build(rect, 0);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _build(rect, side.width);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    // Trait centré sur un contour rentré d'une demi-épaisseur : il reste
    // donc entièrement à l'intérieur de la forme.
    canvas.drawPath(_build(rect, side.width / 2), side.toPaint());
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => TicketBorder(
        side: side.scale(t),
        radius: radius * t,
        notchRadius: notchRadius * t,
        notchCenterInset: notchCenterInset * t,
        notchCenter: notchCenter,
        notchFitBand: notchFitBand * t,
      );

  @override
  TicketBorder copyWith({
    BorderSide? side,
    double? radius,
    double? notchRadius,
    double? notchCenterInset,
    double? notchCenter,
    double? notchFitBand,
  }) =>
      TicketBorder(
        side: side ?? this.side,
        radius: radius ?? this.radius,
        notchRadius: notchRadius ?? this.notchRadius,
        notchCenterInset: notchCenterInset ?? this.notchCenterInset,
        notchCenter: notchCenter ?? this.notchCenter,
        notchFitBand: notchFitBand ?? this.notchFitBand,
      );

  // == / hashCode : sans eux, ShapeDecoration se croit toujours modifiée
  // et repeint chaque carte à chaque frame.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TicketBorder &&
          other.side == side &&
          other.radius == radius &&
          other.notchRadius == notchRadius &&
          other.notchCenterInset == notchCenterInset &&
          other.notchCenter == notchCenter &&
          other.notchFitBand == notchFitBand;

  @override
  int get hashCode => Object.hash(side, radius, notchRadius, notchCenterInset,
      notchCenter, notchFitBand);
}
