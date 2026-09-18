import '../conversation/message_block.dart';

class PendingAgentRun {
  const PendingAgentRun({
    required this.id,
    required this.workspaceId,
    required this.userPrompt,
    required this.modelPrompt,
    required this.priorMessages,
    required this.startedAt,
    this.actionLedgerVersion = 1,
    this.actionLedger = const [],
    this.protocolVersion = 1,
    this.modelMessages = const [],
    this.toolSchema = const [],
    this.toolIndex = '',
    this.modelStep = 0,
  });

  final String id;
  final String workspaceId;
  final String userPrompt;
  final Object modelPrompt;
  final List<AgentMessage> priorMessages;
  final DateTime startedAt;
  final int actionLedgerVersion;
  final List<Map<String, Object?>> actionLedger;
  final int protocolVersion;

  /// Provider protocol state, kept apart from the UI's MessageBlock history.
  final List<Map<String, Object?>> modelMessages;
  final List<Map<String, Object?>> toolSchema;
  final String toolIndex;
  final int modelStep;

  PendingAgentRun copyWith({
    int? actionLedgerVersion,
    List<Map<String, Object?>>? actionLedger,
    int? protocolVersion,
    List<Map<String, Object?>>? modelMessages,
    List<Map<String, Object?>>? toolSchema,
    String? toolIndex,
    int? modelStep,
  }) => PendingAgentRun(
    id: id,
    workspaceId: workspaceId,
    userPrompt: userPrompt,
    modelPrompt: modelPrompt,
    priorMessages: priorMessages,
    startedAt: startedAt,
    actionLedgerVersion: actionLedgerVersion ?? this.actionLedgerVersion,
    actionLedger: actionLedger ?? this.actionLedger,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    modelMessages: modelMessages ?? this.modelMessages,
    toolSchema: toolSchema ?? this.toolSchema,
    toolIndex: toolIndex ?? this.toolIndex,
    modelStep: modelStep ?? this.modelStep,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'userPrompt': userPrompt,
    'modelPrompt': modelPrompt,
    'priorMessages': priorMessages.map(_messageToJson).toList(growable: false),
    'startedAt': startedAt.toIso8601String(),
    'actionLedgerVersion': actionLedgerVersion,
    'actionLedger': actionLedger,
    'protocolVersion': protocolVersion,
    'modelMessages': modelMessages,
    'toolSchema': toolSchema,
    'toolIndex': toolIndex,
    'modelStep': modelStep,
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
      actionLedgerVersion: json['actionLedgerVersion'] is int
          ? json['actionLedgerVersion']! as int
          : 0,
      actionLedger: _actionLedgerFromJson(json['actionLedger']),
      protocolVersion: json['protocolVersion'] is int
          ? json['protocolVersion']! as int
          : 0,
      modelMessages: _mapListFromJson(json['modelMessages']),
      toolSchema: _mapListFromJson(json['toolSchema']),
      toolIndex: json['toolIndex'] as String? ?? '',
      modelStep: json['modelStep'] is int ? json['modelStep']! as int : 0,
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

  static Map<String, Object?> _blockToJson(MessageBlock block) =>
      block.toJson();

  static MessageBlock _blockFromJson(Object? value) =>
      MessageBlock.fromJson(value);

  static Map<String, Object?> _objectMap(Object? value) {
    final map = value as Map<Object?, Object?>;
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Map<String, Object?>> _actionLedgerFromJson(Object? value) {
    return _mapListFromJson(value);
  }

  static List<Map<String, Object?>> _mapListFromJson(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) {
          return item.map((key, value) => MapEntry(key.toString(), value));
        })
        .toList(growable: false);
  }
}
