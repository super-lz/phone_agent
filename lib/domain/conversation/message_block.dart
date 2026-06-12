enum MessageRole { user, assistant, system }

enum MessageBlockType {
  markdownText,
  codeBlock,
  image,
  fileAttachment,
  toolCall,
  toolResult,
  approvalRequest,
  taskProgress,
  todoList,
  citation,
  artifactCard,
  webAppCard,
  errorCard,
}

class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.blocks,
  });

  final String id;
  final MessageRole role;
  final DateTime createdAt;
  final List<MessageBlock> blocks;
}

class MessageBlock {
  const MessageBlock({required this.type, required this.data});

  final MessageBlockType type;
  final Map<String, Object?> data;
  static const _jsonMarker = '__messageBlock';

  Map<String, Object?> toJson() => {
    _jsonMarker: true,
    'type': type.name,
    'data': _jsonValue(data),
  };

  static MessageBlock fromJson(Object? value) {
    final json = _objectMap(value);
    return MessageBlock(
      type: MessageBlockType.values.byName(json['type']! as String),
      data: _objectMap(_decodeJsonValue(json['data'])),
    );
  }

  static MessageBlock? tryFromJson(Object? value) {
    if (value is MessageBlock) {
      return value;
    }
    try {
      return fromJson(value);
    } on Object {
      return null;
    }
  }

  factory MessageBlock.markdown(String text) =>
      MessageBlock(type: MessageBlockType.markdownText, data: {'text': text});

  factory MessageBlock.intermediateMarkdown(String text) => MessageBlock(
    type: MessageBlockType.markdownText,
    data: {'text': text, 'intermediate': true},
  );

  factory MessageBlock.code(String language, String code) => MessageBlock(
    type: MessageBlockType.codeBlock,
    data: {'language': language, 'code': code},
  );

  factory MessageBlock.image({
    required String name,
    required String uri,
    int? bytes,
    String? mimeType,
  }) => MessageBlock(
    type: MessageBlockType.image,
    data: {
      'name': name,
      'uri': uri,
      'bytes': ?bytes,
      if (mimeType != null && mimeType.isNotEmpty) 'mimeType': mimeType,
    },
  );

  factory MessageBlock.fileAttachment({
    required String name,
    required String uri,
    int? bytes,
    String? extension,
  }) => MessageBlock(
    type: MessageBlockType.fileAttachment,
    data: {
      'name': name,
      'uri': uri,
      'bytes': ?bytes,
      if (extension != null && extension.isNotEmpty) 'extension': extension,
    },
  );

  factory MessageBlock.toolCall(
    String capabilityId,
    Map<String, Object?> input,
  ) => MessageBlock(
    type: MessageBlockType.toolCall,
    data: {'capabilityId': capabilityId, 'input': input},
  );

  factory MessageBlock.toolResult(
    String capabilityId,
    Map<String, Object?> output,
  ) => MessageBlock(
    type: MessageBlockType.toolResult,
    data: {'capabilityId': capabilityId, 'output': output},
  );

  factory MessageBlock.approvalRequest({
    required String requestId,
    required String toolName,
    required String capabilityId,
    required String workspaceId,
    required Map<String, Object?> input,
    required String detail,
    String? userPrompt,
  }) => MessageBlock(
    type: MessageBlockType.approvalRequest,
    data: {
      'requestId': requestId,
      'toolName': toolName,
      'capabilityId': capabilityId,
      'workspaceId': workspaceId,
      'input': input,
      'detail': detail,
      if (userPrompt != null && userPrompt.trim().isNotEmpty)
        'userPrompt': userPrompt.trim(),
      'status': 'pending',
    },
  );

  factory MessageBlock.artifactCard(String artifactId, String title) =>
      MessageBlock(
        type: MessageBlockType.artifactCard,
        data: {'artifactId': artifactId, 'title': title},
      );

  factory MessageBlock.webAppCard(String artifactId, String title) =>
      MessageBlock(
        type: MessageBlockType.webAppCard,
        data: {'artifactId': artifactId, 'title': title},
      );

  factory MessageBlock.todoList(List<String> items) =>
      MessageBlock(type: MessageBlockType.todoList, data: {'items': items});

  factory MessageBlock.error(String title, String detail) => MessageBlock(
    type: MessageBlockType.errorCard,
    data: {'title': title, 'detail': detail},
  );

  static List<String> stringList(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    return value.whereType<String>().toList(growable: false);
  }

  static Object? _jsonValue(Object? value) {
    if (value is MessageBlock) {
      return value.toJson();
    }
    if (value is Map<Object?, Object?>) {
      return value.map((key, value) {
        return MapEntry(key.toString(), _jsonValue(value));
      });
    }
    if (value is Iterable<Object?>) {
      return value.map(_jsonValue).toList(growable: false);
    }
    return value;
  }

  static Object? _decodeJsonValue(Object? value) {
    if (value is Iterable<Object?>) {
      return value.map(_decodeJsonValue).toList(growable: false);
    }
    if (value is Map<Object?, Object?>) {
      if (_isMarkedMessageBlock(value)) {
        return fromJson(value);
      }
      return value.map((key, value) {
        return MapEntry(key.toString(), _decodeJsonValue(value));
      });
    }
    return value;
  }

  static bool _isMarkedMessageBlock(Map<Object?, Object?> value) {
    if (value[_jsonMarker] != true ||
        !value.containsKey('type') ||
        value['data'] is! Map<Object?, Object?>) {
      return false;
    }
    final typeName = value['type'];
    if (typeName is! String) {
      return false;
    }
    return MessageBlockType.values.any((type) => type.name == typeName);
  }

  static Map<String, Object?> _objectMap(Object? value) {
    final map = value as Map<Object?, Object?>;
    return map.map((key, value) => MapEntry(key.toString(), value));
  }
}
