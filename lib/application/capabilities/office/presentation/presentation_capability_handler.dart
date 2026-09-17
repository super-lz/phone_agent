import 'dart:convert';
import 'dart:typed_data';

import '../../../../domain/files/app_file_store.dart';
import '../../capability_execution_result.dart';
import '../office_file_io.dart';
import 'presentation_markdown.dart';
import 'presentation_model.dart';
import 'presentation_pptx.dart';

class PresentationCapabilityHandler {
  const PresentationCapabilityHandler({
    this.io = const OfficeFileIo(),
    this.markdown = const PresentationMarkdown(),
    this.pptx = const PresentationPptxCodec(),
  });

  final OfficeFileIo io;
  final PresentationMarkdown markdown;
  final PresentationPptxCodec pptx;

  Future<CapabilityExecutionResult> extract({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    const capabilityId = 'presentation.extract';
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final rawPath = arguments['path'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'path is required'},
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
        return const CapabilityExecutionResult(
          capabilityId: capabilityId,
          output: {'ok': false, 'error': 'file store unavailable'},
        );
      }
      if (read.truncated) {
        return const CapabilityExecutionResult(
          capabilityId: capabilityId,
          output: {
            'ok': false,
            'error': 'file too large',
            'detail': '当前版本最多解析 12MB 以内的演示文稿。',
          },
        );
      }
      final extracted = _decode(read.path, read.bytes);
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
          'summary': '已提取演示文稿文本。可编辑源是 Markdown 幻灯片，pptx 只用于导入和导出。',
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
          'error': 'presentation extract failed',
          'detail': error.toString(),
        },
      );
    }
  }

  Future<CapabilityExecutionResult> generate({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    const capabilityId = 'presentation.generate';
    final slides = markdown.slidesFrom(arguments['slides']);
    if (slides.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'slides is required'},
      );
    }
    return _writeDeck(
      capabilityId: capabilityId,
      workspaceId: workspaceId,
      arguments: arguments,
      slides: slides,
      fileStore: fileStore,
      fallbackFormat: 'md',
    );
  }

  Future<CapabilityExecutionResult> export({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    const capabilityId = 'presentation.export';
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    var slides = markdown.slidesFrom(arguments['slides']);
    final sourcePath = io.asString(arguments['path']);
    if (slides.isEmpty && sourcePath != null) {
      try {
        final read = await io.readBytes(
          workspaceId: workspaceId,
          path: sourcePath,
          store: store,
        );
        if (read == null) {
          return const CapabilityExecutionResult(
            capabilityId: capabilityId,
            output: {'ok': false, 'error': 'file store unavailable'},
          );
        }
        slides = markdown.parse(_decode(read.path, read.bytes));
      } on AppFileStoreException catch (error) {
        return CapabilityExecutionResult(
          capabilityId: capabilityId,
          output: {'ok': false, 'error': error.code, 'detail': error.message},
        );
      }
    }
    if (slides.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'slides or path is required'},
      );
    }
    final outputArguments = Map<String, Object?>.from(arguments);
    outputArguments['path'] =
        io.asString(arguments['output_path']) ??
        (sourcePath == null ? null : _pptxPathForSource(sourcePath));
    outputArguments['format'] = 'pptx';
    return _writeDeck(
      capabilityId: capabilityId,
      workspaceId: workspaceId,
      arguments: outputArguments,
      slides: slides,
      fileStore: fileStore,
      fallbackFormat: 'pptx',
      sourcePath: sourcePath,
    );
  }

  Future<CapabilityExecutionResult> _writeDeck({
    required String capabilityId,
    required String workspaceId,
    required Map<String, Object?> arguments,
    required List<SlideContent> slides,
    required AppFileStore? fileStore,
    required String fallbackFormat,
    String? sourcePath,
  }) async {
    final title = io.asString(arguments['title']) ?? 'presentation';
    final format = io.formatOf(arguments, fallback: fallbackFormat);
    final path = io.outputPathOf(
      arguments,
      fallback: 'presentations/$title.$format',
    );
    final markdownSource = markdown.serialize(slides);
    final bytes = switch (format) {
      'pptx' => pptx.encode(slides),
      'md' => Uint8List.fromList(utf8.encode(markdownSource)),
      'html' => Uint8List.fromList(
        utf8.encode(markdown.previewHtml(title, slides)),
      ),
      _ => null,
    };
    if (bytes == null) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'unsupported format', 'format': format},
      );
    }
    final extra = <String, Object?>{};
    if (format == 'pptx') {
      final markdownPath = sourcePath ?? io.replaceExtension(path, 'slides.md');
      extra['sourcePath'] = markdownPath;
      extra['editableSource'] = 'markdown';
      await io.writeGenerated(
        capabilityId: capabilityId,
        workspaceId: workspaceId,
        path: markdownPath,
        bytes: Uint8List.fromList(utf8.encode(markdownSource)),
        fileStore: fileStore,
        summary: '已写入可编辑幻灯片源：$markdownPath。',
      );
    }
    return io.writeGenerated(
      capabilityId: capabilityId,
      workspaceId: workspaceId,
      path: path,
      bytes: bytes,
      fileStore: fileStore,
      summary: format == 'pptx'
          ? '已导出 PPT：$path。可编辑源是 ${extra['sourcePath']}。'
          : '已生成演示文稿文件：$path。',
      extra: extra,
    );
  }

  String _pptxPathForSource(String sourcePath) {
    const suffix = '.slides.md';
    if (sourcePath.toLowerCase().endsWith(suffix)) {
      return '${sourcePath.substring(0, sourcePath.length - suffix.length)}.pptx';
    }
    return io.replaceExtension(sourcePath, 'pptx');
  }

  String _decode(String path, Uint8List bytes) {
    final extension = io.extensionOf(path);
    if (extension == 'pptx') {
      return pptx.extract(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
