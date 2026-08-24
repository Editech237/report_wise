import 'package:academic_engine/academic_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// End-to-end pipeline: resolve rules for a context, then compute.
({double? general, List<SubjectConfig> subs}) pipeline(
  AcademicContext ctx,
  List<CurriculumEntry> curricula,
  List<CoefficientConfig> coefs,
  List<SchemeConfig> schemes,
  List<ComponentMark> marks,
) {
  final engine = RulesEngine();
  final subjects = engine.resolveSubjects(
    ctx: ctx,
    curricula: curricula,
    coefficientConfigs: coefs,
  );
  final scheme = engine.resolveScheme(ctx, schemes)!;
  final result = computeStudentPeriod(
    studentId: 'st1',
    scheme: scheme,
    subjects: subjects,
    marks: marks,
    policy: defaultPolicy,
    display: DisplayPrecision.standard,
  );
  return (general: result.generalAverage, subs: subjects);
}

void main() {
  // Shared knowledgeable curricula.
  const curricFrancophone3eme = CurriculumEntry(
    id: 'cf-3eme',
    source: ConfigSource.nationalDefault,
    levelId: '3EME',
    subsystem: 'FRANCOPHONE',
    subjects: [
      CurriculumSubject(subjectId: 'MATHS', coefficient: 5),
      CurriculumSubject(subjectId: 'PHY', coefficient: 4),
      CurriculumSubject(subjectId: 'FR', coefficient: 4),
    ],
  );
  const curricAnglophoneForm3 = CurriculumEntry(
    id: 'cf-f3',
    source: ConfigSource.nationalDefault,
    levelId: 'FORM_3',
    subsystem: 'ANGLOPHONE',
    subjects: [
      CurriculumSubject(subjectId: 'ENG', coefficient: 3),
      CurriculumSubject(subjectId: 'MATHS', coefficient: 4),
      CurriculumSubject(subjectId: 'PHY', coefficient: 2),
    ],
  );
  const curricTechnicalGCA = CurriculumEntry(
    id: 'ct-gca',
    source: ConfigSource.nationalDefault,
    levelId: 'TLE',
    seriesId: 'STT',
    specialtyId: 'GCA',
    educationTypeId: 'TECHNICAL',
    subjects: [
      CurriculumSubject(
          subjectId: 'ACCT',
          coefficient: 3,
          subjectType: SubjectType.professional),
      CurriculumSubject(
          subjectId: 'PRAC',
          coefficient: 2,
          subjectType: SubjectType.practical),
      CurriculumSubject(subjectId: 'ICT', coefficient: 1),
    ],
  );
  const classic = SchemeConfig(
    id: 'classic',
    name: 'Classic',
    source: ConfigSource.nationalDefault,
    components: [
      AssessmentComponent(
          id: 'interro', name: 'Interro', componentType: 'CLASS_TEST', weight: 0.2, maxScore: 20),
      AssessmentComponent(
          id: 'devoir', name: 'Devoir', componentType: 'ASSIGNMENT', weight: 0.3, maxScore: 20),
      AssessmentComponent(
          id: 'exam', name: 'Exam', componentType: 'EXAM', weight: 0.5, maxScore: 20),
    ],
  );
  const allCurricula = [curricFrancophone3eme, curricAnglophoneForm3, curricTechnicalGCA];

  group('final domain test (section 45)', () {
    test('1) Francophone general/grammar school', () {
      final res = pipeline(
        context(level: '3EME', subsystem: 'FRANCOPHONE'),
        allCurricula,
        const [],
        const [classic],
        [
          mark('MATHS', score: 14, componentId: 'interro'),
          mark('MATHS', score: 12, componentId: 'devoir'),
          mark('MATHS', score: 16, componentId: 'exam'),
          mark('PHY', score: 10, componentId: 'interro'),
          mark('PHY', score: 12, componentId: 'devoir'),
          mark('PHY', score: 13, componentId: 'exam'),
          mark('FR', score: 12),
        ],
      );
      expect(res.subs.map((s) => s.subjectId), ['MATHS', 'PHY', 'FR']);
      expect(res.subs.map((s) => s.coefficient), [5, 4, 4]);
      // MATHS 14.4*5 + PHY 12.1*4 + FR 12*4 = 168.4 ; /13 = 12.953...
      expect(res.general, 12.95);
    });

    test('2) Anglophone general/grammar school', () {
      final res = pipeline(
        context(level: 'FORM_3', subsystem: 'ANGLOPHONE'),
        allCurricula,
        const [],
        const [classic],
        [
          mark('ENG', score: 16),
          mark('MATHS', score: 14),
          mark('PHY', score: 12),
        ],
      );
      expect(res.subs.map((s) => s.subjectId), ['ENG', 'MATHS', 'PHY']);
      // 48 + 56 + 24 = 128 ; /9 = 14.222...
      expect(res.general, 14.22);
    });

    test('3) Technical/vocational school (STT -> GCA)', () {
      final res = pipeline(
        context(
            level: 'TLE', series: 'STT', specialty: 'GCA', eduType: 'TECHNICAL'),
        allCurricula,
        const [],
        const [classic],
        [
          mark('ACCT', score: 15),
          mark('PRAC', score: 12),
          mark('ICT', score: 10),
        ],
      );
      expect(res.subs.map((s) => s.subjectId), ['ACCT', 'PRAC', 'ICT']);
      expect(res.subs[0].subjectType, SubjectType.professional);
      expect(res.subs[1].subjectType, SubjectType.practical);
      // 45 + 24 + 10 = 79 ; /6 = 13.166...
      expect(res.general, 13.17);
    });

    test('4) Bilingual school runs both subsystems side by side', () {
      final fr = pipeline(
        context(school: 'bi1', level: '3EME', subsystem: 'FRANCOPHONE'),
        allCurricula,
        const [],
        const [classic],
        [mark('MATHS', score: 10), mark('PHY', score: 10), mark('FR', score: 10)],
      );
      final en = pipeline(
        context(school: 'bi1', level: 'FORM_3', subsystem: 'ANGLOPHONE'),
        allCurricula,
        const [],
        const [classic],
        [mark('ENG', score: 10), mark('MATHS', score: 10), mark('PHY', score: 10)],
      );

      expect(fr.subs.map((s) => s.subjectId), ['MATHS', 'PHY', 'FR']);
      expect(en.subs.map((s) => s.subjectId), ['ENG', 'MATHS', 'PHY']);
      expect(fr.general, 10.0);
      expect(en.general, 10.0);
    });

    test('5) School with custom coefficients end to end', () {
      final res = pipeline(
        context(level: '3EME'),
        const [curricFrancophone3eme],
        const [
          CoefficientConfig(
            id: 'ov',
            subjectId: 'MATHS',
            coefficient: 6,
            source: ConfigSource.schoolConfiguration,
            schoolId: 's1',
          )
        ],
        const [classic],
        [mark('MATHS', score: 10), mark('PHY', score: 10), mark('FR', score: 10)],
      );
      expect(res.subs[0].coefficient, 6);
      expect(res.subs[0].source, ConfigSource.schoolConfiguration);
      // General average now uses 6 for maths: (60+40+40)/14 = 10.0
      expect(res.general, 10.0);
    });

    test('6) Custom assessment weighting (CA 40 / Exam 60)', () {
      const caScheme = SchemeConfig(
        id: 'ca',
        name: 'CA/Exam',
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        components: [
          AssessmentComponent(
              id: 'ca', name: 'CA', componentType: 'CONTINUOUS_ASSESSMENT', weight: 0.4, maxScore: 20),
          AssessmentComponent(
              id: 'exam', name: 'Exam', componentType: 'EXAM', weight: 0.6, maxScore: 20),
        ],
      );
      const curricula = CurriculumEntry(
        id: 'lvl',
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        levelId: '3EME',
        subjects: [CurriculumSubject(subjectId: 'MATHS', coefficient: 5)],
      );
      final res = pipeline(
        context(level: '3EME'),
        const [curricula],
        const [],
        const [classic, caScheme],
        [mark('MATHS', score: 15, componentId: 'ca'), mark('MATHS', score: 10, componentId: 'exam')],
      );
      // 0.4*15 + 0.6*10 = 12.0
      expect(res.general, 12.0);
    });

    test('7) Student changing level/stream between academic years', () {
      // 2025/26: 2nde series C
      const c2025 = CurriculumEntry(
        id: 'y25',
        source: ConfigSource.nationalDefault,
        levelId: '2NDE',
        seriesId: 'C',
        subjects: [
          CurriculumSubject(subjectId: 'MATHS', coefficient: 5),
          CurriculumSubject(subjectId: 'SVT', coefficient: 3),
        ],
      );
      // 2026/27: 1ère series D
      const c2026 = CurriculumEntry(
        id: 'y26',
        source: ConfigSource.nationalDefault,
        levelId: '1ERE',
        seriesId: 'D',
        subjects: [
          CurriculumSubject(subjectId: 'MATHS', coefficient: 5),
          CurriculumSubject(subjectId: 'SVT', coefficient: 4),
        ],
      );
      const curricula = [c2025, c2026];

      final y25 = pipeline(
        context(year: '2025/2026', level: '2NDE', series: 'C'),
        curricula,
        const [],
        const [classic],
        [mark('MATHS', score: 14), mark('SVT', score: 12)],
      );
      final y26 = pipeline(
        context(year: '2026/2027', level: '1ERE', series: 'D'),
        curricula,
        const [],
        const [classic],
        [mark('MATHS', score: 14), mark('SVT', score: 12)],
      );

      expect(y25.subs.map((s) => s.coefficient), [5, 3]);
      expect(y26.subs.map((s) => s.coefficient), [5, 4]);
      // 25/26: (70+36)/8 = 13.25 ; 26/27: (70+48)/9 = 13.111...
      expect(y25.general, 13.25);
      expect(y26.general, 13.11);
    });

    test('8) historical report cards unchanged after config changes', () {
      const v25 = CoefficientConfig(
        id: 'v25',
        subjectId: 'MATHS',
        coefficient: 5,
        source: ConfigSource.academicYear,
        schoolId: 's1',
        academicYearId: '2025/2026',
        levelId: '3EME',
      );
      const v26 = CoefficientConfig(
        id: 'v26',
        subjectId: 'MATHS',
        coefficient: 6,
        source: ConfigSource.academicYear,
        schoolId: 's1',
        academicYearId: '2026/2027',
        levelId: '3EME',
      );

      double oldAverage(List<CoefficientConfig> configs) => pipeline(
            context(year: '2025/2026', level: '3EME'),
            const [curricFrancophone3eme],
            configs,
            const [classic],
            [mark('MATHS', score: 10), mark('PHY', score: 10), mark('FR', score: 10)],
          ).general!;

      final before = oldAverage(const [v25, v26]);

      // New configuration added for a later year must NOT alter 2025/26.
      const v27 = CoefficientConfig(
        id: 'v27',
        subjectId: 'MATHS',
        coefficient: 7,
        source: ConfigSource.academicYear,
        schoolId: 's1',
        academicYearId: '2027/2028',
        levelId: '3EME',
      );
      final after = oldAverage(const [v25, v26, v27]);

      expect(before, after);
      expect(before, 10.0); // (50 + 40 + 40) / 13
      // And the historical coefficient resolution itself is unchanged.
      expect(
        resolveCoefficient(context(year: '2025/2026', level: '3EME'), 'MATHS',
            const [v25, v26, v27]),
        5,
      );
      expect(
        resolveCoefficient(context(year: '2026/2027', level: '3EME'), 'MATHS',
            const [v25, v26, v27]),
        6,
      );
    });
  });
}