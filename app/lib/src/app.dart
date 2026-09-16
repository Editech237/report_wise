import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/auth_provider.dart';
import 'core/providers/supabase_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';
import 'features/shell/schools_gate.dart';

/// ReportWise — Cameroon Secondary School Management Platform.
///
/// One codebase targeting Windows/macOS/Linux desktop and Android/iOS for
/// the offline-first teacher app.
///
/// When no Supabase client is supplied (e.g. widget tests), the app shows the
/// standalone engine demo. Riverpod now drives reactivity instead of setState.
class ReportWiseApp extends ConsumerWidget {
  const ReportWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    if (client == null) {
      return MaterialApp(
        title: 'ReportWise',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
      );
    }
    return MaterialApp(
      title: 'ReportWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    // Also watch the stream to ensure rebuilds on events
    ref.watch(authStateProvider);
    if (session == null) {
      return const AuthScreen();
    }
    return const SchoolsGate();
  }
}