// ============================================================
// Plugbet – Wordmark / logo de marque réutilisable
// ============================================================
// Deux façons d'afficher la marque dans l'app :
//
//  • [PlugbetWordmark] : le wordmark en TEXTE (« PLUG » + « BET »),
//    gras + italique. Recolorable selon le fond — sur fond sombre on
//    passe « PLUG » en blanc et « BET » en vert d'accent (c'est la
//    version voulue pour la topbar Paris). C'est la seule variante
//    lisible sur fond bleu-nuit, car le « BET » de logo_home.png est
//    noir (invisible sur sombre).
//
//  • [PlugbetLogoImage] : l'image `assets/icon/logo_home.png` (le
//    wordmark PLUG vert / BET noir sur fond transparent). À réserver
//    aux surfaces claires (splash, écran de connexion, cartes claires).
//
// `app_icon.png` reste l'icône carrée du launcher — ne PAS l'utiliser
// comme logo in-app.
// ============================================================

import 'package:flutter/material.dart';

/// Vert d'accent du wordmark (repris de la charte : #2ECC71).
const Color kPlugbetGreen = Color(0xFF2ECC71);

/// Wordmark « PLUGBET » en texte, gras + italique, deux tons.
///
/// Par défaut : « PLUG » blanc + « BET » vert (pensé pour un fond
/// sombre). Passer [plugColor] pour l'adapter à un fond clair.
class PlugbetWordmark extends StatelessWidget {
  final double fontSize;

  /// Couleur du segment « PLUG ». Blanc par défaut (fond sombre).
  final Color plugColor;

  /// Couleur du segment « BET ». Vert d'accent par défaut.
  final Color betColor;

  const PlugbetWordmark({
    super.key,
    this.fontSize = 24,
    this.plugColor = Colors.white,
    this.betColor = kPlugbetGreen,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.5,
      height: 1,
    );

    return Semantics(
      label: 'PLUGBET',
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: 'PLUG', style: base.copyWith(color: plugColor)),
            TextSpan(text: 'BET', style: base.copyWith(color: betColor)),
          ],
        ),
      ),
    );
  }
}

/// Le logo image, ADAPTATIF au thème :
///  • thème clair  -> `logo_home.png` (BET noir, pensé pour fond clair)
///  • thème sombre -> `logo_home_sombre.png` (lisible sur fond sombre)
/// Utilisé en haut de la page d'accueil et dans l'onglet Menu.
class PlugbetLogoImage extends StatelessWidget {
  final double height;
  final BoxFit fit;

  const PlugbetLogoImage({
    super.key,
    this.height = 34,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      isDark ? 'assets/icon/logo_home_sombre.png' : 'assets/icon/logo_home.png',
      height: height,
      fit: fit,
      semanticLabel: 'PLUGBET',
      errorBuilder: (_, __, ___) => PlugbetWordmark(
        fontSize: height * 0.7,
        plugColor: isDark ? Colors.white : kPlugbetGreen,
        betColor: isDark ? kPlugbetGreen : Colors.black,
      ),
    );
  }
}
