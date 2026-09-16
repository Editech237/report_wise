import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/core/providers/supabase_provider.dart';
import 'src/core/supabase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SupabaseClient? client;
  try {
    await initSupabase();
    client = Supabase.instance.client;
  } catch (e) {
    debugPrint('Supabase init failed: $e');
  }

  runApp(ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
    ],
    child: const ReportWiseApp(),
  ));
}