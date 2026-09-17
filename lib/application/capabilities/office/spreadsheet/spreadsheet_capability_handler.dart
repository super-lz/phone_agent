import 'dart:convert';
import 'dart:typed_data';

import '../../../../domain/files/app_file_store.dart';
import '../../capability_execution_result.dart';
import '../office_file_io.dart';
import 'spreadsheet_codec.dart';

class SpreadsheetCapabilityHandler {
  const SpreadsheetCapabilityHandler({
    this.io = const OfficeFileIo(),
    this.codec = const SpreadsheetCodec(),
  });

  final OfficeFileIo io;
  final SpreadsheetCodec codec;

  Future<CapabilityExecutionResult> extract({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
  }) async {
    const capabilityId = 'spreadsheet.extract';
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
            'detail': '当前版本最多解析 12MB 以内的表格文件。',
          },
        );
      }
      final extracted = codec.extract(read.path, read.bytes);
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
          'summary': '已提取表格内容。后续可基于该文本总结、问答或生成新表格。',
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
          'error': 'spreadsheet extract failed',
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
    const capabilityId = 'spreadsheet.generate';
    final rows = _rows(arguments['rows']);
    if (rows.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': 'rows is required'},
      );
    }
    final title = io.asString(arguments['title']) ?? 'spreadsheet';
    final format = io.formatOf(arguments, fallback: 'xlsx');
    final path = io.outputPathOf(
      arguments,
      fallback: 'spreadsheets/$title.$format',
    );
    final bytes = switch (format) {
      'xlsx' => codec.encodeXlsx(rows),
      'csv' => Uint8List.fromList(utf8.encode(codec.encodeCsv(rows))),
      _ => null,
    };
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
      summary: '已生成表格文件：$path。',
    );
  }

  List<List<String>> _rows(Object? value) {
    if (value is! List<Object?>) {
      return const [];
    }
    return value
        .whereType<List<Object?>>()
        .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
        .toList();
  }
}
