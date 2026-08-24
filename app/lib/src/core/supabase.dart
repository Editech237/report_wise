import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

/// Initializes the global Supabase client. Safe to call multiple times.
Future<void> initSupabase() async {
  if (!AppConfig.isConfigured) {
    throw StateError(
        'Supabase is not configured. Pass --dart-define=SUPABASE_URL and '
        '--dart-define=SUPABASE_ANON_KEY.');
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      persistSession: false,
      localStorage: EmptyLocalStorage(),
    ),
  );
}