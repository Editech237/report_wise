import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/entities.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';

/// Current user's school memberships (with joined schools). Auto-refreshes when auth changes.
/// Replaces SchoolsGate's FutureBuilder + manual _reload setState.
final myMembershipsProvider = FutureProvider<List<SchoolMembership>>((ref) async {
  // Rebuild on any auth event (signIn/signOut)
  ref.watch(authStateProvider);
  final repo = ref.watch(schoolRepositoryProvider);
  if (repo == null) return [];
  return repo.myMemberships();
});

/// Selected school membership — UI writes here via StateProvider instead of local _current setState.
final selectedMembershipProvider = StateProvider<SchoolMembership?>((ref) => null);

/// Selected AppSection for the shell — replaces _section setState.
final selectedSectionProvider = StateProvider<String>((ref) => 'dashboard');
