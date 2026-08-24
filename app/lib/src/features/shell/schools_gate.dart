import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/entities.dart';
import '../../data/repositories/academic_repository.dart';
import '../../data/repositories/school_repository.dart';
import '../onboarding/onboarding_screen.dart';
import 'school_shell.dart';

/// After authentication: loads the user's school memberships and routes to
/// onboarding (no school yet) or the school shell.
class SchoolsGate extends StatefulWidget {
  final SupabaseClient client;

  const SchoolsGate({super.key, required this.client});

  @override
  State<SchoolsGate> createState() => _SchoolsGateState();
}

class _SchoolsGateState extends State<SchoolsGate> {
  late final SchoolRepository _schools;
  late final AcademicRepository _academics;
  late Future<List<SchoolMembership>> _future;

  @override
  void initState() {
    super.initState();
    _schools = SchoolRepository(widget.client);
    _academics = AcademicRepository(widget.client);
    _future = _schools.myMemberships();
  }

  void _reload() {
    setState(() {
      _future = _schools.myMemberships();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SchoolMembership>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your schools.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final memberships = snapshot.data ?? const [];
        if (memberships.isEmpty) {
          return OnboardingScreen(
            schools: _schools,
            academics: _academics,
            onDone: _reload,
          );
        }
        return SchoolShell(
          client: widget.client,
          memberships: memberships,
          onSchoolsChanged: _reload,
        );
      },
    );
  }
}