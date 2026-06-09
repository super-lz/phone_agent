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

  test('file_read_app_file can return a line range', () async {
    final runtime = CapabilityRuntime();
    final fileStore = InMemoryAppFileStore();
    await fileStore.writeText(
      workspaceId: 'work',
      path: 'apps/demo/app.js',
      content: 'const a = 1;\nfunction broken() {\n  return "bug";\n}\n',
      overwrite: true,
    );

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-file-read-range',
        name: 'file_read_app_file',
        arguments: {
          'path': 'apps/demo/app.js',
          'start_line': 2,
          'line_count': 2,
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );

    expect(result.capabilityId, 'file.read_app_file');
    expect(result.output['ok'], isTrue);
    expect(result.output['lineStart'], 2);
    expect(result.output['lineEnd'], 3);
    expect(result.output['content'], 'function broken() {\n  return "bug";');
  });

  test('file_search_app_files returns line-numbered snippets', () async {
    final runtime = CapabilityRuntime();
    final fileStore = InMemoryAppFileStore();
    await fileStore.writeText(
      workspaceId: 'work',
      path: 'apps/demo/app.js',
      content: 'const ok = true;\nconsole.error("broken state");\n',
      overwrite: true,
    );
    await fileStore.writeText(
      workspaceId: 'work',
      path: 'notes/todo.md',
      content: 'broken outside project',
      overwrite: true,
    );

    final result = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-file-search',
        name: 'file_search_app_files',
        arguments: {
          'query': 'broken',
          'path_prefix': 'apps/demo',
          'context_lines': 1,
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );
    final matches = result.output['matches']! as List<Object?>;
    final first = matches.single! as Map<Object?, Object?>;

    expect(result.capabilityId, 'file.search_app_files');
    expect(result.output['ok'], isTrue);
    expect(first['path'], 'apps/demo/app.js');
    expect(first['lineNumber'], 2);
    expect(first['snippet'], contains('console.error'));
  });

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
      expect(
        artifacts.single.metadata['manifestPath'],
        'games/gold-miner/.phone-agent/manifest.json',
      );
      expect(storedFile.content, contains('黄金矿工'));
      expect(result.output['version'], 1);
      expect(artifacts.single.metadata['currentVersion'], 1);
      final manifest = await fileStore.readText(
        workspaceId: 'work',
        path: 'games/gold-miner/.phone-agent/manifest.json',
        maxChars: 12000,
      );
      expect(manifest.content, contains('"schema": "phone-agent.webapp.v1"'));
      expect(
        manifest.content,
        contains('"entry": "games/gold-miner/index.html"'),
      );
      final version = await fileStore.readText(
        workspaceId: 'work',
        path: 'games/gold-miner/.phone-agent/versions/v0001.json',
        maxChars: 12000,
      );
      expect(version.content, contains('"version": 1'));
    },
  );

  test(
    'project_update_web_app versions and reverts existing artifact',
    () async {
      final runtime = CapabilityRuntime();
      final fileStore = InMemoryAppFileStore();
      final artifacts = <AgentArtifact>[];

      final createResult = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-project-create-versioned',
          name: 'project_create_web_app',
          arguments: {
            'title': '备忘录应用',
            'summary': '一个可维护的备忘录 Web App。',
            'entry_path': 'apps/memo/index.html',
            'files': [
              {
                'path': 'apps/memo/index.html',
                'content': '<!doctype html><html><body>旧按钮</body></html>',
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
      final artifactId = createResult.output['artifactId']! as String;

      final updateResult = await runtime.execute(
        toolCall: ToolCallRequest(
          id: 'call-project-update',
          name: 'project_update_web_app',
          arguments: {
            'artifact_id': artifactId,
            'summary': '修复按钮文案',
            'patches': const [
              {
                'path': 'apps/memo/index.html',
                'old_text': '旧按钮',
                'new_text': '新按钮',
              },
            ],
            'files': const [
              {
                'path': 'apps/memo/styles.css',
                'content': 'body { color: #169af3; }',
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

      expect(updateResult.capabilityId, 'project.update_web_app');
      expect(updateResult.output['ok'], isTrue);
      expect(updateResult.output['artifactId'], artifactId);
      expect(updateResult.output['type'], 'webApp');
      expect(updateResult.output['title'], '备忘录应用');
      expect(updateResult.output['version'], 2);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.id, artifactId);
      expect(artifacts.single.metadata['currentVersion'], 2);
      expect(artifacts.single.metadata['html'], contains('新按钮'));

      final updatedHtml = await fileStore.readText(
        workspaceId: 'work',
        path: 'apps/memo/index.html',
        maxChars: 12000,
      );
      expect(updatedHtml.content, contains('新按钮'));

      final historyResult = await runtime.execute(
        toolCall: ToolCallRequest(
          id: 'call-project-history',
          name: 'project_version_history',
          arguments: {'artifact_id': artifactId},
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: artifacts,
        fileStore: fileStore,
      );
      final items = historyResult.output['items']! as List<Object?>;
      expect(historyResult.output['ok'], isTrue);
      expect(items, hasLength(2));

      final revertResult = await runtime.execute(
        toolCall: ToolCallRequest(
          id: 'call-project-revert',
          name: 'project_revert_web_app',
          arguments: {'artifact_id': artifactId, 'version': 1},
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: artifacts,
        fileStore: fileStore,
      );

      expect(revertResult.capabilityId, 'project.revert_web_app');
      expect(revertResult.output['ok'], isTrue);
      expect(revertResult.output['artifactId'], artifactId);
      expect(revertResult.output['type'], 'webApp');
      expect(revertResult.output['title'], '备忘录应用');
      expect(revertResult.output['version'], 3);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.metadata['currentVersion'], 3);
      expect(artifacts.single.metadata['html'], contains('旧按钮'));

      final revertedHtml = await fileStore.readText(
        workspaceId: 'work',
        path: 'apps/memo/index.html',
        maxChars: 12000,
      );
      expect(revertedHtml.content, contains('旧按钮'));
      final files = await fileStore.listFiles(workspaceId: 'work');
      expect(
        files.map((file) => file.path),
        isNot(contains('apps/memo/styles.css')),
      );
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

  test('runtime exposes battery and network status capabilities', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final batteryResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-battery',
        name: 'battery_status',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final networkResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-network',
        name: 'network_status',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(batteryResult.capabilityId, 'battery.status');
    expect(batteryResult.output['level'], 76);
    expect(networkResult.capabilityId, 'network.status');
    expect(networkResult.output['connected'], isTrue);
    expect(networkResult.output['types'], ['wifi']);
  });

  test('runtime exposes share and system feedback capabilities', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final shareResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-share',
        name: 'share_text',
        arguments: {'text': '分享这段文字', 'subject': 'Phone Agent'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final hapticResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-haptic',
        name: 'system_haptic_feedback',
        arguments: {'type': 'selection'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final soundResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-sound',
        name: 'system_sound_alert',
        arguments: {'type': 'click'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(shareResult.capabilityId, 'share.text');
    expect(shareResult.output['ok'], isTrue);
    expect(hapticResult.capabilityId, 'system.haptic_feedback');
    expect(hapticResult.output['type'], 'selection');
    expect(soundResult.capabilityId, 'system.sound_alert');
    expect(soundResult.output['type'], 'click');
  });

  test('runtime exposes permission settings and sensor snapshots', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final settingsResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-settings',
        name: 'permission_open_settings',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final accelerometerResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-accelerometer',
        name: 'sensor_accelerometer_read',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final gyroscopeResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-gyroscope',
        name: 'sensor_gyroscope_read',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final magnetometerResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-magnetometer',
        name: 'sensor_magnetometer_read',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(settingsResult.capabilityId, 'permission.open_settings');
    expect(settingsResult.output['opened'], isTrue);
    expect(accelerometerResult.capabilityId, 'sensor.accelerometer.read');
    expect(accelerometerResult.output['x'], 1.0);
    expect(gyroscopeResult.capabilityId, 'sensor.gyroscope.read');
    expect(gyroscopeResult.output['y'], 5.0);
    expect(magnetometerResult.capabilityId, 'sensor.magnetometer.read');
    expect(magnetometerResult.output['z'], 9.0);
  });

  test('runtime exposes external url and keep-awake capabilities', () async {
    final runtime = CapabilityRuntime(nativeAdapter: _FakeNativeAdapter());

    final urlResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-open-url',
        name: 'url_open_external',
        arguments: {'url': 'https://example.com'},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final keepAwakeResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-keep-awake',
        name: 'screen_keep_awake',
        arguments: {'enabled': true},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );
    final statusResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-keep-awake-status',
        name: 'screen_keep_awake_status',
        arguments: {},
      ),
      workspaceId: 'default',
      memories: const [],
      notes: const [],
      artifacts: const [],
    );

    expect(urlResult.capabilityId, 'url.open_external');
    expect(urlResult.output['opened'], isTrue);
    expect(keepAwakeResult.capabilityId, 'screen.keep_awake');
    expect(keepAwakeResult.output['enabled'], isTrue);
    expect(statusResult.capabilityId, 'screen.keep_awake_status');
    expect(statusResult.output['enabled'], isTrue);
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

  test('office document tools generate extract and patch docx files', () async {
    final runtime = CapabilityRuntime();
    final fileStore = InMemoryAppFileStore();

    final generateResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-doc-generate',
        name: 'document_generate',
        arguments: {
          'title': '合同审阅',
          'body': '付款周期为 30 天。\n违约责任需要补充。',
          'path': 'office/contract.docx',
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );
    expect(generateResult.capabilityId, 'document.generate');
    expect(generateResult.output['ok'], isTrue);

    final extractResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-doc-extract',
        name: 'document_extract',
        arguments: {'path': 'office/contract.docx'},
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );
    expect(extractResult.capabilityId, 'document.extract');
    expect(extractResult.output['content'], contains('付款周期为 30 天'));

    final patchResult = await runtime.execute(
      toolCall: const ToolCallRequest(
        id: 'call-doc-patch',
        name: 'document_apply_text_patch',
        arguments: {
          'path': 'office/contract.docx',
          'old_text': '付款周期为 30 天。',
          'new_text': '付款周期为 15 天。',
          'output_path': 'office/contract.patched.docx',
        },
      ),
      workspaceId: 'work',
      memories: const [],
      notes: const [],
      artifacts: const [],
      fileStore: fileStore,
    );
    expect(patchResult.capabilityId, 'document.apply_text_patch');
    expect(patchResult.output['ok'], isTrue);
    expect(patchResult.output['preservedFormatting'], isFalse);
  });

  test(
    'office generators create extractable spreadsheet presentation and pdf',
    () async {
      final runtime = CapabilityRuntime();
      final fileStore = InMemoryAppFileStore();

      final spreadsheet = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-xlsx-generate',
          name: 'spreadsheet_generate',
          arguments: {
            'title': '财报摘要',
            'path': 'office/report.xlsx',
            'rows': [
              ['项目', '金额'],
              ['收入', '100'],
            ],
          },
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );
      expect(spreadsheet.output['ok'], isTrue);

      final spreadsheetText = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-xlsx-extract',
          name: 'spreadsheet_extract',
          arguments: {'path': 'office/report.xlsx'},
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );
      expect(spreadsheetText.output['content'], contains('收入'));

      final presentation = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-ppt-generate',
          name: 'presentation_generate',
          arguments: {
            'title': '路演',
            'path': 'office/deck.pptx',
            'slides': [
              {
                'title': '第一页',
                'bullets': ['市场机会', '产品能力'],
              },
            ],
          },
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );
      expect(presentation.output['ok'], isTrue);

      final deckText = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-ppt-extract',
          name: 'presentation_extract',
          arguments: {'path': 'office/deck.pptx'},
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );
      expect(deckText.output['content'], contains('市场机会'));

      final pdf = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-pdf-generate',
          name: 'pdf_generate',
          arguments: {
            'title': '摘要',
            'body': '这是 PDF 内容',
            'path': 'office/a.pdf',
          },
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );
      expect(pdf.output['ok'], isTrue);

      final pdfText = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-pdf-extract',
          name: 'pdf_extract',
          arguments: {'path': 'office/a.pdf'},
        ),
        workspaceId: 'work',
        memories: const [],
        notes: const [],
        artifacts: const [],
        fileStore: fileStore,
      );
      expect(pdfText.output['content'], contains('这是 PDF 内容'));
    },
  );
}

class _FakeNativeAdapter extends NativeCapabilityAdapter {
  _FakeNativeAdapter({
    this.deviceInfoOutput = const {'ok': true},
    this.locationOutput = const {'ok': true},
  });

  final Map<String, Object?> deviceInfoOutput;
  final Map<String, Object?> locationOutput;
  String _clipboardText = '';
  bool _keepAwake = false;

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
  Future<Map<String, Object?>> getBatteryStatus() async {
    return {
      'ok': true,
      'level': 76,
      'state': 'charging',
      'isCharging': true,
      'isFull': false,
      'isInBatterySaveMode': false,
    };
  }

  @override
  Future<Map<String, Object?>> getNetworkStatus() async {
    return {
      'ok': true,
      'connected': true,
      'types': ['wifi'],
      'hasWifi': true,
      'hasMobile': false,
    };
  }

  @override
  Future<Map<String, Object?>> shareText({
    required String text,
    String? subject,
  }) async {
    return {'ok': true, 'status': 'success', 'length': text.length};
  }

  @override
  Future<Map<String, Object?>> hapticFeedback(String type) async {
    return {'ok': true, 'type': type};
  }

  @override
  Future<Map<String, Object?>> playSystemSound(String type) async {
    return {'ok': true, 'type': type};
  }

  @override
  Future<Map<String, Object?>> openPermissionSettings() async {
    return {'ok': true, 'opened': true};
  }

  @override
  Future<Map<String, Object?>> openExternalUrl(Uri uri) async {
    return {'ok': true, 'opened': true, 'url': uri.toString()};
  }

  @override
  Future<Map<String, Object?>> setKeepScreenAwake(bool enabled) async {
    _keepAwake = enabled;
    return {'ok': true, 'enabled': _keepAwake};
  }

  @override
  Future<Map<String, Object?>> getKeepScreenAwake() async {
    return {'ok': true, 'enabled': _keepAwake};
  }

  @override
  Future<Map<String, Object?>> readAccelerometer() async {
    return {
      'ok': true,
      'sensor': 'accelerometer',
      'x': 1.0,
      'y': 2.0,
      'z': 3.0,
    };
  }

  @override
  Future<Map<String, Object?>> readGyroscope() async {
    return {'ok': true, 'sensor': 'gyroscope', 'x': 4.0, 'y': 5.0, 'z': 6.0};
  }

  @override
  Future<Map<String, Object?>> readMagnetometer() async {
    return {'ok': true, 'sensor': 'magnetometer', 'x': 7.0, 'y': 8.0, 'z': 9.0};
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
