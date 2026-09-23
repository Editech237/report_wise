import 'package:supabase_flutter/supabase_flutter.dart';
import '../entities.dart';

class StudentWithEnrollment {
  final Student student;
  final String? enrollmentId;
  final String? classId;
  final String? className;
  final String? status;

  StudentWithEnrollment({
    required this.student,
    this.enrollmentId,
    this.classId,
    this.className,
    this.status,
  });
}

class StudentRepository {
  final SupabaseClient _client;
  StudentRepository(this._client);

  Future<List<StudentWithEnrollment>> list({
    required String schoolId,
    required String academicYearId,
  }) async {
    // Optimized: query enrollments directly — uses index (school_id, academic_year_id), avoids scanning all students
    final rows = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final page = await _client
          .from('student_enrollments')
          .select(
            'id, class_id, status, student:students(id, school_id, full_name, matricule, date_of_birth, gender, place_of_birth, guardian_name, guardian_phone, repeater), class:classes(name)',
          )
          .eq('school_id', schoolId)
          .eq('academic_year_id', academicYearId)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) break;
    }

    return (rows as List)
        .map((r) {
          final m = r as Map<String, dynamic>;
          final studentMap = m['student'] as Map<String, dynamic>?;
          if (studentMap == null) return null;
          final student = Student.fromMap(studentMap);
          final classMap = m['class'] as Map<String, dynamic>?;
          return StudentWithEnrollment(
            student: student,
            enrollmentId: m['id']?.toString(),
            classId: m['class_id']?.toString(),
            className: classMap?['name']?.toString(),
            status: m['status']?.toString(),
          );
        })
        .whereType<StudentWithEnrollment>()
        .toList()
      ..sort((a, b) => a.student.fullName.compareTo(b.student.fullName));
  }

  // Fallback for case where enrollment filter via PostgREST fails — uses broader query
  Future<List<StudentWithEnrollment>> listAllForSchool(String schoolId) async {
    final rows = await _client
        .from('students')
        .select('*, enrollments:student_enrollments(*, class:classes(name))')
        .eq('school_id', schoolId)
        .order('full_name');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final student = Student.fromMap(m);
      final enrollments =
          (m['enrollments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final enr = enrollments.isEmpty ? null : enrollments.first;
      return StudentWithEnrollment(
        student: student,
        enrollmentId: enr?['id']?.toString(),
        classId: enr?['class_id']?.toString(),
        className: enr?['class'] is Map
            ? (enr?['class'] as Map)['name']?.toString()
            : null,
        status: enr?['status']?.toString(),
      );
    }).toList();
  }

  Future<Student> create({
    required String schoolId,
    required String fullName,
    String? matricule,
    DateTime? dateOfBirth,
    String? gender,
    String? placeOfBirth,
    String? guardianName,
    String? guardianPhone,
    bool repeater = false,
    String? classId,
    String? academicYearId,
  }) async {
    final row = await _client
        .from('students')
        .insert({
          'school_id': schoolId,
          'full_name': fullName.trim(),
          // Matricules are assigned by the database. The optional parameter is
          // retained for imported school identifiers, which may override it.
          'matricule': matricule?.trim().isEmpty ?? true
              ? null
              : matricule!.trim(),
          'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
          'gender': gender,
          'place_of_birth': placeOfBirth?.trim().isEmpty ?? true
              ? null
              : placeOfBirth!.trim(),
          'guardian_name': guardianName?.trim().isEmpty ?? true
              ? null
              : guardianName!.trim(),
          'guardian_phone': guardianPhone?.trim().isEmpty ?? true
              ? null
              : guardianPhone!.trim(),
          'repeater': repeater,
        })
        .select()
        .single();
    final student = Student.fromMap(row);

    // Auto-enroll if classId + academicYearId provided
    if (classId != null && academicYearId != null) {
      await _client.from('student_enrollments').insert({
        'school_id': schoolId,
        'student_id': student.id,
        'academic_year_id': academicYearId,
        'class_id': classId,
        'status': 'ENROLLED',
        'enrolled_on': DateTime.now().toIso8601String().split('T').first,
      });
    }
    return student;
  }

  Future<Student> update(
    String studentId, {
    String? fullName,
    String? matricule,
    DateTime? dateOfBirth,
    String? gender,
    String? placeOfBirth,
    String? guardianName,
    String? guardianPhone,
    bool? repeater,
  }) async {
    final patch = <String, dynamic>{};
    if (fullName != null) patch['full_name'] = fullName.trim();
    if (matricule != null)
      patch['matricule'] = matricule.trim().isEmpty ? null : matricule.trim();
    if (dateOfBirth != null)
      patch['date_of_birth'] = dateOfBirth.toIso8601String().split('T').first;
    if (gender != null) patch['gender'] = gender;
    if (placeOfBirth != null)
      patch['place_of_birth'] = placeOfBirth.trim().isEmpty
          ? null
          : placeOfBirth.trim();
    if (guardianName != null)
      patch['guardian_name'] = guardianName.trim().isEmpty
          ? null
          : guardianName.trim();
    if (guardianPhone != null)
      patch['guardian_phone'] = guardianPhone.trim().isEmpty
          ? null
          : guardianPhone.trim();
    if (repeater != null) patch['repeater'] = repeater;
    if (patch.isEmpty) throw ArgumentError('No fields to update');
    final row = await _client
        .from('students')
        .update(patch)
        .eq('id', studentId)
        .select()
        .single();
    return Student.fromMap(row);
  }

  Future<void> delete(String studentId) async {
    await _client.from('students').delete().eq('id', studentId);
  }

  Future<void> enroll({
    required String schoolId,
    required String studentId,
    required String academicYearId,
    required String classId,
  }) async {
    await _client.from('student_enrollments').insert({
      'school_id': schoolId,
      'student_id': studentId,
      'academic_year_id': academicYearId,
      'class_id': classId,
      'status': 'ENROLLED',
    });
  }

  Future<int> importBatch({
    required String schoolId,
    required String academicYearId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final result = await _client.rpc(
      'import_students_batch',
      params: {'p_school': schoolId, 'p_year': academicYearId, 'p_rows': rows},
    );
    return (result as num?)?.toInt() ?? rows.length;
  }

  Future<void> updateEnrollment(
    String enrollmentId, {
    required String classId,
  }) async {
    await _client
        .from('student_enrollments')
        .update({'class_id': classId})
        .eq('id', enrollmentId);
  }
}
