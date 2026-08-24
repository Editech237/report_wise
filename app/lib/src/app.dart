import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';
import 'features/shell/schools_gate.dart';

/// ReportWise — Cameroon Secondary School Management Platform.
///
/// One codebase targeting Windows/macOS/Linux desktop and Android/iOS for
/// the offline-first teacher app.
///
/// When no Supabase client is supplied (e.g. widget tests), the app shows the
/// standalone engine demo.
class ReportWiseApp extends StatelessWidget {
  final SupabaseClient? client;

  const ReportWiseApp({super.key, this.client});

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'ReportWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: client == null
          ? const HomeScreen()
          : AuthGate(client: client!),
    );
    if (client == null) return app;

    // Rebuild GateScreen when the auth state changes.
    return ListenableBuilder(
      listenable: _AuthStateNotifier(client!),
      builder: (context, _) => app,
    );
  }
}

/// Minimal ChangeNotifier bridging Supabase's auth state stream so the widget
/// tree rebuilds on sign-in/out without extra packages.
class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier(SupabaseClient client) {
    client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

/// Routes on the current session: sign-in screen or the app gate.
class AuthGate extends StatefulWidget {
  final SupabaseClient client;

  const AuthGate({super.key, required this.client});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.client.auth.onAuthStateChange.listen((data) {
      print('AuthGate listener: event=${data.event}, session=${data.session != null}');
      setState(() {}); // Force rebuild on auth change
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.client.auth.currentSession;
    print('AuthGate build: session=${session != null}, user=${session?.user.id}');
    if (session == null) {
      return AuthScreen(auth: AuthRepository(widget.client));
    }
    return SchoolsGate(client: widget.client);
  }
}