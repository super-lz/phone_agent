import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/capabilities/web_capability_adapter.dart';
import 'package:phone_agent/data/models/model_api_key_store.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';
import 'package:phone_agent/features/workbench/controllers/workbench_controller.dart';

void main() {
  test('normal prompt uses configured model', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(contentDelta: '真实'),
          const ChatStreamEvent(contentDelta: '模型'),
          const ChatStreamEvent(contentDelta: '回复'),
        ],
      ]),
    );

    await controller.sendPrompt('你好');

    expect(controller.messages.last.blocks.first.data['text'], '真实模型回复');
  });

  test('next prompt includes earlier conversation context', () async {
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '你好，张三。')],
      [const ChatStreamEvent(contentDelta: '你叫张三。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('我叫张三');
    await controller.sendPrompt('我叫什么？');

    final secondCallMessages = chatClient.capturedMessages[1];
    expect(
      secondCallMessages.any((message) => message['content'] == '我叫张三'),
      isTrue,
    );
    expect(controller.messages.last.blocks.first.data['text'], '你叫张三。');
  });

  test('normal prompt asks for api key when not configured', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore(null),
      chatClient: _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '不会被调用')],
      ]),
    );

    await controller.sendPrompt('你好');

    expect(controller.messages.last.blocks.first.data['title'], '缺少模型 API Key');
  });

  test('model tool call can create memory and continue answer', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-memory-1',
                name: 'memory_create',
                argumentsDelta: '{"content":"喜欢简洁回答"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已记住。')],
      ]),
    );

    await controller.sendPrompt('记住我喜欢简洁回答');

    expect(
      controller.visibleMemories.any((memory) => memory.content == '喜欢简洁回答'),
      isTrue,
    );
    expect(controller.messages.last.blocks.first.data['text'], '已记住。');
  });

  test('model tool call can search web through capability runtime', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      capabilityRuntime: CapabilityRuntime(
        webAdapter: _FakeWebAdapter(
          searchOutput: const {
            'ok': true,
            'results': [
              {
                'title': 'Flutter',
                'url': 'https://flutter.dev',
                'snippet': 'Build apps',
              },
            ],
          },
          fetchOutput: const {},
        ),
      ),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-search-1',
                name: 'web_search',
                argumentsDelta: '{"query":"Flutter"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '找到 Flutter 来源。')],
      ]),
    );

    await controller.sendPrompt('搜索 Flutter 最新信息');

    final toolBlocks = controller.messages
        .expand((message) => message.blocks)
        .where((block) => block.data['capabilityId'] == 'web.search');
    expect(toolBlocks, isNotEmpty);
    expect(
      controller.messages.last.blocks.first.data['text'],
      '找到 Flutter 来源。',
    );
  });

  test('model tool call can create workspace note', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-note-1',
                name: 'db_note_create',
                argumentsDelta: '{"title":"待办","content":"周五前整理需求清单"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已记录到当前工作区。')],
      ]),
    );

    await controller.sendPrompt('记录一个待办：周五前整理需求清单');

    expect(
      controller.workspaceNotes.any(
        (note) => note.title == '待办' && note.content == '周五前整理需求清单',
      ),
      isTrue,
    );
    expect(controller.messages.last.blocks.first.data['text'], '已记录到当前工作区。');
  });

  test('workspace notes are scoped to current workspace', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-work-note',
                name: 'db_note_create',
                argumentsDelta: '{"title":"工作事项","content":"同步 Agent 方案"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已记录。')],
      ]),
    );
    controller.setWorkspace('work');

    await controller.sendPrompt('记录工作事项');

    expect(
      controller.workspaceNotes.any((note) => note.title == '工作事项'),
      isTrue,
    );

    controller.setWorkspace('study');

    expect(
      controller.workspaceNotes.any((note) => note.title == '工作事项'),
      isFalse,
    );
  });

  test('model tool call can create artifact card', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-artifact-1',
                name: 'artifact_create',
                argumentsDelta:
                    '{"type":"report","title":"搜索报告","summary":"可复用的调研结论"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已生成报告。')],
      ]),
    );

    await controller.sendPrompt('生成一份可复用报告');

    expect(
      controller.workspaceArtifacts.any((artifact) => artifact.title == '搜索报告'),
      isTrue,
    );
    final artifactCards = controller.messages
        .expand((message) => message.blocks)
        .where((block) => block.type == MessageBlockType.artifactCard);
    expect(artifactCards, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '已生成报告。');
  });

  test('agent loop can continue beyond three tool rounds', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [_toolCallRound(0, 'call-memory-query-1')],
        [_toolCallRound(0, 'call-memory-query-2')],
        [_toolCallRound(0, 'call-memory-query-3')],
        [_toolCallRound(0, 'call-memory-query-4')],
        [const ChatStreamEvent(contentDelta: '已经完成多轮工具处理。')],
      ]),
    );

    await controller.sendPrompt('连续查询记忆直到完成');

    final memoryQueryBlocks = controller.messages
        .expand((message) => message.blocks)
        .where((block) => block.data['capabilityId'] == 'memory.query');
    expect(memoryQueryBlocks.length, 4);
    expect(controller.messages.last.blocks.first.data['text'], '已经完成多轮工具处理。');
  });

  test('user can create update and delete visible memory', () {
    final controller = WorkbenchController(apiKeyStore: _FakeApiKeyStore(null));

    controller.createMemory(content: '长期记住 Flutter 项目');
    final created = controller.visibleMemories.last;

    controller.updateMemory(
      memoryId: created.id,
      content: '长期记住 Flutter 项目和 Dart',
    );

    expect(
      controller.visibleMemories.any(
        (memory) =>
            memory.id == created.id &&
            memory.content == '长期记住 Flutter 项目和 Dart',
      ),
      isTrue,
    );

    controller.deleteMemory(created.id);

    expect(
      controller.visibleMemories.any((memory) => memory.id == created.id),
      isFalse,
    );
  });

  test('memory remains visible across workspace switches', () {
    final controller = WorkbenchController(apiKeyStore: _FakeApiKeyStore(null));

    controller.createWorkspace();
    controller.createMemory(content: '跨工作区都应该记住');

    controller.setWorkspace('default');

    expect(
      controller.visibleMemories.any((memory) => memory.content == '跨工作区都应该记住'),
      isTrue,
    );
  });
}

ChatStreamEvent _toolCallRound(int index, String id) {
  return ChatStreamEvent(
    toolCallDeltas: [
      ToolCallDelta(
        index: index,
        id: id,
        name: 'memory_query',
        argumentsDelta: '{"query":"偏好"}',
      ),
    ],
  );
}

class _FakeApiKeyStore extends ModelApiKeyStore {
  _FakeApiKeyStore(this.apiKey);

  final String? apiKey;

  @override
  Future<String?> readApiKey(String providerId) async {
    return apiKey;
  }
}

class _FakeWebAdapter extends WebCapabilityAdapter {
  _FakeWebAdapter({required this.searchOutput, required this.fetchOutput});

  final Map<String, Object?> searchOutput;
  final Map<String, Object?> fetchOutput;

  @override
  Future<Map<String, Object?>> search(
    Map<String, Object?> arguments, {
    String? apiKey,
  }) async {
    return searchOutput;
  }

  @override
  Future<Map<String, Object?>> fetch(
    Map<String, Object?> arguments, {
    String? apiKey,
  }) async {
    return fetchOutput;
  }
}

class _FakeChatClient extends OpenAiCompatibleChatClient {
  _FakeChatClient(this.rounds);

  final List<List<ChatStreamEvent>> rounds;
  final List<List<Map<String, Object?>>> capturedMessages = [];
  int callCount = 0;

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    capturedMessages.add(messages);
    final events = rounds[callCount];
    callCount += 1;
    for (final event in events) {
      yield event;
    }
  }
}
