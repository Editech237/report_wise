import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:report_wise/src/app.dart';

void main() {
  testWidgets('ReportWise app boots and runs the grading engine demo',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      // No Supabase is configured in tests → supabaseClientProvider is null and
      // the app renders the standalone grading-engine demo.
      const ProviderScope(child: ReportWiseApp()),
    );

    expect(find.text('ReportWise'), findsOneWidget);
    expect(find.text('Cameroon Secondary School Management Platform'),
        findsOneWidget);

    // The engine demo computes 148/11 = 13.45 (section 30 validation example).
    expect(find.text('13.45'), findsOneWidget);
  });
}