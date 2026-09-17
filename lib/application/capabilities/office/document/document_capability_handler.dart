import 'dart:convert';
import 'dart:typed_data';

import '../../../../domain/files/app_file_store.dart';
import '../../capability_execution_result.dart';
import '../office_file_io.dart';
import 'document_codec.dart';

class DocumentCapabilityHandler {
  const DocumentCapabilityHandler({
    this.io = const OfficeFileIo(),
    this.codec = const DocumentCodec(),
  });

  final OfficeFileIo io;
  final DocumentCodec codec;

  Future<CapabilityExecutionResult> extract({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) {
    return _extract(
      workspaceId: workspaceId,
      capabilityId: 'document.extract',
      arguments: arguments,
      fileStore: fileStore,
    );
  }

  Future<CapabilityExecutionResult> generate({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    const capabilityId = 'document.generate';
    final title = io.asString(arguments['title']) ?? 'Untitled';
    final body =
        io.asString(arguments['body']) ?? io.asString(arguments['content']);
    if (body == null) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'body is required'},
      );
    }
    final format = io.formatOf(arguments, fallback: 'docx');
    final path = io.outputPathOf(
      arguments,
      fallback: 'documents/$title.$format',
    );
    final bytes = await _encode(format: format, title: title, body: body);
    if (bytes == null) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'unsupported format', 'format': format},
      );
    }
    return io.writeGenerated(
      capabilityId: capabilityId,
      workspaceId: workspaceId,
      path: path,
      bytes: bytes,
      fileStore: fileStore,
      summary: '已生成文档文件：$path。',
    );
  }

  Future<CapabilityExecutionResult> applyTextPatch({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    const capabilityId = 'document.apply_text_patch';
    final path = io.asString(arguments['path']);
    final oldText = io.asString(arguments['old_text']);
    final newText = io.asString(arguments['new_text']);
    if (path == null || oldText == null || newText == null) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': false,
          'error': 'path, old_text and new_text are required',
        },
      );
    }
    final extractResult = await _extract(
      workspaceId: workspaceId,
      capabilityId: capabilityId,
      arguments: {'path': path, 'max_chars': 5 * 1024 * 1024},
      fileStore: fileStore,
    );
    if (extractResult.output['ok'] != true) {
      return extractResult;
    }
    final content = io.asString(extractResult.output['content']) ?? '';
    final patched = _replaceText(
      content: content,
      oldText: oldText,
      newText: newText,
      replaceAll: arguments['replace_all'] == true,
    );
    if (patched.error != null) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': false,
          'error': patched.error,
          if (patched.matches != null) 'matches': patched.matches,
        },
      );
    }
    final format = io.extensionOf(path);
    final outputPath =
        io.asString(arguments['output_path']) ??
        io.patchedPath(path, extension: format.isEmpty ? 'docx' : format);
    final title = io.asString(arguments['title']) ?? 'Patched Document';
    final outputFormat = io.extensionOf(outputPath);
    final bytes = await _encode(
      format: outputFormat.isEmpty ? 'docx' : outputFormat,
      title: title,
      body: patched.content,
    );
    if (bytes == null) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': false,
          'error': 'unsupported format',
          'format': outputFormat,
        },
      );
    }
    return io.writeGenerated(
      capabilityId: capabilityId,
      workspaceId: workspaceId,
      path: outputPath,
      bytes: bytes,
      fileStore: fileStore,
      summary: '已完成受控局部修改并生成新文件：$outputPath。',
      extra: {
        'preservedFormatting': false,
        'replacements': patched.replacements,
      },
    );
  }

  Future<CapabilityExecutionResult> _extract({
    required String workspaceId,
    required String capabilityId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final store = fileStore;
    if (store == null) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: const {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final rawPath = arguments['path'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: const {'ok': false, 'error': 'path is required'},
      );
    }
    final maxChars = io.asPositiveInt(arguments['max_chars'], fallback: 12000);
    try {
      final read = await io.readBytes(
        workspaceId: workspaceId,
        path: rawPath,
        store: store,
      );
      if (read == null) {
        return CapabilityExecutionResult(
          capabilityId: capabilityId,
          output: const {'ok': false, 'error': 'file store unavailable'},
        );
      }
      if (read.truncated) {
        return CapabilityExecutionResult(
          capabilityId: capabilityId,
          output: const {
            'ok': false,
            'error': 'file too large',
            'detail': '当前版本最多解析 12MB 以内的文档文件。',
          },
        );
      }
      final extracted = await _decode(read.path, read.bytes);
      final truncated = extracted.length > maxChars;
      final content = truncated ? extracted.substring(0, maxChars) : extracted;
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': read.path,
          'format': io.extensionOf(read.path),
          'content': content,
          'length': extracted.length,
          'truncated': truncated,
          'summary': '已提取文档内容。后续可基于该文本总结、问答或局部修改。',
        },
      );
    } on AppFileStoreException catch (error) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': error.code, 'detail': error.message},
      );
    } on Object catch (error) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': false,
          'error': 'document extract failed',
          'detail': error.toString(),
        },
      );
    }
  }

  Future<String> _decode(String path, Uint8List bytes) async {
    final extension = io.extensionOf(path);
    if (extension == 'docx') {
      return codec.extract(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List?> _encode({
    required String format,
    required String title,
    required String body,
  }) async {
    return switch (format) {
      'docx' => codec.encodeDocx(title: title, body: body),
      'html' => Uint8List.fromList(
        utf8.encode(
          '<!doctype html><html><head><meta charset="utf-8"><title>$title</title></head>'
          '<body><h1>$title</h1><pre>$body</pre></body></html>',
        ),
      ),
      'md' => Uint8List.fromList(utf8.encode('# $title\n\n$body\n')),
      'txt' => Uint8List.fromList(utf8.encode('$title\n\n$body\n')),
      _ => null,
    };
  }

  ({String content, int replacements, String? error, int? matches})
  _replaceText({
    required String content,
    required String oldText,
    required String newText,
    required bool replaceAll,
  }) {
    final matches = oldText.allMatches(content).length;
    final normalizedContent = content.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedOldText = oldText.replaceAll(RegExp(r'\s+'), ' ');
    final normalizedMatches = RegExp(
      RegExp.escape(normalizedOldText),
    ).allMatches(normalizedContent).length;
    if (matches == 0 && normalizedMatches == 0) {
      return (
        content: content,
        replacements: 0,
        error: 'old_text_not_found',
        matches: null,
      );
    }
    if (matches > 0) {
      if (matches > 1 && !replaceAll) {
        return (
          content: content,
          replacements: 0,
          error: 'old_text_not_unique',
          matches: matches,
        );
      }
      return (
        content: replaceAll
            ? content.replaceAll(oldText, newText)
            : content.replaceFirst(oldText, newText),
        replacements: replaceAll ? matches : 1,
        error: null,
        matches: matches,
      );
    }
    final pattern = RegExp(
      oldText.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+'),
      dotAll: true,
    );
    final fuzzyMatches = pattern.allMatches(content).length;
    return (
      content: replaceAll
          ? content.replaceAll(pattern, newText)
          : content.replaceFirst(pattern, newText),
      replacements: replaceAll ? fuzzyMatches : 1,
      error: null,
      matches: fuzzyMatches,
    );
  }
}
