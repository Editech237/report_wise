import 'package:academic_engine/academic_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Cameroonian coefficient model', () {
    test('spec validation example (section 30): 148/11 = 13.45', () {
      final subjects = [
        subject('MATHS', coefficient: 5),
        subject('PHY', coefficient: 4),
        subject('ENG', coefficient: 2),
      ];
      final marks = [
        mark('MATHS', score: 14),
        mark('PHY', score: 12),
        mark('ENG', score: 15),
      ];

      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: singleExamScheme(),
        subjects: subjects,
        marks: marks,
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      final maths = result.subjects[0];
      final phy = result.subjects[1];
      final eng = result.subjects[2];

      expect(maths.subjectAverage, closeTo(14, 1e-9));
      expect(maths.weightedPoints, closeTo(70, 1e-9));
      expect(phy.weightedPoints, closeTo(48, 1e-9));
      expect(eng.weightedPoints, closeTo(30, 1e-9));

      expect(result.totalWeightedPoints, closeTo(148, 1e-9));
      expect(result.totalCoefficients, closeTo(11, 1e-9));
      expect(result.generalAverage, 13.45);
    });

    test('coefficient 1, 2 and 5 scales correctly', () {
      for (final c in [1, 2, 5]) {
        final result = computeStudentPeriod(
          studentId: 'st1',
          scheme: singleExamScheme(),
          subjects: [subject('MATHS', coefficient: c.toDouble())],
          marks: [mark('MATHS', score: 16)],
          policy: defaultPolicy,
          display: DisplayPrecision.standard,
        );
        expect(result.subjects.single.weightedPoints,
            closeTo(16 * c, 1e-9));
        expect(result.generalAverage, r(16 * c / c));
        expect(result.generalAverage, 16);
      }
    });

    test('decimal subject averages are weighted with full precision', () {
      final scheme = const SchemeConfig(
        id: 'thirds',
        name: 'thirds',
        components: [
          AssessmentComponent(
              id: 'a', name: 'a', componentType: 'EXAM', weight: 1 / 3, maxScore: 20),
          AssessmentComponent(
              id: 'b', name: 'b', componentType: 'EXAM', weight: 1 / 3, maxScore: 20),
          AssessmentComponent(
              id: 'c', name: 'c', componentType: 'EXAM', weight: 1 / 3, maxScore: 20),
        ],
        source: ConfigSource.nationalDefault,
      );
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: scheme,
        subjects: [subject('MATHS', coefficient: 3)],
        marks: [
          mark('MATHS', score: 3, componentId: 'a'),
          mark('MATHS', score: 3, componentId: 'b'),
          mark('MATHS', score: 4, componentId: 'c'),
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      final maths = result.subjects.single;
      expect(maths.subjectAverage, closeTo(10 / 3, 1e-9));
      expect(maths.weightedPoints, closeTo(10, 1e-9));
      expect(result.generalAverage, 3.33);
    });

    test('no intermediate rounding when weighting (subj avg 10.055 × coef 4)', () {
      final scheme = const SchemeConfig(
        id: 'half',
        name: 'half',
        components: [
          AssessmentComponent(
              id: 'a', name: 'a', componentType: 'EXAM', weight: 0.5, maxScore: 20),
          AssessmentComponent(
              id: 'b', name: 'b', componentType: 'EXAM', weight: 0.5, maxScore: 20),
        ],
        source: ConfigSource.nationalDefault,
      );
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: scheme,
        subjects: [subject('A', coefficient: 4), subject('B', coefficient: 1)],
        marks: [
          mark('A', score: 10.10, componentId: 'a'),
          mark('A', score: 10.01, componentId: 'b'),
          mark('B', score: 20, componentId: 'a'),
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      // Raw subject average (10.055) must flow into weighting unrounded.
      expect(result.subjects[0].subjectAverage, closeTo(10.055, 1e-9));
      expect(result.subjects[0].weightedPoints, closeTo(40.22, 1e-6));
      expect(result.totalWeightedPoints, closeTo(60.22, 1e-6));
      // (40.22 + 20) / 5 = 12.044 -> 12.04. If A had been pre-rounded to
      // 10.06 the result would be 12.05.
      expect(result.generalAverage, 12.04);
    });

    test('subject with no marks is excluded, not counted as zero', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: singleExamScheme(),
        subjects: [subject('MATHS', coefficient: 5), subject('PHY', coefficient: 4)],
        marks: [mark('MATHS', score: 14)],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      expect(result.excludedSubjects, ['PHY']);
      expect(result.totalCoefficients, closeTo(5, 1e-9));
      expect(result.generalAverage, 14.0);
    });

    test('absent and excused are excluded from numerator and denominator', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: singleExamScheme(),
        subjects: [
          subject('MATHS', coefficient: 5),
          subject('PHY', coefficient: 4),
          subject('ENG', coefficient: 2),
        ],
        marks: [
          mark('MATHS', score: 14),
          absentMark('PHY', status: AbsenceStatus.absent),
          absentMark('ENG', status: AbsenceStatus.excused),
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      expect(result.excludedSubjects, containsAll(['PHY', 'ENG']));
      expect(result.totalCoefficients, closeTo(5, 1e-9));
      expect(result.generalAverage, 14.0);
    });

    test('NOT_APPLICABLE never touches the denominator', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: singleExamScheme(),
        subjects: [subject('MATHS', coefficient: 5), subject('ICT', coefficient: 1)],
        marks: [
          mark('MATHS', score: 14),
          absentMark('ICT', status: AbsenceStatus.notApplicable),
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      expect(result.excludedSubjects, ['ICT']);
      expect(result.totalCoefficients, closeTo(5, 1e-9));
      expect(result.generalAverage, 14.0);
    });

    test('ZERO is an academic score and counts toward the average', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: singleExamScheme(),
        subjects: [subject('A', coefficient: 1), subject('B', coefficient: 1)],
        marks: [
          mark('A', score: 20),
          absentMark('B', status: AbsenceStatus.zero),
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      expect(result.excludedSubjects, isEmpty);
      expect(result.generalAverage, 10.0);
    });

    test('subjects flagged out of the average keep their coefficient out', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: singleExamScheme(),
        subjects: [
          subject('MATHS', coefficient: 5),
          subject('EPS', coefficient: 2, countsInAverage: false),
        ],
        marks: [mark('MATHS', score: 10), mark('EPS', score: 20)],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );

      expect(result.totalCoefficients, closeTo(5, 1e-9));
      expect(result.generalAverage, 10.0);
    });

    test('all subjects missing -> no general average', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: singleExamScheme(),
        subjects: [subject('A'), subject('B')],
        marks: [absentMark('A'), absentMark('B')],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );
      expect(result.generalAverage, isNull);
      expect(result.excludedSubjects, ['A', 'B']);
    });

    test('a max_score different from 20 is normalized to /20', () {
      final component = AssessmentComponent(
          id: 'q', name: 'Quiz', componentType: 'QUIZ', weight: 1.0, maxScore: 10);
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: SchemeConfig(
            id: 'q', name: 'q', components: [component], source: ConfigSource.nationalDefault),
        subjects: [subject('MATHS', coefficient: 2)],
        marks: [
          const ComponentMark(
              subjectId: 'MATHS', componentId: 'q', score: 8, maxScore: 10)
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );
      // 8/10 == 16/20
      expect(result.subjects.single.subjectAverage, closeTo(16, 1e-9));
      expect(result.generalAverage, 16.0);
    });

    test('mixed component weights (20/30/50) produce weighted subject average', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: classicScheme(),
        subjects: [subject('MATHS', coefficient: 5)],
        marks: [
          mark('MATHS', score: 14, componentId: 'interro'),
          mark('MATHS', score: 12, componentId: 'devoir'),
          mark('MATHS', score: 16, componentId: 'exam'),
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );
      // 0.2*14 + 0.3*12 + 0.5*16 = 14.4
      expect(result.subjects.single.subjectAverage, closeTo(14.4, 1e-9));
      expect(result.generalAverage, 14.4);
    });

    test('missing component renormalizes the remaining weights', () {
      final result = computeStudentPeriod(
        studentId: 'st1',
        scheme: classicScheme(),
        subjects: [subject('MATHS', coefficient: 5)],
        marks: [
          mark('MATHS', score: 10, componentId: 'devoir'),
          mark('MATHS', score: 20, componentId: 'exam'),
        ],
        policy: defaultPolicy,
        display: DisplayPrecision.standard,
      );
      // only Devoir(30%) + Exam(50%) apply: (0.3*10 + 0.5*20) / 0.8 = 16.25
      expect(result.subjects.single.subjectAverage, closeTo(16.25, 1e-9));
      expect(result.generalAverage, 16.25);
    });
  });

  group('term and annual averages', () {
    test('term average is the mean of sequence averages', () {
      final term = computeTermAverage(
        sequenceAverages: [10.5, 11.5],
        display: DisplayPrecision.standard,
      );
      expect(term, 11.0);
    });

    test('annual average is the mean of term averages by default', () {
      final annual = computeAnnualAverage(
        termAverages: [10.5, 12.0, 11.5],
        method: AnnualAverageMethod.meanOfTermAverages,
        display: DisplayPrecision.standard,
      );
      expect(annual, 11.33); // 34/3 = 11.333...
    });

    test('custom annual method: mean of sequence averages', () {
      final annual = computeAnnualAverage(
        termAverages: [10.5, 11.5],
        method: AnnualAverageMethod.meanOfSequenceAverages,
        display: DisplayPrecision.standard,
      );
      expect(annual, 11.0);
    });
  });

  group('display rounding', () {
    test('half-up rounding', () {
      expect(displayRound(2.345, const DisplayPrecision(decimals: 2)), 2.35);
      expect(displayRound(2.344, const DisplayPrecision(decimals: 2)), 2.34);
      expect(displayRound(1.005, const DisplayPrecision(decimals: 2)), 1.01);
      expect(displayRound(13.4545, const DisplayPrecision(decimals: 2)), 13.45);
      expect(displayRound(13.4545, const DisplayPrecision(decimals: 3)), 13.455);
    });

    test('configurable display precision', () {
      expect(displayRound(10.5, const DisplayPrecision(decimals: 1)), 10.5);
      expect(displayRound(10.5, const DisplayPrecision(decimals: 2)), 10.5);
      expect(displayRound(10.555, const DisplayPrecision(decimals: 2)), 10.56);
    });
  });
}