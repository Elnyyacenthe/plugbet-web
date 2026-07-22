// ============================================================
// Plugbet – Tokens de surface (relief, matière, profondeur)
// ============================================================
// Source unique du vocabulaire « 3D » de l'application.
//
// Avant ce fichier, chaque écran réécrivait ses propres BoxShadow :
// le motif d'AppBar en profondeur de Fantasy était recopié à
// l'identique dans 6 fichiers, la double ombre des cartes dans
// chaque jeu. Toute nouvelle surface doit passer par ici.
//
// Trois familles :
//   • les ARÊTES  (edgeLight / edgeDark)  → le biseau, ce qui fait
//     qu'une surface a une épaisseur plutôt qu'un contour.
//   • les OMBRES  (raised / pressed / …)  → où la surface se situe
//     dans la profondeur.
//   • les MATIÈRES (raisedGradient / dome / metal) → de quoi elle est
//     faite : plastique bombé, métal brossé, verre.
//
// Tout est sensible au thème : en sombre on creuse avec du noir dense,
// en clair on sculpte avec une arête blanche et une ombre douce.
// ============================================================

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Échelle de rayons. Une seule progression pour toute l'app, de la
/// pastille au grand panneau. Ne pas inventer de valeur intermédiaire.
class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;

  static BorderRadius get brXs => BorderRadius.circular(xs);
  static BorderRadius get brSm => BorderRadius.circular(sm);
  static BorderRadius get brMd => BorderRadius.circular(md);
  static BorderRadius get brLg => BorderRadius.circular(lg);
  static BorderRadius get brXl => BorderRadius.circular(xl);
}

class AppSurfaces {
  const AppSurfaces._();

  static bool get _dark => AppColors.isDark;

  // ── Utilitaires de teinte ────────────────────────────────────
  // Le relief se construit presque entièrement en éclaircissant et en
  // assombrissant une couleur de base : l'arête haute reçoit la lumière,
  // l'arête basse la refuse.

  static Color lighten(Color c, double amount) =>
      Color.lerp(c, Colors.white, amount)!;

  static Color darken(Color c, double amount) =>
      Color.lerp(c, Colors.black, amount)!;

  /// Teinte une surface avec un accent, sans la saturer.
  static Color tint(Color surface, Color accent, double amount) =>
      Color.lerp(surface, accent, amount)!;

  /// Encre lisible à poser sur [background]. Le vert de marque veut du
  /// noir par-dessus, mais un rouge ou un violet veulent du blanc :
  /// on ne peut pas figer [AppColors.onPrimary] partout.
  static Color inkOn(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? Colors.white
          : AppColors.onPrimary;

  // ── Arêtes (biseaux) ─────────────────────────────────────────

  /// Arête supérieure : la lumière frappe le haut de la surface.
  static Color get edgeLight =>
      Colors.white.withValues(alpha: _dark ? 0.10 : 0.95);

  /// Arête inférieure : le bas de la surface plonge dans l'ombre.
  static Color get edgeDark =>
      Colors.black.withValues(alpha: _dark ? 0.55 : 0.12);

  /// Filet neutre, pour séparer sans creuser.
  static Color get hairline => _dark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.black.withValues(alpha: 0.08);

  // ── Ombres ───────────────────────────────────────────────────

  /// Surface **surélevée** : elle flotte au-dessus du fond.
  ///
  /// Trois couches, et c'est ce qui distingue une vraie ombre d'un flou
  /// gris : une ombre de contact courte et dense qui ancre l'objet, une
  /// ombre portée large et douce qui donne la hauteur, et — si un
  /// [glow] est fourni — un halo coloré qui fait vibrer l'accent.
  ///
  /// [elevation] multiplie la hauteur : 0.6 pour une pastille, 1.0 pour
  /// une carte, 1.8 pour une feuille modale.
  static List<BoxShadow> raised({Color? glow, double elevation = 1.0}) {
    final e = elevation;
    return [
      // Contact : ancre l'objet sur le fond.
      BoxShadow(
        color: Colors.black.withValues(alpha: _dark ? 0.42 : 0.07),
        blurRadius: 3 * e,
        offset: Offset(0, 1.5 * e),
      ),
      // Portée : donne la hauteur.
      BoxShadow(
        color: Colors.black.withValues(alpha: _dark ? 0.50 : 0.11),
        blurRadius: 16 * e,
        spreadRadius: -3,
        offset: Offset(0, 7 * e),
      ),
      // Halo d'accent : facultatif, toujours en dernier.
      if (glow != null)
        BoxShadow(
          color: glow.withValues(alpha: _dark ? 0.22 : 0.18),
          blurRadius: 22 * e,
          spreadRadius: -5,
          offset: Offset(0, 5 * e),
        ),
    ];
  }

  /// Surface **enfoncée** sous le doigt : l'objet se rapproche du fond,
  /// donc son ombre se resserre et pâlit. À utiliser avec une
  /// translation de 1 à 2 px vers le bas.
  static List<BoxShadow> pressed({Color? glow}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: _dark ? 0.38 : 0.06),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        if (glow != null)
          BoxShadow(
            color: glow.withValues(alpha: _dark ? 0.14 : 0.10),
            blurRadius: 10,
            spreadRadius: -4,
          ),
      ];

  /// Feuille modale / bottom sheet : très haut, ombre longue.
  static List<BoxShadow> floating({Color? glow}) =>
      raised(glow: glow, elevation: 1.9);

  /// Halo pur, sans ombre portée. Pour les éléments actifs (onglet
  /// sélectionné, bouton primaire) qui doivent rayonner sans décoller.
  static List<BoxShadow> glowOnly(Color color, {double strength = 1.0}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.28 * strength),
          blurRadius: 18 * strength,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.14 * strength),
          blurRadius: 34 * strength,
          spreadRadius: 2,
        ),
      ];

  // ── Matières ─────────────────────────────────────────────────

  /// Plastique bombé : clair en haut, sombre en bas. C'est le dégradé
  /// par défaut de toute surface qui doit paraître épaisse.
  static LinearGradient raisedGradient(Color base) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lighten(base, _dark ? 0.09 : 0.02),
          base,
          darken(base, _dark ? 0.20 : 0.05),
        ],
        stops: const [0.0, 0.52, 1.0],
      );

  /// L'inverse : creusé, sombre en haut. Pour les fonds de champ, les
  /// pistes de progression, les zones de saisie.
  static LinearGradient sunkenGradient(Color base) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          darken(base, _dark ? 0.28 : 0.07),
          base,
        ],
        stops: const [0.0, 0.85],
      );

  /// Carte standard, prête à l'emploi.
  static LinearGradient get cardBevel => raisedGradient(AppColors.bgCard);

  /// Métal brossé, éclairé en diagonale. Barres de navigation, AppBars,
  /// drawer : tout le chrome de l'app.
  static LinearGradient get metal => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _dark
            ? [
                const Color(0xFF16233A),
                const Color(0xFF0C1728),
                const Color(0xFF070E1A),
              ]
            : [
                Colors.white,
                const Color(0xFFF2F5FC),
                const Color(0xFFE6ECF8),
              ],
        stops: const [0.0, 0.55, 1.0],
      );

  /// Dôme : jeton, médaillon, pastille d'icône. La source lumineuse est
  /// en haut à gauche, comme partout ailleurs dans l'app.
  static RadialGradient dome(Color base) => RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 0.95,
        colors: [
          lighten(base, 0.50),
          base,
          darken(base, 0.42),
        ],
        stops: const [0.0, 0.55, 1.0],
      );

  /// Reflet spéculaire : une bande de lumière en diagonale, à poser en
  /// surimpression sur une carte. Discret par construction.
  static LinearGradient get sheen => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: _dark ? 0.07 : 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45],
      );

  /// Dégradé d'arête : blanc en haut, noir en bas, transparent au
  /// milieu. Posé sur une surface, il lui sculpte un biseau.
  static LinearGradient get bevelOverlay => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          edgeLight,
          Colors.transparent,
          Colors.transparent,
          edgeDark,
        ],
        stops: const [0.0, 0.06, 0.90, 1.0],
      );

  // ── Chrome ───────────────────────────────────────────────────

  /// AppBar / barre de navigation en profondeur. Remplace le motif
  /// recopié 7 fois dans lib/fantasy.
  static BoxDecoration chrome({bool shadowBelow = true}) => BoxDecoration(
        gradient: metal,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _dark ? 0.45 : 0.10),
            blurRadius: 14,
            offset: Offset(0, shadowBelow ? 5 : -5),
          ),
        ],
      );

  // Le cadre des cartes vit dans `TicketBorder` (app_shapes.dart), pas
  // ici : c'est une forme, pas une décoration.
}
