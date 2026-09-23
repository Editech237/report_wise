import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<(String, String)> _readEnv() async {
  final f = File('.env');
  if (!await f.exists()) throw StateError('.env not found');
  final lines = await f.readAsLines();
  String url = '';
  String key = '';
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    final name = line.substring(0, eq);
    final value = line.substring(eq + 1);
    if (name == 'SUPABASE_URL') url = value;
    if (name == 'SUPABASE_ANON_KEY') key = value;
  }
  return (url, key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Supabase.initialize against real project',
    () async {
      SharedPreferences.setMockInitialValues({});
      final (url, key) = await _readEnv();

      try {
        await Supabase.initialize(url: url, publishableKey: key);
        final c = Supabase.instance.client;
        print('INIT_OK client=$c');
        final r = await c
            .from('education_types')
            .select()
            .timeout(const Duration(seconds: 10));
        print('QUERY_OK rows=${(r as List).length}');
      } catch (e, st) {
        print('INIT_FAILED: $e');
        print('STACK:\n$st');
        rethrow;
      } finally {
        await Supabase.instance.dispose();
      }
    },
    skip: !const bool.fromEnvironment('RUN_SUPABASE_DIAGNOSTIC'),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
