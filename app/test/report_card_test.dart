import 'package:flutter_test/flutter_test.dart';
import 'package:report_wise/src/data/entities.dart';
import 'package:report_wise/src/features/reports/report_card.dart';
import 'package:report_wise/src/features/reports/report_pdf.dart';

void main() {
  group('appreciationFor', () {
    test('maps Cameroon appreciation bands', () {
      expect(appreciationFor(18.5), 'Excellent');
      expect(appreciationFor(16), 'Très bien');
      expect(appreciationFor(14.2), 'Bien');
      expect(appreciationFor(12), 'Assez bien');
      expect(appreciationFor(10.5), 'Passable');
      expect(appreciationFor(9.9), 'Insuffisant');
    });
  });

  group('buildReportCardData', () {
    final result = PeriodResult(
      id: 'pr1',
      studentEnrollmentId: 'e1',
      studentName: 'Abanda Marie',
      matricule: 'CM-001',
      generalAverage: 13.45,
      totalWeightedPoints: 148,
      totalCoefficients: 11,
      classAverage: 12.1,
      rank: 3,
      status: 'FINAL',
      subjects: [
        SubjectResultItem(subjectId: 's1', subjectName: 'Mathematics', subjectAverage: 14, coefficient: 5, weightedPoints: 70),
        SubjectResultItem(subjectId: 's2', subjectName: 'Physics', subjectAverage: 12, coefficient: 4, weightedPoints: 48),
      ],
    );

    final school = School(
      id: 'sc1',
      name: 'GBHS Yaoundé',
      schoolType: 'GENERAL',
      subsystem: 'FRANCOPHONE',
      address: 'Yaoundé',
    );

    final cls = SchoolClass(
      id: 'c1',
      schoolId: 'sc1',
      academicYearId: 'y1',
      subsystem: 'FRANCOPHONE',
      educationTypeId: 'et1',
      cycleId: 'cy1',
      levelId: 'lv1',
      name: '3ème A',
      seriesName: 'A',
    );

    test('maps snapshot fields and computes appreciation', () {
      final data = buildReportCardData(
        school: school,
        academicYearName: '2026/2027',
        periodLabel: 'Sequence 1',
        cls: cls,
        result: result,
      );
      expect(data.studentName, 'Abanda Marie');
      expect(data.matricule, 'CM-001');
      expect(data.generalAverage, 13.45);
      expect(data.totalWeightedPoints, 148);
      expect(data.totalCoefficients, 11);
      expect(data.rank, 3);
      expect(data.appreciation, 'Assez bien');
      expect(data.subjects.length, 2);
      expect(data.subjects.first.name, 'Mathematics');
      expect(data.subjects.first.coefficient, 5);
      expect(data.subjects.last.points, 48);
    });

    test('appreciation is a dash when there is no average', () {
      final noAvg = PeriodResult(
        id: 'pr2',
        studentEnrollmentId: 'e2',
        studentName: 'Bello',
        generalAverage: null,
        status: 'DRAFT',
      );
      final data = buildReportCardData(
        school: school,
        academicYearName: '2026/2027',
        periodLabel: 'Sequence 1',
        cls: cls,
        result: noAvg,
      );
      expect(data.appreciation, '—');
    });
  });

  test('buildReportPdf produces a non-empty PDF', () async {
    final data = ReportCardData(
      schoolName: 'GBHS Yaoundé',
      academicYearName: '2026/2027',
      periodLabel: 'Sequence 1',
      studentName: 'Abanda Marie',
      matricule: 'CM-001',
      className: '3ème A',
      seriesName: 'A',
      generalAverage: 13.45,
      totalWeightedPoints: 148,
      totalCoefficients: 11,
      classAverage: 12.1,
      rank: 3,
      appreciation: 'Bien',
      subjects: const [
        ReportSubjectRow(name: 'Mathematics', coefficient: 5, average: 14, points: 70),
        ReportSubjectRow(name: 'Physics', coefficient: 4, average: 12, points: 48),
      ],
    );
    final bytes = await buildReportPdf(data);
    expect(bytes.length, greaterThan(1000));
    expect(bytes.sublist(0, 4), [37, 80, 68, 70]); // %PDF
  });
}