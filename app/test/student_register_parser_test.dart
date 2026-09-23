import 'package:flutter_test/flutter_test.dart';
import 'package:report_wise/src/data/imports/student_register_parser.dart';

Map<String, dynamic> word(
  String text,
  double x,
  double y, {
  double? confidence,
}) => {
  'text': text,
  'x': x,
  'y': y,
  'height': .012,
  'width': .025,
  'confidence': ?confidence,
};

List<Map<String, dynamic>> line(List<String> cells, double y) => [
  for (var column = 0; column < cells.length; column++)
    for (var part = 0; part < cells[column].split(' ').length; part++)
      if (cells[column].split(' ')[part].isNotEmpty)
        word(
          cells[column].split(' ')[part],
          .04 + column * .18 + part * .032,
          y,
        ),
];

Map<String, dynamic> page(List<Map<String, dynamic>> words) => {
  'page_number': 1,
  'raw_text': 'source text',
  'words': words,
};

void main() {
  test(
    'maps full names, optional IDs, class and ISO dates without auto approval',
    () {
      final result = StudentRegisterParser().parse([
        page([
          ...line(['Student ID', 'Full Name', 'DOB', 'Sex', 'Class'], .1),
          ...line(['S-001', 'Amina Bello', '2012-03-12', 'F', 'Form 1A'], .15),
          ...line(['', 'David Tamba', '', 'M', 'Form 1A'], .2),
        ]),
      ]).single;
      final rows = result['rows'] as List;
      expect(rows, hasLength(2));
      expect(rows.first['normalized_data']['full_name'], 'Amina Bello');
      expect(rows.first['normalized_data']['matricule'], 'S-001');
      expect(rows.first['normalized_data']['external_student_id'], 'S-001');
      expect(rows.last['normalized_data']['matricule'], isNull);
      expect(rows.last['normalized_data']['date_of_birth'], isNull);
      expect(
        rows.first['confidence'],
        isEmpty,
        reason: 'Windows provides no confidence score',
      );
    },
  );

  test('combines French split names with accents', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['Prénom', 'Nom', 'Matricule', 'Classe', 'Sexe'], .1),
                ...line(['Thérèse', 'Ngassa', 'MAT-001', '5ème A', 'F'], .15),
              ]),
            ]).single['rows']
            as List;
    expect(rows.single['normalized_data']['full_name'], 'Thérèse Ngassa');
    expect(rows.single['normalized_data']['matricule'], 'MAT-001');
  });

  test('tolerates one OCR error in a long heading without changing IDs', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['Maticul', 'Full Name', 'Class'], .1),
                ...line(['MAT-S-001', 'Khadija Issa', '5eme A'], .15),
              ]),
            ]).single['rows']
            as List;
    expect(rows.single['normalized_data']['matricule'], 'MAT-S-001');
  });

  test('exact ordinal heading wins over fuzzy first-name heading', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['N°', 'First name', 'Last name', 'Class'], .1),
                ...line(['1', 'Ursula', 'Ateba', '3eme A'], .15),
              ]),
            ]).single['rows']
            as List;
    expect(rows.single['normalized_data']['full_name'], 'Ursula Ateba');
    expect(rows.single['raw_data']['_number'], '1');
  });

  test('joins an identifier wrapped across two text lines', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['Matricule', 'Name', 'Class'], .1),
                word('MAT-5-', .04, .144),
                word('001', .04, .156),
                ...line(['', 'Khadija Issa', '5eme A'], .15),
                ...line(['', 'Nadia Ojong', '5eme A'], .21),
              ]),
            ]).single['rows']
            as List;
    expect(rows, hasLength(2));
    expect(rows.first['normalized_data']['matricule'], 'MAT-5-001');
    expect(rows.last['normalized_data']['matricule'], isNull);
  });

  test('repeated headings are not students and can change column order', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['Name', 'Class', 'Sex'], .1),
                ...line(['Amina Bello', 'Form 1A', 'F'], .15),
                ...line(['Sex', 'Name', 'Class'], .3),
                ...line(['M', 'David Tamba', 'Form 1B'], .35),
              ]),
            ]).single['rows']
            as List;
    expect(rows.map((r) => r['normalized_data']['full_name']), [
      'Amina Bello',
      'David Tamba',
    ]);
  });

  test('does not invent students from unstructured prose', () {
    final result = StudentRegisterParser().parse([
      page(line(['Registrar note: check all names'], .1)),
    ]).single;
    expect(result['rows'], isEmpty);
    expect(result['raw_text'], 'source text');
    expect(result['warnings'], isNotEmpty);
  });

  test(
    'preserves ambiguous or invalid dates in raw values and flags review',
    () {
      final row =
          (StudentRegisterParser().parse([
                    page([
                      ...line(['Name', 'DOB', 'Class'], .1),
                      ...line(['Amina Bello', '12/03/2012', 'Form 1A'], .15),
                    ]),
                  ]).single['rows']
                  as List)
              .single;
      expect(row['normalized_data']['date_of_birth'], isNull);
      expect(row['raw_data']['date_of_birth'], '12/03/2012');
      expect(row['warnings'], isNotEmpty);
      expect(StudentRegisterParser.normalizeDate('2012-02-30'), isNull);
      expect(StudentRegisterParser.normalizeDate('31/08/2009'), '2009-08-31');
      expect(StudentRegisterParser.normalizeDate('2012-02-29'), '2012-02-29');
    },
  );

  test('blank pages produce a warning instead of a manual-mode claim', () {
    final result = StudentRegisterParser().parse([page([])]).single;
    expect(result['rows'], isEmpty);
    expect(result['warnings'].single, contains('No text'));
  });

  test('footer prose across multiple columns is not a student', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['Name', 'DOB', 'Class'], .1),
                ...line(['Amina Bello', '2012-03-12', 'Form 1A'], .15),
                ...line(['Registrar note', 'for review', ''], .4),
                ...line(['Synthetic test document', 'Page 1', ''], .8),
              ]),
            ]).single['rows']
            as List;
    expect(rows, hasLength(1));
  });

  test('unknown columns do not contaminate student names', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['Name', 'Address', 'Class'], .1),
                ...line(['Amina Bello', 'Buea Town', 'Form 1A'], .15),
              ]),
            ]).single['rows']
            as List;
    expect(rows.single['normalized_data']['full_name'], 'Amina Bello');
    expect(rows.single['normalized_data']['class_name'], 'Form 1A');
  });

  test('a misread ordinal does not discard a student with valid fields', () {
    final rows =
        StudentRegisterParser().parse([
              page([
                ...line(['No', 'Name', 'Class'], .1),
                ...line(['I', 'Amina Bello', 'Form 1A'], .15),
              ]),
            ]).single['rows']
            as List;
    expect(rows, hasLength(1));
  });
}
