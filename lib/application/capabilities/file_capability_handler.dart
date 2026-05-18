import '../../core/logging/app_logger.dart';
import '../../domain/files/app_file_store.dart';
import 'capability_execution_result.dart';

class FileCapabilityHandler {
  const FileCapabilityHandler();

  Future<CapabilityExecutionResult> write({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.write_app_file',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final rawPath = arguments['path'];
    final rawContent = arguments['content'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.write_app_file',
        output: {'ok': false, 'error': 'path is required'},
      );
    }
    if (rawContent is! String) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.write_app_file',
        output: {'ok': false, 'error': 'content is required'},
      );
    }

    final rawOverwrite = arguments['overwrite'];
    final overwrite = rawOverwrite is bool ? rawOverwrite : true;
    try {
      final result = await store.writeText(
        workspaceId: workspaceId,
        path: rawPath,
        content: rawContent,
        overwrite: overwrite,
      );
      return CapabilityExecutionResult(
        capabilityId: 'file.write_app_file',
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': result.path,
          'uri': result.uri.toString(),
          'bytes': result.bytes,
        },
      );
    } on AppFileStoreException catch (error) {
      return _errorResult('file.write_app_file', error);
    } on Object catch (error) {
      AppLogger.warning('file.write_app_file.failed', {
        'workspaceId': workspaceId,
        'error': error.toString(),
      });
      return CapabilityExecutionResult(
        capabilityId: 'file.write_app_file',
        output: {
          'ok': false,
          'error': 'file write failed',
          'detail': error.toString(),
        },
      );
    }
  }

  Future<CapabilityExecutionResult> read({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.read_app_file',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final rawPath = arguments['path'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.read_app_file',
        output: {'ok': false, 'error': 'path is required'},
      );
    }
    final rawMaxChars = arguments['max_chars'];
    final maxChars = rawMaxChars is int ? rawMaxChars : 12000;
    final rawStartLine = arguments['start_line'];
    final startLine = rawStartLine is int ? rawStartLine : null;
    final rawLineCount = arguments['line_count'];
    final lineCount = rawLineCount is int ? rawLineCount : null;

    try {
      final result = await store.readText(
        workspaceId: workspaceId,
        path: rawPath,
        maxChars: startLine == null ? maxChars : 5 * 1024 * 1024,
      );
      final lineWindow = startLine == null
          ? null
          : _lineWindow(
              content: result.content,
              startLine: startLine,
              lineCount: lineCount ?? 120,
              maxChars: maxChars,
            );
      return CapabilityExecutionResult(
        capabilityId: 'file.read_app_file',
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': result.path,
          'content': lineWindow?.content ?? result.content,
          'length': result.length,
          'truncated': result.truncated || (lineWindow?.truncated ?? false),
          if (lineWindow != null) ...{
            'lineStart': lineWindow.lineStart,
            'lineEnd': lineWindow.lineEnd,
            'totalLines': lineWindow.totalLines,
          },
        },
      );
    } on AppFileStoreException catch (error) {
      return _errorResult('file.read_app_file', error);
    } on Object catch (error) {
      AppLogger.warning('file.read_app_file.failed', {
        'workspaceId': workspaceId,
        'error': error.toString(),
      });
      return CapabilityExecutionResult(
        capabilityId: 'file.read_app_file',
        output: {
          'ok': false,
          'error': 'file read failed',
          'detail': error.toString(),
        },
      );
    }
  }

  Future<CapabilityExecutionResult> search({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.search_app_files',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final rawQuery = arguments['query'];
    if (rawQuery is! String || rawQuery.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.search_app_files',
        output: {'ok': false, 'error': 'query is required'},
      );
    }
    final query = rawQuery.trim();
    final rawPath = arguments['path'];
    final rawPrefix = arguments['path_prefix'];
    final maxResults = _positiveInt(arguments['max_results'], fallback: 20);
    final contextLines = _positiveInt(arguments['context_lines'], fallback: 2);

    try {
      final paths = await _searchPaths(
        store: store,
        workspaceId: workspaceId,
        rawPath: rawPath,
        rawPrefix: rawPrefix,
      );
      final matches = <Map<String, Object?>>[];
      var truncated = false;
      for (final path in paths) {
        final result = await store.readText(
          workspaceId: workspaceId,
          path: path,
          maxChars: 2 * 1024 * 1024,
        );
        if (result.truncated) {
          continue;
        }
        final lines = result.content.split('\n');
        for (var index = 0; index < lines.length; index += 1) {
          if (!lines[index].toLowerCase().contains(query.toLowerCase())) {
            continue;
          }
          matches.add(
            _searchMatch(
              path: result.path,
              lines: lines,
              index: index,
              contextLines: contextLines,
            ),
          );
          if (matches.length >= maxResults) {
            truncated = true;
            break;
          }
        }
        if (truncated) {
          break;
        }
      }
      return CapabilityExecutionResult(
        capabilityId: 'file.search_app_files',
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'query': query,
          'count': matches.length,
          'truncated': truncated,
          'matches': matches,
        },
      );
    } on AppFileStoreException catch (error) {
      return _errorResult('file.search_app_files', error);
    } on Object catch (error) {
      AppLogger.warning('file.search_app_files.failed', {
        'workspaceId': workspaceId,
        'error': error.toString(),
      });
      return CapabilityExecutionResult(
        capabilityId: 'file.search_app_files',
        output: {
          'ok': false,
          'error': 'file search failed',
          'detail': error.toString(),
        },
      );
    }
  }

  Future<CapabilityExecutionResult> applyTextPatch({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.apply_text_patch',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final rawPath = arguments['path'];
    final oldText = arguments['old_text'];
    final newText = arguments['new_text'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.apply_text_patch',
        output: {'ok': false, 'error': 'path is required'},
      );
    }
    if (oldText is! String || oldText.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.apply_text_patch',
        output: {'ok': false, 'error': 'old_text is required'},
      );
    }
    if (newText is! String) {
      return const CapabilityExecutionResult(
        capabilityId: 'file.apply_text_patch',
        output: {'ok': false, 'error': 'new_text is required'},
      );
    }
    final replaceAll = arguments['replace_all'] == true;

    try {
      final readResult = await store.readText(
        workspaceId: workspaceId,
        path: rawPath,
        maxChars: 5 * 1024 * 1024,
      );
      if (readResult.truncated) {
        return const CapabilityExecutionResult(
          capabilityId: 'file.apply_text_patch',
          output: {
            'ok': false,
            'error': 'file too large',
            'detail': '文件超过当前补丁能力可安全处理的大小。',
          },
        );
      }
      final matches = oldText.allMatches(readResult.content).length;
      if (matches == 0) {
        return const CapabilityExecutionResult(
          capabilityId: 'file.apply_text_patch',
          output: {
            'ok': false,
            'error': 'old_text_not_found',
            'detail': '未在目标文件中找到要替换的原文。',
          },
        );
      }
      if (matches > 1 && !replaceAll) {
        return CapabilityExecutionResult(
          capabilityId: 'file.apply_text_patch',
          output: {
            'ok': false,
            'error': 'old_text_not_unique',
            'detail':
                '原文在目标文件中出现 $matches 次；请提供更精确的 old_text，或设置 replace_all=true。',
            'matches': matches,
          },
        );
      }
      final patched = replaceAll
          ? readResult.content.replaceAll(oldText, newText)
          : readResult.content.replaceFirst(oldText, newText);
      final writeResult = await store.writeText(
        workspaceId: workspaceId,
        path: readResult.path,
        content: patched,
        overwrite: true,
      );
      return CapabilityExecutionResult(
        capabilityId: 'file.apply_text_patch',
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': writeResult.path,
          'uri': writeResult.uri.toString(),
          'bytes': writeResult.bytes,
          'replacements': replaceAll ? matches : 1,
        },
      );
    } on AppFileStoreException catch (error) {
      return _errorResult('file.apply_text_patch', error);
    } on Object catch (error) {
      AppLogger.warning('file.apply_text_patch.failed', {
        'workspaceId': workspaceId,
        'error': error.toString(),
      });
      return CapabilityExecutionResult(
        capabilityId: 'file.apply_text_patch',
        output: {
          'ok': false,
          'error': 'file patch failed',
          'detail': error.toString(),
        },
      );
    }
  }

  CapabilityExecutionResult _errorResult(
    String capabilityId,
    AppFileStoreException error,
  ) {
    return CapabilityExecutionResult(
      capabilityId: capabilityId,
      output: {'ok': false, 'error': error.code, 'detail': error.message},
    );
  }

  _LineWindow _lineWindow({
    required String content,
    required int startLine,
    required int lineCount,
    required int maxChars,
  }) {
    final lines = content.split('\n');
    final safeStart = startLine < 1 ? 1 : startLine;
    final safeCount = lineCount < 1 ? 120 : lineCount;
    final startIndex = safeStart - 1;
    final endIndex = startIndex >= lines.length
        ? lines.length
        : (startIndex + safeCount).clamp(0, lines.length);
    final selected = startIndex >= lines.length
        ? ''
        : lines.sublist(startIndex, endIndex).join('\n');
    final limit = maxChars <= 0 ? 12000 : maxChars;
    final truncated = selected.length > limit;
    return _LineWindow(
      content: truncated ? selected.substring(0, limit) : selected,
      lineStart: safeStart,
      lineEnd: endIndex,
      totalLines: lines.length,
      truncated: truncated,
    );
  }

  int _positiveInt(Object? value, {required int fallback}) {
    if (value is int && value > 0) {
      return value;
    }
    return fallback;
  }

  Future<List<String>> _searchPaths({
    required AppFileStore store,
    required String workspaceId,
    required Object? rawPath,
    required Object? rawPrefix,
  }) async {
    if (rawPath is String && rawPath.trim().isNotEmpty) {
      return [normalizeAppFilePath(rawPath)];
    }
    final prefix = rawPrefix is String && rawPrefix.trim().isNotEmpty
        ? normalizeAppFilePath(rawPrefix)
        : null;
    final files = await store.listFiles(workspaceId: workspaceId);
    return files
        .map((file) => file.path)
        .where((path) => prefix == null || path.startsWith(prefix))
        .toList(growable: false);
  }

  Map<String, Object?> _searchMatch({
    required String path,
    required List<String> lines,
    required int index,
    required int contextLines,
  }) {
    final startIndex = (index - contextLines).clamp(0, lines.length);
    final endIndex = (index + contextLines + 1).clamp(0, lines.length);
    return {
      'path': path,
      'lineNumber': index + 1,
      'line': lines[index],
      'lineStart': startIndex + 1,
      'lineEnd': endIndex,
      'snippet': lines.sublist(startIndex, endIndex).join('\n'),
    };
  }
}

class _LineWindow {
  const _LineWindow({
    required this.content,
    required this.lineStart,
    required this.lineEnd,
    required this.totalLines,
    required this.truncated,
  });

  final String content;
  final int lineStart;
  final int lineEnd;
  final int totalLines;
  final bool truncated;
}
