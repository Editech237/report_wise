import 'package:flutter_test/flutter_test.dart';

import 'package:report_wise/src/app.dart';

void main() {
  testWidgets('ReportWise app boots and runs the grading engine demo',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ReportWiseApp());

    expect(find.text('ReportWise'), findsOneWidget);
    expect(find.text('Cameroon Secondary School Management Platform'),
        findsOneWidget);

    // The engine demo computes 148/11 = 13.45 (section 30 validation example).
    expect(find.text('13.45'), findsOneWidget);
  });
}