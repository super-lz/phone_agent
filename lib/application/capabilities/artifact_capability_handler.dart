import '../../domain/artifacts/artifact.dart';
import '../../domain/artifacts/web_app_runtime_log.dart';
import 'capability_execution_result.dart';

class ArtifactCapabilityHandler {
  const ArtifactCapabilityHandler();

  CapabilityExecutionResult create({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required List<AgentArtifact> artifacts,
  }) {
    final rawTitle = arguments['title'];
    final rawSummary = arguments['summary'];
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'artifact.create',
        output: {'ok': false, 'error': 'title is required'},
      );
    }
    if (rawSummary is! String || rawSummary.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'artifact.create',
        output: {'ok': false, 'error': 'summary is required'},
      );
    }

    final type = _parseType(arguments['type']);
    final artifactId = 'artifact-${DateTime.now().microsecondsSinceEpoch}';
    final metadata = _metadataFor(arguments, artifactId: artifactId);
    if (type == ArtifactType.webApp && !_hasRunnableHtml(metadata)) {
      return const CapabilityExecutionResult(
        capabilityId: 'artifact.create',
        output: {
          'ok': false,
          'error': 'web_app_html is required',
          'detail':
              'web_app artifacts must include content_html or metadata.html',
        },
      );
    }

    final artifact = AgentArtifact(
      id: artifactId,
      workspaceId: workspaceId,
      type: type,
      title: rawTitle.trim(),
      summary: rawSummary.trim(),
      createdAt: DateTime.now(),
      metadata: metadata,
    );
    artifacts.add(artifact);

    return CapabilityExecutionResult(
      capabilityId: 'artifact.create',
      output: {
        'ok': true,
        'artifact': _toOutput(artifact),
        'artifactId': artifact.id,
        'type': artifact.type.name,
        'title': artifact.title,
      },
    );
  }

  CapabilityExecutionResult query({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required List<AgentArtifact> artifacts,
  }) {
    final rawQuery = arguments['query'];
    final keyword = rawQuery is String ? rawQuery.trim() : '';
    final rawType = arguments['type'];
    final type = rawType is String && rawType.trim().isNotEmpty
        ? _parseType(rawType)
        : null;

    final matched = artifacts
        .where((artifact) {
          if (artifact.workspaceId != workspaceId) {
            return false;
          }
          if (type != null && artifact.type != type) {
            return false;
          }
          if (keyword.isEmpty) {
            return true;
          }
          return artifact.title.contains(keyword) ||
              artifact.summary.contains(keyword);
        })
        .map(_toOutput)
        .toList(growable: false);

    return CapabilityExecutionResult(
      capabilityId: 'artifact.query',
      output: {'ok': true, 'items': matched},
    );
  }

  ArtifactType _parseType(Object? value) {
    if (value is! String) {
      return ArtifactType.document;
    }
    final normalized = value.trim().toLowerCase().replaceAll('-', '_');
    switch (normalized) {
      case 'image':
        return ArtifactType.image;
      case 'table':
        return ArtifactType.table;
      case 'report':
        return ArtifactType.report;
      case 'note':
        return ArtifactType.note;
      case 'task_list':
      case 'tasklist':
      case 'todo':
        return ArtifactType.taskList;
      case 'file':
        return ArtifactType.file;
      case 'web_app':
      case 'webapp':
      case 'app':
        return ArtifactType.webApp;
      case 'document':
      default:
        return ArtifactType.document;
    }
  }

  Map<String, Object?> _metadataFor(
    Map<String, Object?> arguments, {
    required String artifactId,
  }) {
    final rawMetadata = arguments['metadata'];
    final metadata = rawMetadata is Map<String, Object?>
        ? Map<String, Object?>.of(rawMetadata)
        : <String, Object?>{};
    if (_parseType(arguments['type']) == ArtifactType.webApp) {
      metadata.putIfAbsent('entry', () => 'index.html');
      metadata.putIfAbsent('permissions', () => <String>[]);
      metadata.putIfAbsent(
        'runtimeLogPath',
        () => WebAppRuntimeLogPaths.forMetadata(
          artifactId: artifactId,
          metadata: metadata,
        ),
      );
      final contentHtml = arguments['content_html'];
      if (contentHtml is String && contentHtml.trim().isNotEmpty) {
        metadata['html'] = contentHtml;
      }
    }
    return metadata;
  }

  bool _hasRunnableHtml(Map<String, Object?> metadata) {
    final html = metadata['html'];
    return html is String && html.trim().isNotEmpty;
  }

  Map<String, Object?> _toOutput(AgentArtifact artifact) {
    return {
      'id': artifact.id,
      'workspaceId': artifact.workspaceId,
      'type': artifact.type.name,
      'title': artifact.title,
      'summary': artifact.summary,
      if (artifact.uri != null) 'uri': artifact.uri.toString(),
      'metadata': artifact.metadata,
    };
  }
}
