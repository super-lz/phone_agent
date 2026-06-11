import 'dart:convert';

import '../../domain/artifacts/artifact.dart';
import '../../domain/artifacts/web_app_runtime_log.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/web_apps/web_app_data_namespace.dart';
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

    var files = <_ProjectFile>[];
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
    var entryPath = '';
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
    final artifactId = 'artifact-${DateTime.now().microsecondsSinceEpoch}';
    final scopedProject = _scopeProjectFilesForCreate(
      files: files,
      entryPath: entryPath,
      title: title,
      artifactId: artifactId,
    );
    files = scopedProject.files;
    entryPath = scopedProject.entryPath;
    seenPaths
      ..clear()
      ..addAll(files.map((file) => file.path));
    if (seenPaths.length != files.length) {
      return CapabilityExecutionResult(
        capabilityId: 'project.create_web_app',
        output: {
          'ok': false,
          'error': 'duplicate_path',
          'detail': '自动套入项目目录后出现重复路径，请合并同名文件后重试。',
        },
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

    final projectId = _projectIdFor(arguments, artifactId);
    final createdAt = DateTime.now();
    final permissions = _permissions(arguments['permissions']);
    final databaseNamespace =
        _stringArgument(arguments, 'database_namespace') ??
        WebAppDataNamespace.databaseForId(
          workspaceId: workspaceId,
          webAppId: artifactId,
        );
    final fileNamespace =
        _stringArgument(arguments, 'file_namespace') ??
        WebAppDataNamespace.filesForId(
          workspaceId: workspaceId,
          webAppId: artifactId,
        );
    Map<String, Object?>? server = _serverSpec(arguments['server']);
    final rawMetadataForServer = arguments['metadata'];
    if (server == null && rawMetadataForServer is Map<Object?, Object?>) {
      server = _serverSpec(rawMetadataForServer['server']);
    }
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
        databaseNamespace: databaseNamespace,
        fileNamespace: fileNamespace,
        server: server,
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
      'databaseNamespace': databaseNamespace,
      'fileNamespace': fileNamespace,
    });
    if (server == null) {
      metadata.remove('server');
    } else {
      metadata['server'] = server;
    }

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

    final output = <String, Object?>{
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
      'databaseNamespace': databaseNamespace,
      'fileNamespace': fileNamespace,
    };
    if (server != null) {
      output['server'] = server;
    }
    return CapabilityExecutionResult(
      capabilityId: 'project.create_web_app',
      output: output,
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
      final server = arguments.containsKey('server')
          ? _serverSpec(arguments['server'])
          : manifest.server;
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
          databaseNamespace: manifest.databaseNamespace,
          fileNamespace: manifest.fileNamespace,
          server: server,
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
        databaseNamespace: manifest.databaseNamespace,
        fileNamespace: manifest.fileNamespace,
        server: server,
        version: version,
        updatedAt: updatedAt,
      );
      _replaceArtifact(artifacts, updatedArtifact);
      final output = <String, Object?>{
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
      };
      if (server != null) {
        output['server'] = server;
      }
      return CapabilityExecutionResult(
        capabilityId: 'project.update_web_app',
        output: output,
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

  Future<CapabilityExecutionResult> testWebApp({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required AppFileStore? fileStore,
    required List<AgentArtifact> artifacts,
  }) async {
    final store = fileStore;
    if (store == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'project.test_web_app',
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
      capabilityId: 'project.test_web_app',
    );
    if (manifestLookup.error != null) {
      return manifestLookup.error!;
    }
    final manifest = manifestLookup.manifest!;
    final issues = <Map<String, Object?>>[];
    final checkedFiles = <String>{};
    final projectFiles = manifest.files.toSet();
    final fileContents = <String, String>{};

    if (!projectFiles.contains(manifest.entryPath)) {
      issues.add({
        'severity': 'error',
        'path': manifest.entryPath,
        'message': '入口文件未包含在 manifest files 中。',
      });
    }

    for (final path in manifest.files) {
      late final AppFileReadResult result;
      try {
        result = await store.readText(
          workspaceId: workspaceId,
          path: path,
          maxChars: 2 * 1024 * 1024,
        );
      } on AppFileStoreException catch (error) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': error.code == 'not_found'
              ? 'manifest 声明的文件不存在。'
              : error.message,
        });
        continue;
      }
      checkedFiles.add(path);
      fileContents[path] = result.content;
      if (result.truncated) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': '文件过大，当前测试能力无法完整检查。',
        });
        continue;
      }
      final content = result.content;
      if (path.endsWith('.html') || path.endsWith('.htm')) {
        _analyzeHtml(
          path: path,
          content: content,
          projectFiles: projectFiles,
          issues: issues,
        );
      } else if (path.endsWith('.js') || path.endsWith('.mjs')) {
        _analyzeJavaScript(path: path, content: content, issues: issues);
      } else if (path.endsWith('.css')) {
        _analyzeCss(path: path, content: content, issues: issues);
      }
    }
    _analyzeServer(
      server: manifest.server,
      permissions: manifest.permissions.toSet(),
      projectRoot: manifest.projectRoot,
      projectFiles: projectFiles,
      fileContents: fileContents,
      issues: issues,
    );

    final passed = !issues.any((issue) => issue['severity'] == 'error');
    return CapabilityExecutionResult(
      capabilityId: 'project.test_web_app',
      output: {
        'ok': true,
        'passed': passed,
        'artifactId': artifact.id,
        'projectId': manifest.projectId,
        'version': manifest.version,
        'entryPath': manifest.entryPath,
        'checkedFiles': checkedFiles.toList(growable: false)..sort(),
        'issues': issues,
        'summary': passed ? 'Web App 项目静态检查通过。' : 'Web App 项目静态检查发现问题。',
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
          databaseNamespace: manifest.databaseNamespace,
          fileNamespace: manifest.fileNamespace,
          server: manifest.server,
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
        databaseNamespace: manifest.databaseNamespace,
        fileNamespace: manifest.fileNamespace,
        server: manifest.server,
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

  Map<String, Object?>? _serverSpec(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final server = _jsonMap(value);
    return server.isEmpty ? null : server;
  }

  Map<String, Object?> _jsonMap(Map<Object?, Object?> value) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _jsonValue(entry.value),
    };
  }

  Object? _jsonValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return _jsonMap(value);
    }
    if (value is Iterable<Object?>) {
      return [for (final item in value) _jsonValue(item)];
    }
    return value.toString();
  }

  _ProjectFile? _fileByPath(List<_ProjectFile> files, String path) {
    for (final file in files) {
      if (file.path == path) {
        return file;
      }
    }
    return null;
  }

  _ScopedProjectFiles _scopeProjectFilesForCreate({
    required List<_ProjectFile> files,
    required String entryPath,
    required String title,
    required String artifactId,
  }) {
    final root = _projectRootForCreate(
      files: files,
      entryPath: entryPath,
      title: title,
      artifactId: artifactId,
    );
    if (root == null) {
      return _ScopedProjectFiles(files: files, entryPath: entryPath);
    }
    return _ScopedProjectFiles(
      files: [
        for (final file in files)
          _ProjectFile(_pathUnderProjectRoot(root, file.path), file.content),
      ],
      entryPath: _pathUnderProjectRoot(root, entryPath),
    );
  }

  String? _projectRootForCreate({
    required List<_ProjectFile> files,
    required String entryPath,
    required String title,
    required String artifactId,
  }) {
    final entryDirectory = _directoryForPath(entryPath);
    if (entryDirectory.isEmpty) {
      return _autoProjectRoot(title: title, artifactId: artifactId);
    }
    final allFilesUnderEntryDirectory = files.every(
      (file) => file.path.startsWith('$entryDirectory/'),
    );
    return allFilesUnderEntryDirectory ? null : entryDirectory;
  }

  String _pathUnderProjectRoot(String root, String path) {
    if (path.startsWith('$root/')) {
      return path;
    }
    return '$root/$path';
  }

  String _directoryForPath(String path) {
    final slash = path.lastIndexOf('/');
    if (slash < 0) {
      return '';
    }
    return path.substring(0, slash);
  }

  String _autoProjectRoot({required String title, required String artifactId}) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final suffix = artifactId.split('-').last;
    return 'apps/${slug.isEmpty ? 'web-app' : slug}-$suffix';
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
      final defaultDatabaseNamespace = WebAppDataNamespace.databaseForId(
        workspaceId: workspaceId,
        webAppId: artifact.id,
      );
      final defaultFileNamespace = WebAppDataNamespace.filesForId(
        workspaceId: workspaceId,
        webAppId: artifact.id,
      );
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
          databaseNamespace: _manifestString(
            manifest['databaseNamespace'],
            fallback: _manifestString(
              artifact.metadata['databaseNamespace'],
              fallback: defaultDatabaseNamespace,
            ),
          ),
          fileNamespace: _manifestString(
            manifest['fileNamespace'],
            fallback: _manifestString(
              artifact.metadata['fileNamespace'],
              fallback: defaultFileNamespace,
            ),
          ),
          server: _serverSpec(manifest['server']),
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
      final defaultDatabaseNamespace = WebAppDataNamespace.databaseForId(
        workspaceId: workspaceId,
        webAppId: artifact.id,
      );
      final defaultFileNamespace = WebAppDataNamespace.filesForId(
        workspaceId: workspaceId,
        webAppId: artifact.id,
      );
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
          databaseNamespace: _manifestString(
            artifact.metadata['databaseNamespace'],
            fallback: defaultDatabaseNamespace,
          ),
          fileNamespace: _manifestString(
            artifact.metadata['fileNamespace'],
            fallback: defaultFileNamespace,
          ),
          server: _serverSpec(artifact.metadata['server']),
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
    required String databaseNamespace,
    required String fileNamespace,
    required Map<String, Object?>? server,
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
    final metadata = <String, Object?>{
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
      'databaseNamespace': databaseNamespace,
      'fileNamespace': fileNamespace,
    };
    if (server == null) {
      metadata.remove('server');
    } else {
      metadata['server'] = server;
    }
    return AgentArtifact(
      id: artifact.id,
      workspaceId: artifact.workspaceId,
      type: artifact.type,
      title: artifact.title,
      summary: artifact.summary,
      createdAt: artifact.createdAt,
      uri: uriText is String ? Uri.tryParse(uriText) : artifact.uri,
      metadata: metadata,
    );
  }

  String _projectPath(String path, {required String projectRoot}) {
    final normalized = normalizeAppFilePath(path);
    if (projectRoot.isEmpty || normalized.startsWith('$projectRoot/')) {
      return normalized;
    }
    if (normalized == projectRoot) {
      throw const AppFileStoreException(
        'invalid_path',
        '项目更新路径必须指向文件，不能指向项目根目录。',
      );
    }
    final projectRootTop = projectRoot.split('/').first;
    final normalizedTop = normalized.split('/').first;
    if (normalizedTop == projectRootTop) {
      throw const AppFileStoreException(
        'path_outside_project',
        '项目更新只能修改该 Web App 项目目录内的文件。',
      );
    }
    return '$projectRoot/$normalized';
  }

  void _analyzeHtml({
    required String path,
    required String content,
    required Set<String> projectFiles,
    required List<Map<String, Object?>> issues,
  }) {
    final lower = content.toLowerCase();
    if (!lower.contains('<!doctype html') && !lower.contains('<html')) {
      issues.add({
        'severity': 'warning',
        'path': path,
        'message': 'HTML 入口缺少 doctype 或 html 标签。',
      });
    }
    final scriptTag = RegExp(
      r'<script\b([^>]*)>([\s\S]*?)<\/script>',
      caseSensitive: false,
    );
    for (final match in scriptTag.allMatches(content)) {
      final attrs = match.group(1) ?? '';
      final src = _htmlAttribute(attrs, 'src');
      if (src != null && src.trim().isNotEmpty) {
        final resolved = _resolveProjectReference(path, src);
        if (resolved == null || !projectFiles.contains(resolved)) {
          issues.add({
            'severity': 'error',
            'path': path,
            'message': 'script 引用的项目文件不存在：$src',
          });
        }
      } else {
        _analyzeJavaScript(
          path: '$path <inline script>',
          content: match.group(2) ?? '',
          issues: issues,
        );
      }
    }

    final stylesheetTag = RegExp(
      r'''<link\b([^>]*\brel\s*=\s*["']?stylesheet["']?[^>]*)>''',
      caseSensitive: false,
    );
    for (final match in stylesheetTag.allMatches(content)) {
      final href = _htmlAttribute(match.group(1) ?? '', 'href');
      if (href == null || href.trim().isEmpty) {
        continue;
      }
      final resolved = _resolveProjectReference(path, href);
      if (resolved == null || !projectFiles.contains(resolved)) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': 'stylesheet 引用的项目文件不存在：$href',
        });
      }
    }
  }

  void _analyzeCss({
    required String path,
    required String content,
    required List<Map<String, Object?>> issues,
  }) {
    _balancedDelimiterIssue(
      path: path,
      content: _stripCssComments(content),
      open: '{',
      close: '}',
      label: 'CSS 大括号',
      issues: issues,
    );
  }

  void _analyzeJavaScript({
    required String path,
    required String content,
    required List<Map<String, Object?>> issues,
  }) {
    final stack = <String>[];
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    for (var i = 0; i < content.length; i += 1) {
      final char = content[i];
      final next = i + 1 < content.length ? content[i + 1] : '';
      if (lineComment) {
        if (char == '\n') {
          lineComment = false;
        }
        continue;
      }
      if (blockComment) {
        if (char == '*' && next == '/') {
          blockComment = false;
          i += 1;
        }
        continue;
      }
      if (quote.isNotEmpty) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '/' && next == '/') {
        lineComment = true;
        i += 1;
        continue;
      }
      if (char == '/' && next == '*') {
        blockComment = true;
        i += 1;
        continue;
      }
      if (char == '"' || char == "'" || char == '`') {
        quote = char;
        continue;
      }
      if (char == '(' || char == '[' || char == '{') {
        stack.add(char);
        continue;
      }
      if (char == ')' || char == ']' || char == '}') {
        if (stack.isEmpty || !_delimiterMatches(stack.removeLast(), char)) {
          issues.add({
            'severity': 'error',
            'path': path,
            'message': 'JavaScript 存在不匹配的闭合符号：$char',
          });
          return;
        }
      }
    }
    if (quote.isNotEmpty) {
      issues.add({
        'severity': 'error',
        'path': path,
        'message': 'JavaScript 字符串或模板字面量未闭合。',
      });
    }
    if (blockComment) {
      issues.add({
        'severity': 'error',
        'path': path,
        'message': 'JavaScript 块注释未闭合。',
      });
    }
    if (stack.isNotEmpty) {
      issues.add({
        'severity': 'error',
        'path': path,
        'message': 'JavaScript 存在未闭合的 ${stack.last}。',
      });
    }
  }

  void _analyzeServer({
    required Map<String, Object?>? server,
    required Set<String> permissions,
    required String projectRoot,
    required Set<String> projectFiles,
    required Map<String, String> fileContents,
    required List<Map<String, Object?>> issues,
  }) {
    if (server == null) {
      return;
    }
    final routes = server['routes'];
    if (routes is! Iterable<Object?>) {
      issues.add({
        'severity': 'error',
        'path': 'server.routes',
        'message': 'server.routes 必须是路由数组。',
      });
      return;
    }
    final seen = <String>{};
    for (final route in routes) {
      if (route is! Map<Object?, Object?>) {
        issues.add({
          'severity': 'error',
          'path': 'server.routes',
          'message': '每个 server route 必须是对象。',
        });
        continue;
      }
      final method = route['method'];
      final path = route['path'];
      final capabilityId = route['capability'] ?? route['capabilityId'];
      final handlerPath = route['handlerPath'] ?? route['handler_path'];
      final handler = route['handler'];
      if (method is! String || !_isAllowedServerMethod(method)) {
        issues.add({
          'severity': 'error',
          'path': 'server.routes',
          'message': 'server route method 必须是 GET、POST、PUT、PATCH 或 DELETE。',
        });
      }
      if (path is! String || !path.startsWith('/api/')) {
        issues.add({
          'severity': 'error',
          'path': 'server.routes',
          'message': 'server route path 必须以 /api/ 开头。',
        });
      }
      final capabilityText = capabilityId is String
          ? capabilityId.trim()
          : null;
      final handlerPathText = handlerPath is String ? handlerPath.trim() : null;
      final hasCapability = capabilityText != null && capabilityText.isNotEmpty;
      final hasHandlerPath =
          handlerPathText != null && handlerPathText.isNotEmpty;
      final hasInlineHandler = handler is Map<Object?, Object?>;
      if (!hasCapability && !hasHandlerPath && !hasInlineHandler) {
        issues.add({
          'severity': 'error',
          'path': 'server.routes',
          'message': 'server route 必须声明 capability、handler 或 handlerPath。',
        });
      } else if (hasCapability && !permissions.contains(capabilityText)) {
        issues.add({
          'severity': 'error',
          'path': 'server.routes',
          'message':
              'server route 使用的 capability 未在 permissions 中声明：$capabilityText',
        });
      }
      if (hasInlineHandler) {
        _analyzeServerHandler(
          handler: handler,
          permissions: permissions,
          path: 'server.routes.handler',
          issues: issues,
        );
      }
      if (hasHandlerPath) {
        late final String normalized;
        try {
          normalized = _serverHandlerProjectPath(
            handlerPathText,
            projectRoot: projectRoot,
          );
        } on AppFileStoreException catch (error) {
          issues.add({
            'severity': 'error',
            'path': 'server.routes',
            'message': error.message,
          });
          continue;
        }
        final content = fileContents[normalized];
        if (!projectFiles.contains(normalized) || content == null) {
          issues.add({
            'severity': 'error',
            'path': normalized,
            'message':
                'server route handlerPath 指向的服务端代码文件不存在或未包含在 manifest files 中。',
          });
        } else {
          try {
            final decoded = jsonDecode(content);
            if (decoded is! Map<Object?, Object?>) {
              issues.add({
                'severity': 'error',
                'path': normalized,
                'message': 'server action handler 必须是 JSON 对象。',
              });
            } else {
              _analyzeServerHandler(
                handler: decoded,
                permissions: permissions,
                path: normalized,
                issues: issues,
              );
            }
          } on Object {
            issues.add({
              'severity': 'error',
              'path': normalized,
              'message': 'server action handler 不是有效 JSON。',
            });
          }
        }
      }
      if (method is String && path is String) {
        final key = '${method.toUpperCase()} $path';
        if (!seen.add(key)) {
          issues.add({
            'severity': 'error',
            'path': 'server.routes',
            'message': 'server route 重复：$key',
          });
        }
      }
    }
  }

  void _analyzeServerHandler({
    required Map<Object?, Object?> handler,
    required Set<String> permissions,
    required String path,
    required List<Map<String, Object?>> issues,
  }) {
    final steps = handler['steps'];
    if (steps is! Iterable<Object?>) {
      issues.add({
        'severity': 'error',
        'path': path,
        'message': 'server action handler 必须声明 steps 数组。',
      });
      return;
    }
    final seenStepIds = <String>{};
    for (final step in steps) {
      if (step is! Map<Object?, Object?>) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': 'server action step 必须是对象。',
        });
        continue;
      }
      final stepId = step['id'];
      final capabilityId = step['capability'] ?? step['capabilityId'];
      if (stepId is! String || stepId.trim().isEmpty) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': 'server action step 必须声明 id。',
        });
      } else if (!seenStepIds.add(stepId.trim())) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': 'server action step id 重复：${stepId.trim()}',
        });
      }
      if (capabilityId is! String || capabilityId.trim().isEmpty) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': 'server action step 必须声明 capability。',
        });
      } else if (!permissions.contains(capabilityId.trim())) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message':
              'server action step 使用的 capability 未在 permissions 中声明：${capabilityId.trim()}',
        });
      }
    }
  }

  String _serverHandlerProjectPath(
    String rawPath, {
    required String projectRoot,
  }) {
    final normalizedPath = normalizeAppFilePath(rawPath);
    if (projectRoot.isEmpty || normalizedPath.startsWith('$projectRoot/')) {
      return normalizedPath;
    }
    return '$projectRoot/$normalizedPath';
  }

  bool _isAllowedServerMethod(String method) {
    return const {
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
    }.contains(method.toUpperCase());
  }

  bool _delimiterMatches(String open, String close) {
    return (open == '(' && close == ')') ||
        (open == '[' && close == ']') ||
        (open == '{' && close == '}');
  }

  void _balancedDelimiterIssue({
    required String path,
    required String content,
    required String open,
    required String close,
    required String label,
    required List<Map<String, Object?>> issues,
  }) {
    var depth = 0;
    for (final codeUnit in content.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (char == open) {
        depth += 1;
      } else if (char == close) {
        depth -= 1;
      }
      if (depth < 0) {
        issues.add({
          'severity': 'error',
          'path': path,
          'message': '$label 存在多余的闭合符号。',
        });
        return;
      }
    }
    if (depth > 0) {
      issues.add({'severity': 'error', 'path': path, 'message': '$label 未闭合。'});
    }
  }

  String _stripCssComments(String content) {
    return content.replaceAll(RegExp(r'\/\*[\s\S]*?\*\/'), '');
  }

  String? _htmlAttribute(String attrs, String name) {
    final quoted = RegExp(
      "$name\\s*=\\s*([\"'])(.*?)\\1",
      caseSensitive: false,
    ).firstMatch(attrs);
    if (quoted != null) {
      return quoted.group(2);
    }
    return RegExp(
      '$name\\s*=\\s*([^\\s>]+)',
      caseSensitive: false,
    ).firstMatch(attrs)?.group(1);
  }

  String? _resolveProjectReference(String fromPath, String reference) {
    final raw = reference.trim();
    if (raw.isEmpty ||
        raw.startsWith('#') ||
        raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('data:') ||
        raw.startsWith('blob:') ||
        raw.startsWith('//') ||
        raw.startsWith('/')) {
      return null;
    }
    final dir = fromPath.contains('/')
        ? fromPath.substring(0, fromPath.lastIndexOf('/'))
        : '';
    try {
      return normalizeAppFilePath(dir.isEmpty ? raw : '$dir/$raw');
    } on AppFileStoreException {
      return null;
    }
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
    required String databaseNamespace,
    required String fileNamespace,
    required Map<String, Object?>? server,
    required List<String> files,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    final manifest = <String, Object?>{
      'schema': 'phone-agent.webapp.v1',
      'projectId': projectId,
      'artifactId': artifactId,
      'workspaceId': workspaceId,
      'title': title,
      'summary': summary,
      'entry': entryPath,
      'permissions': permissions,
      'databaseNamespace': databaseNamespace,
      'fileNamespace': fileNamespace,
      'files': files,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
    if (server != null) {
      manifest['server'] = server;
    }
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert(manifest)}\n';
  }
}

class _ProjectFile {
  const _ProjectFile(this.path, this.content);

  final String path;
  final String content;
}

class _ScopedProjectFiles {
  const _ScopedProjectFiles({required this.files, required this.entryPath});

  final List<_ProjectFile> files;
  final String entryPath;
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
    required this.databaseNamespace,
    required this.fileNamespace,
    required this.server,
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
  final String databaseNamespace;
  final String fileNamespace;
  final Map<String, Object?>? server;
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
      databaseNamespace: databaseNamespace,
      fileNamespace: fileNamespace,
      server: server,
      files: files,
      version: version,
      createdAt: createdAt,
    );
  }
}
