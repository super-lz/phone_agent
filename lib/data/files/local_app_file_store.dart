import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  @override
  Future<AppFileWriteResult> writeBytes({
    required String workspaceId,
    required String path,
    required Uint8List bytes,
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
    await file.writeAsBytes(bytes, flush: true);
    return AppFileWriteResult(
      path: normalizedPath,
      uri: file.uri,
      bytes: bytes.length,
    );
  }

  @override
  Future<AppFileBytesReadResult> readBytes({
    required String workspaceId,
    required String path,
    required int maxBytes,
  }) async {
    final normalizedPath = normalizeAppFilePath(path);
    final file = await _fileFor(
      workspaceId: workspaceId,
      normalizedPath: normalizedPath,
    );
    if (!await file.exists()) {
      throw const AppFileStoreException('not_found', 'file not found');
    }
    final bytes = await file.readAsBytes();
    final limit = maxBytes <= 0 ? 12 * 1024 * 1024 : maxBytes;
    final truncated = bytes.length > limit;
    return AppFileBytesReadResult(
      path: normalizedPath,
      bytes: Uint8List.fromList(truncated ? bytes.sublist(0, limit) : bytes),
      length: bytes.length,
      truncated: truncated,
    );
  }

  @override
  Future<List<AppFileEntry>> listFiles({required String workspaceId}) async {
    final workspaceRoot = await _workspaceFilesRoot(workspaceId);
    if (!await workspaceRoot.exists()) {
      return const [];
    }
    final entries = <AppFileEntry>[];
    await for (final entity in workspaceRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      final relativePath = p
          .relative(entity.path, from: workspaceRoot.path)
          .replaceAll('\\', '/');
      entries.add(
        AppFileEntry(
          path: relativePath,
          uri: entity.uri,
          bytes: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  @override
  Future<void> deleteFile({
    required String workspaceId,
    required String path,
  }) async {
    final normalizedPath = normalizeAppFilePath(path);
    final file = await _fileFor(
      workspaceId: workspaceId,
      normalizedPath: normalizedPath,
    );
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> clearAll() async {
    final root = await _root();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);
  }

  Future<File> _fileFor({
    required String workspaceId,
    required String normalizedPath,
  }) async {
    final workspaceRoot = (await _workspaceFilesRoot(workspaceId)).path;
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

  Future<Directory> _workspaceFilesRoot(String workspaceId) async {
    final root = await _root();
    final workspaceSegment = Uri.encodeComponent(workspaceId);
    return Directory(p.join(root.path, workspaceSegment, 'files'));
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
