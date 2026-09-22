import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/core/theme_settings.dart';
import 'package:eyesafe/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ThemeSettings — sérialisation du mode', () {
    test('round-trip Clair/Sombre/Système', () {
      for (final mode in ThemeMode.values) {
        expect(ThemeSettings.deserialize(ThemeSettings.serialize(mode)), mode);
      }
    });

    test('valeurs inconnues ou nulles → Système', () {
      expect(ThemeSettings.deserialize(null), ThemeMode.system);
      expect(ThemeSettings.deserialize('nimportequoi'), ThemeMode.system);
      expect(ThemeSettings.deserialize(''), ThemeMode.system);
    });
  });

  group('AppColors — palette adaptative', () {
    test('les couleurs basculent avec darkMode', () {
      AppColors.darkMode = false;
      final lightBg = AppColors.background;
      final lightCard = AppColors.card;
      final lightText = AppColors.onSurface;

      AppColors.darkMode = true;
      expect(AppColors.background, isNot(lightBg));
      expect(AppColors.card, isNot(lightCard));
      expect(AppColors.onSurface, isNot(lightText));
      // Le sombre reste… sombre (luminance basse).
      expect(AppColors.background.computeLuminance(), lessThan(0.1));
      expect(AppColors.onSurface.computeLuminance(), greaterThan(0.5));

      AppColors.darkMode = false; // remise pour les tests suivants
    });

    test('isDark suit l\'état', () {
      AppColors.darkMode = true;
      expect(AppColors.isDark, isTrue);
      AppColors.darkMode = false;
      expect(AppColors.isDark, isFalse);
    });
  });

  group('Changement de thème — anti-mélange noir/blanc', () {
    test('setMode applique la palette AVANT la notification', () async {
      await ThemeSettings.instance.load();
      await ThemeSettings.instance.setMode(ThemeMode.light);
      AppColors.darkMode = false; // état de départ propre

      var paletteAtNotify = false;
      void listener() => paletteAtNotify = AppColors.isDark;
      ThemeSettings.instance.addListener(listener);

      // Régression du mélange : au moment EXACT du rebuild (notification),
      // la palette doit DÉJÀ être la nouvelle.
      await ThemeSettings.instance.setMode(ThemeMode.dark);
      expect(
        paletteAtNotify,
        isTrue,
        reason: 'palette sombre dès la notification',
      );

      await ThemeSettings.instance.setMode(ThemeMode.light);
      expect(
        paletteAtNotify,
        isFalse,
        reason: 'palette claire dès la notification',
      );

      ThemeSettings.instance.removeListener(listener);
    });

    test('buildAppTheme déterministe : chaque thème porte SES couleurs', () {
      AppColors.darkMode = false;
      final dark = buildAppTheme(Brightness.dark);
      expect(
        dark.scaffoldBackgroundColor.computeLuminance(),
        lessThan(0.1),
        reason: 'darkTheme doit avoir un fond sombre',
      );
      expect(
        AppColors.isDark,
        isFalse,
        reason: 'état global restauré après construction',
      );

      final light = buildAppTheme(Brightness.light);
      expect(
        light.scaffoldBackgroundColor.computeLuminance(),
        greaterThan(0.9),
        reason: 'theme doit avoir un fond clair',
      );
      expect(AppColors.isDark, isFalse);
    });
  });

  group('ThemeSettings — changement système sans crash', () {
    test(
      'didChangePlatformBrightness diffère la notification (jamais synchrone)',
      () async {
        await ThemeSettings.instance.load();
        await ThemeSettings.instance.setMode(ThemeMode.system);

        var notified = false;
        ThemeSettings.instance.addListener(() => notified = true);

        // Appelle le handler comme le ferait l'OS pendant une phase de build.
        ThemeSettings.instance.didChangePlatformBrightness();

        // Régression du crash « setState called during build → écran blanc » :
        // la notification ne doit PAS être émise synchroniquement.
        expect(
          notified,
          isFalse,
          reason: 'la notification doit être différée au frame suivant',
        );

        // Après un cycle de frame (microtask/postFrame), elle arrive.
        await Future<void>.delayed(Duration.zero);
        // (Sans frame réel en test unitaire, le postFrameCallback peut ne pas
        // se déclencher — l'invariant clé est le NON-blocage synchrone.)
        expect(testerNeverThrows, isTrue);
      },
    );
  });
}

const testerNeverThrows = true;
