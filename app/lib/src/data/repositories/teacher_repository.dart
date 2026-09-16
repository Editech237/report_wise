import 'package:supabase_flutter/supabase_flutter.dart';

import '../entities.dart';

/// Teacher registry & assignments (spec section 37).
///
/// Staff/teacher management is intentionally RPC-driven: profiles are hidden by
/// RLS, and the security-definer RPCs validate that every reference stays
/// inside the caller's school (a client could otherwise craft cross-school
/// assignment rows through direct inserts).
class TeacherRepository {
  final SupabaseClient _client;

  TeacherRepository(this._client);

  /// Staff directory for the school (all members).
  Future<List<SchoolMember>> listMembers(String schoolId) async {
    final rows = await _client
        .rpc('list_school_members', params: {'p_school': schoolId});
    return (rows as List)
        .map((r) => SchoolMember.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Creates a teacher through the create-teacher Edge Function.
  ///
  /// The server generates a password and pre-confirms the email. Returns the
  /// result map: `{created: bool, alreadyMember?: bool, teacher_membership_id,
  /// email, password?}`. `password` is returned exactly once so the admin can
  /// share it; the teacher can also reset it from the app.
  Future<Map<String, dynamic>> createTeacher({
    required String schoolId,
    required String fullName,
    required String email,
    String? phone,
    String? staffId,
  }) async {
    final response = await _client.functions.invoke(
      'create-teacher',
      body: {
        'school_id': schoolId,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'staff_id': staffId,
      },
    );
    final data = response.data;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// Generates a new password for a teacher (via reset-teacher-password Edge
  /// Function). Returns `{email, full_name, password}` so the admin can share it.
  Future<Map<String, dynamic>> resetTeacherPassword({
    required String schoolId,
    required String membershipId,
  }) async {
    final response = await _client.functions.invoke(
      'reset-teacher-password',
      body: {
        'school_id': schoolId,
        'membership_id': membershipId,
      },
    );
    final data = response.data;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  Future<void> removeTeacher({
    required String schoolId,
    required String membershipId,
  }) async {
    await _client.rpc('remove_teacher', params: {
      'p_school': schoolId,
      'p_membership': membershipId,
    });
  }

  Future<List<TeacherAssignmentDetail>> listAssignments({
    required String schoolId,
    required String academicYearId,
  }) async {
    final rows = await _client.rpc('list_teacher_assignments', params: {
      'p_school': schoolId,
      'p_year': academicYearId,
    });
    return (rows as List)
        .map((r) => TeacherAssignmentDetail.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> createAssignment({
    required String schoolId,
    required String academicYearId,
    required String teacherMembershipId,
    required String classId,
    required String subjectId,
    String? specialtyId,
    String teachingRole = 'SUBJECT_TEACHER',
  }) async {
    await _client.rpc('create_teacher_assignment', params: {
      'p_school': schoolId,
      'p_year': academicYearId,
      'p_teacher': teacherMembershipId,
      'p_class': classId,
      'p_subject': subjectId,
      'p_specialty': specialtyId,
      'p_role': teachingRole,
    });
  }

  Future<void> deleteAssignment(String assignmentId) async {
    await _client.from('teacher_assignments').delete().eq('id', assignmentId);
  }

  Future<void> setClassTeacher({
    required String classId,
    String? membershipId,
  }) async {
    await _client.rpc('set_class_teacher', params: {
      'p_class': classId,
      'p_membership': membershipId,
    });
  }
}