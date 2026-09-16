import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/schools_provider.dart';
import '../../core/widgets/shimmer.dart';
import '../onboarding/onboarding_screen.dart';
import 'school_shell.dart';

/// After authentication: loads the user's school memberships and routes to
/// onboarding (no school yet) or the school shell. Riverpod AsyncValue replaces
/// FutureBuilder + setState reload.
class SchoolsGate extends ConsumerWidget {
  const SchoolsGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membershipsAsync = ref.watch(myMembershipsProvider);

    return membershipsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: Padding(padding: EdgeInsets.all(24), child: ShimmerPanel())),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your schools.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(myMembershipsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (memberships) {
        if (memberships.isEmpty) {
          final schools = ref.watch(schoolRepositoryProvider);
          final academics = ref.watch(academicRepositoryProvider);
          if (schools == null || academics == null) {
            return const Scaffold(body: Center(child: Text('Repositories not ready')));
          }
          return OnboardingScreen(
            schools: schools,
            academics: academics,
            onDone: () => ref.invalidate(myMembershipsProvider),
          );
        }
        return SchoolShell(
          memberships: memberships,
          onSchoolsChanged: () => ref.invalidate(myMembershipsProvider),
        );
      },
    );
  }
}
