import 'dart:convert';

class AppFileStoreException implements Exception {
  const AppFileStoreException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() {
    return '$code: $message';
  }
}

class AppFileWriteResult {
  const AppFileWriteResult({
    required this.path,
    required this.uri,
    required this.bytes,
  });

  final String path;
  final Uri uri;
  final int bytes;
}

class AppFileReadResult {
  const AppFileReadResult({
    required this.path,
    required this.content,
    required this.length,
    required this.truncated,
  });

  final String path;
  final String content;
  final int length;
  final bool truncated;
}

class AppFileEntry {
  const AppFileEntry({
    required this.path,
    required this.uri,
    required this.bytes,
    required this.modifiedAt,
  });

  final String path;
  final Uri uri;
  final int bytes;
  final DateTime modifiedAt;
}

abstract class AppFileStore {
  Future<AppFileWriteResult> writeText({
    required String workspaceId,
    required String path,
    required String content,
    required bool overwrite,
  });

  Future<AppFileReadResult> readText({
    required String workspaceId,
    required String path,
    required int maxChars,
  });

  Future<List<AppFileEntry>> listFiles({required String workspaceId});
}

class InMemoryAppFileStore implements AppFileStore {
  final Map<String, _InMemoryAppFile> _files = {};

  @override
  Future<AppFileWriteResult> writeText({
    required String workspaceId,
    required String path,
    required String content,
    required bool overwrite,
  }) async {
    final normalizedPath = normalizeAppFilePath(path);
    final key = _key(workspaceId, normalizedPath);
    if (!overwrite && _files.containsKey(key)) {
      throw const AppFileStoreException('file_exists', 'file already exists');
    }
    _files[key] = _InMemoryAppFile(content, DateTime.now());
    return AppFileWriteResult(
      path: normalizedPath,
      uri: Uri(path: '/memory/$workspaceId/$normalizedPath'),
      bytes: utf8.encode(content).length,
    );
  }

  @override
  Future<AppFileReadResult> readText({
    required String workspaceId,
    required String path,
    required int maxChars,
  }) async {
    final normalizedPath = normalizeAppFilePath(path);
    final file = _files[_key(workspaceId, normalizedPath)];
    if (file == null) {
      throw const AppFileStoreException('not_found', 'file not found');
    }
    final content = file.content;
    final limit = maxChars <= 0 ? 12000 : maxChars;
    final truncated = content.length > limit;
    return AppFileReadResult(
      path: normalizedPath,
      content: truncated ? content.substring(0, limit) : content,
      length: content.length,
      truncated: truncated,
    );
  }

  @override
  Future<List<AppFileEntry>> listFiles({required String workspaceId}) async {
    final prefix = '$workspaceId::';
    final entries = <AppFileEntry>[];
    for (final entry in _files.entries) {
      if (!entry.key.startsWith(prefix)) {
        continue;
      }
      final path = entry.key.substring(prefix.length);
      entries.add(
        AppFileEntry(
          path: path,
          uri: Uri(path: '/memory/$workspaceId/$path'),
          bytes: utf8.encode(entry.value.content).length,
          modifiedAt: entry.value.modifiedAt,
        ),
      );
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  String _key(String workspaceId, String path) {
    return '$workspaceId::$path';
  }
}

class _InMemoryAppFile {
  const _InMemoryAppFile(this.content, this.modifiedAt);

  final String content;
  final DateTime modifiedAt;
}

String normalizeAppFilePath(String path) {
  final raw = path.trim().replaceAll('\\', '/');
  if (raw.isEmpty) {
    throw const AppFileStoreException('invalid_path', 'path is required');
  }
  if (raw.startsWith('/')) {
    throw const AppFileStoreException(
      'invalid_path',
      'absolute paths are not allowed',
    );
  }

  final parts = <String>[];
  for (final part in raw.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      throw const AppFileStoreException(
        'invalid_path',
        'path traversal is not allowed',
      );
    }
    parts.add(part);
  }
  if (parts.isEmpty) {
    throw const AppFileStoreException('invalid_path', 'path is required');
  }
  return parts.join('/');
}
