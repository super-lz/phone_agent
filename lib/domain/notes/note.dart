class AgentNote {
  const AgentNote({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String title;
  final String content;
  final DateTime createdAt;
}
