import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/capabilities/native_capability_adapter.dart';
import 'package:phone_agent/data/capabilities/web_capability_adapter.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/artifacts/artifact.dart';
import 'package:phone_agent/domain/capabilities/capability.dart';
import 'package:phone_agent/domain/files/app_file_store.dart';
import 'package:phone_agent/domain/memory/memory.dart';
import 'package:phone_agent/domain/notes/note.dart';
import 'package:phone_agent/domain/notes/note_store.dart';
import 'package:phone_agent/domain/permissions/permission_policy.dart';
import 'package:phone_agent/domain/workspace/workspace.dart';

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

  test(
    'permission policy blocks high risk capability before execution',
    () async {
      final runtime = CapabilityRuntime();
      final memories = [
        AgentMemory(
          id: 'memory-one',
          content: '不能静默删除',
          createdAt: DateTime(2026),
        ),
      ];

      final result = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-delete-needs-confirmation',
          name: 'memory_delete',
          arguments: {'memory_id': 'memory-one'},
        ),
        workspaceId: 'default',
        memories: memories,
        notes: const [],
        artifacts: const [],
        capabilities: const [
          CapabilityDefinition(
            id: 'memory.delete',
            description: 'delete memory',
            inputSchema: {'type': 'object'},
            outputSchema: {'type': 'object'},
            risk: CapabilityRisk.high,
            requiredPermissions: [],
            adapter: CapabilityAdapter.memory,
          ),
        ],
        permissionMode: PermissionMode.defaultMode,
      );

      expect(result.capabilityId, 'memory.delete');
      expect(result.output['ok'], isFalse);
      expect(result.output['error'], 'permission_confirmation_required');
      expect(memories.single.id, 'memory-one');
    },
  );

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

  test(
    'file_write_app_file and file_read_app_file use workspace file store',
    () async {
      final runtime = CapabilityRuntime();
      final fileStore = InMemoryAppFileStore();

      final writeResult = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-file-write',
          name: 'file_write_app_file',
          arguments: {
            'path': 'reports/summary.md',
            'content': '# 总结\nPhone Agent 文件能力。',
          },
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );

      final readResult = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-file-read',
          name: 'file_read_app_file',
          arguments: {'path': 'reports/summary.md'},
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );

      expect(writeResult.capabilityId, 'file.write_app_file');
      expect(writeResult.output['ok'], isTrue);
      expect(readResult.capabilityId, 'file.read_app_file');
      expect(readResult.output['ok'], isTrue);
      expect(readResult.output['content'], contains('Phone Agent 文件能力'));
      final files = await fileStore.listFiles(workspaceId: 'work');
      expect(files.single.path, 'reports/summary.md');
      expect(files.single.bytes, greaterThan(0));
    },
  );

  test('file_apply_text_patch updates an existing workspace file', () async {
    final runtime = CapabilityRuntime();
    final fileStore = InMemoryAppFileStore();

    await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-file-write-before-patch',
        name: 'file_write_app_file',
        arguments: {
          'path': 'games/gold-miner/index.html',
          'content': '<h1>黄金矿工</h1><p>旧版玩法</p>',
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );
    final patchResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-file-patch',
        name: 'file_apply_text_patch',
        arguments: {
          'path': 'games/gold-miner/index.html',
          'old_text': '旧版玩法',
          'new_text': '新版玩法',
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );
    final readResult = await fileStore.readText(
      workspaceId: 'work',
      path: 'games/gold-miner/index.html',
      maxChars: 12000,
    );

    expect(patchResult.capabilityId, 'file.apply_text_patch');
    expect(patchResult.output['ok'], isTrue);
    expect(readResult.content, contains('新版玩法'));
    expect(readResult.content, isNot(contains('旧版玩法')));
  });

  test(
    'project_create_web_app writes files and creates web app artifact',
    () async {
      final runtime = CapabilityRuntime();
      final fileStore = InMemoryAppFileStore();
      final artifacts = <AgentArtifact>[];

      final result = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-project-create',
          name: 'project_create_web_app',
          arguments: {
            'title': '黄金矿工小游戏',
            'summary': '一个可维护的本地 HTML 小游戏。',
            'entry_path': 'games/gold-miner/index.html',
            'files': [
              {
                'path': 'games/gold-miner/index.html',
                'content': '<!doctype html><html><body>黄金矿工</body></html>',
              },
            ],
          },
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: artifacts,
        fileStore: fileStore,
      );
      final storedFile = await fileStore.readText(
        workspaceId: 'work',
        path: 'games/gold-miner/index.html',
        maxChars: 12000,
      );

      expect(result.capabilityId, 'project.create_web_app');
      expect(result.output['ok'], isTrue);
      expect(result.output['artifactId'], artifacts.single.id);
      expect(artifacts.single.type, ArtifactType.webApp);
      expect(artifacts.single.metadata['entry'], 'games/gold-miner/index.html');
      expect(artifacts.single.metadata['html'], contains('黄金矿工'));
      expect(
        artifacts.single.metadata['runtimeLogPath'],
        'games/gold-miner/.phone-agent/runtime.log',
      );
      expect(storedFile.content, contains('黄金矿工'));
    },
  );

  test('file_read_app_file does not leak files across workspaces', () async {
    final runtime = CapabilityRuntime();
    final fileStore = InMemoryAppFileStore();

    await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-file-write-a',
        name: 'file_write_app_file',
        arguments: {'path': 'private.txt', 'content': 'workspace a secret'},
      ),
      workspaceId: 'workspace-a',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );
    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-file-read-b',
        name: 'file_read_app_file',
        arguments: {'path': 'private.txt'},
      ),
      workspaceId: 'workspace-b',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );

    expect(result.output['ok'], isFalse);
    expect(result.output['error'], 'not_found');
  });

  test('file capability rejects path traversal', () async {
    final runtime = CapabilityRuntime();
    final fileStore = InMemoryAppFileStore();

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-file-traversal',
        name: 'file_write_app_file',
        arguments: {'path': '../escape.txt', 'content': 'bad'},
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );

    expect(result.output['ok'], isFalse);
    expect(result.output['error'], 'invalid_path');
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

  test('artifact_create writes runnable web app html', () async {
    final runtime = CapabilityRuntime();
    final artifacts = <AgentArtifact>[];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-webapp-create',
        name: 'artifact_create',
        arguments: {
          'type': 'web_app',
          'title': '美食网页',
          'summary': '带样式的本地网页',
          'content_html':
              '<main><style>body{background:#fafafa}</style><h1>美食</h1></main>',
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: artifacts,
    );

    expect(result.capabilityId, 'artifact.create');
    expect(result.output['ok'], isTrue);
    expect(artifacts.single.type, ArtifactType.webApp);
    expect(artifacts.single.metadata['html'], contains('<style>'));
  });

  test('artifact_create rejects web app without html', () async {
    final runtime = CapabilityRuntime();
    final artifacts = <AgentArtifact>[];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-webapp-missing-html',
        name: 'artifact_create',
        arguments: {'type': 'web_app', 'title': '空网页', 'summary': '没有真实页面内容'},
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: artifacts,
    );

    expect(result.capabilityId, 'artifact.create');
    expect(result.output['ok'], isFalse);
    expect(result.output['error'], 'web_app_html is required');
    expect(artifacts, isEmpty);
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

  test('workspace_create adds and activates a workspace', () async {
    final runtime = CapabilityRuntime();
    final workspaces = <AgentWorkspace>[
      AgentWorkspace(
        id: 'default',
        name: '默认',
        description: '默认工作区',
        createdAt: DateTime(2026),
      ),
    ];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-workspace-create',
        name: 'workspace_create',
        arguments: {'name': '生活', 'description': '生活事项'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
      workspaces: workspaces,
    );

    expect(result.capabilityId, 'workspace.create');
    expect(result.output['ok'], isTrue);
    expect(workspaces.map((workspace) => workspace.name), contains('生活'));
    expect(result.output['activeWorkspaceId'], workspaces.last.id);
  });

  test('workspace_switch finds workspace by name', () async {
    final runtime = CapabilityRuntime();
    final workspaces = <AgentWorkspace>[
      AgentWorkspace(
        id: 'default',
        name: '默认',
        description: '默认工作区',
        createdAt: DateTime(2026),
      ),
      AgentWorkspace(
        id: 'work',
        name: '工作',
        description: '工作事项',
        createdAt: DateTime(2026),
      ),
    ];

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-workspace-switch',
        name: 'workspace_switch',
        arguments: {'name': '工作'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
      workspaces: workspaces,
    );

    expect(result.capabilityId, 'workspace.switch');
    expect(result.output['ok'], isTrue);
    expect(result.output['activeWorkspaceId'], 'work');
  });

  test('workspace_switch reports missing workspace', () async {
    final runtime = CapabilityRuntime();

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-workspace-missing',
        name: 'workspace_switch',
        arguments: {'name': '不存在'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
      workspaces: const [],
    );

    expect(result.capabilityId, 'workspace.switch');
    expect(result.output['ok'], isFalse);
    expect(result.output['error'], 'workspace not found');
  });

  test(
    'runtime exposes native device info through the same execute path',
    () async {
      final runtime = CapabilityRuntime(
        nativeAdapter: _FakeNativeAdapter(
          deviceInfoOutput: const {
            'ok': true,
            'device': {'platform': 'android'},
          },
        ),
      );

      final result = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-device-info',
          name: 'device_info',
          arguments: {},
        ),
        workspaceId: 'default',
        memories: const [],
        notes: const [],
        artifacts: const [],
      );

      expect(result.capabilityId, 'device.info');
      expect(result.output['ok'], isTrue);
      expect(result.output['device'], isA<Map<String, Object?>>());
    },
  );

  test('runtime exposes current device time through native adapter', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-time',
        name: 'time_get_current',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'time.get_current');
    expect(result.output['ok'], isTrue);
    expect(result.output['localIso'], '2026-05-18T10:00:00.000');
    expect(result.output['timeZoneOffsetMinutes'], 480);
  });

  test('runtime can read and write clipboard through native adapter', () async {
    final adapter = _FakeNativeAdapter();
    final runtime = CapabilityRuntime(nativeAdapter: adapter);

    final writeResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-clipboard-write',
        name: 'clipboard_write',
        arguments: {'text': '复制这段文字'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final readResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-clipboard-read',
        name: 'clipboard_read',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(writeResult.capabilityId, 'clipboard.write');
    expect(writeResult.output['ok'], isTrue);
    expect(readResult.capabilityId, 'clipboard.read');
    expect(readResult.output['text'], '复制这段文字');
  });

  test('runtime exposes current location through native adapter', () async {
    final runtime = CapabilityRuntime(
      nativeAdapter: _FakeNativeAdapter(
        locationOutput: const {
          'ok': true,
          'latitude': 31.2304,
          'longitude': 121.4737,
          'accuracy': 12.0,
        },
      ),
    );

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-location',
        name: 'location_get_current',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'location.get_current');
    expect(result.output['ok'], isTrue);
    expect(result.output['latitude'], 31.2304);
  });

  test('runtime returns structured location denial', () async {
    final runtime = CapabilityRuntime(
      nativeAdapter: _FakeNativeAdapter(
        locationOutput: const {
          'ok': false,
          'error': 'permission_denied',
          'detail': 'location permission denied',
        },
      ),
    );

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-location-denied',
        name: 'location_get_current',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'location.get_current');
    expect(result.output['ok'], isFalse);
    expect(result.output['error'], 'permission_denied');
  });

  test('runtime can schedule notification through native adapter', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-notification',
        name: 'notification_schedule',
        arguments: {
          'title': '提醒',
          'body': '整理 Phone Agent 需求',
          'delay_seconds': 60,
        },
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'notification.schedule');
    expect(result.output['ok'], isTrue);
    expect(result.output['title'], '提醒');
  });

  test('notification_schedule validates required body', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-notification-invalid',
        name: 'notification_schedule',
        arguments: {'title': '提醒'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'notification.schedule');
    expect(result.output['ok'], isFalse);
    expect(result.output['error'], 'body is required');
  });

  test('runtime can create calendar event through native adapter', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-calendar',
        name: 'calendar_event_create',
        arguments: {
          'title': '需求同步',
          'description': '确认 Phone Agent 日历能力',
          'location': '线上会议',
          'start_at': '2026-05-18T10:00:00+08:00',
          'duration_minutes': 30,
        },
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'calendar.event.create');
    expect(result.output['ok'], isTrue);
    expect(result.output['title'], '需求同步');
    expect(result.output['requiresUserConfirmation'], isTrue);
  });

  test('calendar_event_create validates required start_at', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-calendar-invalid',
        name: 'calendar_event_create',
        arguments: {'title': '需求同步'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(result.capabilityId, 'calendar.event.create');
    expect(result.output['ok'], isFalse);
    expect(result.output['error'], 'invalid start_at');
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

class _FakeNativeAdapter extends NativeCapabilityAdapter {
  _FakeNativeAdapter({
    this.deviceInfoOutput = const {'ok': true},
    this.locationOutput = const {'ok': true},
  });

  final Map<String, Object?> deviceInfoOutput;
  final Map<String, Object?> locationOutput;
  String _clipboardText = '';

  @override
  Future<Map<String, Object?>> getDeviceInfo() async {
    return deviceInfoOutput;
  }

  @override
  Future<Map<String, Object?>> getCurrentTime() async {
    return {
      'ok': true,
      'localIso': DateTime(2026, 5, 18, 10).toIso8601String(),
      'utcIso': DateTime.utc(2026, 5, 18, 2).toIso8601String(),
      'epochMilliseconds': DateTime(2026, 5, 18, 10).millisecondsSinceEpoch,
      'timeZoneName': 'CST',
      'timeZoneOffsetMinutes': 480,
      'weekday': 1,
    };
  }

  @override
  Future<Map<String, Object?>> readClipboard() async {
    return {
      'ok': true,
      'hasText': _clipboardText.isNotEmpty,
      'text': _clipboardText,
    };
  }

  @override
  Future<Map<String, Object?>> writeClipboard(String text) async {
    _clipboardText = text;
    return {'ok': true, 'length': text.length};
  }

  @override
  Future<Map<String, Object?>> getCurrentLocation() async {
    return locationOutput;
  }

  @override
  Future<Map<String, Object?>> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    return {
      'ok': true,
      'notificationId': 1,
      'title': title,
      'body': body,
      'scheduledAt': scheduledAt.toIso8601String(),
    };
  }

  @override
  Future<Map<String, Object?>> createCalendarEvent({
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool allDay = false,
  }) async {
    return {
      'ok': true,
      'title': title,
      'description': description,
      'location': location,
      'startsAt': startsAt.toIso8601String(),
      'endsAt': endsAt.toIso8601String(),
      'allDay': allDay,
      'requiresUserConfirmation': true,
    };
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
