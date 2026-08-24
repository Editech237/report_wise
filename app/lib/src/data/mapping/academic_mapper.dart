/// Conversion of raw Supabase/Postgrest row maps into engine models.
///
/// Pure Dart and side-effect free so it can be unit tested without a database.
/// Rows use snake_case column names; Postgrest may return `numeric` columns as
/// strings or numbers, so coercion is defensive.
library;

import 'package:academic_engine/academic_engine.dart';

String _str(Object? v, [String def = '']) => v == null ? def : v.toString();

double _dbl(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

DateTime? _updatedAt(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString());

String? _nullish(Object? v) => v?.toString();

/// Engine model for a `subject_coefficient_configurations` row.
CoefficientConfig coefficientConfigFromRow(Map<String, dynamic> row) {
  return CoefficientConfig(
    id: _str(row['id']),
    subjectId: _str(row['subject_id']),
    coefficient: _dbl(row['coefficient']),
    source: ConfigSource.fromCode(_str(row['source'], 'NATIONAL_DEFAULT')),
    sourceRef: _nullish(row['source_ref']),
    schoolId: _nullish(row['school_id']),
    academicYearId: _nullish(row['academic_year_id']),
    subsystem: _nullish(row['subsystem']),
    educationTypeId: _nullish(row['education_type_id']),
    cycleId: _nullish(row['cycle_id']),
    levelId: _nullish(row['level_id']),
    seriesId: _nullish(row['series_id']),
    specialtyId: _nullish(row['specialty_id']),
    updatedAt: _updatedAt(row['updated_at']),
  );
}

/// Engine model for a `curriculum` row + its curriculum_subjects children.
CurriculumEntry curriculumFromRow(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> subjectRows,
) {
  return CurriculumEntry(
    id: _str(row['id']),
    source: ConfigSource.fromCode(_str(row['source'], 'NATIONAL_DEFAULT')),
    sourceRef: _nullish(row['source_ref']),
    schoolId: _nullish(row['school_id']),
    academicYearId: _nullish(row['academic_year_id']),
    subsystem: _nullish(row['subsystem']),
    educationTypeId: _nullish(row['education_type_id']),
    cycleId: _nullish(row['cycle_id']),
    levelId: _nullish(row['level_id']),
    seriesId: _nullish(row['series_id']),
    specialtyId: _nullish(row['specialty_id']),
    updatedAt: _updatedAt(row['updated_at']),
    subjects: subjectRows.map(curriculumSubjectFromRow).toList(),
  );
}

/// Engine model for one `curriculum_subjects` row.
CurriculumSubject curriculumSubjectFromRow(Map<String, dynamic> row) {
  return CurriculumSubject(
    subjectId: _str(row['subject_id']),
    coefficient: _dbl(row['coefficient']),
    weeklyHours: row['weekly_hours'] == null ? null : _dbl(row['weekly_hours']),
    subjectType: SubjectType.fromCode(_nullish(row['subject_type'])),
    countsInAverage: row['counts_in_average'] != false,
    countsInRanking: row['counts_in_ranking'] != false,
    showsOnReport: row['shows_on_report'] != false,
  );
}

/// Engine model for an `assessment_schemes` row + its components.
SchemeConfig schemeFromRow(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> componentRows,
) {
  return SchemeConfig(
    id: _str(row['id']),
    name: _str(row['name']),
    source: ConfigSource.fromCode(_str(row['source'], 'NATIONAL_DEFAULT')),
    schoolId: _nullish(row['school_id']),
    academicYearId: _nullish(row['academic_year_id']),
    educationTypeId: _nullish(row['education_type_id']),
    levelId: _nullish(row['level_id']),
    seriesId: _nullish(row['series_id']),
    updatedAt: _updatedAt(row['updated_at']),
    components: componentRows.map(assessmentComponentFromRow).toList(),
  );
}

AssessmentComponent assessmentComponentFromRow(Map<String, dynamic> row) {
  return AssessmentComponent(
    id: _str(row['id']),
    name: _str(row['name']),
    componentType: _str(row['component_type'], 'EXAM'),
    weight: _dbl(row['weight']) / 100,
    maxScore: _dbl(row['max_score']),
  );
}

/// Engine model for a student's academic context, built from a class row
/// plus the user's session school/year.
AcademicContext academicContextFromClassRow(
  Map<String, dynamic> classRow, {
  required String schoolId,
  required String academicYearId,
}) {
  return AcademicContext(
    schoolId: schoolId,
    academicYearId: academicYearId,
    subsystem: _str(classRow['subsystem']),
    educationTypeId: _str(classRow['education_type_id']),
    cycleId: _str(classRow['cycle_id']),
    levelId: _str(classRow['level_id']),
    seriesId: _nullish(classRow['series_id']),
    specialtyId: _nullish(classRow['specialty_id']),
    classId: _str(classRow['id']),
  );
}