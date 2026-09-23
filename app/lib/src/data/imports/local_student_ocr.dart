import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'student_register_parser.dart';

class LocalStudentOcr {
  static const _channel = MethodChannel('reportwise/local_student_ocr');
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  Future<List<Map<String, dynamic>>> extract(
    String path, {
    void Function(int page, int total)? onProgress,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Free scanning is available in the Windows and Mac desktop apps.',
      );
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onProgress?.call(args['page'] as int, args['total'] as int);
      }
    });
    try {
      final result = await _channel.invokeListMethod<dynamic>('extractPdf', {
        'path': path,
      });
      final pages = (result ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      if (pages.isEmpty) {
        throw const FormatException('This PDF has no readable pages.');
      }
      return StudentRegisterParser().parse(pages);
    } on MissingPluginException {
      throw StateError(
        'Restart the updated desktop app to enable free PDF scanning.',
      );
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
