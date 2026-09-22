import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../pages/login_page.dart';
import 'app_shell.dart';

import 'theme.dart';

/// Routeur d'authentification — **mode réel uniquement** :
/// - backend configuré + session active → [AppShell]
/// - backend configuré, aucune session → [LoginPage]
/// - backend NON configuré → écran d'erreur de configuration
///   (plus de mode démo en production : compiler avec `./build_apk.sh`).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    if (!AppConfig.isBackendConfigured) return;
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isBackendConfigured) {
      return const _BackendNotConfiguredScreen();
    }
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    return loggedIn
        ? AppShell(
            onLogout: _signOut,
            userEmail: Supabase.instance.client.auth.currentUser?.email,
          )
        : const LoginPage();
  }
}

/// Affiché quand l'APK est compilé sans dart-defines : le mode démo a été
/// retiré — compilation commerciale obligatoire via `./build_apk.sh`.
class _BackendNotConfiguredScreen extends StatelessWidget {
  const _BackendNotConfiguredScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 56,
                color: AppColors.error,
              ),
              const SizedBox(height: 20),
              Text(
                'Configuration serveur manquante',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Cette application est compilée pour fonctionner avec le'
                'backend EyeSafe. Le mode démonstration a été retiré.\n\n'
                'Recompilez l\'APK avec ./build_apk.sh (dart-defines '
                'SUPABASE_URL et SUPABASE_ANON_KEY).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
