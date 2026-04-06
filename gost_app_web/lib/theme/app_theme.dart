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

  // --- Fond principal (adaptatif dark/light) ---
  static Color get bgDark => _isDark ? const Color(0xFF040810) : const Color(0xFFF4F6FA);
  static Color get bgBlueNight => _isDark ? const Color(0xFF0B1726) : const Color(0xFFE8EEFF);
  static Color get bgCard => _isDark ? const Color(0xFF0E1A2E) : const Color(0xFFFFFFFF);
  static Color get bgCardLight => _isDark ? const Color(0xFF142035) : const Color(0xFFF0F4FF);
  static Color get bgElevated => _isDark ? const Color(0xFF182842) : const Color(0xFFE8EEFF);

  // --- Accents (plus foncés en mode clair pour contraste sur blanc) ---
  static Color get neonGreen => _isDark ? const Color(0xFF00E676) : const Color(0xFF00A854);
  static Color get neonRed => _isDark ? const Color(0xFFFF1744) : const Color(0xFFD32F2F);
  static Color get neonYellow => _isDark ? const Color(0xFFFFD600) : const Color(0xFFF9A825);
  static Color get neonBlue => _isDark ? const Color(0xFF448AFF) : const Color(0xFF1565C0);
  static Color get neonOrange => _isDark ? const Color(0xFFFF9100) : const Color(0xFFE65100);
  static Color get neonPurple => _isDark ? const Color(0xFFE040FB) : const Color(0xFF9C27B0);

  // --- Texte (adaptatif) ---
  static Color get textPrimary => _isDark ? const Color(0xFFF0F2F5) : const Color(0xFF1A2035);
  static Color get textSecondary => _isDark ? const Color(0xFF8E99A4) : const Color(0xFF4A5568);
  static Color get textMuted => _isDark ? const Color(0xFF4A5568) : const Color(0xFF9BA3AF);

  // --- Surfaces (adaptatif) ---
  static Color get divider => _isDark ? const Color(0xFF1A2940) : const Color(0xFFE0E6EF);
  static Color get shimmerBase => _isDark ? const Color(0xFF0F1B2D) : const Color(0xFFE8EEFF);
  static Color get shimmerHighlight => _isDark ? const Color(0xFF1A2940) : const Color(0xFFF4F6FA);

  // --- Gradients (adaptatif) ---
  static LinearGradient get bgGradient => _isDark
      ? LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF040810), Color(0xFF0B1726), Color(0xFF091320)],
          stops: [0.0, 0.5, 1.0],
        )
      : LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFF4F6FA), Color(0xFFECF0FA), Color(0xFFE8EEFF)],
          stops: [0.0, 0.5, 1.0],
        );

  static LinearGradient get cardGradient => _isDark
      ? LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0E1A2E), Color(0xFF142035)],
        )
      : LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF0F4FF)],
        );

  static LinearGradient get liveGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1B0A0A), Color(0xFF0A1628)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFFF0F0), Color(0xFFF0F4FF)],
        );

  static LinearGradient get goalGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.centerLeft, end: Alignment.centerRight,
          colors: [Color(0x3300E676), Colors.transparent],
        )
      : const LinearGradient(
          begin: Alignment.centerLeft, end: Alignment.centerRight,
          colors: [Color(0x2200C853), Colors.transparent],
        );

  static LinearGradient get headerGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0D1F35), Color(0xFF0A1628)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
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
  Color get appCardLightColor => _isDark ? AppColors.bgCardLight : AppColors.lightCardElevated;
  Color get appElevatedColor => _isDark ? AppColors.bgElevated : const Color(0xFFE8EEFF);

  // Textes
  Color get appTextPrimary => _isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
  Color get appTextSecondary => _isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
  Color get appTextMuted => _isDark ? AppColors.textMuted : AppColors.lightTextMuted;

  // Séparateurs
  Color get appDividerColor => _isDark ? AppColors.divider : AppColors.lightDivider;

  // Gradient de fond principal
  LinearGradient get appBgGradient =>
      _isDark ? AppColors.bgGradient : AppColors.lightBgGradient;

  // BoxDecoration prête à l'emploi
  BoxDecoration get appBgDecoration =>
      BoxDecoration(gradient: appBgGradient);
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
      colorScheme: ColorScheme.light(
        primary: Color(0xFF00C853),
        secondary: AppColors.neonBlue,
        surface: Colors.white,
        error: AppColors.neonRed,
        onPrimary: Colors.white,
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
        selectedItemColor: Color(0xFF00C853),
        unselectedItemColor: Color(0xFF8E99A4),
        type: BottomNavigationBarType.fixed,
        elevation: 4,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A2035),
        ),
        iconTheme: IconThemeData(color: Color(0xFF1A2035)),
      ),
      dividerTheme: DividerThemeData(
        color: Color(0xFFE0E6EF), thickness: 0.5,
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
        primary: AppColors.neonGreen,
        secondary: AppColors.neonBlue,
        surface: Color(0xFF0E1A2E),
        error: AppColors.neonRed,
        onPrimary: Color(0xFF040810),
        onSecondary: Color(0xFFF0F2F5),
        onSurface: Color(0xFFF0F2F5),
        onError: Color(0xFFF0F2F5),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 48, fontWeight: FontWeight.w800,
          color: Color(0xFFF0F2F5), letterSpacing: -1.5,
        ),
        displayMedium: TextStyle(
          fontSize: 34, fontWeight: FontWeight.w700,
          color: Color(0xFFF0F2F5), letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w700,
          color: Color(0xFFF0F2F5),
        ),
        titleLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600,
          color: Color(0xFFF0F2F5),
        ),
        titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600,
          color: Color(0xFFF0F2F5),
        ),
        bodyLarge: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w400,
          color: Color(0xFFF0F2F5),
        ),
        bodyMedium: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w400,
          color: Color(0xFF8E99A4),
        ),
        bodySmall: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w400,
          color: Color(0xFF4A5568),
        ),
        labelLarge: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600,
          color: AppColors.neonGreen, letterSpacing: 0.5,
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
        selectedItemColor: AppColors.neonGreen,
        unselectedItemColor: Color(0xFF4A5568),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF0F2F5),
        ),
        iconTheme: IconThemeData(color: Color(0xFFF0F2F5)),
      ),
      dividerTheme: DividerThemeData(
        color: Color(0xFF1A2940), thickness: 0.5,
      ),
    );
  }
}
