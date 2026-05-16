enum ArtifactType {
  document,
  image,
  table,
  report,
  note,
  taskList,
  file,
  webApp,
}

class AgentArtifact {
  const AgentArtifact({
    required this.id,
    required this.workspaceId,
    required this.type,
    required this.title,
    required this.summary,
    required this.createdAt,
    this.uri,
    this.metadata = const {},
  });

  final String id;
  final String workspaceId;
  final ArtifactType type;
  final String title;
  final String summary;
  final DateTime createdAt;
  final Uri? uri;
  final Map<String, Object?> metadata;
}

extension ArtifactTypeLabel on ArtifactType {
  String get label {
    switch (this) {
      case ArtifactType.document:
        return '文档';
      case ArtifactType.image:
        return '图片';
      case ArtifactType.table:
        return '表格';
      case ArtifactType.report:
        return '报告';
      case ArtifactType.note:
        return '笔记';
      case ArtifactType.taskList:
        return '任务清单';
      case ArtifactType.file:
        return '文件';
      case ArtifactType.webApp:
        return 'Web App';
    }
  }
}
