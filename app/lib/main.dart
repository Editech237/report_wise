import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/core/supabase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SupabaseClient? client;
  try {
    await initSupabase();
    client = Supabase.instance.client;
  } catch (e) {
    // Misconfigured --dart-define values: still show the app shell so the
    // developer sees the failure clearly instead of a blank screen.
    debugPrint('Supabase init failed: $e');
  }

  runApp(ReportWiseApp(client: client));
}