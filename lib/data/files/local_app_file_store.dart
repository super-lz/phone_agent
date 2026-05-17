import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/files/app_file_store.dart';

class LocalAppFileStore implements AppFileStore {
  LocalAppFileStore({Directory? rootDirectory})
    : _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;

  @override
  Future<AppFileWriteResult> writeText({
    required String workspaceId,
    required String path,
    required String content,
    required bool overwrite,
  }) async {
    final normalizedPath = normalizeAppFilePath(path);
    final file = await _fileFor(
      workspaceId: workspaceId,
      normalizedPath: normalizedPath,
    );
    if (!overwrite && await file.exists()) {
      throw const AppFileStoreException('file_exists', 'file already exists');
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content, encoding: utf8, flush: true);
    return AppFileWriteResult(
      path: normalizedPath,
      uri: file.uri,
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
    final file = await _fileFor(
      workspaceId: workspaceId,
      normalizedPath: normalizedPath,
    );
    if (!await file.exists()) {
      throw const AppFileStoreException('not_found', 'file not found');
    }
    final content = await file.readAsString(encoding: utf8);
    final limit = maxChars <= 0 ? 12000 : maxChars;
    final truncated = content.length > limit;
    return AppFileReadResult(
      path: normalizedPath,
      content: truncated ? content.substring(0, limit) : content,
      length: content.length,
      truncated: truncated,
    );
  }

  Future<File> _fileFor({
    required String workspaceId,
    required String normalizedPath,
  }) async {
    final root = await _root();
    final workspaceSegment = Uri.encodeComponent(workspaceId);
    final workspaceRoot = p.join(root.path, workspaceSegment, 'files');
    final fullPath = p.joinAll([workspaceRoot, ...normalizedPath.split('/')]);
    final normalizedFullPath = p.normalize(fullPath);
    final normalizedWorkspaceRoot = p.normalize(workspaceRoot);
    if (!p.isWithin(normalizedWorkspaceRoot, normalizedFullPath) &&
        normalizedWorkspaceRoot != normalizedFullPath) {
      throw const AppFileStoreException(
        'invalid_path',
        'path escapes workspace directory',
      );
    }
    return File(normalizedFullPath);
  }

  Future<Directory> _root() async {
    final existing = _rootDirectory;
    if (existing != null) {
      return existing;
    }
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'workspaces'));
  }
}
