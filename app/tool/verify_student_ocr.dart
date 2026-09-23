import 'dart:convert';
import 'dart:io';
import 'package:report_wise/src/data/imports/student_register_parser.dart';

// Run against the JSON emitted by tool/ocr_smoke/main.swift.
void main(List<String> args) {
  final input = (jsonDecode(File(args.single).readAsStringSync()) as List)
      .map((page) => Map<String, dynamic>.from(page as Map))
      .toList();
  final pages = StudentRegisterParser().parse(input);
  const expectedNames = [
    'Amina Bello',
    'Blaise Mballa',
    'Chantal Ngozi',
    'David Tamba',
    'Esther Njoya',
    'Fabrice Kenne',
    'Grace Atabong',
    'Hassan Abdou',
    'Irene Fombad',
    'Joel Nsom',
    'Khadija Issa',
    'Louis Etoundi',
    'Madeleine Abena',
    'Nadia Ojong',
    'Olivier Tchana',
    'Pauline Etoa',
    'Quentin Mvondo',
    'Rebecca Sama',
    'Samuel Neba',
    'Therese Ngassa',
    'Ursula Ateba',
    'Victor Bikong',
    'William Dika',
    'Xavier Ewane',
    'Yvette Fouda',
    'Zacharie Nana',
    'Adeline Onana',
    'Brice Toko',
    'Carine Wamba',
    'Doris Yondo',
  ];
  var count = 0;
  for (final page in pages) {
    final rows = page['rows'] as List;
    stdout.writeln(
      'Page ${page['page_number']}: ${rows.length} rows. ${page['warnings']}',
    );
    for (final row in rows) {
      final data = row['normalized_data'];
      final expectedIndex = count + rows.indexOf(row);
      if (expectedIndex >= expectedNames.length ||
          data['full_name'] != expectedNames[expectedIndex]) {
        stderr.writeln(
          'Unexpected name: ${data['full_name']} at row ${expectedIndex + 1}',
        );
        exitCode = 1;
      }
      stdout.writeln(
        '${data['full_name']} | ${data['matricule'] ?? '(generate ID)'}',
      );
    }
    count += rows.length;
  }
  if (count != 30) {
    stderr.writeln('Expected 30 synthetic students, found $count.');
    exitCode = 1;
  }
}
