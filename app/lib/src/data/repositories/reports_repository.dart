import 'package:supabase_flutter/supabase_flutter.dart';

/// Report card generation records (spec section 26): each generated report is
/// recorded, versioned, and tied to its immutable period_result snapshot.
class ReportsRepository {
  final SupabaseClient _client;

  ReportsRepository(this._client);

  /// The national default template id for a period kind (SEQUENCE/TERM/ANNUAL).
  Future<String?> defaultTemplateId({required String kind}) async {
    final row = await _client
        .from('report_templates')
        .select('id')
        .isFilter('school_id', null)
        .eq('kind', kind)
        .eq('is_default', true)
        .maybeSingle();
    return row?['id']?.toString();
  }

  /// Records that a report card was generated for a period result (versioned).
  Future<void> recordReportCard({
    required String schoolId,
    required String academicYearId,
    required String periodResultId,
    String? templateId,
    int version = 1,
  }) async {
    await _client.from('report_cards').insert({
      'school_id': schoolId,
      'academic_year_id': academicYearId,
      'period_result_id': periodResultId,
      'template_id': templateId,
      'version': version,
    });
  }

  /// Whether a report card already exists for a period result.
  Future<bool> hasReport(String periodResultId) async {
    final row = await _client
        .from('report_cards')
        .select('id')
        .eq('period_result_id', periodResultId)
        .limit(1)
        .maybeSingle();
    return row != null;
  }
}