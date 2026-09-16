import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides the global SupabaseClient. Overridden in main() after init.
/// Nullable for widget tests where no Supabase is configured.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);
