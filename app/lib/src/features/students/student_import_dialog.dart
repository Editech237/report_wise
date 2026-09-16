import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/theme/app_colors.dart';
import '../../data/entities.dart';
import '../../data/repositories/student_repository.dart';

class StudentImportDialog extends StatefulWidget {
  final School school;
  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<StudentWithEnrollment> existing;
  final StudentRepository repository;

  const StudentImportDialog({
    super.key,
    required this.school,
    required this.year,
    required this.classes,
    required this.existing,
    required this.repository,
  });

  @override
  State<StudentImportDialog> createState() => _StudentImportDialogState();
}

class _StudentImportDialogState extends State<StudentImportDialog> {
  List<_ImportRow> _rows = const [];
  bool _busy = false;
  String? _fileName;

  Future<void> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    if (result.isEmpty) return;
    try {
      final file = result.first;
      final rows = _parse(await file.readAsBytes(), file.name);
      setState(() {
        _fileName = file.name;
        _rows = rows;
      });
    } catch (e) {
      if (mounted) _message('Could not read this file: $e', error: true);
    }
  }

  List<_ImportRow> _parse(Uint8List bytes, String name) {
    final raw = name.toLowerCase().endsWith('.csv')
        ? _csv(utf8.decode(bytes, allowMalformed: true))
        : _xlsx(bytes);
    if (raw.isEmpty) throw FormatException('The file has no rows');
    final headers = raw.first.map((v) => _key(v)).toList();
    final result = <_ImportRow>[];
    for (var i = 1; i < raw.length; i++) {
      final values = raw[i];
      if (values.every((v) => v.trim().isEmpty)) continue;
      final map = <String, String>{};
      for (var c = 0; c < headers.length; c++) {
        if (headers[c].isNotEmpty)
          map[headers[c]] = c < values.length ? values[c].trim() : '';
      }
      result.add(
        _ImportRow.fromMap(i + 1, map, widget.classes, widget.existing),
      );
    }
    return result;
  }

  List<List<String>> _xlsx(Uint8List bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final workbook = zip.findFile('xl/workbook.xml');
    final rels = zip.findFile('xl/_rels/workbook.xml.rels');
    if (workbook == null || rels == null)
      throw FormatException('Invalid Excel workbook');
    final workbookDoc = XmlDocument.parse(
      utf8.decode(workbook.content as List<int>),
    );
    final firstSheet = workbookDoc.findAllElements('sheet').firstOrNull;
    final relationId = firstSheet?.getAttribute('r:id');
    final relation = XmlDocument.parse(utf8.decode(rels.content as List<int>))
        .findAllElements('Relationship')
        .where((r) => r.getAttribute('Id') == relationId)
        .firstOrNull;
    final target = relation?.getAttribute('Target');
    if (target == null) throw FormatException('Excel worksheet not found');
    final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final sheet = zip.findFile(path);
    if (sheet == null) throw FormatException('Excel worksheet not found');
    final shared = zip.findFile('xl/sharedStrings.xml');
    final sharedValues = shared == null
        ? const <String>[]
        : XmlDocument.parse(utf8.decode(shared.content as List<int>))
              .findAllElements('si')
              .map((e) => e.findAllElements('t').map((t) => t.innerText).join())
              .toList();
    final doc = XmlDocument.parse(utf8.decode(sheet.content as List<int>));
    final rows = <List<String>>[];
    for (final row in doc.findAllElements('row')) {
      final cells = <String>[];
      for (final cell in row.findAllElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final column = RegExp(r'^[A-Z]+').firstMatch(ref)?.group(0) ?? 'A';
        final index = _columnIndex(column);
        while (cells.length <= index) cells.add('');
        final value = cell.getElement('v')?.innerText ?? '';
        cells[index] = cell.getAttribute('t') == 's'
            ? (int.tryParse(value) != null &&
                      int.parse(value) < sharedValues.length
                  ? sharedValues[int.parse(value)]
                  : '')
            : value;
      }
      rows.add(cells);
    }
    return rows;
  }

  int _columnIndex(String value) =>
      value.codeUnits.fold(0, (n, c) => n * 26 + c - 64) - 1;

  List<List<String>> _csv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') {
        if (quoted && i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if ((ch == '\n' || ch == '\r') && !quoted) {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        rows.add(row);
        row = <String>[];
        cell = StringBuffer();
      } else {
        cell.write(ch);
      }
    }
    if (cell.length > 0 || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  String _key(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'[\s_\-/]+'), '_');

  Future<void> _import() async {
    final valid = _rows.where((r) => r.error == null && !r.duplicate).toList();
    if (valid.isEmpty)
      return _message(
        'There are no new valid students to import.',
        error: true,
      );
    setState(() => _busy = true);
    var imported = 0;
    try {
      for (final row in valid) {
        await widget.repository.create(
          schoolId: widget.school.id,
          fullName: row.name,
          matricule: row.matricule,
          dateOfBirth: row.dateOfBirth,
          gender: row.gender,
          placeOfBirth: row.placeOfBirth,
          guardianName: row.guardianName,
          guardianPhone: row.guardianPhone,
          repeater: row.repeater,
          classId: row.classId,
          academicYearId: widget.year.id,
        );
        imported++;
      }
      if (mounted) Navigator.pop(context, imported);
    } catch (e) {
      if (mounted)
        _message('Imported $imported students, then failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? AppColors.accentRed : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final invalid = _rows.where((r) => r.error != null).length;
    final duplicates = _rows.where((r) => r.duplicate).length;
    return AlertDialog(
      title: const Text('Import students'),
      content: SizedBox(
        width: 760,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use CSV or Excel (.xlsx) with headers: full_name, matricule, date_of_birth, gender, place_of_birth, guardian_name, guardian_phone, class.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_fileName ?? 'Choose CSV or XLSX file'),
                ),
                const SizedBox(width: 12),
                if (_rows.isNotEmpty)
                  Text(
                    '${_rows.length} rows · $invalid invalid · $duplicates existing',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Choose a file to preview and validate it before importing.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final problem =
                            r.error ??
                            (r.duplicate ? 'Already enrolled' : 'Ready');
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            r.error == null && !r.duplicate
                                ? Icons.check_circle
                                : Icons.warning_amber,
                            color: r.error == null && !r.duplicate
                                ? AppColors.accentGreen
                                : AppColors.accentRed,
                          ),
                          title: Text(
                            '${r.rowNumber}. ${r.name.isEmpty ? '(missing name)' : r.name}',
                          ),
                          subtitle: Text(
                            '${r.className ?? 'No class'} · ${r.matricule ?? 'No matricule'} · $problem',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy || _rows.isEmpty ? null : _import,
          icon: const Icon(Icons.person_add),
          label: Text(_busy ? 'Importing…' : 'Import valid students'),
        ),
      ],
    );
  }
}

class _ImportRow {
  final int rowNumber;
  final String name;
  final String? matricule;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? placeOfBirth;
  final String? guardianName;
  final String? guardianPhone;
  final bool repeater;
  final String? classId;
  final String? className;
  final String? error;
  final bool duplicate;

  _ImportRow({
    required this.rowNumber,
    required this.name,
    this.matricule,
    this.dateOfBirth,
    this.gender,
    this.placeOfBirth,
    this.guardianName,
    this.guardianPhone,
    this.repeater = false,
    this.classId,
    this.className,
    this.error,
    this.duplicate = false,
  });

  factory _ImportRow.fromMap(
    int row,
    Map<String, String> m,
    List<SchoolClass> classes,
    List<StudentWithEnrollment> existing,
  ) {
    final name = m['full_name'] ?? m['name'] ?? '';
    final className = m['class'] ?? m['class_name'];
    final cls = classes
        .where((c) => _norm(c.name) == _norm(className ?? ''))
        .firstOrNull;
    final matricule = _clean(m['matricule']);
    final dob = _parseDate(m['date_of_birth'] ?? m['dob'] ?? '');
    final duplicate = existing.any(
      (e) =>
          (matricule != null && e.student.matricule == matricule) ||
          (dob != null &&
              _norm(e.student.fullName) == _norm(name) &&
              e.student.dateOfBirth == dob),
    );
    String? error;
    if (name.trim().isEmpty)
      error = 'Missing full_name';
    else if (className == null || className.trim().isEmpty)
      error = 'Missing class';
    else if (cls == null)
      error = 'Class not found';
    return _ImportRow(
      rowNumber: row,
      name: name.trim(),
      matricule: matricule,
      dateOfBirth: dob,
      gender: _clean(m['gender']),
      placeOfBirth: _clean(m['place_of_birth']),
      guardianName: _clean(m['guardian_name']),
      guardianPhone: _clean(m['guardian_phone']),
      repeater: (m['repeater'] ?? '').toLowerCase() == 'true',
      classId: cls?.id,
      className: cls?.name,
      error: error,
      duplicate: duplicate,
    );
  }
}

String? _clean(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
String _norm(String value) =>
    value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
DateTime? _parseDate(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  final iso = DateTime.tryParse(v);
  if (iso != null) return iso;
  final parts = v.split(RegExp(r'[/.-]'));
  if (parts.length != 3) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  final c = int.tryParse(parts[2]);
  if (a == null || b == null || c == null) return null;
  return a > 31 ? DateTime(a, b, c) : DateTime(c, b, a);
}
