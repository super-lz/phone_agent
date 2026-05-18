import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/capabilities/native_capability_adapter.dart';
import 'package:phone_agent/data/capabilities/web_capability_adapter.dart';
import 'package:phone_agent/data/models/model_api_key_store.dart';
import 'package:phone_agent/data/models/model_settings_store.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/artifacts/artifact.dart';
import 'package:phone_agent/domain/artifacts/web_app_runtime_log.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/domain/files/app_file_store.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';
import 'package:phone_agent/domain/notes/note_store.dart';
import 'package:phone_agent/domain/workbench/workbench_store.dart';
import 'package:phone_agent/features/workbench/controllers/workbench_controller.dart';

void main() {
  test('normal prompt uses configured model', () async {
    final chatClient = _FakeChatClient([
      [
        const ChatStreamEvent(contentDelta: '真实'),
        const ChatStreamEvent(contentDelta: '模型'),
        const ChatStreamEvent(contentDelta: '回复'),
      ],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('你好');

    expect(controller.messages.last.blocks.first.data['text'], '真实模型回复');
    expect(chatClient.capturedTools.single, isEmpty);
  });

  test(
    'retries transient model stream failure before receiving content',
    () async {
      final chatClient = _RetryOnceChatClient();
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('你好');

      expect(chatClient.callCount, 2);
      expect(controller.messages.last.blocks.first.data['text'], '重试成功');
    },
  );

  test('defers transient retry until app returns foreground', () async {
    final chatClient = _RetryOnceChatClient();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );
    controller.setAppInForeground(false);

    final sendFuture = controller.sendPrompt('你好');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(chatClient.callCount, 1);
    expect(controller.isSending, isTrue);
    expect(
      controller.messages.last.blocks.first.data['text'],
      contains('回到前台后会自动重试一次'),
    );

    controller.setAppInForeground(true);
    await sendFuture;

    expect(chatClient.callCount, 2);
    expect(controller.messages.last.blocks.first.data['text'], '重试成功');
  });

  test('keeps partial text when stream breaks after output started', () async {
    final chatClient = _InterruptAfterContentChatClient();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('你好');

    expect(chatClient.callCount, 1);
    final blocks = controller.messages.last.blocks;
    expect(blocks.first.data['text'], '部分回复');
    expect(blocks.last.type, MessageBlockType.errorCard);
    expect(blocks.last.data['title'], '模型连接中断');
  });

  test(
    'normal prompt uses configured model name from settings store',
    () async {
      final settingsStore = InMemoryModelSettingsStore();
      await settingsStore.saveModelName(
        ModelProviders.aliyunBailianQwenFlash.id,
        'qwen3.6-flash',
      );
      final chatClient = _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '模型已切换')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        modelSettingsStore: settingsStore,
        chatClient: chatClient,
      );

      await controller.sendPrompt('你好');

      expect(chatClient.capturedModels.single, 'qwen3.6-flash');
    },
  );

  test('prompt can include local attachment summaries', () async {
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '已看到附件摘要。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt(
      '帮我看看附件',
      attachments: [
        MessageBlock.fileAttachment(
          name: '需求.md',
          uri: 'file:///tmp/requirements.md',
          bytes: 2048,
          extension: 'md',
        ),
      ],
    );

    final userMessage = controller.messages.firstWhere(
      (message) => message.role == MessageRole.user,
    );
    expect(
      userMessage.blocks.any(
        (block) => block.type == MessageBlockType.fileAttachment,
      ),
      isTrue,
    );
    final sentPrompt = chatClient.capturedMessages.single.last['content'];
    expect(sentPrompt, contains('需求.md'));
    expect(sentPrompt, contains('file:///tmp/requirements.md'));
    expect(controller.messages.last.blocks.first.data['text'], '已看到附件摘要。');
  });

  test('prompt sends local image attachments as multimodal content', () async {
    final tempDir = await Directory.systemTemp.createTemp('phone-agent-image-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDir.path}/sample.png');
    await imageFile.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '已读取图片。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt(
      '看看这张图',
      attachments: [
        MessageBlock.image(
          name: 'sample.png',
          uri: imageFile.uri.toString(),
          bytes: await imageFile.length(),
          mimeType: 'image/png',
        ),
      ],
    );

    final sentContent = chatClient.capturedMessages.single.last['content'];
    expect(sentContent, isA<List<Object?>>());
    final parts = sentContent! as List<Object?>;
    expect(parts, hasLength(2));
    expect(parts.first, isA<Map<Object?, Object?>>());
    expect(parts.last, isA<Map<Object?, Object?>>());
    final textPart = parts.first! as Map<Object?, Object?>;
    expect(textPart['type'], 'text');
    expect(textPart['text'], contains('已作为多模态 image_url 输入发送给模型'));
    final imagePart = parts.last! as Map<Object?, Object?>;
    expect(imagePart['type'], 'image_url');
    expect(
      jsonEncode(imagePart),
      contains('data:image/png;base64,iVBORw0KGgo='),
    );
    expect(controller.messages.last.blocks.first.data['text'], '已读取图片。');
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

  test('conversation messages persist through workbench store', () async {
    final store = InMemoryWorkbenchStore();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '持久回复')],
      ]),
      workbenchStore: store,
    );

    await controller.sendPrompt('记住这轮会话');

    final restored = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore(null),
      workbenchStore: store,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      restored.messages.any(
        (message) => message.blocks.any(
          (block) => block.data.values.any((value) => value == '持久回复'),
        ),
      ),
      isTrue,
    );
  });

  test('follow-up tool routing uses recent assistant context', () async {
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '我可以先读取你当前位置，再搜索天气信息。')],
      [const ChatStreamEvent(contentDelta: '正在处理。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('天气怎么查？');
    await controller.sendPrompt('你自己做');

    final followUpTools = _capturedToolNames(chatClient.capturedTools[1]);
    expect(followUpTools, containsAll(['location_get_current', 'web_search']));
  });

  test('user can stop a running agent turn', () async {
    final chatClient = _SlowChatClient();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    final sendFuture = controller.sendPrompt('创建一个俄罗斯方块 Web App');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.isSending, isTrue);
    expect(controller.currentRun, isNotNull);

    controller.cancelCurrentRun();
    await sendFuture;

    expect(controller.isSending, isFalse);
    expect(controller.currentRun, isNull);
    final finalBlock = controller.messages.last.blocks.single;
    expect(finalBlock.type, MessageBlockType.errorCard);
    expect(finalBlock.data['title'], '本轮任务已停止');
  });

  test('clear local workspace data resets workspace content only', () async {
    final workbenchStore = InMemoryWorkbenchStore();
    final noteStore = InMemoryAgentNoteStore();
    final fileStore = InMemoryAppFileStore();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [_webAppToolCallRound(0)],
        [const ChatStreamEvent(contentDelta: '已生成 Web App。')],
      ]),
      workbenchStore: workbenchStore,
      noteStore: noteStore,
      fileStore: fileStore,
    );

    controller.createWorkspace();
    controller.createMemory(content: '需要清理的长期记忆');
    await _createWebApp(controller);

    expect(controller.workspaces.length, greaterThan(1));
    expect(controller.visibleMemories, isNotEmpty);
    expect(controller.workspaceArtifacts, isNotEmpty);
    expect(controller.workspaceFiles, isNotEmpty);

    await controller.clearLocalWorkspaceData();

    expect(controller.workspaceId, 'default');
    expect(controller.workspaces.map((workspace) => workspace.id), ['default']);
    expect(controller.visibleMemories, isEmpty);
    expect(controller.workspaceArtifacts, isEmpty);
    expect(controller.workspaceNotes, isEmpty);
    expect(controller.workspaceFiles, isEmpty);
    expect(
      controller.messages.single.blocks.first.data['text'],
      contains('模型设置和 API Key 已保留'),
    );
    expect(await fileStore.listFiles(workspaceId: 'workspace-4'), isEmpty);
    expect(await noteStore.loadAll(), isEmpty);
    expect(await workbenchStore.loadInvocations(), isEmpty);
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

  test(
    'default permission mode blocks high risk memory delete tool call',
    () async {
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: _FakeChatClient([
          [
            const ChatStreamEvent(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call-memory-delete',
                  name: 'memory_delete',
                  argumentsDelta: '{"memory_id":"mem-global-1"}',
                ),
              ],
            ),
          ],
          [const ChatStreamEvent(contentDelta: '删除需要确认。')],
        ]),
      );

      await controller.sendPrompt('忘记第一条记忆');

      expect(
        controller.visibleMemories.any((memory) => memory.id == 'mem-global-1'),
        isTrue,
      );
      final deleteResultBlocks = controller.messages
          .expand((message) => message.blocks)
          .where(
            (block) =>
                block.type == MessageBlockType.toolResult &&
                block.data['capabilityId'] == 'memory.delete',
          );
      expect(deleteResultBlocks, isNotEmpty);
      final output =
          deleteResultBlocks.first.data['output']! as Map<String, Object?>;
      expect(output['error'], 'permission_confirmation_required');
      expect(controller.messages.last.blocks.first.data['text'], '删除需要确认。');
    },
  );

  test('model tool call can search web through capability runtime', () async {
    final chatClient = _FakeChatClient([
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
    ]);
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
      chatClient: chatClient,
    );

    await controller.sendPrompt('搜索 Flutter 最新信息');

    final toolNames = _capturedToolNames(chatClient.capturedTools.first);
    expect(toolNames, containsAll(['web_search', 'web_fetch']));
    expect(toolNames, isNot(contains('device_info')));
    expect(
      toolNames.length,
      lessThan(CapabilityRuntime().toolDefinitions.length),
    );
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

  test('model tool call can create runnable web app card', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-webapp-1',
                name: 'artifact_create',
                argumentsDelta:
                    '{"type":"web_app","title":"美食网页","summary":"带样式的本地网页","content_html":"<main><style>body{background:#fff7ed}</style><h1>美食</h1></main>"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已生成网页。')],
      ]),
    );

    await controller.sendPrompt('生成一个美食网页');

    final webApp = controller.workspaceArtifacts.singleWhere(
      (artifact) => artifact.title == '美食网页',
    );
    expect(webApp.type, ArtifactType.webApp);
    expect(webApp.metadata['html'], contains('background'));
    final webAppCards = controller.messages
        .expand((message) => message.blocks)
        .where((block) => block.type == MessageBlockType.webAppCard);
    expect(webAppCards, isNotEmpty);
  });

  test('model tool call can write and read workspace file', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-file-write',
                name: 'file_write_app_file',
                argumentsDelta:
                    '{"path":"reports/today.md","content":"今天的工作总结"}',
              ),
            ],
          ),
        ],
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-file-read',
                name: 'file_read_app_file',
                argumentsDelta: '{"path":"reports/today.md"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '文件已保存并读回。')],
      ]),
    );

    await controller.sendPrompt('保存并读取今天总结');

    final fileBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              (block.data['capabilityId'] == 'file.write_app_file' ||
                  block.data['capabilityId'] == 'file.read_app_file'),
        );
    expect(fileBlocks.length, 2);
    expect(controller.workspaceFiles.map((file) => file.path), [
      'reports/today.md',
    ]);
    expect(controller.messages.last.blocks.first.data['text'], '文件已保存并读回。');
  });

  test('model tool call can create maintainable web project card', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-project-create',
                name: 'project_create_web_app',
                argumentsDelta: jsonEncode({
                  'title': '黄金矿工小游戏',
                  'summary': '可打开并后续维护的本地小游戏。',
                  'entry_path': 'games/gold-miner/index.html',
                  'files': [
                    {
                      'path': 'games/gold-miner/index.html',
                      'content':
                          '<!doctype html><html><body><h1>黄金矿工</h1></body></html>',
                    },
                  ],
                }),
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已创建。')],
      ]),
    );

    await controller.sendPrompt('创建黄金矿工小游戏');

    expect(controller.workspaceFiles.map((file) => file.path), [
      'games/gold-miner/.phone-agent/manifest.json',
      'games/gold-miner/index.html',
    ]);
    expect(controller.workspaceArtifacts.last.title, '黄金矿工小游戏');
    final webAppCards = controller.messages
        .expand((message) => message.blocks)
        .where((block) => block.type == MessageBlockType.webAppCard);
    expect(webAppCards, isNotEmpty);
  });

  test(
    'web page request cannot be completed without real project tool',
    () async {
      final chatClient = _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '个人网站已创建！点击上方卡片预览。')],
        [
          ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-project-create',
                name: 'project_create_web_app',
                argumentsDelta: jsonEncode({
                  'title': '个人网页',
                  'summary': '个人介绍网页。',
                  'entry_path': 'personal-site/index.html',
                  'files': [
                    {
                      'path': 'personal-site/index.html',
                      'content':
                          '<!doctype html><html><body><h1>个人网页</h1></body></html>',
                    },
                  ],
                }),
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '个人网页已创建，可以从卡片打开预览。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('写一个个人网页');

      expect(chatClient.callCount, 3);
      expect(controller.workspaceFiles.map((file) => file.path), [
        'personal-site/.phone-agent/manifest.json',
        'personal-site/index.html',
      ]);
      expect(controller.workspaceArtifacts.last.title, '个人网页');
      final finalText = controller.messages.last.blocks.first.data['text'];
      expect(finalText, '个人网页已创建，可以从卡片打开预览。');
    },
  );

  test(
    'failed required project tool does not count as completed web app',
    () async {
      final chatClient = _FakeChatClient([
        [
          ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-project-create-bad',
                name: 'project_create_web_app',
                argumentsDelta: jsonEncode({
                  'title': '个人网页',
                  'summary': '个人介绍网页。',
                }),
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '个人网站已创建！点击上方卡片即可预览。')],
        [const ChatStreamEvent(contentDelta: '个人网站已创建！点击上方卡片即可预览。')],
        [const ChatStreamEvent(contentDelta: '个人网站已创建！点击上方卡片即可预览。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('写一个个人网页');

      expect(chatClient.callCount, 4);
      expect(controller.workspaceFiles, isEmpty);
      expect(
        controller.workspaceArtifacts.where(
          (artifact) => artifact.type == ArtifactType.webApp,
        ),
        isEmpty,
      );
      final finalBlock = controller.messages.last.blocks.single;
      expect(finalBlock.type, MessageBlockType.errorCard);
      expect(finalBlock.data['title'], '未创建真实产物');
      expect(finalBlock.data['detail'], contains('必需工具没有成功完成'));
    },
  );

  test('model tool call can use native clipboard capability', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      capabilityRuntime: CapabilityRuntime(nativeAdapter: _FakeNativeAdapter()),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-clipboard-write',
                name: 'clipboard_write',
                argumentsDelta: '{"text":"Phone Agent"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已复制。')],
      ]),
    );

    await controller.sendPrompt('复制 Phone Agent');

    final clipboardBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              block.data['capabilityId'] == 'clipboard.write',
        );
    expect(clipboardBlocks, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '已复制。');
  });

  test('model tool call can use current location capability', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      capabilityRuntime: CapabilityRuntime(nativeAdapter: _FakeNativeAdapter()),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-location',
                name: 'location_get_current',
                argumentsDelta: '{}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已获取当前位置。')],
      ]),
    );

    await controller.sendPrompt('用我的当前位置推荐附近事项');

    final locationBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              block.data['capabilityId'] == 'location.get_current',
        );
    expect(locationBlocks, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '已获取当前位置。');
  });

  test(
    'model tool process echo is replaced with readable final answer',
    () async {
      final chatClient = _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-location',
                name: 'location_get_current',
                argumentsDelta: '{}',
              ),
            ],
          ),
        ],
        [
          const ChatStreamEvent(
            contentDelta:
                '工具调用 location_get_current: {} 工具结果 location.get_current: {ok: true, latitude: 31.2304, longitude: 121.4737}',
          ),
        ],
        [const ChatStreamEvent(contentDelta: '你当前在上海市附近，定位精度约 65 米。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        capabilityRuntime: CapabilityRuntime(
          nativeAdapter: _FakeNativeAdapter(),
        ),
        chatClient: chatClient,
      );

      await controller.sendPrompt('我在哪');

      expect(chatClient.callCount, 3);
      final finalText = controller.messages.last.blocks.first.data['text'];
      expect(finalText, '你当前在上海市附近，定位精度约 65 米。');
      expect(finalText, isNot(contains('工具调用')));
      expect(finalText, isNot(contains('{ok:')));
    },
  );

  test('model tool call can read current time capability', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      capabilityRuntime: CapabilityRuntime(nativeAdapter: _FakeNativeAdapter()),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-time',
                name: 'time_get_current',
                argumentsDelta: '{}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '当前时间已校准。')],
      ]),
    );

    await controller.sendPrompt('现在几点');

    final timeBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              block.data['capabilityId'] == 'time.get_current',
        );
    expect(timeBlocks, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '当前时间已校准。');
  });

  test('model tool call can schedule notification capability', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      capabilityRuntime: CapabilityRuntime(nativeAdapter: _FakeNativeAdapter()),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-notification',
                name: 'notification_schedule',
                argumentsDelta:
                    '{"title":"提醒","body":"整理 Phone Agent 需求","delay_seconds":60}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已安排提醒。')],
      ]),
    );

    await controller.sendPrompt('一分钟后提醒我整理需求');

    final notificationBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              block.data['capabilityId'] == 'notification.schedule',
        );
    expect(notificationBlocks, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '已安排提醒。');
  });

  test('model tool call can create calendar event capability', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      capabilityRuntime: CapabilityRuntime(nativeAdapter: _FakeNativeAdapter()),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-calendar',
                name: 'calendar_event_create',
                argumentsDelta:
                    '{"title":"需求同步","start_at":"2026-05-18T10:00:00+08:00","duration_minutes":30}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已打开日历创建日程。')],
      ]),
    );

    await controller.sendPrompt('帮我把明天 10 点需求同步加入日历');

    final calendarBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              block.data['capabilityId'] == 'calendar.event.create',
        );
    expect(calendarBlocks, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '已打开日历创建日程。');
  });

  test('web app bridge can call allowed capability', () async {
    final controller = _controllerWithWebAppCreationRounds(1);

    final webApp = await _createWebApp(controller);
    final result = await controller.callCapabilityFromWebApp(
      webApp: webApp,
      capabilityId: 'db.note.create',
      input: const {'title': 'Web App Note', 'content': '来自 JSBridge'},
    );

    expect(result['ok'], isTrue);
    expect(result['capabilityId'], 'db.note.create');
    expect(
      controller.workspaceNotes.any((note) => note.content == '来自 JSBridge'),
      isFalse,
    );
    final queryResult = await controller.callCapabilityFromWebApp(
      webApp: webApp,
      capabilityId: 'db.note.query',
      input: const {'query': 'JSBridge'},
    );
    final output = queryResult['output']! as Map<String, Object?>;
    final items = output['items']! as List<Object?>;
    expect(items.length, 1);
  });

  test('web app bridge denies undeclared capability', () async {
    final controller = _controllerWithWebAppCreationRounds(1);

    final webApp = await _createWebApp(controller);
    final result = await controller.callCapabilityFromWebApp(
      webApp: webApp,
      capabilityId: 'clipboard.write',
      input: const {'text': 'not allowed'},
    );

    expect(result['ok'], isFalse);
    expect(result['error'], 'permission denied');
  });

  test('web app bridge keeps note namespaces isolated', () async {
    final controller = _controllerWithWebAppCreationRounds(2);
    final firstWebApp = await _createWebApp(controller);
    final secondWebApp = await _createWebApp(controller);

    await controller.callCapabilityFromWebApp(
      webApp: firstWebApp,
      capabilityId: 'db.note.create',
      input: const {'title': '私有记录', 'content': '第一个 Web App 的数据'},
    );
    final result = await controller.callCapabilityFromWebApp(
      webApp: secondWebApp,
      capabilityId: 'db.note.query',
      input: const {'query': '第一个 Web App'},
    );

    final output = result['output']! as Map<String, Object?>;
    final items = output['items']! as List<Object?>;
    expect(result['ok'], isTrue);
    expect(items, isEmpty);
  });

  test('web app bridge keeps file namespaces isolated', () async {
    final controller = _controllerWithWebAppCreationRounds(2);
    final firstWebApp = await _createWebApp(controller);
    final secondWebApp = await _createWebApp(controller);

    await controller.callCapabilityFromWebApp(
      webApp: firstWebApp,
      capabilityId: 'file.write_app_file',
      input: const {'path': 'private.txt', 'content': 'web app secret'},
    );
    final result = await controller.callCapabilityFromWebApp(
      webApp: secondWebApp,
      capabilityId: 'file.read_app_file',
      input: const {'path': 'private.txt'},
    );

    final output = result['output']! as Map<String, Object?>;
    expect(result['ok'], isFalse);
    expect(output['error'], 'not_found');
  });

  test('web app runtime logs are written to project folder', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-project-create-log',
                name: 'project_create_web_app',
                argumentsDelta: jsonEncode({
                  'title': '日志测试 Web App',
                  'summary': '用于验证运行日志写入项目目录。',
                  'entry_path': 'apps/log-test/index.html',
                  'files': [
                    {
                      'path': 'apps/log-test/index.html',
                      'content':
                          '<!doctype html><html><body><script>console.error("boom")</script></body></html>',
                    },
                  ],
                }),
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已创建。')],
      ]),
    );

    await controller.sendPrompt('创建日志测试 Web App');
    final webApp = controller.workspaceArtifacts.lastWhere(
      (artifact) => artifact.type == ArtifactType.webApp,
    );
    await controller.recordWebAppRuntimeLog(
      webApp: webApp,
      entry: WebAppRuntimeLogEntry(
        timestamp: DateTime.utc(2026, 5, 18, 10),
        level: 'error',
        source: 'console.error',
        message: 'boom',
        url: 'https://phone-agent.local/artifact/',
      ),
    );

    expect(
      webApp.metadata['runtimeLogPath'],
      'apps/log-test/.phone-agent/runtime.log',
    );
    expect(
      controller.workspaceFiles.map((file) => file.path),
      contains('apps/log-test/.phone-agent/runtime.log'),
    );
    final logFile = controller.workspaceFiles.firstWhere(
      (file) => file.path == 'apps/log-test/.phone-agent/runtime.log',
    );
    final logContent = await controller.readWorkspaceFile(logFile);
    expect(logContent.content, contains('"source":"console.error"'));
    expect(logContent.content, contains('"message":"boom"'));
  });

  test('model tool call can create and switch workspace', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-workspace-create',
                name: 'workspace_create',
                argumentsDelta: '{"name":"生活","description":"生活事项"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已切换到生活工作区。')],
      ]),
    );

    await controller.sendPrompt('新建一个生活工作区并切换过去');

    expect(
      controller.workspaces.map((workspace) => workspace.name),
      contains('生活'),
    );
    expect(controller.currentWorkspace.name, '生活');
    final workspaceBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              block.data['capabilityId'] == 'workspace.create',
        );
    expect(workspaceBlocks, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '已切换到生活工作区。');
  });

  test('model tool call can switch to existing workspace', () async {
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-workspace-switch',
                name: 'workspace_switch',
                argumentsDelta: '{"name":"工作"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已切换到工作。')],
      ]),
    );

    await controller.sendPrompt('切换到工作');

    expect(controller.workspaceId, 'work');
    final workspaceBlocks = controller.messages
        .expand((message) => message.blocks)
        .where(
          (block) =>
              block.type == MessageBlockType.toolResult &&
              block.data['capabilityId'] == 'workspace.switch',
        );
    expect(workspaceBlocks, isNotEmpty);
    expect(controller.messages.last.blocks.first.data['text'], '已切换到工作。');
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

class _FakeNativeAdapter extends NativeCapabilityAdapter {
  String _clipboardText = '';

  @override
  Future<Map<String, Object?>> getDeviceInfo() async {
    return const {
      'ok': true,
      'device': {'platform': 'test'},
    };
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
    return const {
      'ok': true,
      'latitude': 31.2304,
      'longitude': 121.4737,
      'accuracy': 12.0,
    };
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

WorkbenchController _controllerWithWebAppCreationRounds(int webAppCount) {
  final rounds = <List<ChatStreamEvent>>[];
  for (var index = 0; index < webAppCount; index += 1) {
    rounds
      ..add([_webAppToolCallRound(index)])
      ..add([const ChatStreamEvent(contentDelta: '已生成 Web App。')]);
  }
  return WorkbenchController(
    apiKeyStore: _FakeApiKeyStore('test-key'),
    chatClient: _FakeChatClient(rounds),
  );
}

ChatStreamEvent _webAppToolCallRound(int index) {
  return ChatStreamEvent(
    toolCallDeltas: [
      ToolCallDelta(
        index: 0,
        id: 'call-webapp-$index',
        name: 'project_create_web_app',
        argumentsDelta: jsonEncode({
          'title': '测试 Web App $index',
          'summary': '用于验证 JSBridge 能力隔离。',
          'entry_path': 'test-web-app-$index/index.html',
          'files': [
            {
              'path': 'test-web-app-$index/index.html',
              'content':
                  '<main><h1>测试 Web App $index</h1><button>Run</button></main>',
            },
          ],
          'permissions': [
            'db.note.create',
            'db.note.query',
            'file.read_app_file',
            'file.write_app_file',
            'device.info',
          ],
        }),
      ),
    ],
  );
}

Future<AgentArtifact> _createWebApp(WorkbenchController controller) async {
  await controller.sendPrompt('创建一个本地 Web App');
  return controller.workspaceArtifacts.lastWhere(
    (artifact) => artifact.type == ArtifactType.webApp,
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
  final List<List<Map<String, Object?>>> capturedTools = [];
  final List<String> capturedModels = [];
  int callCount = 0;

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    capturedMessages.add(messages);
    capturedTools.add(tools);
    capturedModels.add(provider.model);
    final events = rounds[callCount];
    callCount += 1;
    for (final event in events) {
      yield event;
    }
  }
}

List<String> _capturedToolNames(List<Map<String, Object?>> tools) {
  final names = <String>[];
  for (final tool in tools) {
    final function = tool['function'];
    if (function is! Map<String, Object?>) {
      continue;
    }
    final name = function['name'];
    if (name is String) {
      names.add(name);
    }
  }
  return names;
}

class _RetryOnceChatClient extends OpenAiCompatibleChatClient {
  int callCount = 0;

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    callCount += 1;
    if (callCount == 1) {
      throw const ModelRequestException('模型流式连接中断', isRetryable: true);
    }
    yield const ChatStreamEvent(contentDelta: '重试成功');
  }
}

class _InterruptAfterContentChatClient extends OpenAiCompatibleChatClient {
  int callCount = 0;

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    callCount += 1;
    yield const ChatStreamEvent(contentDelta: '部分回复');
    throw const ModelRequestException('连接被系统中断', isRetryable: true);
  }
}

class _SlowChatClient extends OpenAiCompatibleChatClient {
  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    yield const ChatStreamEvent(contentDelta: '这段内容不应该成为最终结果');
  }
}
