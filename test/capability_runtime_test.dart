import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/capabilities/web_capability_adapter.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/artifacts/artifact.dart';
import 'package:phone_agent/domain/memory/memory.dart';
import 'package:phone_agent/domain/notes/note.dart';
import 'package:phone_agent/domain/notes/note_store.dart';

void main() {
  test('memory_create writes a global memory', () async {
    final runtime = CapabilityRuntime();
    final memories = <AgentMemory>[];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-1',
        name: 'memory_create',
        arguments: {'content': '用户偏好短答案'},
      ),
      workspaceId: 'workspace-a',
      memories: memories,
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'memory.create');
    expect(result.output['ok'], isTrue);
    expect(memories.single.content, '用户偏好短答案');
  });

  test('memory_query returns matching global memories', () async {
    final runtime = CapabilityRuntime();
    final memories = [
      AgentMemory(
        id: 'memory-1',
        content: '用户喜欢简洁回答',
        createdAt: DateTime(2026),
      ),
      AgentMemory(
        id: 'memory-2',
        content: '用户使用 Flutter',
        createdAt: DateTime(2026),
      ),
      AgentMemory(
        id: 'memory-3',
        content: '用户喜欢蓝色主题',
        createdAt: DateTime(2026),
      ),
    ];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-2',
        name: 'memory_query',
        arguments: {'query': '简洁'},
      ),
      workspaceId: 'default',
      memories: memories,
      notes: const [],
      artifacts: const [],
    );

    final items = result.output['items'];
    expect(result.output['ok'], isTrue);
    expect(items, isA<List<Object?>>());
    expect((items! as List<Object?>).length, 1);
  });

  test('memory_delete removes global memories', () async {
    final runtime = CapabilityRuntime();
    final memories = [
      AgentMemory(
        id: 'memory-one',
        content: '第一条记忆',
        createdAt: DateTime(2026),
      ),
      AgentMemory(
        id: 'memory-two',
        content: '第二条记忆',
        createdAt: DateTime(2026),
      ),
    ];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-delete',
        name: 'memory_delete',
        arguments: {'memory_id': 'memory-one'},
      ),
      workspaceId: 'default',
      memories: memories,
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'memory.delete');
    expect(result.output['ok'], isTrue);
    expect(memories.map((memory) => memory.id), ['memory-two']);
  });

  test('memory_delete reports missing memory', () async {
    final runtime = CapabilityRuntime();
    final memories = [
      AgentMemory(
        id: 'memory-one',
        content: '第一条记忆',
        createdAt: DateTime(2026),
      ),
    ];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-delete-hidden',
        name: 'memory_delete',
        arguments: {'memory_id': 'missing-memory'},
      ),
      workspaceId: 'default',
      memories: memories,
      notes: const [],
      artifacts: const [],
    );

    expect(result.output['ok'], isFalse);
    expect(memories.single.id, 'memory-one');
  });

  test('db_note_create writes a workspace note', () async {
    final runtime = CapabilityRuntime();
    final notes = <AgentNote>[];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-note-create',
        name: 'db_note_create',
        arguments: {'title': '会议纪要', 'content': '明天 10 点同步需求。'},
      ),
      workspaceId: 'work',
      memories: const [],
      notes: notes,
      artifacts: const [],
    );

    expect(result.capabilityId, 'db.note.create');
    expect(result.output['ok'], isTrue);
    expect(notes.single.workspaceId, 'work');
    expect(notes.single.title, '会议纪要');
  });

  test('db_note_create persists through note store when provided', () async {
    final runtime = CapabilityRuntime();
    final notes = <AgentNote>[];
    final noteStore = InMemoryAgentNoteStore();

    await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-note-store-create',
        name: 'db_note_create',
        arguments: {'title': '持久化', 'content': '写入 Note Store'},
      ),
      workspaceId: 'work',
      memories: const [],
      notes: notes,
      artifacts: const [],
      noteStore: noteStore,
    );

    final storedNotes = await noteStore.query(
      workspaceId: 'work',
      keyword: 'Note Store',
    );
    expect(storedNotes, hasLength(1));
    expect(storedNotes.single.title, '持久化');
  });

  test('db_note_query only returns current workspace notes', () async {
    final runtime = CapabilityRuntime();
    final notes = [
      AgentNote(
        id: 'note-work',
        workspaceId: 'work',
        title: 'Flutter 需求',
        content: '实现本地 Note',
        createdAt: DateTime(2026),
      ),
      AgentNote(
        id: 'note-study',
        workspaceId: 'study',
        title: 'Flutter 学习',
        content: '看文档',
        createdAt: DateTime(2026),
      ),
    ];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-note-query',
        name: 'db_note_query',
        arguments: {'query': 'Flutter'},
      ),
      workspaceId: 'work',
      memories: const [],
      notes: notes,
      artifacts: const [],
    );

    final rawItems = result.output['items'];
    expect(result.capabilityId, 'db.note.query');
    expect(result.output['ok'], isTrue);
    expect(rawItems, isA<List<Object?>>());
    final items = rawItems! as List<Object?>;
    expect(items.length, 1);
    expect((items.first! as Map<String, Object?>)['id'], 'note-work');
  });

  test('db_note_create validates content', () async {
    final runtime = CapabilityRuntime();
    final notes = <AgentNote>[];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-note-invalid',
        name: 'db_note_create',
        arguments: {'title': '空内容'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: notes,
      artifacts: const [],
    );

    expect(result.capabilityId, 'db.note.create');
    expect(result.output['ok'], isFalse);
    expect(notes, isEmpty);
  });

  test('artifact_create writes a workspace artifact', () async {
    final runtime = CapabilityRuntime();
    final artifacts = <AgentArtifact>[];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-artifact-create',
        name: 'artifact_create',
        arguments: {
          'type': 'report',
          'title': '调研报告',
          'summary': '关于移动端 Agent 架构的结论。',
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: artifacts,
    );

    expect(result.capabilityId, 'artifact.create');
    expect(result.output['ok'], isTrue);
    expect(artifacts.single.workspaceId, 'work');
    expect(artifacts.single.type, ArtifactType.report);
  });

  test('artifact_query only returns current workspace artifacts', () async {
    final runtime = CapabilityRuntime();
    final artifacts = [
      AgentArtifact(
        id: 'artifact-work',
        workspaceId: 'work',
        type: ArtifactType.webApp,
        title: '备忘录 Web App',
        summary: '可运行的小应用',
        createdAt: DateTime(2026),
      ),
      AgentArtifact(
        id: 'artifact-study',
        workspaceId: 'study',
        type: ArtifactType.webApp,
        title: '学习 Web App',
        summary: '学习工具',
        createdAt: DateTime(2026),
      ),
    ];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-artifact-query',
        name: 'artifact_query',
        arguments: {'type': 'web_app', 'query': 'Web App'},
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: artifacts,
    );

    final rawItems = result.output['items'];
    expect(result.capabilityId, 'artifact.query');
    expect(result.output['ok'], isTrue);
    expect(rawItems, isA<List<Object?>>());
    final items = rawItems! as List<Object?>;
    expect(items.length, 1);
    expect((items.first! as Map<String, Object?>)['id'], 'artifact-work');
  });

  test('runtime exposes web tools through the same execute path', () async {
    final runtime = CapabilityRuntime(
      webAdapter: _FakeWebAdapter(
        searchOutput: const {
          'ok': true,
          'results': [
            {'title': 'Result', 'url': 'https://example.com', 'snippet': 'One'},
          ],
        },
        fetchOutput: const {
          'ok': true,
          'url': 'https://example.com',
          'content': 'Example content',
        },
      ),
    );

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-3',
        name: 'web_search',
        arguments: {'query': 'Phone Agent'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'web.search');
    expect(result.output['ok'], isTrue);
  });
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
