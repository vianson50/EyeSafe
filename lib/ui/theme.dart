import 'package:flutter/material.dart';

/// Palette NOIR & BLANC + accents sémantiques.
///
/// Fond et texte sont monochromes (noir en mode sombre — le mode par
/// défaut de l'app —, blanc en mode clair). Les couleurs d'accent ont
/// une SIGNIFICATION fixe, définie par le produit :
///   • [focus]  (jaune) — mise au point / recentrage ;
///   • [record] (rouge) — enregistrement / replay ;
///   • [primary]/[options] (bleu) — options & paramètres, actions ;
///   • [secondary]/[menu] (gris) — menus secondaires, éléments neutres.
///
/// Les couleurs sont des **getters** pilotés par [darkMode] : tous les
/// widgets qui référencent `AppColors.…` s'adaptent au thème sans
/// changement de code. Le mode est piloté par `ThemeSettings`
/// (`core/theme_settings.dart`).
class AppColors {
  AppColors._();

  static bool _dark = true;

  /// État sombre global — positionné par ThemeSettings au démarrage et
  /// à chaque bascule (y compris suivie du système).
  static set darkMode(bool value) => _dark = value;

  static bool get isDark => _dark;

  // ── Fonds & surfaces — NOIR / BLANC ──
  static Color get background =>
      _dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color get sidebar =>
      _dark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA);
  static Color get surfaceLow =>
      _dark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F5);
  static Color get surface =>
      _dark ? const Color(0xFF141414) : const Color(0xFFEFEFEF);
  static Color get surfaceHigh =>
      _dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E5E5);

  /// Cartes / dialogs — noir profond en sombre, blanc pur en clair.
  static Color get card => _dark ? const Color(0xFF0D0D0D) : Colors.white;

  static Color get terminal =>
      _dark ? const Color(0xFF050505) : const Color(0xFFF7F7F7);

  // ── Textes — blanc / noir ──
  static Color get onSurface =>
      _dark ? const Color(0xFFFFFFFF) : const Color(0xFF0A0A0A);
  static Color get onSurfaceVariant =>
      _dark ? const Color(0xFFB8B8B8) : const Color(0xFF4A4A4A);
  static Color get onSurfaceFaint =>
      _dark ? const Color(0xFF7A7A7A) : const Color(0xFF6E6E6E);

  // ── Contours ──
  static Color get outline =>
      _dark ? const Color(0xFF2A2A2A) : const Color(0xFFD4D4D4);
  static Color get outlineVariant =>
      _dark ? const Color(0xFF1C1C1C) : const Color(0xFFE8E8E8);

  // ── BLEU : options / paramètres / actions principales ──
  static Color get primary =>
      _dark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
  static Color get primaryDim =>
      _dark ? const Color(0xFF2563EB) : const Color(0xFF1E40AF);
  static Color get primaryContainer =>
      _dark ? const Color(0xFF0E1E38) : const Color(0xFFDBEAFE);
  static Color get onPrimaryContainer =>
      _dark ? const Color(0xFFBFDBFE) : const Color(0xFF1E3A8A);

  // ── GRIS : menus secondaires / éléments neutres ──
  static Color get secondary =>
      _dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  static Color get secondaryContainer =>
      _dark ? const Color(0xFF1F1F1F) : const Color(0xFFF3F4F6);

  static Color get tertiary =>
      _dark ? const Color(0xFFD4D4D4) : const Color(0xFF525252);
  static Color get tertiaryContainer =>
      _dark ? const Color(0xFF1A1A1A) : const Color(0xFFF0F0F0);

  // ── ROUGE : enregistrement / erreurs ──
  static Color get error =>
      _dark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

  /// Bouton d'enregistrement / replay (rouge).
  static Color get record => error;

  // ── JAUNE : mise au point / recentrage ──
  static Color get focus =>
      _dark ? const Color(0xFFFACC15) : const Color(0xFFCA8A04);

  // ── Alias sémantiques (lisibilité du code appelant) ──

  /// Options / paramètres → bleu.
  static Color get options => primary;

  /// Menus secondaires → gris.
  static Color get menu => secondary;
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
