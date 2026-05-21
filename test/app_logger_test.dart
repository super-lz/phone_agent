import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/core/logging/app_logger.dart';

void main() {
  test('long console log lines are split into readable chunks', () {
    final originalDebugPrint = debugPrint;
    final originalConsoleLevel = AppLogger.consoleLevel;
    final logs = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      logs.add(message ?? '');
    };
    AppLogger.consoleLevel = AppLogLevel.info;
    addTearDown(() {
      debugPrint = originalDebugPrint;
      AppLogger.consoleLevel = originalConsoleLevel;
    });

    AppLogger.info('model.stream_chat.request_prompt', {
      'messages': '${'x' * 6500}END',
    });

    expect(logs.length, greaterThan(1));
    expect(logs.first, contains('[chunk 1/'));
    expect(logs.last, contains('END'));
  });
}
