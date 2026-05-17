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

    try {
      final result = await store.readText(
        workspaceId: workspaceId,
        path: rawPath,
        maxChars: maxChars,
      );
      return CapabilityExecutionResult(
        capabilityId: 'file.read_app_file',
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'path': result.path,
          'content': result.content,
          'length': result.length,
          'truncated': result.truncated,
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

  CapabilityExecutionResult _errorResult(
    String capabilityId,
    AppFileStoreException error,
  ) {
    return CapabilityExecutionResult(
      capabilityId: capabilityId,
      output: {'ok': false, 'error': error.code, 'detail': error.message},
    );
  }
}
