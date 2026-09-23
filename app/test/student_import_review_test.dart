import 'package:flutter_test/flutter_test.dart';
import 'package:report_wise/src/core/school_labels.dart';
import 'package:report_wise/src/data/entities.dart';
import 'package:report_wise/src/data/imports/student_import_review.dart';
import 'package:report_wise/src/data/repositories/student_import_repository.dart';

void main() {
  final classes = [
    SchoolClass(
      id: 'c',
      schoolId: 's',
      academicYearId: 'y',
      subsystem: 'ANGLOPHONE',
      educationTypeId: 'e',
      cycleId: 'cy',
      levelId: 'l',
      name: 'Form 1 A',
    ),
  ];
  StudentImportRow row(
    Map<String, dynamic> raw, {
    Map<String, dynamic> normalized = const {},
    String status = 'NEEDS_REVIEW',
  }) => StudentImportRow(
    id: 'r',
    rowNumber: 1,
    normalizedData: normalized,
    rawData: raw,
    confidence: {},
    status: status,
  );

  test('review prefills source aliases and maps a unique class', () {
    final values = reviewValues(
      row({
        'first_name': 'Jane',
        'last_name': 'Doe',
        'student_id': 'OLD-12',
        'class': 'Form 1 A',
        'dob': '2011-09-20',
        'sex': 'Female',
      }),
      classes,
    );
    expect(values['full_name'], 'Jane Doe');
    expect(values['matricule'], 'OLD-12');
    expect(values['date_of_birth'], '2011-09-20');
    expect(values['gender'], 'F');
    expect(values['class_id'], 'c');
    expect(approvalProblem(values, classes), isNull);
  });
  test('ambiguous dates remain visible and block quick approval', () {
    final values = reviewValues(
      row({'name': 'Jane Doe', 'class': 'Form 1 A', 'dob': '03/04/2011'}),
      classes,
    );
    expect(values['date_of_birth'], '03/04/2011');
    expect(approvalProblem(values, classes), isNotNull);
  });
  test('saved corrections and cleared dates are not replaced by OCR', () {
    final values = reviewValues(
      row(
        {'name': 'Bad OCR', 'dob': '03/04/2011'},
        normalized: {
          'full_name': 'Jane Doe',
          'class_id': 'c',
          'date_of_birth': null,
        },
        status: 'APPROVED',
      ),
      classes,
    );
    expect(values['full_name'], 'Jane Doe');
    expect(values['date_of_birth'], isNull);
  });
  test('blank rows and unknown classes cannot be approved', () {
    expect(approvalProblem(reviewValues(row({}), classes), classes), isNotNull);
    expect(
      approvalProblem(
        reviewValues(row({'name': 'Jane', 'class': 'Unknown'}), classes),
        classes,
      ),
      isNotNull,
    );
  });
  test('bilingual school reports follow the student class section', () {
    final english = SchoolLabels.forClass('BILINGUAL', 'ANGLOPHONE');
    final french = SchoolLabels.forClass('BILINGUAL', 'FRANCOPHONE');
    expect(english.period('Trimestre 1'), 'Term 1');
    expect(french.period('Term 1'), 'Trimestre 1');
    expect(english.text('Subject', 'Matière'), 'Subject');
    expect(french.text('Subject', 'Matière'), 'Matière');
    expect(english.period('Mid-year examination'), 'Mid-year examination');
  });
}
