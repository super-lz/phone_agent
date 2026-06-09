import 'dart:convert';

import '../../domain/artifacts/artifact.dart';
import '../../domain/artifacts/web_app_runtime_log.dart';
import '../../domain/files/app_file_store.dart';
import 'capability_execution_result.dart';
import 'web_app_project_version_store.dart';

class ProjectCapabilityHandler {
  const ProjectCapabilityHandler();

  static const _versionStore = WebAppProjectVersionStore();

  Future<CapabilityExecutionResult> createWebApp({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
    required List<AgentArtifact> artifacts,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }

    final title = _stringArgument(arguments, 'title');
    final summary = _stringArgument(arguments, 'summary');
    if (title == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {'ok': false, 'error': 'title is required'},
      );
    }
    if (summary == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {'ok': false, 'error': 'summary is required'},
      );
    }

    final rawFiles = _files(arguments['files']);
    if (rawFiles.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {'ok': false, 'error': 'files are required'},
      );
    }

    final files = <_ProjectFile>[];
    final seenPaths = <String>{};
    try {
      for (final file in rawFiles) {
        final normalizedPath = normalizeAppFilePath(file.path);
        if (!seenPaths.add(normalizedPath)) {
          return CapabilityExecutionResult(
            capabilityId: 'project.create_web_app',
            output: {
              'ok': false,
              'error': 'duplicate_path',
              'detail': '同一个项目中不能写入重复路径。',
              'path': normalizedPath,
            },
          );
        }
        files.add(_ProjectFile(normalizedPath, file.content));
      }
    } on AppFileStoreException catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {'ok': false, 'error': error.code, 'detail': error.message},
      );
    }

    final requestedEntry = _stringArgument(arguments, 'entry_path');
    late final String entryPath;
    try {
      entryPath = requestedEntry == null
          ? files.first.path
          : normalizeAppFilePath(requestedEntry);
    } on AppFileStoreException catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {'ok': false, 'error': error.code, 'detail': error.message},
      );
    }
    final entryFile = _fileByPath(files, entryPath);
    if (entryFile == null) {
      return CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {
          'ok': false,
          'error': 'entry_path_not_found',
          'detail': 'entry_path 必须指向 files 中的一个文件。',
          'entryPath': entryPath,
        },
      );
    }

    final artifactId = 'artifact-${DateTime.now().microsecondsSinceEpoch}';
    final projectId = _projectIdFor(arguments, artifactId);
    final createdAt = DateTime.now();
    final permissions = _permissions(arguments['permissions']);
    final manifestPath = _manifestPathFor(entryPath);
    final writeResults = <AppFileWriteResult>[];
    try {
      for (final file in files) {
        writeResults.add(
          await store.writeText(
            workspaceId: workspaceId,
            path: file.path,
            content: file.content,
            overwrite: true,
          ),
        );
      }
      final manifest = _manifestContent(
        projectId: projectId,
        artifactId: artifactId,
        workspaceId: workspaceId,
        title: title,
        summary: summary,
        entryPath: entryPath,
        permissions: permissions,
        files: files.map((file) => file.path).toList(growable: false),
        version: 1,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      writeResults.add(
        await store.writeText(
          workspaceId: workspaceId,
          path: manifestPath,
          content: manifest,
          overwrite: true,
        ),
      );
      final snapshot = await _versionStore.capture(
        fileStore: store,
        workspaceId: workspaceId,
        projectId: projectId,
        artifactId: artifactId,
        version: 1,
        summary: '创建 Web App 项目',
        entryPath: entryPath,
        manifestPath: manifestPath,
        files: files.map((file) => file.path).toList(growable: false),
        changedFiles: files.map((file) => file.path).toList(growable: false),
        createdAt: createdAt,
      );
      await _versionStore.write(
        fileStore: store,
        workspaceId: workspaceId,
        snapshot: snapshot,
      );
    } on AppFileStoreException catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {'ok': false, 'error': error.code, 'detail': error.message},
      );
    } on Object catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {
          'ok': false,
          'error': 'project file write failed',
          'detail': error.toString(),
        },
      );
    }

    final metadata = <String, Object?>{};
    final rawMetadata = arguments['metadata'];
    if (rawMetadata is Map<Object?, Object?>) {
      for (final entry in rawMetadata.entries) {
        metadata[entry.key.toString()] = entry.value;
      }
    }
    metadata.addAll({
      'entry': entryPath,
      'html': entryFile.content,
      'project': true,
      'projectId': projectId,
      'manifestPath': manifestPath,
      'currentVersion': 1,
      'runtimeLogPath': WebAppRuntimeLogPaths.forMetadata(
        artifactId: artifactId,
        metadata: {'entry': entryPath},
      ),
      'files': writeResults
          .map(
            (file) => {
              'path': file.path,
              'uri': file.uri.toString(),
              'bytes': file.bytes,
            },
          )
          .toList(growable: false),
      'permissions': permissions,
    });

    final artifact = AgentArtifact(
      id: artifactId,
      workspaceId: workspaceId,
      type: ArtifactType.webApp,
      title: title,
      summary: summary,
      createdAt: createdAt,
      uri: writeResults.firstWhere((file) => file.path == entryPath).uri,
      metadata: metadata,
    );
    artifacts.add(artifact);

    return CapabilityExecutionResult(
      capabilityId: 'project.create_web_app',
      output: {
        'ok': true,
        'workspaceId': workspaceId,
        'artifactId': artifact.id,
        'type': artifact.type.name,
        'title': artifact.title,
        'entryPath': entryPath,
        'manifestPath': manifestPath,
        'projectId': projectId,
        'version': 1,
        'files': metadata['files'],
      },
    );
  }

  Future<CapabilityExecutionResult> updateWebApp({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
    required List<AgentArtifact> artifacts,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.update_web_app',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final artifactLookup = _webAppArtifact(
      workspaceId: workspaceId,
      artifacts: artifacts,
      artifactId: arguments['artifact_id'] ?? arguments['artifactId'],
    );
    if (artifactLookup.error != null) {
      return artifactLookup.error!;
    }
    final artifact = artifactLookup.artifact!;
    final manifestLookup = await _readManifest(
      store: store,
      workspaceId: workspaceId,
      artifact: artifact,
      capabilityId: 'project.update_web_app',
    );
    if (manifestLookup.error != null) {
      return manifestLookup.error!;
    }
    final manifest = manifestLookup.manifest!;

    final patches = _patches(arguments['patches']);
    final files = _files(arguments['files']);
    if (patches.isEmpty && files.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.update_web_app',
        output: {'ok': false, 'error': 'patches or files are required'},
      );
    }

    final changedPaths = <String>{};
    final projectFiles = manifest.files.toSet();
    try {
      for (final patch in patches) {
        final path = _projectPath(
          patch.path,
          projectRoot: manifest.projectRoot,
        );
        final current = await store.readText(
          workspaceId: workspaceId,
          path: path,
          maxChars: 5 * 1024 * 1024,
        );
        if (current.truncated) {
          return _projectError(
            'project.update_web_app',
            'file_too_large',
            '文件超过当前补丁能力可安全处理的大小。',
          );
        }
        final matches = patch.oldText.allMatches(current.content).length;
        if (matches == 0) {
          return _projectError(
            'project.update_web_app',
            'old_text_not_found',
            '未在目标文件中找到要替换的原文。',
            path: path,
          );
        }
        if (matches > 1 && !patch.replaceAll) {
          return CapabilityExecutionResult(
            capabilityId: 'project.update_web_app',
            output: {
              'ok': false,
              'error': 'old_text_not_unique',
              'detail': '原文在目标文件中出现 $matches 次。',
              'path': path,
              'matches': matches,
            },
          );
        }
        final updated = patch.replaceAll
            ? current.content.replaceAll(patch.oldText, patch.newText)
            : current.content.replaceFirst(patch.oldText, patch.newText);
        await store.writeText(
          workspaceId: workspaceId,
          path: path,
          content: updated,
          overwrite: true,
        );
        changedPaths.add(path);
        projectFiles.add(path);
      }

      for (final file in files) {
        final path = _projectPath(file.path, projectRoot: manifest.projectRoot);
        await store.writeText(
          workspaceId: workspaceId,
          path: path,
          content: file.content,
          overwrite: true,
        );
        changedPaths.add(path);
        projectFiles.add(path);
      }

      final updatedAt = DateTime.now();
      final version = manifest.version + 1;
      final permissions = _permissions(arguments['permissions']).isEmpty
          ? manifest.permissions
          : _permissions(arguments['permissions']);
      final summary = _stringArgument(arguments, 'summary') ?? '更新 Web App 项目';
      final sortedFiles = projectFiles.toList(growable: false)..sort();
      await store.writeText(
        workspaceId: workspaceId,
        path: manifest.manifestPath,
        content: _manifestContent(
          projectId: manifest.projectId,
          artifactId: artifact.id,
          workspaceId: workspaceId,
          title: artifact.title,
          summary: artifact.summary,
          entryPath: manifest.entryPath,
          permissions: permissions,
          files: sortedFiles,
          version: version,
          createdAt: manifest.createdAt,
          updatedAt: updatedAt,
        ),
        overwrite: true,
      );
      final snapshot = await _versionStore.capture(
        fileStore: store,
        workspaceId: workspaceId,
        projectId: manifest.projectId,
        artifactId: artifact.id,
        version: version,
        summary: summary,
        entryPath: manifest.entryPath,
        manifestPath: manifest.manifestPath,
        files: sortedFiles,
        changedFiles: changedPaths.toList(growable: false)..sort(),
        createdAt: updatedAt,
      );
      await _versionStore.write(
        fileStore: store,
        workspaceId: workspaceId,
        snapshot: snapshot,
      );
      final updatedArtifact = await _updatedArtifact(
        store: store,
        workspaceId: workspaceId,
        artifact: artifact,
        manifest: manifest,
        files: sortedFiles,
        permissions: permissions,
        version: version,
        updatedAt: updatedAt,
      );
      _replaceArtifact(artifacts, updatedArtifact);
      return CapabilityExecutionResult(
        capabilityId: 'project.update_web_app',
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'artifactId': artifact.id,
          'type': updatedArtifact.type.name,
          'title': updatedArtifact.title,
          'projectId': manifest.projectId,
          'version': version,
          'manifestPath': manifest.manifestPath,
          'changedFiles': changedPaths.toList(growable: false)..sort(),
          'versionPath': _versionStore.versionPath(
            manifest.manifestPath,
            version,
          ),
        },
      );
    } on AppFileStoreException catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.update_web_app',
        output: {'ok': false, 'error': error.code, 'detail': error.message},
      );
    } on Object catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.update_web_app',
        output: {
          'ok': false,
          'error': 'project update failed',
          'detail': error.toString(),
        },
      );
    }
  }

  Future<CapabilityExecutionResult> versionHistory({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
    required List<AgentArtifact> artifacts,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.version_history',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final artifactLookup = _webAppArtifact(
      workspaceId: workspaceId,
      artifacts: artifacts,
      artifactId: arguments['artifact_id'] ?? arguments['artifactId'],
    );
    if (artifactLookup.error != null) {
      return artifactLookup.error!;
    }
    final manifestLookup = await _readManifest(
      store: store,
      workspaceId: workspaceId,
      artifact: artifactLookup.artifact!,
      capabilityId: 'project.version_history',
    );
    if (manifestLookup.error != null) {
      return manifestLookup.error!;
    }
    final manifest = manifestLookup.manifest!;
    final items = await _versionStore.history(
      fileStore: store,
      workspaceId: workspaceId,
      manifestPath: manifest.manifestPath,
    );
    return CapabilityExecutionResult(
      capabilityId: 'project.version_history',
      output: {
        'ok': true,
        'artifactId': artifactLookup.artifact!.id,
        'projectId': manifest.projectId,
        'currentVersion': manifest.version,
        'items': items,
      },
    );
  }

  Future<CapabilityExecutionResult> revertWebApp({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
    required List<AgentArtifact> artifacts,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.revert_web_app',
        output: {'ok': false, 'error': 'file store unavailable'},
      );
    }
    final targetVersion = arguments['version'];
    if (targetVersion is! int || targetVersion < 1) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.revert_web_app',
        output: {'ok': false, 'error': 'version is required'},
      );
    }
    final artifactLookup = _webAppArtifact(
      workspaceId: workspaceId,
      artifacts: artifacts,
      artifactId: arguments['artifact_id'] ?? arguments['artifactId'],
    );
    if (artifactLookup.error != null) {
      return artifactLookup.error!;
    }
    final artifact = artifactLookup.artifact!;
    final manifestLookup = await _readManifest(
      store: store,
      workspaceId: workspaceId,
      artifact: artifact,
      capabilityId: 'project.revert_web_app',
    );
    if (manifestLookup.error != null) {
      return manifestLookup.error!;
    }
    final manifest = manifestLookup.manifest!;

    try {
      final snapshot = await _versionStore.read(
        fileStore: store,
        workspaceId: workspaceId,
        manifestPath: manifest.manifestPath,
        version: targetVersion,
      );
      final snapshotPaths = snapshot.files.map((file) => file.path).toSet();
      for (final path in manifest.files) {
        if (!snapshotPaths.contains(path)) {
          await store.deleteFile(workspaceId: workspaceId, path: path);
        }
      }
      for (final file in snapshot.files) {
        await store.writeText(
          workspaceId: workspaceId,
          path: file.path,
          content: file.content,
          overwrite: true,
        );
      }

      final updatedAt = DateTime.now();
      final version = manifest.version + 1;
      final files = snapshotPaths.toList(growable: false)..sort();
      final summary =
          _stringArgument(arguments, 'summary') ??
          '回滚到 v${targetVersion.toString()}';
      await store.writeText(
        workspaceId: workspaceId,
        path: manifest.manifestPath,
        content: _manifestContent(
          projectId: manifest.projectId,
          artifactId: artifact.id,
          workspaceId: workspaceId,
          title: artifact.title,
          summary: artifact.summary,
          entryPath: snapshot.entryPath,
          permissions: manifest.permissions,
          files: files,
          version: version,
          createdAt: manifest.createdAt,
          updatedAt: updatedAt,
        ),
        overwrite: true,
      );
      final revertSnapshot = await _versionStore.capture(
        fileStore: store,
        workspaceId: workspaceId,
        projectId: manifest.projectId,
        artifactId: artifact.id,
        version: version,
        summary: summary,
        entryPath: snapshot.entryPath,
        manifestPath: manifest.manifestPath,
        files: files,
        changedFiles: files,
        createdAt: updatedAt,
        revertedFromVersion: targetVersion,
      );
      await _versionStore.write(
        fileStore: store,
        workspaceId: workspaceId,
        snapshot: revertSnapshot,
      );
      final updatedArtifact = await _updatedArtifact(
        store: store,
        workspaceId: workspaceId,
        artifact: artifact,
        manifest: manifest.copyWith(entryPath: snapshot.entryPath),
        files: files,
        permissions: manifest.permissions,
        version: version,
        updatedAt: updatedAt,
      );
      _replaceArtifact(artifacts, updatedArtifact);
      return CapabilityExecutionResult(
        capabilityId: 'project.revert_web_app',
        output: {
          'ok': true,
          'workspaceId': workspaceId,
          'artifactId': artifact.id,
          'type': updatedArtifact.type.name,
          'title': updatedArtifact.title,
          'projectId': manifest.projectId,
          'version': version,
          'revertedFromVersion': targetVersion,
          'manifestPath': manifest.manifestPath,
          'changedFiles': files,
        },
      );
    } on AppFileStoreException catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.revert_web_app',
        output: {'ok': false, 'error': error.code, 'detail': error.message},
      );
    } on Object catch (error) {
      return CapabilityExecutionResult(
        capabilityId: 'project.revert_web_app',
        output: {
          'ok': false,
          'error': 'project revert failed',
          'detail': error.toString(),
        },
      );
    }
  }

  String? _stringArgument(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  String _projectIdFor(Map<String, Object?> arguments, String artifactId) {
    final metadata = arguments['metadata'];
    if (metadata is Map<Object?, Object?>) {
      final projectId = metadata['projectId'];
      if (projectId is String && projectId.trim().isNotEmpty) {
        return projectId.trim();
      }
    }
    return 'project-$artifactId';
  }

  List<_ProjectFile> _files(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    final files = <_ProjectFile>[];
    for (final item in value) {
      if (item is! Map<Object?, Object?>) {
        continue;
      }
      final path = item['path'];
      final content = item['content'];
      if (path is String &&
          path.trim().isNotEmpty &&
          content is String &&
          content.isNotEmpty) {
        files.add(_ProjectFile(path.trim(), content));
      }
    }
    return files;
  }

  List<_ProjectPatch> _patches(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    final patches = <_ProjectPatch>[];
    for (final item in value) {
      if (item is! Map<Object?, Object?>) {
        continue;
      }
      final path = item['path'];
      final oldText = item['old_text'] ?? item['oldText'];
      final newText = item['new_text'] ?? item['newText'];
      if (path is String &&
          path.trim().isNotEmpty &&
          oldText is String &&
          oldText.isNotEmpty &&
          newText is String) {
        patches.add(
          _ProjectPatch(
            path: path.trim(),
            oldText: oldText,
            newText: newText,
            replaceAll: item['replace_all'] == true,
          ),
        );
      }
    }
    return patches;
  }

  List<String> _permissions(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    return value.whereType<String>().toList(growable: false);
  }

  _ProjectFile? _fileByPath(List<_ProjectFile> files, String path) {
    for (final file in files) {
      if (file.path == path) {
        return file;
      }
    }
    return null;
  }

  String _manifestPathFor(String entryPath) {
    final slash = entryPath.lastIndexOf('/');
    if (slash < 0) {
      return '.phone-agent/manifest.json';
    }
    return '${entryPath.substring(0, slash)}/.phone-agent/manifest.json';
  }

  _WebAppArtifactLookup _webAppArtifact({
    required String workspaceId,
    required List<AgentArtifact> artifacts,
    required Object? artifactId,
  }) {
    if (artifactId is! String || artifactId.trim().isEmpty) {
      return _WebAppArtifactLookup(
        error: const CapabilityExecutionResult(
          capabilityId: 'project.web_app',
          output: {'ok': false, 'error': 'artifact_id is required'},
        ),
      );
    }
    for (final artifact in artifacts) {
      if (artifact.id == artifactId.trim() &&
          artifact.workspaceId == workspaceId) {
        if (artifact.type != ArtifactType.webApp) {
          return _WebAppArtifactLookup(
            error: const CapabilityExecutionResult(
              capabilityId: 'project.web_app',
              output: {'ok': false, 'error': 'artifact is not a web app'},
            ),
          );
        }
        return _WebAppArtifactLookup(artifact: artifact);
      }
    }
    return _WebAppArtifactLookup(
      error: CapabilityExecutionResult(
        capabilityId: 'project.web_app',
        output: {
          'ok': false,
          'error': 'artifact_not_found',
          'artifactId': artifactId,
        },
      ),
    );
  }

  Future<_ProjectManifestLookup> _readManifest({
    required AppFileStore store,
    required String workspaceId,
    required AgentArtifact artifact,
    required String capabilityId,
  }) async {
    final rawManifestPath = artifact.metadata['manifestPath'];
    final rawEntry = artifact.metadata['entry'];
    final entryPath = rawEntry is String && rawEntry.trim().isNotEmpty
        ? normalizeAppFilePath(rawEntry)
        : 'index.html';
    final manifestPath =
        rawManifestPath is String && rawManifestPath.trim().isNotEmpty
        ? normalizeAppFilePath(rawManifestPath)
        : _manifestPathFor(entryPath);
    try {
      final result = await store.readText(
        workspaceId: workspaceId,
        path: manifestPath,
        maxChars: 512 * 1024,
      );
      final decoded = jsonDecode(result.content);
      if (decoded is! Map<Object?, Object?>) {
        return _ProjectManifestLookup(
          error: _projectError(
            capabilityId,
            'invalid_manifest',
            'Web App manifest 不是有效 JSON 对象。',
          ),
        );
      }
      final manifest = Map<String, Object?>.from(decoded);
      return _ProjectManifestLookup(
        manifest: _ProjectManifest(
          projectId: _manifestString(
            manifest['projectId'],
            fallback: 'project-${artifact.id}',
          ),
          artifactId: artifact.id,
          workspaceId: workspaceId,
          title: _manifestString(manifest['title'], fallback: artifact.title),
          summary: _manifestString(
            manifest['summary'],
            fallback: artifact.summary,
          ),
          entryPath: _manifestString(manifest['entry'], fallback: entryPath),
          manifestPath: manifestPath,
          permissions: _stringItems(manifest['permissions']),
          files: _stringItems(manifest['files']),
          version: _intValue(manifest['version'], fallback: 1),
          createdAt: _dateValue(manifest['createdAt']) ?? artifact.createdAt,
        ),
      );
    } on AppFileStoreException catch (error) {
      if (error.code != 'not_found') {
        return _ProjectManifestLookup(
          error: CapabilityExecutionResult(
            capabilityId: capabilityId,
            output: {'ok': false, 'error': error.code, 'detail': error.message},
          ),
        );
      }
      final files = _metadataFiles(artifact);
      return _ProjectManifestLookup(
        manifest: _ProjectManifest(
          projectId: 'project-${artifact.id}',
          artifactId: artifact.id,
          workspaceId: workspaceId,
          title: artifact.title,
          summary: artifact.summary,
          entryPath: entryPath,
          manifestPath: manifestPath,
          permissions: _stringItems(artifact.metadata['permissions']),
          files: files.isEmpty ? [entryPath] : files,
          version: _intValue(artifact.metadata['currentVersion'], fallback: 1),
          createdAt: artifact.createdAt,
        ),
      );
    } on Object catch (error) {
      return _ProjectManifestLookup(
        error: CapabilityExecutionResult(
          capabilityId: capabilityId,
          output: {
            'ok': false,
            'error': 'manifest read failed',
            'detail': error.toString(),
          },
        ),
      );
    }
  }

  Future<AgentArtifact> _updatedArtifact({
    required AppFileStore store,
    required String workspaceId,
    required AgentArtifact artifact,
    required _ProjectManifest manifest,
    required List<String> files,
    required List<String> permissions,
    required int version,
    required DateTime updatedAt,
  }) async {
    final entry = await store.readText(
      workspaceId: workspaceId,
      path: manifest.entryPath,
      maxChars: 5 * 1024 * 1024,
    );
    final entries = await store.listFiles(workspaceId: workspaceId);
    final fileSet = files.toSet();
    final fileOutputs = entries
        .where((entry) => fileSet.contains(entry.path))
        .map(
          (entry) => {
            'path': entry.path,
            'uri': entry.uri.toString(),
            'bytes': entry.bytes,
          },
        )
        .toList(growable: false);
    Map<String, Object?>? entryOutput;
    for (final file in fileOutputs) {
      if (file['path'] == manifest.entryPath) {
        entryOutput = file;
        break;
      }
    }
    final uriText = entryOutput?['uri'];
    return AgentArtifact(
      id: artifact.id,
      workspaceId: artifact.workspaceId,
      type: artifact.type,
      title: artifact.title,
      summary: artifact.summary,
      createdAt: artifact.createdAt,
      uri: uriText is String ? Uri.tryParse(uriText) : artifact.uri,
      metadata: {
        ...artifact.metadata,
        'entry': manifest.entryPath,
        'html': entry.content,
        'project': true,
        'projectId': manifest.projectId,
        'manifestPath': manifest.manifestPath,
        'currentVersion': version,
        'updatedAt': updatedAt.toIso8601String(),
        'files': fileOutputs,
        'permissions': permissions,
      },
    );
  }

  String _projectPath(String path, {required String projectRoot}) {
    final normalized = normalizeAppFilePath(path);
    if (projectRoot.isEmpty || normalized.startsWith('$projectRoot/')) {
      return normalized;
    }
    throw const AppFileStoreException(
      'path_outside_project',
      '项目更新只能修改该 Web App 项目目录内的文件。',
    );
  }

  CapabilityExecutionResult _projectError(
    String capabilityId,
    String error,
    String detail, {
    String? path,
  }) {
    final output = <String, Object?>{
      'ok': false,
      'error': error,
      'detail': detail,
    };
    if (path != null) {
      output['path'] = path;
    }
    return CapabilityExecutionResult(
      capabilityId: capabilityId,
      output: output,
    );
  }

  void _replaceArtifact(List<AgentArtifact> artifacts, AgentArtifact artifact) {
    final index = artifacts.indexWhere((item) => item.id == artifact.id);
    if (index >= 0) {
      artifacts[index] = artifact;
    } else {
      artifacts.add(artifact);
    }
  }

  String _manifestString(Object? value, {required String fallback}) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  int _intValue(Object? value, {required int fallback}) {
    return value is int && value > 0 ? value : fallback;
  }

  DateTime? _dateValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }

  List<String> _stringItems(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    return value.whereType<String>().toList(growable: false);
  }

  List<String> _metadataFiles(AgentArtifact artifact) {
    final files = artifact.metadata['files'];
    if (files is! Iterable<Object?>) {
      return const [];
    }
    final paths = <String>[];
    for (final file in files) {
      if (file is String) {
        paths.add(file);
      } else if (file is Map<Object?, Object?>) {
        final path = file['path'];
        if (path is String && path.trim().isNotEmpty) {
          paths.add(path.trim());
        }
      }
    }
    return paths.toList(growable: false)..sort();
  }

  String _manifestContent({
    required String projectId,
    required String artifactId,
    required String workspaceId,
    required String title,
    required String summary,
    required String entryPath,
    required List<String> permissions,
    required List<String> files,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    final manifest = {
      'schema': 'phone-agent.webapp.v1',
      'projectId': projectId,
      'artifactId': artifactId,
      'workspaceId': workspaceId,
      'title': title,
      'summary': summary,
      'entry': entryPath,
      'permissions': permissions,
      'files': files,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert(manifest)}\n';
  }
}

class _ProjectFile {
  const _ProjectFile(this.path, this.content);

  final String path;
  final String content;
}

class _ProjectPatch {
  const _ProjectPatch({
    required this.path,
    required this.oldText,
    required this.newText,
    required this.replaceAll,
  });

  final String path;
  final String oldText;
  final String newText;
  final bool replaceAll;
}

class _WebAppArtifactLookup {
  const _WebAppArtifactLookup({this.artifact, this.error});

  final AgentArtifact? artifact;
  final CapabilityExecutionResult? error;
}

class _ProjectManifestLookup {
  const _ProjectManifestLookup({this.manifest, this.error});

  final _ProjectManifest? manifest;
  final CapabilityExecutionResult? error;
}

class _ProjectManifest {
  const _ProjectManifest({
    required this.projectId,
    required this.artifactId,
    required this.workspaceId,
    required this.title,
    required this.summary,
    required this.entryPath,
    required this.manifestPath,
    required this.permissions,
    required this.files,
    required this.version,
    required this.createdAt,
  });

  final String projectId;
  final String artifactId;
  final String workspaceId;
  final String title;
  final String summary;
  final String entryPath;
  final String manifestPath;
  final List<String> permissions;
  final List<String> files;
  final int version;
  final DateTime createdAt;

  String get projectRoot {
    final marker = '/.phone-agent/manifest.json';
    if (manifestPath.endsWith(marker)) {
      return manifestPath.substring(0, manifestPath.length - marker.length);
    }
    final slash = entryPath.lastIndexOf('/');
    return slash < 0 ? '' : entryPath.substring(0, slash);
  }

  _ProjectManifest copyWith({String? entryPath}) {
    return _ProjectManifest(
      projectId: projectId,
      artifactId: artifactId,
      workspaceId: workspaceId,
      title: title,
      summary: summary,
      entryPath: entryPath ?? this.entryPath,
      manifestPath: manifestPath,
      permissions: permissions,
      files: files,
      version: version,
      createdAt: createdAt,
    );
  }
}
