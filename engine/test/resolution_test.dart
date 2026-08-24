import 'package:academic_engine/academic_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('coefficient resolution (most specific wins)', () {
    test('school override beats national default (section 8)', () {
      final national = CoefficientConfig(
        id: 'nat',
        subjectId: 'MATHS',
        coefficient: 4,
        source: ConfigSource.nationalDefault,
        levelId: '3EME',
      );
      final schoolCfg = CoefficientConfig(
        id: 'sch',
        subjectId: 'MATHS',
        coefficient: 5,
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
      );

      final schoolOne = context(school: 's1', level: '3EME');
      final schoolTwo = context(school: 's2', level: '3EME');

      expect(resolveCoefficient(schoolOne, 'MATHS', [national, schoolCfg]), 5);
      // A second school sees only the national default.
      expect(resolveCoefficient(schoolTwo, 'MATHS', [national, schoolCfg]), 4);
    });

    test('school-type default loses to school-specific config (section 7)', () {
      final general = CoefficientConfig(
        id: 'g',
        subjectId: 'MATHS',
        coefficient: 4,
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        educationTypeId: 'GENERAL',
      );
      final exact = CoefficientConfig(
        id: 'e',
        subjectId: 'MATHS',
        coefficient: 6,
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        educationTypeId: 'GENERAL',
        levelId: '3EME',
      );

      expect(
        resolveCoefficient(
            context(level: '3EME'), 'MATHS', [general, exact]),
        6,
      );
      // Same school, different level: falls back to the broader row.
      expect(
        resolveCoefficient(
            context(level: '5EME'), 'MATHS', [general, exact]),
        4,
      );
    });

    test('academic-year versioning: old report cards stay reproducible',
        () {
      final v2025 = CoefficientConfig(
        id: 'v25',
        subjectId: 'MATHS',
        coefficient: 5,
        source: ConfigSource.academicYear,
        schoolId: 's1',
        academicYearId: '2025/2026',
      );
      final v2026 = CoefficientConfig(
        id: 'v26',
        subjectId: 'MATHS',
        coefficient: 6,
        source: ConfigSource.academicYear,
        schoolId: 's1',
        academicYearId: '2026/2027',
      );

      expect(
        resolveCoefficient(context(year: '2025/2026'), 'MATHS', [v2025, v2026]),
        5,
      );
      expect(
        resolveCoefficient(context(year: '2026/2027'), 'MATHS', [v2025, v2026]),
        6,
      );
    });

    test('academic-year version wins over unversioned school row', () {
      final schoolYear = CoefficientConfig(
        id: 'syn',
        subjectId: 'MATHS',
        coefficient: 5,
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
      );
      final versioned = CoefficientConfig(
        id: 'ver',
        subjectId: 'MATHS',
        coefficient: 6,
        source: ConfigSource.academicYear,
        schoolId: 's1',
        academicYearId: '2026/2027',
      );

      expect(
        resolveCoefficient(context(year: '2026/2027'), 'MATHS', [schoolYear, versioned]),
        6,
      );
      // Outside the versioned year, the unversioned school row applies.
      expect(
        resolveCoefficient(context(year: '2025/2026'), 'MATHS', [schoolYear, versioned]),
        5,
      );
    });

    test('series-scoped config beats level-scoped config (technical series)', () {
      final byLevel = CoefficientConfig(
        id: 'lvl',
        subjectId: 'ACCT',
        coefficient: 3,
        source: ConfigSource.schoolConfiguration,
        schoolId: 'tech1',
        levelId: 'TLE',
      );
      final bySeries = CoefficientConfig(
        id: 'srs',
        subjectId: 'ACCT',
        coefficient: 5,
        source: ConfigSource.schoolConfiguration,
        schoolId: 'tech1',
        levelId: 'TLE',
        seriesId: 'STT',
        specialtyId: 'GCA',
      );

      expect(
        resolveCoefficient(
            context(school: 'tech1', level: 'TLE', series: 'STT', specialty: 'GCA'),
            'ACCT',
            [byLevel, bySeries]),
        5,
      );
    });

    test('subsystem-scoped config applies only to its subsystem', () {
      final fr = CoefficientConfig(
        id: 'fr',
        subjectId: 'FR',
        coefficient: 4,
        source: ConfigSource.schoolConfiguration,
        schoolId: 'bi1',
        subsystem: 'FRANCOPHONE',
      );

      expect(
        resolveCoefficient(context(school: 'bi1', subsystem: 'FRANCOPHONE'), 'FR', [fr]),
        4,
      );
      expect(
        resolveCoefficient(context(school: 'bi1', subsystem: 'ANGLOPHONE'), 'FR', [fr]),
        isNull,
      );
    });

    test('fully default row applies everywhere as the fallback', () {
      const fallback = CoefficientConfig(
        id: 'fb',
        subjectId: 'MATHS',
        coefficient: 4,
        source: ConfigSource.nationalDefault,
      );
      expect(resolveCoefficient(context(), 'MATHS', [fallback]), 4);
    });

    test('deterministic tie-break: source priority, then updated_at, then id', () {
      final older = CoefficientConfig(
        id: 'aaa',
        subjectId: 'MATHS',
        coefficient: 5,
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        updatedAt: DateTime(2026, 1, 1),
      );
      final newer = CoefficientConfig(
        id: 'aba',
        subjectId: 'MATHS',
        coefficient: 4,
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        updatedAt: DateTime(2026, 2, 1),
      );
      expect(resolveCoefficient(context(), 'MATHS', [older, newer]), 4);
      expect(resolveCoefficient(context(), 'MATHS', [newer, older]), 4);

      // Identical scopes AND timestamps -> lower id wins (still deterministic).
      final another = CoefficientConfig(
        id: 'abb',
        subjectId: 'MATHS',
        coefficient: 6,
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        updatedAt: DateTime(2026, 2, 1),
      );
      expect(resolveCoefficient(context(), 'MATHS', [newer, another]), 4); // 'aba' < 'abb'
    });
  });

  group('curriculum + rules engine (section 23, 25)', () {
    const national3emi = CurriculumEntry(
      id: 'nat-3eme',
      source: ConfigSource.nationalDefault,
      levelId: '3EME',
      subjects: [
        CurriculumSubject(
            subjectId: 'MATHS', coefficient: 5, subjectType: SubjectType.general),
        CurriculumSubject(
            subjectId: 'PHY', coefficient: 4, subjectType: SubjectType.general),
      ],
    );

    const technicalTle = CurriculumEntry(
      id: 'tech-tle',
      source: ConfigSource.nationalDefault,
      levelId: 'TLE',
      subjects: [
        CurriculumSubject(
            subjectId: 'ACCT',
            coefficient: 3,
            subjectType: SubjectType.professional),
        CurriculumSubject(
            subjectId: 'PRAC',
            coefficient: 2,
            subjectType: SubjectType.practical),
      ],
    );

    test('grammar school: national curriculum resolves by level', () {
      final engine = RulesEngine();
      final subjects = engine.resolveSubjects(
        ctx: context(level: '3EME'),
        curricula: const [national3emi, technicalTle],
        coefficientConfigs: const [],
      );

      expect(subjects.map((s) => s.subjectId), ['MATHS', 'PHY']);
      expect(subjects[0].coefficient, 5);
      expect(subjects[1].coefficient, 4);
    });

    test('technical school: professional/practical subjects resolve', () {
      final engine = RulesEngine();
      final subjects = engine.resolveSubjects(
        ctx: context(eduType: 'TECHNICAL', level: 'TLE', series: 'STT', specialty: 'GCA'),
        curricula: const [national3emi, technicalTle],
        coefficientConfigs: const [],
      );

      expect(subjects.map((s) => s.subjectId), ['ACCT', 'PRAC']);
      expect(subjects[0].subjectType, SubjectType.professional);
    });

    test('school coefficient override flows through subject resolution', () {
      final engine = RulesEngine();
      final subjects = engine.resolveSubjects(
        ctx: context(level: '3EME'),
        curricula: const [national3emi],
        coefficientConfigs: const [
          CoefficientConfig(
            id: 'ov',
            subjectId: 'MATHS',
            coefficient: 6,
            source: ConfigSource.schoolConfiguration,
            schoolId: 's1',
          )
        ],
      );

      expect(subjects[0].coefficient, 6);
      expect(subjects[0].source, ConfigSource.schoolConfiguration);
    });

    test('assessment scheme resolves by context', () {
      const nationalScheme = SchemeConfig(
        id: 'nat',
        name: 'national',
        source: ConfigSource.nationalDefault,
        components: [
          AssessmentComponent(
              id: 'e', name: 'Exam', componentType: 'EXAM', weight: 1.0, maxScore: 20)
        ],
      );
      const schoolScheme = SchemeConfig(
        id: 'sch',
        name: 'school',
        source: ConfigSource.schoolConfiguration,
        schoolId: 's1',
        components: [
          AssessmentComponent(
              id: 'ca',
              name: 'Continuous assessment',
              componentType: 'CONTINUOUS_ASSESSMENT',
              weight: 0.4,
              maxScore: 20),
          AssessmentComponent(
              id: 'e', name: 'Exam', componentType: 'EXAM', weight: 0.6, maxScore: 20),
        ],
      );

      final engine = RulesEngine();
      final s1 = engine.resolveScheme(context(school: 's1'), [nationalScheme, schoolScheme]);
      final s2 = engine.resolveScheme(context(school: 's2'), [nationalScheme, schoolScheme]);

      expect(s1!.id, 'sch');
      expect(s2!.id, 'nat');
      expect(s1.totalWeight, closeTo(1.0, 1e-9));
    });
  });

  group('annual calculation config', () {
    test('annual method is resolved from rules, not hardcoded', () {
      // Schools can configure MEAN_OF_SEQUENCE_AVERAGES instead of term averages.
      final custom = computeAnnualAverage(
        termAverages: [10.5, 11.5, 12.0],
        method: AnnualAverageMethod.meanOfTermAverages,
        display: DisplayPrecision.standard,
      );
      expect(custom, 11.33);
    });
  });
}