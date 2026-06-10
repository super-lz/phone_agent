import '../conversation/message_block.dart';

class PendingAgentRun {
  const PendingAgentRun({
    required this.id,
    required this.workspaceId,
    required this.userPrompt,
    required this.modelPrompt,
    required this.priorMessages,
    required this.startedAt,
  });

  final String id;
  final String workspaceId;
  final String userPrompt;
  final Object modelPrompt;
  final List<AgentMessage> priorMessages;
  final DateTime startedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'userPrompt': userPrompt,
    'modelPrompt': modelPrompt,
    'priorMessages': priorMessages.map(_messageToJson).toList(growable: false),
    'startedAt': startedAt.toIso8601String(),
  };

  static PendingAgentRun fromJson(Map<String, Object?> json) {
    final priorMessages = json['priorMessages'];
    return PendingAgentRun(
      id: json['id']! as String,
      workspaceId: json['workspaceId']! as String,
      userPrompt: json['userPrompt']! as String,
      modelPrompt: json['modelPrompt']!,
      priorMessages: priorMessages is Iterable<Object?>
          ? priorMessages.map(_messageFromJson).toList(growable: false)
          : const [],
      startedAt: DateTime.parse(json['startedAt']! as String),
    );
  }

  static Map<String, Object?> _messageToJson(AgentMessage message) => {
    'id': message.id,
    'role': message.role.name,
    'createdAt': message.createdAt.toIso8601String(),
    'blocks': message.blocks.map(_blockToJson).toList(growable: false),
  };

  static AgentMessage _messageFromJson(Object? value) {
    final json = _objectMap(value);
    final blocks = json['blocks'];
    return AgentMessage(
      id: json['id']! as String,
      role: MessageRole.values.byName(json['role']! as String),
      createdAt: DateTime.parse(json['createdAt']! as String),
      blocks: blocks is Iterable<Object?>
          ? blocks.map(_blockFromJson).toList(growable: false)
          : const [],
    );
  }

  static Map<String, Object?> _blockToJson(MessageBlock block) => {
    'type': block.type.name,
    'data': block.data,
  };

  static MessageBlock _blockFromJson(Object? value) {
    final json = _objectMap(value);
    return MessageBlock(
      type: MessageBlockType.values.byName(json['type']! as String),
      data: _objectMap(json['data']),
    );
  }

  static Map<String, Object?> _objectMap(Object? value) {
    final map = value as Map<Object?, Object?>;
    return map.map((key, value) => MapEntry(key.toString(), value));
  }
}
