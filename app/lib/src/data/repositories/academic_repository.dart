import 'package:academic_engine/academic_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/academic_cache.dart';
import '../entities.dart';
import '../mapping/academic_mapper.dart';

/// Default Cameroon academic calendar: 3 terms x 2 sequences = 6 sequences.
const int defaultTermCount = 3;
const int defaultSequencesPerTerm = 2;

const defaultTermNames = ['Term 1', 'Term 2', 'Term 3'];
const defaultSequenceNames = [
  'Sequence 1', 'Sequence 2', 'Sequence 3',
  'Sequence 4', 'Sequence 5', 'Sequence 6',
];

String _rid(Object? v) => v?.toString() ?? '';

/// Academic structure + configuration access: academic years, terms,
/// sequences, hierarchy lookups and the rule data the engine resolves
/// (curriculum, coefficient configurations, assessment schemes).
class AcademicRepository {
  final SupabaseClient _client;

  AcademicRepository(this._client);

  // ---------------------------------------------------------------------------
  // Academic year / terms / sequences
  // ---------------------------------------------------------------------------

  Future<AcademicYear> createAcademicYear({
    required String schoolId,
    required String name,
    DateTime? startsOn,
    DateTime? endsOn,
    bool isCurrent = true,
  }) async {
    final rows = await _client
        .from('academic_years')
        .insert({
          'school_id': schoolId,
          'name': name,
          'starts_on': startsOn?.toIso8601String(),
          'ends_on': endsOn?.toIso8601String(),
          'is_current': isCurrent,
          'status': 'ACTIVE',
        })
        .select()
        .single();
    clearAcademicYearsCache(schoolId);
    return AcademicYear.fromMap(rows);
  }

  Future<List<AcademicYear>> academicYears(String schoolId) async {
    return AcademicCache().getOrFetch('academic_years:$schoolId', () async {
      final rows = await _client
          .from('academic_years')
          .select('id, school_id, name, starts_on, ends_on, is_current, status')
          .eq('school_id', schoolId)
          .order('name');
      return (rows as List).map((r) => AcademicYear.fromMap(r)).toList();
    }, ttl: const Duration(minutes: 5));
  }

  void clearAcademicYearsCache(String schoolId) => AcademicCache().invalidate('academic_years:$schoolId');

  Future<List<Term>> terms(String academicYearId) async {
    final rows = await _client
        .from('terms')
        .select()
        .eq('academic_year_id', academicYearId)
        .order('number');
    return (rows as List).map((r) => Term.fromMap(r)).toList();
  }

  Future<List<Sequence>> sequences(String termId) async {
    final rows = await _client
        .from('sequences')
        .select()
        .eq('term_id', termId)
        .order('number');
    return (rows as List).map((r) => Sequence.fromMap(r)).toList();
  }

  /// Creates 3 terms (2 sequences each) and returns them nested.
  Future<List<Term>> seedDefaultCalendar({
    required AcademicYear year,
  }) async {
    final terms = <Term>[];
    for (var t = 1; t <= defaultTermCount; t++) {
      final termRows = await _client
          .from('terms')
          .insert({
            'school_id': year.schoolId,
            'academic_year_id': year.id,
            'number': t,
            'name': defaultTermNames[t - 1],
            'starts_on': year.startsOn?.toIso8601String(),
            'ends_on': year.endsOn?.toIso8601String(),
          })
          .select()
          .single();
      final term = Term.fromMap(termRows);

      for (var s = 1; s <= defaultSequencesPerTerm; s++) {
        final seqIndex = (t - 1) * defaultSequencesPerTerm + (s - 1);
        await _client.from('sequences').insert({
          'school_id': year.schoolId,
          'term_id': term.id,
          'number': s,
          'name': defaultSequenceNames[seqIndex],
          'starts_on': year.startsOn?.toIso8601String(),
          'ends_on': year.endsOn?.toIso8601String(),
        });
      }
      terms.add(term);
    }
    return terms;
  }

  // ---------------------------------------------------------------------------
  // Hierarchy lookups
  // ---------------------------------------------------------------------------

  Future<List<EducationType>> educationTypes() async {
    return AcademicCache().getOrFetch('education_types', () async {
      final rows = await _client.from('education_types').select().order('sort_order');
      return (rows as List).map((r) => EducationType.fromMap(r)).toList();
    }, ttl: const Duration(minutes: 30));
  }

  Future<List<Cycle>> cycles() async {
    return AcademicCache().getOrFetch('cycles_all', () async {
      final rows = await _client.from('cycles').select().order('sort_order');
      return (rows as List).map((r) => Cycle.fromMap(r)).toList();
    }, ttl: const Duration(minutes: 30));
  }

  Future<List<Level>> levels({String? subsystem, String? cycleId}) async {
    final key = 'levels:${subsystem ?? 'all'}:${cycleId ?? 'all'}';
    return AcademicCache().getOrFetch(key, () async {
      var query = _client.from('levels').select();
      if (subsystem != null) query = query.eq('subsystem', subsystem);
      if (cycleId != null) query = query.eq('cycle_id', cycleId);
      final rows = await query.order('sort_order');
      return (rows as List).map((r) => Level.fromMap(r)).toList();
    }, ttl: const Duration(minutes: 30));
  }

  Future<List<Series>> series({String? educationTypeId}) async {
    final key = 'series:${educationTypeId ?? 'all'}';
    return AcademicCache().getOrFetch(key, () async {
      var query = _client.from('series').select();
      if (educationTypeId != null) query = query.eq('education_type_id', educationTypeId);
      final rows = await query.order('sort_order');
      return (rows as List).map((r) => Series.fromMap(r)).toList();
    }, ttl: const Duration(minutes: 30));
  }

  Future<List<Specialty>> specialties({String? seriesId}) async {
    final key = 'specialties:${seriesId ?? 'all'}';
    return AcademicCache().getOrFetch(key, () async {
      var query = _client.from('specialties').select();
      if (seriesId != null) query = query.eq('series_id', seriesId);
      final rows = await query.order('sort_order');
      return (rows as List).map((r) => Specialty.fromMap(r)).toList();
    }, ttl: const Duration(minutes: 30));
  }

  // ---------------------------------------------------------------------------
  // Academic rule data for the engine
  // ---------------------------------------------------------------------------

  /// All curriculum rows relevant to the school (national defaults +
  /// school rows). The engine picks the most specific match.
  Future<List<CurriculumEntry>> curriculaFor(AcademicContext ctx) async {
    final rows = await _client
        .from('curriculum')
        .select('*, curriculum_subjects(*)')
        .or('school_id.is.null, school_id.eq.${ctx.schoolId}');
    return (rows as List)
        .map((r) {
          final m = r as Map<String, dynamic>;
          final subjectRows = (m['curriculum_subjects'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const <Map<String, dynamic>>[];
          return curriculumFromRow(m, subjectRows);
        })
        .toList();
  }

  Future<List<CoefficientConfig>> coefficientConfigsFor(AcademicContext ctx) async {
    final rows = await _client
        .from('subject_coefficient_configurations')
        .select()
        .or('school_id.is.null, school_id.eq.${ctx.schoolId}');
    return (rows as List)
        .map((r) => coefficientConfigFromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<SchemeConfig>> schemesFor(AcademicContext ctx) async {
    final rows = await _client
        .from('assessment_schemes')
        .select('*, assessment_scheme_components(*)')
        .or('school_id.is.null, school_id.eq.${ctx.schoolId}');
    return (rows as List)
        .map((r) {
          final m = r as Map<String, dynamic>;
          final componentRows = (m['assessment_scheme_components'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const <Map<String, dynamic>>[];
          return schemeFromRow(m, componentRows);
        })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Classes
  // ---------------------------------------------------------------------------

  static const String _classSelect = '*,'
      'education_type:education_types(name),'
      'cycle:cycles(name),'
      'level:levels(name),'
      'series:series(name),'
      'specialty:specialties(name)';

  Future<List<SchoolClass>> classesFor({
    required String schoolId,
    required String academicYearId,
  }) async {
    final rows = await _client
        .from('classes')
        .select(_classSelect)
        .eq('school_id', schoolId)
        .eq('academic_year_id', academicYearId)
        .order('name');
    return (rows as List)
        .map((r) => SchoolClass.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<SchoolClass> createClass({
    required String schoolId,
    required String academicYearId,
    required String subsystem,
    required String educationTypeId,
    required String cycleId,
    required String levelId,
    String? seriesId,
    String? specialtyId,
    required String name,
    String? room,
  }) async {
    final rows = await _client
        .from('classes')
        .insert({
          'school_id': schoolId,
          'academic_year_id': academicYearId,
          'subsystem': subsystem,
          'education_type_id': educationTypeId,
          'cycle_id': cycleId,
          'level_id': levelId,
          'series_id': seriesId,
          'specialty_id': specialtyId,
          'name': name,
          'room': room,
          'is_active': true,
        })
        .select(_classSelect)
        .single();
    return SchoolClass.fromMap(rows);
  }

  Future<void> updateClass(
    String classId, {
    String? name,
    String? room,
    bool? isActive,
  }) async {
    final patch = <String, Object?>{
      'name': ?name,
      'room': ?room,
      'is_active': ?isActive,
    };
    if (patch.isEmpty) return;
    await _client.from('classes').update(patch).eq('id', classId);
  }

  Future<void> deleteClass(String classId) async {
    await _client.from('classes').delete().eq('id', classId);
  }

  // ---------------------------------------------------------------------------
  // Subject catalog + class curricula
  // ---------------------------------------------------------------------------

  /// National (school_id null) + school-owned subjects, by name.
  Future<List<Subject>> subjectsForSchool({required String schoolId}) async {
    return AcademicCache().getOrFetch('subjects:$schoolId', () async {
      final rows = await _client
          .from('subjects')
          .select('id, school_id, code, name, name_fr, subject_type')
          .or('school_id.is.null,school_id.eq.$schoolId')
          .order('name');
      return (rows as List).map((r) => Subject.fromMap(r as Map<String, dynamic>)).toList();
    }, ttl: const Duration(minutes: 10));
  }

  void clearSubjectsCache(String schoolId) => AcademicCache().invalidate('subjects:$schoolId');

  Future<Subject> addSchoolSubject({
    required String schoolId,
    required String code,
    required String name,
    String? nameFr,
    String? subjectType,
  }) async {
    final rows = await _client
        .from('subjects')
        .insert({
          'school_id': schoolId,
          'code': code,
          'name': name,
          'name_fr': nameFr,
          'subject_type': subjectType,
        })
        .select()
        .single();
    clearSubjectsCache(schoolId);
    return Subject.fromMap(rows);
  }

  Future<void> deleteSubject(String subjectId) async {
    await _client.from('subjects').delete().eq('id', subjectId);
    // Conservative: clear all subjects caches (school-specific key unknown here)
    AcademicCache().clear();
  }

  /// Finds or creates the school's own curriculum row for exactly this scope.
  /// Used when an admin overrides the subject set for a class's level/series/
  /// specialty (section 23: SCHOOL_CONFIGURATION beats NATIONAL_DEFAULT).
  Future<String> ensureSchoolCurriculum(AcademicContext ctx) async {
    final rows = await _client
        .from('curriculum')
        .select()
        .eq('school_id', ctx.schoolId)
        .eq('level_id', ctx.levelId)
        .eq('source', 'SCHOOL_CONFIGURATION');
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      if (_sameOrNull(m['academic_year_id'], ctx.academicYearId) &&
          _sameOrNull(m['subsystem'], ctx.subsystem) &&
          _sameOrNull(m['education_type_id'], ctx.educationTypeId) &&
          _sameOrNull(m['cycle_id'], ctx.cycleId) &&
          _sameOrNull(m['series_id'], ctx.seriesId) &&
          _sameOrNull(m['specialty_id'], ctx.specialtyId)) {
        return _rid(m['id']);
      }
    }
    final inserted = await _client
        .from('curriculum')
        .insert({
          'school_id': ctx.schoolId,
          'academic_year_id': ctx.academicYearId,
          'subsystem': ctx.subsystem,
          'education_type_id': ctx.educationTypeId,
          'cycle_id': ctx.cycleId,
          'level_id': ctx.levelId,
          'series_id': ctx.seriesId,
          'specialty_id': ctx.specialtyId,
          'source': 'SCHOOL_CONFIGURATION',
          'name': 'School configuration',
        })
        .select()
        .single();
    return _rid(inserted['id']);
  }

  /// Replaces the class scope's subject set with the given entries. Passing an
  /// empty list leaves the national curriculum active (no school row created).
  Future<void> setClassSubjects({
    required AcademicContext ctx,
    required List<({String subjectId, double coefficient, double? weeklyHours})>
        entries,
  }) async {
    if (entries.isEmpty) return;
    final curriculumId = await ensureSchoolCurriculum(ctx);
    await _client
        .from('curriculum_subjects')
        .delete()
        .eq('curriculum_id', curriculumId);
    var i = 1;
    await _client.from('curriculum_subjects').upsert(
          entries
              .map((e) => {
                    'curriculum_id': curriculumId,
                    'school_id': ctx.schoolId,
                    'subject_id': e.subjectId,
                    'coefficient': e.coefficient,
                    'weekly_hours': e.weeklyHours,
                    'sort_order': i++,
                  })
              .toList(),
          onConflict: 'curriculum_id,subject_id',
        );
  }

  /// Records a new versioned coefficient for a class's scope. Older rows are
  /// kept, so the change is a new ACADEMIC_YEAR layer (section 7, 34) and can
  /// be reverted by removing the latest row.
  Future<CoefficientConfig> setClassCoefficient({
    required String schoolId,
    required String academicYearId,
    required String subsystem,
    required String educationTypeId,
    required String cycleId,
    required String levelId,
    String? seriesId,
    String? specialtyId,
    required String subjectId,
    required double coefficient,
  }) async {
    final rows = await _client
        .from('subject_coefficient_configurations')
        .insert({
          'school_id': schoolId,
          'academic_year_id': academicYearId,
          'subsystem': subsystem,
          'education_type_id': educationTypeId,
          'cycle_id': cycleId,
          'level_id': levelId,
          'series_id': seriesId,
          'specialty_id': specialtyId,
          'subject_id': subjectId,
          'coefficient': coefficient,
          'source': 'ACADEMIC_YEAR',
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();
    return coefficientConfigFromRow(rows);
  }

  /// The most recent ACADEMIC_YEAR coefficient row for a scope+subject, if the
  /// school has set one (used to show "previously set" history in the UI).
  Future<CoefficientConfig?> latestClassCoefficient({
    required String schoolId,
    required String academicYearId,
    required String levelId,
    String? seriesId,
    String? specialtyId,
    required String subjectId,
  }) async {
    var query = _client
        .from('subject_coefficient_configurations')
        .select()
        .eq('school_id', schoolId)
        .eq('academic_year_id', academicYearId)
        .eq('level_id', levelId)
        .eq('subject_id', subjectId)
        .eq('source', 'ACADEMIC_YEAR');
    if (seriesId != null) query = query.eq('series_id', seriesId);
    if (specialtyId != null) query = query.eq('specialty_id', specialtyId);
    final rows = await query.order('created_at', ascending: false).limit(1);
    if (rows.isEmpty) return null;
    return coefficientConfigFromRow(rows.first);
  }

  static bool _sameOrNull(Object? a, Object? b) => a == b;

  // ---------------------------------------------------------------------------
  // Dashboard data helpers
  // ---------------------------------------------------------------------------

  Future<List<TeacherAssignment>> teacherAssignments({
    required String schoolId,
    required String academicYearId,
  }) async {
    final rows = await _client
        .from('teacher_assignments')
        .select('*, subject:subjects(*), class:classes(name)')
        .eq('school_id', schoolId)
        .eq('academic_year_id', academicYearId);
    return (rows as List)
        .map((r) => TeacherAssignment.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Student>> students({
    required String schoolId,
    required String academicYearId,
  }) async {
    // Optimized: query enrollments directly (indexed on school_id, academic_year_id) then join students
    final rows = await _client
        .from('student_enrollments')
        .select('student:students(id, school_id, full_name, matricule, date_of_birth, gender)')
        .eq('school_id', schoolId)
        .eq('academic_year_id', academicYearId)
        .limit(500);
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['student'])
        .where((s) => s != null)
        .map((s) => Student.fromMap(s as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Resolved academic setup for a context
  // ---------------------------------------------------------------------------

  Future<ResolvedAcademicSetup> loadAcademicSetup(AcademicContext ctx) async {
    final results = await Future.wait([
      curriculaFor(ctx),
      coefficientConfigsFor(ctx),
      schemesFor(ctx),
    ]);
    final curricula = results[0] as List<CurriculumEntry>;
    final coefficientConfigs = results[1] as List<CoefficientConfig>;
    final schemes = results[2] as List<SchemeConfig>;

    final engine = RulesEngine();
    return ResolvedAcademicSetup(
      subjects: engine.resolveSubjects(
        ctx: ctx,
        curricula: curricula,
        coefficientConfigs: coefficientConfigs,
      ),
      scheme: engine.resolveScheme(ctx, schemes),
    );
  }
}

class ResolvedAcademicSetup {
  final List<SubjectConfig> subjects;
  final SchemeConfig? scheme;

  ResolvedAcademicSetup({required this.subjects, required this.scheme});
}