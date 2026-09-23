import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:report_wise/src/data/imports/local_student_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('reportwise/local_student_ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'Windows scan calls the native bridge and preserves empty-page warnings',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'extractPdf');
        expect(call.arguments['path'], r'C:\School Registers\term one.pdf');
        return [
          {'page_number': 1, 'raw_text': '', 'words': []},
        ];
      });
      final pages = await LocalStudentOcr().extract(
        r'C:\School Registers\term one.pdf',
      );
      expect(pages.single['rows'], isEmpty);
      expect(pages.single['warnings'], isNotEmpty);
    },
  );

  test(
    'native OCR errors are not silently replaced with manual mode',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'OCR_FAILED',
          message: 'Install an OCR language pack.',
        );
      });
      await expectLater(
        LocalStudentOcr().extract('register.pdf'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('missing bridge asks for an app restart', () async {
    await expectLater(
      LocalStudentOcr().extract('register.pdf'),
      throwsA(isA<StateError>()),
    );
  });

  test('unsupported platforms fail explicitly', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(LocalStudentOcr.isSupported, isFalse);
    await expectLater(
      LocalStudentOcr().extract('register.pdf'),
      throwsUnsupportedError,
    );
  });
}
