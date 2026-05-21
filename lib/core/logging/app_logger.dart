import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum AppLogLevel {
  debug,
  info,
  warning,
  error;

  String get label {
    switch (this) {
      case AppLogLevel.debug:
        return 'DEBUG';
      case AppLogLevel.info:
        return 'INFO';
      case AppLogLevel.warning:
        return 'WARN';
      case AppLogLevel.error:
        return 'ERROR';
    }
  }
}

class AppLogger {
  AppLogger._();

  static const int _consoleChunkSize = 3000;
  static File? _logFile;
  static IOSink? _sink;
  static AppLogLevel consoleLevel = AppLogLevel.info;

  static String? get logFilePath => _logFile?.path;

  static Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDirectory = Directory('${directory.path}/logs');
      if (!logDirectory.existsSync()) {
        logDirectory.createSync(recursive: true);
      }
      _logFile = File('${logDirectory.path}/phone_agent.log');
      await _rotateIfNeeded(_logFile!);
      _sink = _logFile!.openWrite(mode: FileMode.append);
      info('logger.initialized', {'path': _logFile!.path});
    } on Object catch (error, stackTrace) {
      _printToConsole('[ERROR] logger.initialize_failed $error\n$stackTrace');
    }
  }

  static void debug(String event, [Map<String, Object?> data = const {}]) {
    _write(AppLogLevel.debug, event, data);
  }

  static void info(String event, [Map<String, Object?> data = const {}]) {
    _write(AppLogLevel.info, event, data);
  }

  static void warning(String event, [Map<String, Object?> data = const {}]) {
    _write(AppLogLevel.warning, event, data);
  }

  static void error(
    String event,
    Object error, [
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  ]) {
    _write(AppLogLevel.error, event, {
      ...data,
      'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    });
  }

  static Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  static void _write(
    AppLogLevel level,
    String event,
    Map<String, Object?> data,
  ) {
    final line =
        '${DateTime.now().toIso8601String()} ${level.label} $event ${_formatData(data)}'
            .trimRight();
    if (level.index >= consoleLevel.index) {
      _printToConsole(line);
    }
    _sink?.writeln(line);
  }

  static void _printToConsole(String line) {
    if (line.length <= _consoleChunkSize) {
      debugPrint(line);
      return;
    }

    final chunkCount = (line.length / _consoleChunkSize).ceil();
    for (var index = 0; index < chunkCount; index += 1) {
      final start = index * _consoleChunkSize;
      final end = (start + _consoleChunkSize).clamp(0, line.length);
      debugPrint(
        '[chunk ${index + 1}/$chunkCount] ${line.substring(start, end)}',
      );
    }
  }

  static String _formatData(Map<String, Object?> data) {
    if (data.isEmpty) {
      return '';
    }
    return data.entries
        .map((entry) => '${entry.key}=${_sanitize(entry.value)}')
        .join(' ');
  }

  static String _sanitize(Object? value) {
    final text = value?.toString() ?? 'null';
    return text
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]+'), 'sk-***')
        .replaceAll('\n', r'\n');
  }

  static Future<void> _rotateIfNeeded(File file) async {
    if (!file.existsSync()) {
      return;
    }
    final length = await file.length();
    if (length < 1024 * 1024) {
      return;
    }
    final rotated = File('${file.path}.1');
    if (rotated.existsSync()) {
      await rotated.delete();
    }
    await file.rename(rotated.path);
  }
}
