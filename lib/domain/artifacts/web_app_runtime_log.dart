import 'dart:convert';

import 'artifact.dart';

class WebAppRuntimeLogEntry {
  const WebAppRuntimeLogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.url,
    this.filename,
    this.line,
    this.column,
    this.stackTrace,
    this.userAgent,
    this.viewport,
  });

  final DateTime timestamp;
  final String level;
  final String source;
  final String message;
  final String? url;
  final String? filename;
  final int? line;
  final int? column;
  final String? stackTrace;
  final String? userAgent;
  final Map<String, Object?>? viewport;

  factory WebAppRuntimeLogEntry.fromBridgePayload(Object? payload) {
    final data = payload is Map<Object?, Object?>
        ? payload.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    return WebAppRuntimeLogEntry(
      timestamp: DateTime.now(),
      level: _string(data['level'], fallback: 'info'),
      source: _string(data['source'], fallback: 'webview'),
      message: _string(data['message'], fallback: ''),
      url: _optionalString(data['url']),
      filename: _optionalString(data['filename']),
      line: _optionalInt(data['line']),
      column: _optionalInt(data['column']),
      stackTrace: _optionalString(data['stackTrace']),
      userAgent: _optionalString(data['userAgent']),
      viewport: _optionalMap(data['viewport']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level,
      'source': source,
      'message': message,
      if (url != null) 'url': url,
      if (filename != null) 'filename': filename,
      if (line != null) 'line': line,
      if (column != null) 'column': column,
      if (stackTrace != null) 'stackTrace': stackTrace,
      if (userAgent != null) 'userAgent': userAgent,
      if (viewport != null) 'viewport': viewport,
    };
  }

  String toJsonLine() {
    return '${jsonEncode(toJson())}\n';
  }

  static String _string(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static String? _optionalString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static int? _optionalInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static Map<String, Object?>? _optionalMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}

class WebAppRuntimeLogPaths {
  const WebAppRuntimeLogPaths._();

  static String forArtifact(AgentArtifact webApp) {
    final declared = webApp.metadata['runtimeLogPath'];
    if (declared is String && declared.trim().isNotEmpty) {
      return declared.trim();
    }
    return forMetadata(artifactId: webApp.id, metadata: webApp.metadata);
  }

  static String forMetadata({
    required String artifactId,
    required Map<String, Object?> metadata,
  }) {
    final entry = metadata['entry'];
    if (entry is String && entry.trim().isNotEmpty) {
      final normalized = entry.trim().replaceAll('\\', '/');
      final slash = normalized.lastIndexOf('/');
      if (slash > 0) {
        return '${normalized.substring(0, slash)}/.phone-agent/runtime.log';
      }
    }
    return 'webapps/${_safeSegment(artifactId)}/.phone-agent/runtime.log';
  }

  static String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
