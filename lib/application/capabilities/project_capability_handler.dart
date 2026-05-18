import 'dart:convert';

import '../../domain/artifacts/artifact.dart';
import '../../domain/artifacts/web_app_runtime_log.dart';
import '../../domain/files/app_file_store.dart';
import 'capability_execution_result.dart';

class ProjectCapabilityHandler {
  const ProjectCapabilityHandler();

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
        artifactId: artifactId,
        workspaceId: workspaceId,
        title: title,
        summary: summary,
        entryPath: entryPath,
        permissions: permissions,
        files: files.map((file) => file.path).toList(growable: false),
        createdAt: createdAt,
      );
      writeResults.add(
        await store.writeText(
          workspaceId: workspaceId,
          path: manifestPath,
          content: manifest,
          overwrite: true,
        ),
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
      'manifestPath': manifestPath,
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
        'files': metadata['files'],
      },
    );
  }

  String? _stringArgument(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
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

  String _manifestContent({
    required String artifactId,
    required String workspaceId,
    required String title,
    required String summary,
    required String entryPath,
    required List<String> permissions,
    required List<String> files,
    required DateTime createdAt,
  }) {
    final manifest = {
      'schema': 'phone-agent.webapp.v1',
      'artifactId': artifactId,
      'workspaceId': workspaceId,
      'title': title,
      'summary': summary,
      'entry': entryPath,
      'permissions': permissions,
      'files': files,
      'createdAt': createdAt.toIso8601String(),
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
