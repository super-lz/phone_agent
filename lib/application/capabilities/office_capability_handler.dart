import 'dart:convert';
import 'dart:typed_data';

import '../../domain/files/app_file_store.dart';
import 'capability_execution_result.dart';
import 'office_capability_formatters.dart';
import 'office_document_codec.dart';

class OfficeCapabilityHandler {
  const OfficeCapabilityHandler({this.codec = const OfficeDocumentCodec()});

  final OfficeDocumentCodec codec;

  Future<CapabilityExecutionResult> extract({
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
    final maxChars = officePositiveInt(arguments['max_chars'], fallback: 12000);
    try {
      final read = await store.readBytes(
        workspaceId: workspaceId,
        path: rawPath,
        maxBytes: 12 * 1024 * 1024,
      );
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
      final extracted = codec.extractText(read.path, read.bytes);
      final truncated = extracted.length > maxChars;
      final content = truncated ? extracted.substring(0, maxChars) : extracted;
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': read.path,
          'format': officeExtension(read.path),
          'content': content,
          'length': extracted.length,
          'truncated': truncated,
          'summary':
              '已提取 ${officeExtension(read.path).toUpperCase()} 内容。后续可基于该文本总结、问答或局部修改。',
        },
      );
    } on AppFileStoreException catch (error) {
      return _storeError(capabilityId, error);
    } on Object catch (error) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': false,
          'error': 'office extract failed',
          'detail': error.toString(),
        },
      );
    }
  }

  Future<CapabilityExecutionResult> generateDocument({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final title = officeString(arguments['title']) ?? 'Untitled';
    final body =
        officeString(arguments['body']) ?? officeString(arguments['content']);
    if (body == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'document.generate',
        output: {'ok': false, 'error': 'body is required'},
      );
    }
    final format = officeFormat(arguments, fallback: 'docx');
    final path = officeOutputPath(
      arguments,
      fallback: 'documents/$title.$format',
    );
    final bytes = switch (format) {
      'docx' => codec.encodeDocx(title: title, body: body),
      'pdf' => codec.encodePdf(title: title, body: body),
      'html' => Uint8List.fromList(utf8.encode(officeHtml(title, body))),
      'md' => Uint8List.fromList(utf8.encode('# $title\n\n$body\n')),
      'txt' => Uint8List.fromList(utf8.encode('$title\n\n$body\n')),
      _ => null,
    };
    if (bytes == null) {
      return CapabilityExecutionResult(
        capabilityId: 'document.generate',
        output: {'ok': false, 'error': 'unsupported format', 'format': format},
      );
    }
    return _writeGenerated(
      capabilityId: 'document.generate',
      workspaceId: workspaceId,
      path: path,
      bytes: bytes,
      fileStore: fileStore,
      summary: '已生成文档文件：$path。',
    );
  }

  Future<CapabilityExecutionResult> generateSpreadsheet({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final rows = officeRows(arguments['rows']);
    if (rows.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'spreadsheet.generate',
        output: {'ok': false, 'error': 'rows is required'},
      );
    }
    final title = officeString(arguments['title']) ?? 'spreadsheet';
    final format = officeFormat(arguments, fallback: 'xlsx');
    final path = officeOutputPath(
      arguments,
      fallback: 'spreadsheets/$title.$format',
    );
    final bytes = switch (format) {
      'xlsx' => codec.encodeXlsx(rows),
      'csv' => Uint8List.fromList(utf8.encode(officeCsv(rows))),
      _ => null,
    };
    if (bytes == null) {
      return CapabilityExecutionResult(
        capabilityId: 'spreadsheet.generate',
        output: {'ok': false, 'error': 'unsupported format', 'format': format},
      );
    }
    return _writeGenerated(
      capabilityId: 'spreadsheet.generate',
      workspaceId: workspaceId,
      path: path,
      bytes: bytes,
      fileStore: fileStore,
      summary: '已生成表格文件：$path。',
    );
  }

  Future<CapabilityExecutionResult> generatePresentation({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final slides = officeSlides(arguments['slides']);
    if (slides.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'presentation.generate',
        output: {'ok': false, 'error': 'slides is required'},
      );
    }
    final title = officeString(arguments['title']) ?? 'presentation';
    final format = officeFormat(arguments, fallback: 'pptx');
    final path = officeOutputPath(
      arguments,
      fallback: 'presentations/$title.$format',
    );
    final bytes = switch (format) {
      'pptx' => codec.encodePptx(slides),
      'md' => Uint8List.fromList(utf8.encode(officeSlidesMarkdown(slides))),
      'html' => Uint8List.fromList(
        utf8.encode(officeSlidesHtml(title, slides)),
      ),
      _ => null,
    };
    if (bytes == null) {
      return CapabilityExecutionResult(
        capabilityId: 'presentation.generate',
        output: {'ok': false, 'error': 'unsupported format', 'format': format},
      );
    }
    return _writeGenerated(
      capabilityId: 'presentation.generate',
      workspaceId: workspaceId,
      path: path,
      bytes: bytes,
      fileStore: fileStore,
      summary: '已生成演示文稿文件：$path。',
    );
  }

  Future<CapabilityExecutionResult> generatePdf({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final title = officeString(arguments['title']) ?? 'PDF';
    final body =
        officeString(arguments['body']) ?? officeString(arguments['content']);
    if (body == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'pdf.generate',
        output: {'ok': false, 'error': 'body is required'},
      );
    }
    final path = officeOutputPath(arguments, fallback: 'pdf/$title.pdf');
    return _writeGenerated(
      capabilityId: 'pdf.generate',
      workspaceId: workspaceId,
      path: path,
      bytes: codec.encodePdf(title: title, body: body),
      fileStore: fileStore,
      summary: '已生成 PDF 文件：$path。',
    );
  }

  Future<CapabilityExecutionResult> applyTextPatch({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    final path = officeString(arguments['path']);
    final oldText = officeString(arguments['old_text']);
    final newText = officeString(arguments['new_text']);
    if (path == null || oldText == null || newText == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'document.apply_text_patch',
        output: {
          'ok': false,
          'error': 'path, old_text and new_text are required',
        },
      );
    }
    final extractResult = await extract(
      workspaceId: workspaceId,
      capabilityId: 'document.apply_text_patch',
      arguments: {'path': path, 'max_chars': 5 * 1024 * 1024},
      fileStore: fileStore,
    );
    if (extractResult.output['ok'] != true) {
      return extractResult;
    }
    final content = officeString(extractResult.output['content']) ?? '';
    final matches = oldText.allMatches(content).length;
    if (matches == 0) {
      return const CapabilityExecutionResult(
        capabilityId: 'document.apply_text_patch',
        output: {'ok': false, 'error': 'old_text_not_found'},
      );
    }
    if (matches > 1 && arguments['replace_all'] != true) {
      return CapabilityExecutionResult(
        capabilityId: 'document.apply_text_patch',
        output: {
          'ok': false,
          'error': 'old_text_not_unique',
          'matches': matches,
        },
      );
    }
    final patched = arguments['replace_all'] == true
        ? content.replaceAll(oldText, newText)
        : content.replaceFirst(oldText, newText);
    final format = officeExtension(path);
    final outputPath =
        officeString(arguments['output_path']) ??
        officePatchedPath(path, format);
    final title = officeString(arguments['title']) ?? 'Patched Document';
    final bytes = format == 'pdf'
        ? codec.encodePdf(title: title, body: patched)
        : codec.encodeDocx(title: title, body: patched);
    return _writeGenerated(
      capabilityId: 'document.apply_text_patch',
      workspaceId: workspaceId,
      path: outputPath,
      bytes: bytes,
      fileStore: fileStore,
      summary: '已完成受控局部修改并生成新文件：$outputPath。',
      extra: {'preservedFormatting': false, 'replacements': matches},
    );
  }

  Future<CapabilityExecutionResult> _writeGenerated({
    required String capabilityId,
    required String workspaceId,
    required String path,
    required Uint8List bytes,
    required AppFileStore? fileStore,
    required String summary,
    Map<String, Object?> extra = const {},
  }) async {
    final store = fileStore;
    if (store == null) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: const {'ok': false, 'error': 'file store unavailable'},
      );
    }
    try {
      final result = await store.writeBytes(
        workspaceId: workspaceId,
        path: path,
        bytes: bytes,
        overwrite: true,
      );
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': result.path,
          'uri': result.uri.toString(),
          'bytes': result.bytes,
          'summary': summary,
          ...extra,
        },
      );
    } on AppFileStoreException catch (error) {
      return _storeError(capabilityId, error);
    }
  }

  CapabilityExecutionResult _storeError(
    String capabilityId,
    AppFileStoreException error,
  ) {
    return CapabilityExecutionResult(
      capabilityId: capabilityId,
      output: {'ok': false, 'error': error.code, 'detail': error.message},
    );
  }
}
