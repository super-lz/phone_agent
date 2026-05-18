import '../../../domain/conversation/message_block.dart';

List<AgentMessage> coalesceAssistantMessages(List<AgentMessage> messages) {
  final displayMessages = <AgentMessage>[];
  for (final message in messages) {
    final previous = displayMessages.isEmpty ? null : displayMessages.last;
    if (message.role == MessageRole.assistant &&
        previous?.role == MessageRole.assistant) {
      displayMessages[displayMessages.length - 1] = AgentMessage(
        id: '${previous!.id}+${message.id}',
        role: previous.role,
        createdAt: previous.createdAt,
        blocks: [...previous.blocks, ...message.blocks],
      );
      continue;
    }
    displayMessages.add(message);
  }
  return displayMessages;
}
