import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:report_wise/src/data/entities.dart';
import 'package:report_wise/src/data/repositories/student_import_repository.dart';
import 'package:report_wise/src/features/students/student_import_review_dialog.dart';

class FakeImports extends StudentImportRepository {
  FakeImports()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int inserts = 0;
  final updates = <String>[];
  final rows = [
    const StudentImportRow(
      id: 'good',
      rowNumber: 1,
      normalizedData: {
        'full_name': 'Jane Doe',
        'class_id': 'c',
        'matricule': 'OLD-12',
        'date_of_birth': '2011-09-20',
      },
      confidence: {},
      status: 'NEEDS_REVIEW',
    ),
    const StudentImportRow(
      id: 'bad',
      rowNumber: 2,
      normalizedData: {},
      confidence: {},
      status: 'NEEDS_REVIEW',
    ),
  ];
  @override
  Future<List<StudentImportRow>> listRows(String batchId) async => rows;
  @override
  Future<List<Map<String, dynamic>>> listExtractedPages(String batchId) async =>
      [];
  @override
  Future<void> updateRow({
    required String rowId,
    required Map<String, dynamic> normalizedData,
    required String status,
  }) async {
    updates.add(rowId);
    final i = rows.indexWhere((r) => r.id == rowId);
    rows[i] = StudentImportRow(
      id: rowId,
      rowNumber: rows[i].rowNumber,
      normalizedData: normalizedData,
      confidence: {},
      status: status,
    );
  }

  @override
  Future<StudentImportRow> createManualRow({
    required String batchId,
    required int rowNumber,
    required Map<String, dynamic> normalizedData,
  }) async {
    inserts++;
    return rows.first;
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeImports repo) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudentImportReviewDialog(
            academicYearId: 'y',
            batch: StudentImportBatch(
              id: 'b',
              schoolId: 's',
              originalFilename: 'test.pdf',
              status: 'NEEDS_REVIEW',
              storagePath: '',
              pageCount: 1,
              rowCount: 2,
              reviewedCount: 0,
              createdAt: DateTime(2026),
            ),
            classes: [
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
            ],
            repository: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Review opens with the extracted fields already filled', (
    tester,
  ) async {
    await open(tester, FakeImports());
    await tester.tap(find.text('Review').first);
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((w) => w.controller!.text)
        .toList();
    expect(fields, containsAll(['Jane Doe', 'OLD-12', '2011-09-20']));
    expect(find.text('Form 1 A'), findsWidgets);
  });
  testWidgets('Cancelling Add row does not create an empty record', (
    tester,
  ) async {
    final repo = FakeImports();
    await open(tester, repo);
    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.inserts, 0);
  });
  testWidgets(
    'Approve All approves valid rows and leaves invalid rows for review',
    (tester) async {
      final repo = FakeImports();
      await open(tester, repo);
      await tester.tap(find.text('Approve All'));
      await tester.pumpAndSettle();
      expect(repo.updates, ['good']);
      expect(repo.rows.last.status, 'NEEDS_REVIEW');
      expect(find.textContaining('1 rows approved.'), findsOneWidget);
    },
  );
  testWidgets('Approve approves only the selected row', (tester) async {
    final repo = FakeImports();
    await open(tester, repo);
    await tester.tap(find.text('Approve').first);
    await tester.pumpAndSettle();
    expect(repo.updates, ['good']);
    expect(find.text('Edit'), findsOneWidget);
  });
}
