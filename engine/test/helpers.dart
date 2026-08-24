import 'package:academic_engine/academic_engine.dart';

/// Shared builders for the academic engine tests.

SchemeConfig singleExamScheme() => const SchemeConfig(
      id: 'sch-exam',
      name: 'Single exam',
      components: [
        AssessmentComponent(
            id: 'exam', name: 'Exam', componentType: 'EXAM', weight: 1.0, maxScore: 20),
      ],
      source: ConfigSource.nationalDefault,
    );

SchemeConfig classicScheme() => const SchemeConfig(
      id: 'sch-classic',
      name: 'Classic Cameroon',
      components: [
        AssessmentComponent(
            id: 'interro', name: 'Interrogation', componentType: 'CLASS_TEST', weight: 0.2, maxScore: 20),
        AssessmentComponent(
            id: 'devoir', name: 'Devoir', componentType: 'ASSIGNMENT', weight: 0.3, maxScore: 20),
        AssessmentComponent(
            id: 'exam', name: 'Examen', componentType: 'EXAM', weight: 0.5, maxScore: 20),
      ],
      source: ConfigSource.nationalDefault,
    );

const defaultPolicy = MissingMarkPolicy(
  excludedStatuses: {
    AbsenceStatus.notEntered,
    AbsenceStatus.absent,
    AbsenceStatus.excused,
    AbsenceStatus.notApplicable,
    AbsenceStatus.pending,
  },
  zeroIsScore: true,
);

SubjectConfig subject(
  String subjectId, {
  double coefficient = 1,
  bool countsInAverage = true,
  bool countsInRanking = true,
  bool showsOnReport = true,
}) =>
    SubjectConfig(
      subjectId: subjectId,
      code: subjectId,
      name: subjectId,
      coefficient: coefficient,
      countsInAverage: countsInAverage,
      countsInRanking: countsInRanking,
      showsOnReport: showsOnReport,
    );

ComponentMark mark(
  String subjectId, {
  required double score,
  String componentId = 'exam',
  double maxScore = 20,
  AbsenceStatus status = AbsenceStatus.entered,
}) =>
    ComponentMark(
      subjectId: subjectId,
      componentId: componentId,
      score: score,
      maxScore: maxScore,
      absenceStatus: status,
    );

ComponentMark absentMark(String subjectId, {AbsenceStatus status = AbsenceStatus.absent}) =>
    ComponentMark(
      subjectId: subjectId,
      componentId: 'exam',
      absenceStatus: status,
    );

AcademicContext context({
  String school = 's1',
  String year = '2025/2026',
  String subsystem = 'FRANCOPHONE',
  String eduType = 'GENERAL',
  String cycle = 'c1',
  String level = '3EME',
  String? series,
  String? specialty,
  String? classId,
}) =>
    AcademicContext(
      schoolId: school,
      academicYearId: year,
      subsystem: subsystem,
      educationTypeId: eduType,
      cycleId: cycle,
      levelId: level,
      seriesId: series,
      specialtyId: specialty,
      classId: classId,
    );

/// Clamp helper sharing the engine's display rounding for assertions.
double r(double v, [int decimals = 2]) =>
    displayRound(v, DisplayPrecision(decimals: decimals));