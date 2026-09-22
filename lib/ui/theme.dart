import 'package:flutter/material.dart';

/// Palette adaptative Clair/Sombre.
///
/// Les couleurs sont des **getters** pilotés par [darkMode] : tous les
/// widgets qui référencent `AppColors.…` s'adaptent au thème sans
/// changement de code. Le mode est piloté par `ThemeSettings`
/// (`core/theme_settings.dart`).
class AppColors {
  AppColors._();

  static bool _dark = false;

  /// État sombre global — positionné par ThemeSettings au démarrage et
  /// à chaque bascule (y compris suivie du système).
  static set darkMode(bool value) => _dark = value;

  static bool get isDark => _dark;

  // ── Fonds & surfaces ──
  static Color get background =>
      _dark ? const Color(0xFF0F1420) : const Color(0xFFFFFFFF);
  static Color get sidebar =>
      _dark ? const Color(0xFF121826) : const Color(0xFFFAFBFD);
  static Color get surfaceLow =>
      _dark ? const Color(0xFF161D2E) : const Color(0xFFF7F8FB);
  static Color get surface =>
      _dark ? const Color(0xFF1B2334) : const Color(0xFFF2F4F8);
  static Color get surfaceHigh =>
      _dark ? const Color(0xFF232D42) : const Color(0xFFEAEDF3);

  /// Cartes / dialogs / surfaces « blanches » du mode clair.
  static Color get card => _dark ? const Color(0xFF161D2E) : Colors.white;

  static Color get terminal =>
      _dark ? const Color(0xFF0C111C) : const Color(0xFFF8FAFC);

  // ── Textes ──
  static Color get onSurface =>
      _dark ? const Color(0xFFE7EAF2) : const Color(0xFF161B26);
  static Color get onSurfaceVariant =>
      _dark ? const Color(0xFFA6ADC0) : const Color(0xFF5E6575);
  static Color get onSurfaceFaint =>
      _dark ? const Color(0xFF7A8199) : const Color(0xFF8B92A3);

  // ── Contours ──
  static Color get outline =>
      _dark ? const Color(0xFF2C3750) : const Color(0xFFD8DCE4);
  static Color get outlineVariant =>
      _dark ? const Color(0xFF232D42) : const Color(0xFFE7EAF0);

  // ── Marque (légèrement éclaircie en sombre pour le contraste) ──
  static Color get primary =>
      _dark ? const Color(0xFF8B6BE8) : const Color(0xFF6D3BD7);
  static Color get primaryDim =>
      _dark ? const Color(0xFF7A56D6) : const Color(0xFF592CB4);
  static Color get primaryContainer =>
      _dark ? const Color(0xFF2A2350) : const Color(0xFFEFE8FF);
  static Color get onPrimaryContainer =>
      _dark ? const Color(0xFFC9BAFF) : const Color(0xFF3A1691);

  static Color get secondary =>
      _dark ? const Color(0xFF38B6D6) : const Color(0xFF0891B2);
  static Color get secondaryContainer =>
      _dark ? const Color(0xFF113646) : const Color(0xFFE0F5FA);

  static Color get tertiary =>
      _dark ? const Color(0xFF34C98E) : const Color(0xFF0C9E6C);
  static Color get tertiaryContainer =>
      _dark ? const Color(0xFF123B2B) : const Color(0xFFDFF6EC);

  static Color get error =>
      _dark ? const Color(0xFFF06A6A) : const Color(0xFFDC2626);
}

const _jakarta = 'Plus Jakarta Sans';
const _mono = 'JetBrains Mono';

TextStyle monoStyle(
  double size, {
  FontWeight weight = FontWeight.w500,
  double letterSpacing = 0,
  Color? color,
  double? height,
}) {
  return TextStyle(
    fontFamily: _mono,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
    height: height,
  );
}

/// Thème Material — les surfaces et textes suivent [AppColors].
///
/// DÉTERMINISTE : le ThemeData construit porte TOUJOURS les couleurs de SA
/// luminosité, quel que soit l'état global au moment de l'appel (le flag
/// global est positionné le temps de la lecture puis restauré). Sans ça,
/// `theme:` et `darkTheme:` construits l'un après l'autre au même rebuild
/// pouvaient embarquer des couleurs mélangées.
ThemeData buildAppTheme(Brightness brightness) {
  final previousDark = AppColors.isDark;
  AppColors.darkMode = brightness == Brightness.dark;
  try {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        surface: AppColors.background,
        onSurface: AppColors.onSurface,
        surfaceContainerHighest: AppColors.surfaceHigh,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        tertiary: AppColors.tertiary,
        onTertiary: Colors.white,
        error: AppColors.error,
        onError: Colors.white,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(fontFamily: _jakarta)
          .apply(
            bodyColor: AppColors.onSurface,
            displayColor: AppColors.onSurface,
          ),
      dividerTheme: DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
      ),
      // Snackbars : fond onSurface (sombre en clair / clair en sombre) →
      // le texte DOIT prendre la couleur inverse (background) sinon texte
      // illisible (« flou ») en mode sombre.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.onSurface,
        contentTextStyle: TextStyle(
          color: AppColors.background,
          fontFamily: _jakarta,
          fontSize: 14,
        ),
        actionTextColor: AppColors.background,
      ),
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );
  } finally {
    // Restaure l'état global — c'est ThemeSettings qui le possède.
    AppColors.darkMode = previousDark;
  }
}
