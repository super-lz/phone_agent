import '../../../../domain/files/app_file_store.dart';
import '../../capability_execution_result.dart';
import '../office_file_io.dart';
import 'pdf_codec.dart';

class PdfCapabilityHandler {
  const PdfCapabilityHandler({
    this.io = const OfficeFileIo(),
    this.codec = const PdfCodec(),
  });

  final OfficeFileIo io;
  final PdfCodec codec;

  Future<CapabilityExecutionResult> extract({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    const capabilityId = 'pdf.extract';
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
            'detail': '当前版本最多解析 12MB 以内的 PDF 文件。',
          },
        );
      }
      final extracted = await codec.extract(read.bytes);
      final truncated = extracted.length > maxChars;
      final content = truncated ? extracted.substring(0, maxChars) : extracted;
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': read.path,
          'format': 'pdf',
          'content': content,
          'length': extracted.length,
          'truncated': truncated,
          'summary': '已提取 PDF 文本。扫描版 PDF 第一版不做 OCR。',
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
          'error': 'pdf extract failed',
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
    const capabilityId = 'pdf.generate';
    final title = io.asString(arguments['title']) ?? 'PDF';
    final body =
        io.asString(arguments['body']) ?? io.asString(arguments['content']);
    if (body == null) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'body is required'},
      );
    }
    final path = io.outputPathOf(arguments, fallback: 'pdf/$title.pdf');
    try {
      return io.writeGenerated(
        capabilityId: capabilityId,
        workspaceId: workspaceId,
        path: path,
        bytes: await codec.encode(title: title, body: body),
        fileStore: fileStore,
        summary: '已生成 PDF 文件：$path。',
      );
    } on Object catch (error) {
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {
          'ok': false,
          'error': 'pdf generate failed',
          'detail': error.toString(),
        },
      );
    }
  }
}
