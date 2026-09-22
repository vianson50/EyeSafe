import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

/// Réglage du thème : Clair / Sombre / Système — mémorisé sur l'appareil.
///
/// - Positionne [AppColors.darkMode] pour la palette adaptative.
/// - Suit la luminosité du système en mode `system` (observer).
/// - Notifie l'UI (MaterialApp rebuilt) à chaque changement.
class ThemeSettings extends ValueNotifier<ThemeMode>
    with WidgetsBindingObserver {
  ThemeSettings._() : super(ThemeMode.system);

  static final ThemeSettings instance = ThemeSettings._();

  static const _prefsKey = 'eyesafe_theme_mode';

  bool _loaded = false;

  /// Charge le mode mémorisé (appelé au démarrage, avant le runApp).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addObserver(this);
    ThemeMode stored;
    try {
      final prefs = await SharedPreferences.getInstance();
      stored = deserialize(prefs.getString(_prefsKey));
    } catch (_) {
      stored = ThemeMode.system;
    }
    // Même ordre critique que setMode : palette AVANT la notification.
    AppColors.darkMode = _isDarkFor(stored);
    value = stored;
  }

  /// Change de mode, le mémorise et rafraîchit la palette.
  ///
  /// ⚠️ ORDRE CRITIQUE : la palette doit être appliquée AVANT l'affectation
  /// de [value] — celle-ci déclenche `notifyListeners` qui reconstruit le
  /// MaterialApp immédiatement. Si la palette était encore l'ancienne au
  /// moment du rebuild, le thème Material garderait les anciennes couleurs
  /// pendant que les widgets personnalisés basculent → mélange noir/blanc.
  Future<void> setMode(ThemeMode mode) async {
    if (value == mode) return;
    AppColors.darkMode = _isDarkFor(mode); // ① palette d'abord
    value = mode; // ② puis la (re)construction — palette déjà correcte
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // Stockage indisponible : réglage volatile pour cette session.
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (value != ThemeMode.system) return;
    _applyToPalette();
    // ⚠️ Ne JAMAIS notifier immédiatement : ce callback peut tomber pendant
    // une phase de build du framework (le changement de luminosité déclenche
    // aussi un rebuild du MaterialApp) → « setState() called during build »
    // → écran blanc. On diffère au frame suivant.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (value == ThemeMode.system) notifyListeners();
    });
  }

  /// Le mode sombre est-il effectivement actif ?
  bool get isDarkEffective {
    if (value == ThemeMode.dark) return true;
    if (value == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  /// Le mode sombre est-il effectivement actif pour [mode] ?
  /// (variant pure de [isDarkEffective] calculable AVANT l'affectation)
  static bool _isDarkFor(ThemeMode mode) {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  void _applyToPalette() {
    AppColors.darkMode = isDarkEffective;
  }

  /// Sérialisation stable pour les préférences.
  @visibleForTesting
  static String serialize(ThemeMode mode) => mode.name;

  @visibleForTesting
  static ThemeMode deserialize(String? stored) => switch (stored) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
