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
  testWidgets('Supabase.initialize against real project', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final (url, key) = await _readEnv();
    print('URL=$url');
    print('KEY_PRESENT=${key.isNotEmpty}');

    try {
      await Supabase.initialize(url: url, publishableKey: key);
      final c = Supabase.instance.client;
      print('INIT_OK client=$c');
      final r = await c.from('education_types').select();
      print('QUERY_OK rows=${(r as List).length}');
    } catch (e, st) {
      print('INIT_FAILED: $e');
      print('STACK:\n$st');
      rethrow;
    }
  });
}