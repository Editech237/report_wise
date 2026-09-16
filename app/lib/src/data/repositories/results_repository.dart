import 'package:supabase_flutter/supabase_flutter.dart';

import '../entities.dart';

/// Results computation & review (spec sections 15-17, 26, 30, 44).
///
/// The computation itself runs server-side in compute_period_results (the SQL
/// domain engine): the app only resolves the academic configuration for the
/// class (using the tested engine resolver) and hands it to the RPC, which
/// persists period_results + subject_results atomically and immutably.
class ResultsRepository {
  final SupabaseClient _client;

  ResultsRepository(this._client);

  Future<void> computePeriodResults({
    required String schoolId,
    required String classId,
    required String academicYearId,
    required String periodType, // SEQUENCE | TERM | ANNUAL
    String? periodId,
    required List<String> sequenceIds,
    required List<Map<String, Object?>> subjects,
    required List<Map<String, Object?>> scheme,
    required Map<String, Object?> policy,
    required Map<String, Object?> ranking,
    required Map<String, Object?> display,
  }) async {
    await _client.rpc(
      'compute_period_results',
      params: {
        'p_school': schoolId,
        'p_class': classId,
        'p_year': academicYearId,
        'p_period_type': periodType,
        'p_period_id': periodId,
        'p_sequence_ids': sequenceIds,
        'p_subjects': subjects,
        'p_scheme': scheme,
        'p_policy': policy,
        'p_ranking': ranking,
        'p_display': display,
      },
    );
  }

  /// Computed result sets (class + period) for the results-history strip.
  Future<List<PeriodResultSetSummary>> listPeriodResultSets({
    required String schoolId,
    required String academicYearId,
  }) async {
    final rows = await _client.rpc(
      'list_period_result_sets',
      params: {'p_school': schoolId, 'p_year': academicYearId},
    );
    return (rows as List)
        .map((r) => PeriodResultSetSummary.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> finalizePeriodResults({
    required String classId,
    required String periodType,
    String? periodId,
  }) async {
    await _client.rpc(
      'finalize_period_results',
      params: {
        'p_class': classId,
        'p_period_type': periodType,
        'p_period_id': periodId,
      },
    );
  }

  Future<void> unfinalizePeriodResults({
    required String classId,
    required String periodType,
    String? periodId,
    required String reason,
  }) async {
    await _client.rpc(
      'unfinalize_period_results',
      params: {
        'p_class': classId,
        'p_period_type': periodType,
        'p_period_id': periodId,
        'p_reason': reason,
      },
    );
  }

  Future<List<PeriodResult>> periodResults({
    required String classId,
    required String periodType,
    String? periodId,
  }) async {
    var query = _client
        .from('period_results')
        .select(
          '*, enrollment:student_enrollments(student:students(full_name, matricule)), subject_results(*, subject:subjects(name))',
        )
        .eq('class_id', classId)
        .eq('period_type', periodType);
    if (periodId == null) {
      query = query.isFilter('period_id', null);
    } else {
      query = query.eq('period_id', periodId);
    }
    final rows = await query.order('rank', ascending: true);
    return (rows as List)
        .map((r) => PeriodResult.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// A student's own period results (for the profile/details screen).
  Future<List<Map<String, dynamic>>> resultsForEnrollment(
    String enrollmentId,
  ) async {
    final rows = await _client
        .from('period_results')
        .select(
          'period_type, period_id, general_average, total_weighted_points, rank, class_average, status',
        )
        .eq('student_enrollment_id', enrollmentId)
        .order('calculated_at', ascending: false)
        .limit(10);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
