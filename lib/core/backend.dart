import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

/// Initialise Supabase si la configuration est présente.
/// Sans configuration, l'application fonctionne en mode démo.
Future<void> initBackend() async {
  if (!AppConfig.isBackendConfigured) return;
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
}

/// Client Supabase, ou `null` en mode démo.
SupabaseClient? get backend =>
    AppConfig.isBackendConfigured ? Supabase.instance.client : null;
