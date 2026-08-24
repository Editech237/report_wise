/// Compile-time configuration.
///
/// Pass at run/build time:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}