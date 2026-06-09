import 'dart:convert';

import '../../domain/files/app_file_store.dart';

class WebAppProjectVersionStore {
  const WebAppProjectVersionStore();

  Future<WebAppProjectSnapshot> capture({
    required AppFileStore fileStore,
    required String workspaceId,
    required String projectId,
    required String artifactId,
    required int version,
    required String summary,
    required String entryPath,
    required String manifestPath,
    required List<String> files,
    required DateTime createdAt,
    List<String> changedFiles = const [],
    int? revertedFromVersion,
  }) async {
    final snapshots = <WebAppProjectFileSnapshot>[];
    for (final path in files) {
      final read = await fileStore.readText(
        workspaceId: workspaceId,
        path: path,
        maxChars: 5 * 1024 * 1024,
      );
      if (read.truncated) {
        throw const AppFileStoreException(
          'file_too_large',
          '项目文件超过当前版本快照可安全处理的大小。',
        );
      }
      snapshots.add(
        WebAppProjectFileSnapshot(path: read.path, content: read.content),
      );
    }
    return WebAppProjectSnapshot(
      projectId: projectId,
      artifactId: artifactId,
      version: version,
      summary: summary,
      entryPath: entryPath,
      manifestPath: manifestPath,
      files: snapshots,
      changedFiles: changedFiles,
      createdAt: createdAt,
      revertedFromVersion: revertedFromVersion,
    );
  }

  Future<void> write({
    required AppFileStore fileStore,
    required String workspaceId,
    required WebAppProjectSnapshot snapshot,
  }) async {
    await fileStore.writeText(
      workspaceId: workspaceId,
      path: versionPath(snapshot.manifestPath, snapshot.version),
      content:
          '${const JsonEncoder.withIndent('  ').convert(snapshot.toJson())}\n',
      overwrite: true,
    );
  }

  Future<WebAppProjectSnapshot> read({
    required AppFileStore fileStore,
    required String workspaceId,
    required String manifestPath,
    required int version,
  }) async {
    final result = await fileStore.readText(
      workspaceId: workspaceId,
      path: versionPath(manifestPath, version),
      maxChars: 5 * 1024 * 1024,
    );
    final json = jsonDecode(result.content);
    if (json is! Map<String, Object?>) {
      throw const AppFileStoreException('invalid_version', '版本记录不是有效 JSON 对象。');
    }
    return WebAppProjectSnapshot.fromJson(json);
  }

  Future<List<Map<String, Object?>>> history({
    required AppFileStore fileStore,
    required String workspaceId,
    required String manifestPath,
  }) async {
    final prefix = versionsPrefix(manifestPath);
    final entries = await fileStore.listFiles(workspaceId: workspaceId);
    final versionEntries =
        entries
            .where((entry) => entry.path.startsWith(prefix))
            .where((entry) => entry.path.endsWith('.json'))
            .toList(growable: false)
          ..sort((a, b) => a.path.compareTo(b.path));

    final items = <Map<String, Object?>>[];
    for (final entry in versionEntries) {
      try {
        final result = await fileStore.readText(
          workspaceId: workspaceId,
          path: entry.path,
          maxChars: 256 * 1024,
        );
        final json = jsonDecode(result.content);
        if (json is Map<String, Object?>) {
          final files = json['files'];
          items.add({
            'version': json['version'],
            'summary': json['summary'],
            'createdAt': json['createdAt'],
            'changedFiles': json['changedFiles'],
            'fileCount': files is List<Object?> ? files.length : 0,
            'path': entry.path,
            if (json['revertedFromVersion'] != null)
              'revertedFromVersion': json['revertedFromVersion'],
          });
        }
      } on Object {
        items.add({'path': entry.path, 'error': 'invalid_version_record'});
      }
    }
    return items;
  }

  String versionPath(String manifestPath, int version) {
    return '${versionsPrefix(manifestPath)}v${version.toString().padLeft(4, '0')}.json';
  }

  String versionsPrefix(String manifestPath) {
    final slash = manifestPath.lastIndexOf('/');
    if (slash < 0) {
      return '.phone-agent/versions/';
    }
    return '${manifestPath.substring(0, slash)}/versions/';
  }
}

class WebAppProjectSnapshot {
  const WebAppProjectSnapshot({
    required this.projectId,
    required this.artifactId,
    required this.version,
    required this.summary,
    required this.entryPath,
    required this.manifestPath,
    required this.files,
    required this.changedFiles,
    required this.createdAt,
    this.revertedFromVersion,
  });

  final String projectId;
  final String artifactId;
  final int version;
  final String summary;
  final String entryPath;
  final String manifestPath;
  final List<WebAppProjectFileSnapshot> files;
  final List<String> changedFiles;
  final DateTime createdAt;
  final int? revertedFromVersion;

  Map<String, Object?> toJson() => {
    'schema': 'phone-agent.webapp.version.v1',
    'projectId': projectId,
    'artifactId': artifactId,
    'version': version,
    'summary': summary,
    'entry': entryPath,
    'manifestPath': manifestPath,
    'files': files.map((file) => file.toJson()).toList(growable: false),
    'changedFiles': changedFiles,
    'createdAt': createdAt.toIso8601String(),
    if (revertedFromVersion != null) 'revertedFromVersion': revertedFromVersion,
  };

  factory WebAppProjectSnapshot.fromJson(Map<String, Object?> json) {
    final files = json['files'];
    return WebAppProjectSnapshot(
      projectId: json['projectId']! as String,
      artifactId: json['artifactId']! as String,
      version: json['version']! as int,
      summary: json['summary']! as String,
      entryPath: json['entry']! as String,
      manifestPath: json['manifestPath']! as String,
      files: files is List<Object?>
          ? files
                .whereType<Map<String, Object?>>()
                .map(WebAppProjectFileSnapshot.fromJson)
                .toList(growable: false)
          : const [],
      changedFiles:
          (json['changedFiles'] as List<Object?>?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      createdAt: DateTime.parse(json['createdAt']! as String),
      revertedFromVersion: json['revertedFromVersion'] as int?,
    );
  }
}

class WebAppProjectFileSnapshot {
  const WebAppProjectFileSnapshot({required this.path, required this.content});

  final String path;
  final String content;

  Map<String, Object?> toJson() => {
    'path': path,
    'content': content,
    'bytes': utf8.encode(content).length,
    'contentHash': _contentHash(content),
  };

  factory WebAppProjectFileSnapshot.fromJson(Map<String, Object?> json) {
    return WebAppProjectFileSnapshot(
      path: json['path']! as String,
      content: json['content']! as String,
    );
  }
}

String _contentHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
