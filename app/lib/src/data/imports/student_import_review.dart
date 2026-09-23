import '../entities.dart';
import '../repositories/student_import_repository.dart';
import 'student_register_parser.dart';

/// One mapping for the editor and quick approval; never approve different data
/// from what the administrator sees in the form.
Map<String, dynamic> reviewValues(
  StudentImportRow row,
  List<SchoolClass> classes,
) {
  final data = <String, dynamic>{...row.normalizedData};
  String? read(List<String> aliases) {
    for (final source in [
      row.normalizedData,
      if (!['APPROVED', 'IMPORTED'].contains(row.status)) row.rawData,
    ]) {
      for (final alias in aliases) {
        for (final entry in source.entries) {
          if (StudentRegisterParser.key(entry.key) ==
              StudentRegisterParser.key(alias)) {
            final text = entry.value?.toString().trim();
            if (text != null && text.isNotEmpty) return text;
          }
        }
      }
    }
    return null;
  }

  data['full_name'] =
      read(['full_name', 'student_name', 'name', 'nom_complet']) ??
      [
        read(['first_name', 'prenom']),
        read(['last_name', 'surname', 'nom']),
      ].whereType<String>().join(' ');
  data['external_student_id'] = read([
    'external_student_id',
    'school_identifier',
    'student_id',
    'admission_no',
  ]);
  data['matricule'] = read(['matricule']) ?? data['external_student_id'];
  // Preserve even ambiguous source dates in the form instead of showing an
  // empty field. The user must correct or explicitly clear them before approval.
  final date = read(['date_of_birth', 'dob', 'birth_date']);
  data['date_of_birth'] = date == null
      ? null
      : StudentRegisterParser.normalizeDate(date) ?? date;
  final gender = StudentRegisterParser.key(
    read(['gender', 'sex', 'sexe']) ?? '',
  );
  data['gender'] = switch (gender) {
    'm' || 'male' || 'masculin' => 'M',
    'f' || 'female' || 'feminin' => 'F',
    _ => null,
  };
  data['class_name'] = read(['class_name', 'class', 'classe', 'level', 'form']);
  final existing = classes.where((c) => c.id == data['class_id']).firstOrNull;
  final matches = classes
      .where(
        (c) =>
            StudentRegisterParser.key(c.name) ==
            StudentRegisterParser.key(data['class_name']?.toString() ?? ''),
      )
      .toList();
  final selected = existing ?? (matches.length == 1 ? matches.single : null);
  data['class_id'] = selected?.id;
  if (selected != null) data['class_name'] = selected.name;
  return data;
}

String? approvalProblem(Map<String, dynamic> data, List<SchoolClass> classes) {
  if ((data['full_name']?.toString().trim() ?? '').isEmpty)
    return 'Enter a student name.';
  if (!classes.any((c) => c.id == data['class_id']))
    return 'Select an existing class for this academic year.';
  final date = data['date_of_birth']?.toString().trim() ?? '';
  if (date.isNotEmpty &&
      (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          StudentRegisterParser.normalizeDate(date) == null)) {
    return 'Check the birth date and enter YYYY-MM-DD, or clear it.';
  }
  return null;
}
