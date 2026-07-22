// ============================================================
// Plugbet – Widgets de relief partagés
// ============================================================
// Les briques visuelles de l'app, construites sur AppSurfaces.
// Aucun écran ne doit plus écrire de BoxShadow à la main.
//
//   ReliefCard        carte encadrée (cadre biseauté + liseré primary)
//   ReliefButton      bouton plein ou fantôme, qui s'enfonce au doigt
//   DomeIcon          médaillon d'icône bombé
//   InsetPanel        zone encastrée (champ, piste, puits)
//   ReliefProgressBar piste creusée + jauge bombée
//   ReliefAppBar      chrome en profondeur
//   ReliefDivider     filet gravé
//   ReliefPill        pastille / badge
// ============================================================

import 'package:flutter/material.dart';
import 'app_shapes.dart';
import 'app_surfaces.dart';
import 'app_theme.dart';

// ════════════════════════════════════════════════════════════
// ReliefCard
// ════════════════════════════════════════════════════════════

/// Carte au contour « ticket », motif de base des listes répétées
/// (matchs, paris, jeux).
///
/// Un **cadre** épais, sculpté par un dégradé arête-claire → arête-sombre
/// et teinté par l'accent, dans lequel deux demi-ovales sont mordus à
/// mi-hauteur des bords. À l'intérieur, une **surface** creusée, séparée
/// du cadre par un simple filet — pas un second contour.
///
/// La silhouette est une vraie [TicketBorder] : elle pilote aussi
/// l'ombre portée et le rognage du contenu.
class ReliefCard extends StatefulWidget {
  final Widget child;

  /// Couleur du cadre et du halo. Par défaut la couleur de marque.
  final Color? accent;

  /// Marge interne du contenu.
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// Rayon des quatre coins.
  final double radius;

  /// Rayon du cercle qui mord les bords latéraux. 0 = pas d'encoche.
  final double notchRadius;

  /// De combien le centre de ce cercle déborde hors du bord. Plus il
  /// déborde, plus l'encoche est large et peu profonde.
  /// Morsure réelle = [notchRadius] − [notchCenterInset].
  final double notchCenterInset;

  /// Épaisseur du cadre, entre le bord extérieur et la surface.
  final double frameWidth;

  /// Épaisseur du trait qui souligne le contour extérieur.
  final double strokeWidth;

  final double elevation;
  final VoidCallback? onTap;

  /// Reflet spéculaire en diagonale, sous le contenu.
  final bool sheen;

  /// Pour surcharger la matière de la surface intérieure.
  final Gradient? surfaceGradient;

  const ReliefCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = AppRadius.lg,
    this.notchRadius = 22,
    this.notchCenterInset = 10,
    this.frameWidth = 5,
    this.strokeWidth = 2,
    this.elevation = 1.0,
    this.onTap,
    this.sheen = true,
    this.surfaceGradient,
  });

  @override
  State<ReliefCard> createState() => _ReliefCardState();
}

class _ReliefCardState extends State<ReliefCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppColors.primaryInk;
    final fw = widget.frameWidth;

    // Le cadre : métal légèrement teinté d'accent, éclairé par le haut.
    final frameBase = AppSurfaces.tint(AppColors.bgElevated, accent, 0.12);

    final outerShape = TicketBorder(
      radius: widget.radius,
      notchRadius: widget.notchRadius,
      notchCenterInset: widget.notchCenterInset,
      // Se teste sur l'encoche du contour intérieur, la plus haute des
      // deux : les deux creux apparaissent et disparaissent ensemble.
      notchFitBand: fw,
      side: BorderSide(
        color: accent.withValues(alpha: AppColors.isDark ? 0.85 : 0.65),
        width: widget.strokeWidth,
      ),
    );

    // `inner()` fait grandir les encoches et rétrécir les coins : c'est
    // le seul décalage qui laisse une bande d'épaisseur constante. Un
    // simple `notchRadius - fw` collerait les deux contours au fond du
    // creux et le cadre y disparaîtrait.
    final innerShape = outerShape.inner(
      fw,
      side: BorderSide(color: accent.withValues(alpha: 0.15), width: 1),
    );

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.all(fw),
      // La carte s'enfonce de 1.5 px sous le doigt et son ombre se
      // resserre : le mouvement vient de la lumière, pas d'une échelle.
      transform: Matrix4.translationValues(0, _pressed ? 1.5 : 0, 0),
      decoration: ShapeDecoration(
        shape: outerShape,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppSurfaces.lighten(frameBase, AppColors.isDark ? 0.16 : 0.0),
            frameBase,
            AppSurfaces.darken(frameBase, AppColors.isDark ? 0.40 : 0.10),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        // Les ombres suivent le contour, encoches comprises.
        shadows: _pressed
            ? AppSurfaces.pressed(glow: accent)
            : AppSurfaces.raised(glow: accent, elevation: widget.elevation),
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: innerShape,
          gradient: widget.surfaceGradient ?? AppSurfaces.cardBevel,
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: innerShape),
          child: Stack(
            children: [
              // Le reflet passe SOUS le contenu : posé au-dessus, il
              // délaverait le texte en mode clair.
              if (widget.sheen)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: AppSurfaces.sheen),
                    ),
                  ),
                ),
              Padding(padding: widget.padding, child: widget.child),
            ],
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      card = GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }

    if (widget.margin != null) {
      card = Padding(padding: widget.margin!, child: card);
    }
    return card;
  }
}

// ════════════════════════════════════════════════════════════
// ReliefButton
// ════════════════════════════════════════════════════════════

/// Bouton à volume. En variante pleine il utilise [AppColors.primary]
/// (remplissage) avec [AppColors.onPrimary] par-dessus ; en variante
/// fantôme il trace en [AppColors.primaryInk].
class ReliefButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Couleur de remplissage. Par défaut la couleur de marque.
  final Color? color;

  /// Bouton creux : surface neutre, trait et texte colorés.
  final bool ghost;

  final bool expand;
  final double height;
  final double radius;

  const ReliefButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
    this.ghost = false,
    this.expand = false,
    this.height = 50,
    this.radius = AppRadius.sm,
  });

  @override
  State<ReliefButton> createState() => _ReliefButtonState();
}

class _ReliefButtonState extends State<ReliefButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fill = widget.color ?? AppColors.primary;
    final ink = widget.ghost
        ? (widget.color ?? AppColors.primaryDeep)
        : AppSurfaces.inkOn(fill);

    final base = widget.ghost ? AppColors.bgCard : fill;
    final fg = enabled ? ink : AppColors.textMuted;

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 19, color: fg),
          const SizedBox(width: 9),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: fg,
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: enabled ? widget.onPressed : null,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        height: widget.height,
        width: widget.expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        transform: Matrix4.translationValues(0, _pressed ? 1.5 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: AppSurfaces.raisedGradient(
            enabled ? base : AppSurfaces.darken(base, 0.25),
          ),
          border: widget.ghost
              ? Border.all(
                  color: (enabled ? ink : AppColors.textMuted)
                      .withValues(alpha: 0.45),
                  width: 1.2,
                )
              : null,
          boxShadow: !enabled
              ? const []
              : _pressed
                  ? AppSurfaces.pressed(glow: widget.ghost ? null : fill)
                  : AppSurfaces.raised(
                      glow: widget.ghost ? null : fill,
                      elevation: 0.8,
                    ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Le biseau : arête claire en haut, ombre en bas.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius),
                    gradient: AppSurfaces.bevelOverlay,
                  ),
                ),
              ),
            ),
            content,
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// DomeIcon
// ════════════════════════════════════════════════════════════

/// Médaillon d'icône bombé : dôme éclairé en haut à gauche, halo
/// coloré, et une icône légèrement gravée. Remplace les carrés d'icône
/// plats (`color.withValues(alpha: .12)` + `Icon`) partout dans l'app.
class DomeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;

  /// Coin arrondi plutôt que cercle.
  final double? radius;

  const DomeIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: r == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: r == null ? null : BorderRadius.circular(r),
        gradient: AppSurfaces.dome(color),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isDark ? 0.5 : 0.18),
            blurRadius: 5,
            offset: const Offset(0, 2.5),
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.34),
            blurRadius: 12,
            spreadRadius: -2,
          ),
        ],
        border: Border.all(
          color: AppSurfaces.lighten(color, 0.35).withValues(alpha: 0.55),
          width: 0.8,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: iconSize ?? size * 0.48,
          color: Colors.white,
          shadows: [
            Shadow(
              color: AppSurfaces.darken(color, 0.6).withValues(alpha: 0.7),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// InsetPanel
// ════════════════════════════════════════════════════════════

/// Zone **encastrée** : elle s'enfonce dans la surface qui la porte.
/// Pour les champs de saisie, les puits de statistiques, les fonds de
/// piste. C'est l'inverse exact de [ReliefCard].
class InsetPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? baseColor;

  /// Profondeur du creux.
  final double depth;

  const InsetPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = AppRadius.sm,
    this.baseColor,
    this.depth = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final base = baseColor ?? AppColors.bgDark;
    final br = BorderRadius.circular(radius);

    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: AppSurfaces.sunkenGradient(base),
        border: Border.all(color: AppSurfaces.hairline, width: 1),
      ),
      child: CustomPaint(
        painter: _InnerShadowPainter(
          radius: br,
          color: Colors.black
              .withValues(alpha: (AppColors.isDark ? 0.60 : 0.16) * depth),
          blur: 6 * depth,
          offset: Offset(0, 2.5 * depth),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Flutter ne connaît pas l'ombre interne. On la peint : on remplit
/// tout **hors** du rectangle arrondi, on floute, et on découpe au
/// rectangle — il ne reste que l'ombre qui déborde vers l'intérieur.
class _InnerShadowPainter extends CustomPainter {
  final BorderRadius radius;
  final Color color;
  final double blur;
  final Offset offset;

  const _InnerShadowPainter({
    required this.radius,
    required this.color,
    required this.blur,
    required this.offset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rrect = radius.toRRect(bounds);

    canvas.saveLayer(bounds, Paint());
    canvas.clipRRect(rrect);

    final outer = Path()
      ..addRect(bounds.inflate(size.longestSide + blur * 2));
    final inner = Path()..addRRect(rrect.shift(offset));

    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) =>
      old.color != color || old.blur != blur || old.offset != offset;
}

// ════════════════════════════════════════════════════════════
// ReliefProgressBar
// ════════════════════════════════════════════════════════════

/// Piste creusée, jauge bombée. Remplace les `LinearProgressIndicator`
/// et les `Stack` de deux `Container` plats.
class ReliefProgressBar extends StatelessWidget {
  /// Entre 0 et 1.
  final double value;
  final Color? color;
  final Color? endColor;
  final double height;

  const ReliefProgressBar({
    super.key,
    required this.value,
    this.color,
    this.endColor,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final v = value.clamp(0.0, 1.0);
    final br = BorderRadius.circular(height / 2);

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // La piste : un sillon.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: br,
                gradient: AppSurfaces.sunkenGradient(AppColors.bgDark),
                border: Border.all(color: AppSurfaces.hairline, width: 0.8),
              ),
              child: CustomPaint(
                painter: _InnerShadowPainter(
                  radius: br,
                  color: Colors.black
                      .withValues(alpha: AppColors.isDark ? 0.7 : 0.2),
                  blur: 4,
                  offset: const Offset(0, 1.5),
                ),
              ),
            ),
          ),
          // La jauge : un tube.
          if (v > 0)
            FractionallySizedBox(
              widthFactor: v,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: br,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppSurfaces.lighten(c, 0.35),
                      c,
                      AppSurfaces.darken(endColor ?? c, 0.18),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  boxShadow: AppSurfaces.glowOnly(c, strength: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ReliefAppBar
// ════════════════════════════════════════════════════════════

/// AppBar en profondeur : métal brossé éclairé en diagonale, arête
/// claire en haut, liseré de marque en bas, ombre portée.
///
/// Remplace le bloc `flexibleSpace: DecoratedBox(...)` recopié à
/// l'identique dans les 6 écrans de lib/fantasy.
class ReliefAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final Color? accent;
  final bool centerTitle;
  final double toolbarHeight;
  final PreferredSizeWidget? bottom;

  const ReliefAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.accent,
    this.centerTitle = true,
    this.toolbarHeight = kToolbarHeight,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final a = accent ?? AppColors.primaryInk;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      toolbarHeight: toolbarHeight,
      leading: leading,
      actions: actions,
      bottom: bottom,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      title: titleWidget ??
          (title == null
              ? null
              : Text(
                  title!,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                  ),
                )),
      flexibleSpace: DecoratedBox(
        decoration: AppSurfaces.chrome(),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(height: 1, color: AppSurfaces.edgeLight),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  color: a.withValues(alpha: 0.75),
                  boxShadow: AppSurfaces.glowOnly(a, strength: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ReliefDivider
// ════════════════════════════════════════════════════════════

/// Filet gravé : un trait sombre surmonté d'un trait clair. Donne
/// l'impression d'une rainure creusée dans la surface.
class ReliefDivider extends StatelessWidget {
  final double indent;
  final double height;

  const ReliefDivider({super.key, this.indent = 0, this.height = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: indent),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 1, color: AppSurfaces.edgeDark),
              Container(height: 1, color: AppSurfaces.edgeLight),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ReliefPill
// ════════════════════════════════════════════════════════════

/// Pastille bombée : compteur, statut, cote, montant.
class ReliefPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  /// Pastille pleine (fond coloré) plutôt que teintée.
  final bool solid;
  final double fontSize;

  const ReliefPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.solid = false,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final fg = solid ? AppSurfaces.inkOn(color) : color;
    final base = solid ? color : AppSurfaces.tint(AppColors.bgCard, color, 0.14);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: AppSurfaces.raisedGradient(base),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.9),
        boxShadow: AppSurfaces.raised(glow: solid ? color : null, elevation: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
