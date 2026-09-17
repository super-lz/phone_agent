import 'dart:typed_data';

import '../../../domain/files/app_file_store.dart';
import '../capability_execution_result.dart';

/// Shared Workspace file IO for Agent Office capabilities.
///
/// Format codecs must not live here. Each document type owns its own handler.
class OfficeFileIo {
  const OfficeFileIo();

  String? asString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int asPositiveInt(Object? value, {required int fallback}) {
    return value is int && value > 0 ? value : fallback;
  }

  String extensionOf(String path) {
    final index = path.lastIndexOf('.');
    if (index < 0 || index == path.length - 1) {
      return '';
    }
    return path.substring(index + 1).toLowerCase();
  }

  String formatOf(Map<String, Object?> arguments, {required String fallback}) {
    final explicit = asString(arguments['format']);
    final inferred = extensionOf(asString(arguments['path']) ?? '');
    final value = explicit ?? inferred;
    return value.isEmpty ? fallback : value.toLowerCase();
  }

  String outputPathOf(
    Map<String, Object?> arguments, {
    required String fallback,
  }) {
    return asString(arguments['path']) ??
        fallback.replaceAll(RegExp(r'\s+'), '-');
  }

  String replaceExtension(String path, String extension) {
    final suffix = extension.startsWith('.') ? extension : '.$extension';
    final dot = path.lastIndexOf('.');
    if (dot < 0) {
      return '$path$suffix';
    }
    return '${path.substring(0, dot)}$suffix';
  }

  String patchedPath(String path, {String? extension}) {
    final ext = extension ?? extensionOf(path);
    final suffix = ext.isEmpty ? '.docx' : '.$ext';
    final dot = path.lastIndexOf('.');
    final stem = dot < 0 ? path : path.substring(0, dot);
    return '$stem.patched$suffix';
  }

  Future<CapabilityExecutionResult> writeGenerated({
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
      return CapabilityExecutionResult(
        capabilityId: capabilityId,
        output: {'ok': false, 'error': error.code, 'detail': error.message},
      );
    }
  }

  Future<AppFileBytesReadResult?> readBytes({
    required String workspaceId,
    required String path,
    required AppFileStore store,
    int maxBytes = 12 * 1024 * 1024,
  }) {
    return store.readBytes(
      workspaceId: workspaceId,
      path: path,
      maxBytes: maxBytes,
    );
  }
}
