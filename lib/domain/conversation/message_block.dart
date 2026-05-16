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

  factory MessageBlock.markdown(String text) =>
      MessageBlock(type: MessageBlockType.markdownText, data: {'text': text});

  factory MessageBlock.code(String language, String code) => MessageBlock(
    type: MessageBlockType.codeBlock,
    data: {'language': language, 'code': code},
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
}
