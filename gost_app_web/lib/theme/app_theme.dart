// ============================================================
// Plugbet – Thème sombre premium
// Fond noir → bleu nuit, accents néon vert/rouge
// Utilise la police système (fonctionne offline)
// ============================================================

import 'package:flutter/material.dart';

class AppColors {
  // ─── Brightness global (mis à jour par le MaterialApp builder) ───
  static bool _isDark = true;
  static void updateBrightness(Brightness b) => _isDark = b == Brightness.dark;

  /// Exposé pour AppSurfaces : les tokens de relief doivent adapter
  /// leurs ombres/biseaux au mode courant (ombre noire dense en sombre,
  /// ombre douce + arête blanche en clair).
  static bool get isDark => _isDark;

  // --- Tokens dedies a la page Games ---
  static const Color transparent = Color(0x00000000);
  static Color get gamesBackground =>
      _isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF2F3F5);
  static Color get gamesSurface =>
      _isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
  static Color get gamesSurfaceElevated =>
      _isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color get gamesBorder =>
      _isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0);
  static Color get gamesTextPrimary =>
      _isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A);
  static Color get gamesTextSecondary =>
      _isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6B6B6B);
  static Color get gamesAccent => primary;
  static Color get gamesAccentDeep => primary;
  static Color get gamesAccentSoft =>
      primary.withValues(alpha: _isDark ? 0.20 : 0.12);
  static const Color gamesOrange = Color(0xFFFFA726);
  static const Color gamesYellow = Color(0xFFFFB300);
  static const Color gamesOnAccent = Color(0xFFFFFFFF);
  static Color get gamesMutedIcon =>
      _isDark ? const Color(0xFF757575) : const Color(0xFF9E9E9E);
  static Color get gamesSoftShadow =>
      _isDark ? transparent : const Color(0x1F000000);
  static Color get gamesCardShadow =>
      _isDark ? transparent : const Color(0x14000000);
  static const Color gamesImageText = Color(0xFFFFFFFF);
  static const Color gamesImageTextMuted = Color(0xFFD8D8D8);
  static const Color gamesImageOverlayClear = Color(0x00000000);
  static const Color gamesImageOverlaySoft = Color(0x66000000);
  static const Color gamesImageOverlayStrong = Color(0xD9000000);
  static const Color gamesImageControlBg = Color(0x99000000);
  static const Color gamesImageFallbackStart = Color(0xFF263238);
  static const Color gamesImageFallbackEnd = Color(0xFF111111);
  static const Color gamesImageFallbackIcon = Color(0x66FFFFFF);
  static Color get bottomNavBackground =>
      _isDark ? const Color(0xFF0D0D0D) : const Color(0xFFFFFFFF);
  static Color get bottomNavBorder =>
      _isDark ? const Color(0xFF121212) : const Color(0xFFE0E0E0);
  static Color get bottomNavInactive =>
      _isDark ? const Color(0xFF757575) : const Color(0xFF9E9E9E);
  static Color get bottomNavShadow =>
      _isDark ? const Color(0x99000000) : const Color(0x1A000000);
  static const Color bottomNavBadge = Color(0xFFFFA726);
  static Color get bettingBackground =>
      _isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF2F3F5);
  static Color get bettingSurface =>
      _isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
  static Color get bettingSurfaceElevated =>
      _isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color get bettingBorder =>
      _isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0);
  static Color get bettingTextPrimary =>
      _isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A);
  static Color get bettingTextSecondary =>
      _isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6B6B6B);
  static Color get bettingInactive =>
      _isDark ? const Color(0xFF757575) : const Color(0xFF9E9E9E);
  static Color get bettingSoftShadow =>
      _isDark ? transparent : const Color(0x1F000000);
  static const Color bettingViolet = Color(0xFF7C4DFF);
  static const Color bettingOrange = Color(0xFFFF9800);
  static const Color bettingYellow = Color(0xFFFFB300);
  static const Color bettingOnImage = Color(0xFFFFFFFF);
  static const Color bettingOnImageMuted = Color(0xFFD8D8D8);
  static const Color bettingImageOverlayClear = Color(0x00000000);
  static const Color bettingImageOverlaySoft = Color(0x66000000);
  static const Color bettingImageOverlayStrong = Color(0xD9000000);
  static const Color bettingImageScrim = Color(0x73000000);

  // --- Fond principal (adaptatif dark/light) ---
  static Color get bgDark =>
      _isDark ? const Color(0xFF040810) : const Color(0xFFF4F6FA);
  static Color get bgBlueNight =>
      _isDark ? const Color(0xFF0B1726) : const Color(0xFFE8EEFF);
  static Color get bgCard =>
      _isDark ? const Color(0xFF0E1A2E) : const Color(0xFFFFFFFF);
  static Color get bgCardLight =>
      _isDark ? const Color(0xFF142035) : const Color(0xFFF0F4FF);
  static Color get bgElevated =>
      _isDark ? const Color(0xFF182842) : const Color(0xFFE8EEFF);

  // ═══ Couleur de marque — trois rôles ════════════════════════
  // Un seul vert ne peut pas tout faire : #00E676 est éclatant en
  // remplissage mais tombe à 1.67:1 sur blanc, donc invisible en trait.
  // On sépare donc « ce qu'on remplit » de « ce qu'on trace ».

  /// Remplissage : bouton plein, badge, barre de progression, pastille.
  /// Toujours associé à [onPrimary] par-dessus.
  static Color get primary =>
      _isDark ? const Color(0xFF00A854) : const Color(0xFF00E676);

  /// Trait : bordure, liseré de cadre, icône, titre. Lisible sur toutes
  /// les surfaces (7.1:1 sur fond sombre, 2.8:1 sur blanc).
  static const Color primaryInk = Color(0xFF00A854);

  /// Variante profonde pour du **petit texte** vert sur fond clair,
  /// là où [primaryInk] ne suffirait pas (6.1:1 sur blanc → AA).
  static Color get primaryDeep =>
      _isDark ? const Color(0xFF00A854) : const Color(0xFF00713A);

  /// Encre à poser SUR [primary] (12:1 en clair, 7.5:1 en sombre).
  static const Color onPrimary = Color(0xFF031409);

  // --- Accents (plus foncés en mode clair pour contraste sur blanc) ---
  /// ⚠️ Réservé aux **jeux** (accents néon vifs validés lot par lot).
  /// Pour le chrome et les écrans de l'app, utiliser [primary] /
  /// [primaryInk] : le cadre reste sobre, les jeux restent vifs.
  static Color get neonGreen => primary;
  static Color get neonRed =>
      _isDark ? const Color(0xFFFF1744) : const Color(0xFFD32F2F);
  static Color get neonYellow =>
      _isDark ? const Color(0xFFFFD600) : const Color(0xFFF9A825);
  static Color get neonBlue =>
      _isDark ? const Color(0xFF448AFF) : const Color(0xFF1565C0);
  static Color get neonOrange =>
      _isDark ? const Color(0xFFFF9100) : const Color(0xFFE65100);
  static Color get neonPurple =>
      _isDark ? const Color(0xFFE040FB) : const Color(0xFF9C27B0);

  // --- Texte (adaptatif) ---
  static Color get textPrimary =>
      _isDark ? const Color(0xFFF0F2F5) : const Color(0xFF1A2035);
  static Color get textSecondary =>
      _isDark ? const Color(0xFF8E99A4) : const Color(0xFF4A5568);
  static Color get textMuted =>
      _isDark ? const Color(0xFF4A5568) : const Color(0xFF9BA3AF);

  // --- Surfaces (adaptatif) ---
  static Color get divider =>
      _isDark ? const Color(0xFF1A2940) : const Color(0xFFE0E6EF);
  static Color get shimmerBase =>
      _isDark ? const Color(0xFF0F1B2D) : const Color(0xFFE8EEFF);
  static Color get shimmerHighlight =>
      _isDark ? const Color(0xFF1A2940) : const Color(0xFFF4F6FA);

  // --- Gradients (adaptatif) ---
  static LinearGradient get bgGradient => _isDark
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF040810), Color(0xFF0B1726), Color(0xFF091320)],
          stops: [0.0, 0.5, 1.0],
        )
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4F6FA), Color(0xFFECF0FA), Color(0xFFE8EEFF)],
          stops: [0.0, 0.5, 1.0],
        );

  static LinearGradient get cardGradient => _isDark
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1A2E), Color(0xFF142035)],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF0F4FF)],
        );

  static LinearGradient get liveGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B0A0A), Color(0xFF0A1628)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF0F0), Color(0xFFF0F4FF)],
        );

  static LinearGradient get goalGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x3300E676), Colors.transparent],
        )
      : const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x2200C853), Colors.transparent],
        );

  static LinearGradient get headerGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1F35), Color(0xFF0A1628)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8EEFF), Color(0xFFF0F4FF)],
        );

  // --- Couleurs mode clair ---
  static const Color lightBg = Color(0xFFF4F6FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardElevated = Color(0xFFF0F4FF);
  static const Color lightDivider = Color(0xFFE0E6EF);
  static const Color lightTextPrimary = Color(0xFF1A2035);
  static const Color lightTextSecondary = Color(0xFF4A5568);
  static const Color lightTextMuted = Color(0xFF9BA3AF);

  static const LinearGradient lightBgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [lightBg, Color(0xFFECF0FA), Color(0xFFE8EEFF)],
    stops: [0.0, 0.5, 1.0],
  );
}

/// Extension pour accéder aux couleurs adaptées au thème courant
extension ThemeColors on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;

  // Fonds
  Color get appBgColor => _isDark ? AppColors.bgDark : AppColors.lightBg;
  Color get appCardColor => _isDark ? AppColors.bgCard : AppColors.lightCard;
  Color get appCardLightColor =>
      _isDark ? AppColors.bgCardLight : AppColors.lightCardElevated;
  Color get appElevatedColor =>
      _isDark ? AppColors.bgElevated : const Color(0xFFE8EEFF);

  // Textes
  Color get appTextPrimary =>
      _isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
  Color get appTextSecondary =>
      _isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
  Color get appTextMuted =>
      _isDark ? AppColors.textMuted : AppColors.lightTextMuted;

  // Séparateurs
  Color get appDividerColor =>
      _isDark ? AppColors.divider : AppColors.lightDivider;

  // Gradient de fond principal
  LinearGradient get appBgGradient =>
      _isDark ? AppColors.bgGradient : AppColors.lightBgGradient;

  // BoxDecoration prête à l'emploi
  BoxDecoration get appBgDecoration => BoxDecoration(gradient: appBgGradient);
  BoxDecoration get appCardDecoration => BoxDecoration(
        color: appCardColor,
        borderRadius: BorderRadius.circular(16),
      );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFFF4F6FA),
      // Littéraux volontaires : ces getters sont évalués sans garantie
      // sur l'ordre d'appel de AppColors.updateBrightness().
      colorScheme: ColorScheme.light(
        primary: Color(0xFF00E676),
        secondary: AppColors.neonBlue,
        surface: Colors.white,
        error: AppColors.neonRed,
        onPrimary: AppColors.onPrimary,
        onSecondary: Colors.white,
        onSurface: Color(0xFF1A2035),
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primaryInk,
        unselectedItemColor: Color(0xFF8E99A4),
        type: BottomNavigationBarType.fixed,
        elevation: 4,
        selectedLabelStyle:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        // Material 3 reteinte l'AppBar au défilement : c'est ce qui la
        // fait paraître sale et plate. On neutralise, le relief vient
        // de ReliefAppBar.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A2035),
        ),
        iconTheme: IconThemeData(color: Color(0xFF1A2035)),
      ),
      dividerTheme: DividerThemeData(
        color: Color(0xFFE0E6EF),
        thickness: 0.5,
      ),
      elevatedButtonTheme: _elevatedButtons(Colors.black26),
    );
  }

  /// Les appels `ElevatedButton.styleFrom(...)` de l'app ne fixent pas
  /// l'élévation : elle vient donc d'ici, et aucun bouton ne reste plat.
  static ElevatedButtonThemeData _elevatedButtons(Color shadow) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 5,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFF040810),
      colorScheme: ColorScheme.dark(
        primary: Color(0xFF00A854),
        secondary: AppColors.neonBlue,
        surface: Color(0xFF0E1A2E),
        error: AppColors.neonRed,
        onPrimary: AppColors.onPrimary,
        onSecondary: Color(0xFFF0F2F5),
        onSurface: Color(0xFFF0F2F5),
        onError: Color(0xFFF0F2F5),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w800,
          color: Color(0xFFF0F2F5),
          letterSpacing: -1.5,
        ),
        displayMedium: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF0F2F5),
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF0F2F5),
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF0F2F5),
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF0F2F5),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: Color(0xFFF0F2F5),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFF8E99A4),
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFF4A5568),
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryInk,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF0E1A2E),
        elevation: 4,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF040810),
        selectedItemColor: AppColors.primaryInk,
        unselectedItemColor: Color(0xFF4A5568),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        unselectedLabelStyle:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF0F2F5),
        ),
        iconTheme: IconThemeData(color: Color(0xFFF0F2F5)),
      ),
      dividerTheme: DividerThemeData(
        color: Color(0xFF1A2940),
        thickness: 0.5,
      ),
      elevatedButtonTheme: _elevatedButtons(Colors.black87),
    );
  }
}
