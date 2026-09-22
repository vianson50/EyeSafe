import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'core/backend.dart';
import 'core/push_service.dart';
import 'core/theme_settings.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
  );
  await initBackend();
  await PushService.init();
  await ThemeSettings.instance.load();
  runApp(const EyeSafeApp());
}

class EyeSafeApp extends StatelessWidget {
  const EyeSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeSettings.instance,
      builder: (context, _) => MaterialApp(
        title: 'EYESAFE',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeSettings.instance.value,
        // Bascule INSTANTANÉE : l'animation par défaut (200 ms) fait fondre
        // les surfaces Material pendant que les widgets personnalisés
        // (palette statique) basculent déjà → fenêtre de mélange noir/blanc.
        themeAnimationDuration: Duration.zero,
        home: const SplashScreen(),
      ),
    );
  }
}
