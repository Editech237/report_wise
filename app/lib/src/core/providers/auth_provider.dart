import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_provider.dart';

/// Emits the current auth state — driven by Supabase's onAuthStateChange.
/// UI watches this to decide AuthScreen vs SchoolsGate without manual ListenableBuilder.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream.empty();
  return client.auth.onAuthStateChange;
});

/// Current session (null → not signed in). Watches authState stream so it rebuilds on signIn/signOut.
final currentSessionProvider = Provider<Session?>((ref) {
  // Watch the stream to trigger rebuilds; value itself comes from client
  ref.watch(authStateProvider);
  final client = ref.watch(supabaseClientProvider);
  return client?.auth.currentSession;
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  final client = ref.watch(supabaseClientProvider);
  return client?.auth.currentUser;
});
