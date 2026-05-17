class AgentMemory {
  const AgentMemory({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String content;
  final DateTime createdAt;

  AgentMemory copyWith({String? content}) {
    return AgentMemory(
      id: id,
      content: content ?? this.content,
      createdAt: createdAt,
    );
  }
}
