import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/agent_loop_budget.dart';
import 'package:phone_agent/application/agent/agent_run_state.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/background/agent_run_background_service.dart';
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
import 'package:phone_agent/domain/workbench/pending_agent_run.dart';
import 'package:phone_agent/domain/workbench/workbench_store.dart';
import 'package:phone_agent/features/web_app_runtime/web_app_local_server.dart';
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

  test('normal prompt exposes latest context budget snapshot', () async {
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '预算已计算')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('你好');

    expect(controller.contextBudget, isNotNull);
    expect(controller.contextBudget!.usagePercent, greaterThan(0));
    expect(controller.contextBudget!.isConservativeFallback, isTrue);
  });

  test('normal prompt records estimated token usage', () async {
    final store = InMemoryWorkbenchStore();
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: 'Token 已记录')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
      workbenchStore: store,
    );

    await controller.sendPrompt('你好');

    final records = await store.loadTokenUsageRecords();
    expect(records, hasLength(1));
    expect(records.single.workspaceId, 'default');
    expect(records.single.inputTokens, greaterThan(0));
    expect(records.single.reservedOutputTokens, greaterThan(0));
    expect(records.single.modelName, isNotEmpty);
  });

  test('last context budget is restored after controller restart', () async {
    final store = InMemoryWorkbenchStore();
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '预算已保存')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
      workbenchStore: store,
    );

    await controller.sendPrompt('你好');
    final savedPercent = controller.contextBudget!.usagePercent;
    controller.dispose();

    final restoredController = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([]),
      workbenchStore: store,
    );
    await _waitFor(() => restoredController.contextBudget != null);

    expect(restoredController.contextBudget!.usagePercent, savedPercent);
    restoredController.dispose();
  });

  test('context budget overflow is surfaced and persisted', () async {
    final workbenchStore = InMemoryWorkbenchStore();
    final modelSettingsStore = InMemoryModelSettingsStore();
    await modelSettingsStore.saveContextWindowTokens(
      ModelProviders.aliyunBailianQwenFlash.id,
      2048,
    );
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([]),
      modelSettingsStore: modelSettingsStore,
      workbenchStore: workbenchStore,
    );

    await controller.sendPrompt(List.filled(5000, '超').join());

    expect(controller.isSending, isFalse);
    expect(controller.contextBudget, isNotNull);
    expect(controller.contextBudget!.exceedsWindow, isTrue);
    expect(
      await workbenchStore.loadContextBudgetSnapshot('default'),
      isNotNull,
    );
    expect(await workbenchStore.loadPendingAgentRun(), isNull);
    final lastBlock = controller.messages.last.blocks.single;
    expect(lastBlock.type, MessageBlockType.errorCard);
    expect(lastBlock.data['title'], '上下文已超过模型窗口');
  });

  test(
    'running prompt keeps previous context budget until recalculated',
    () async {
      final chatClient = _BlockingSecondRouteChatClient([
        [const ChatStreamEvent(contentDelta: '第一轮')],
        [const ChatStreamEvent(contentDelta: '第二轮')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('你好');
      final firstUsagePercent = controller.contextBudget!.usagePercent;

      final secondRun = controller.sendPrompt('你好');
      await chatClient.secondRouteStarted.future;

      expect(controller.isSending, isTrue);
      expect(controller.contextBudget!.usagePercent, firstUsagePercent);
      expect(
        controller.currentRun!.contextBudget!.usagePercent,
        firstUsagePercent,
      );

      chatClient.releaseSecondRoute.complete();
      await secondRun;
    },
  );

  test(
    'ordinary follow-up fragment ignores capability text from prior answer',
    () async {
      final chatClient = _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '我可以创建工作区、保存报告、生成 Web App 卡片。')],
        [const ChatStreamEvent(contentDelta: '我是 Phone Agent。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('你好');
      await controller.sendPrompt('你是');

      expect(chatClient.capturedTools[1], isEmpty);
      expect(
        controller.messages.last.blocks.first.data['text'],
        '我是 Phone Agent。',
      );
    },
  );

  test(
    'running prompt starts background service and clears recovery record',
    () async {
      final store = InMemoryWorkbenchStore();
      final backgroundService = _RecordingBackgroundService();
      final chatClient = _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '后台运行完成')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
        workbenchStore: store,
        backgroundService: backgroundService,
      );

      await controller.sendPrompt('后台继续处理');

      expect(backgroundService.started.single.detail, contains('后台继续处理'));
      expect(
        backgroundService.stopped.single,
        backgroundService.started.single.runId,
      );
      expect(await store.loadPendingAgentRun(), isNull);
    },
  );

  test('restores pending agent run on controller startup', () async {
    final store = InMemoryWorkbenchStore();
    final pendingRun = PendingAgentRun(
      id: 'pending-run-1',
      workspaceId: 'default',
      userPrompt: '恢复后台会话',
      modelPrompt: '恢复后台会话',
      priorMessages: const [],
      startedAt: DateTime(2026),
    );
    await store.savePendingAgentRun(pendingRun);
    final backgroundService = _RecordingBackgroundService();
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '恢复成功')],
    ]);

    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
      workbenchStore: store,
      backgroundService: backgroundService,
    );

    await _waitFor(() => chatClient.callCount == 1 && !controller.isSending);

    expect(backgroundService.started.single.runId, pendingRun.id);
    expect(backgroundService.stopped.single, pendingRun.id);
    expect(await store.loadPendingAgentRun(), isNull);
    expect(
      controller.messages.map((message) => message.blocks.first.data['text']),
      contains('检测到上次运行中的会话被系统中断，正在继续处理：恢复后台会话'),
    );
    expect(controller.messages.last.blocks.first.data['text'], '恢复成功');
  });

  test('keeps pending run when completion state cannot be persisted', () async {
    final store = _FailingCompletionPersistStore();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '已完成但保存失败')],
      ]),
      workbenchStore: store,
    );

    await controller.sendPrompt('需要可靠恢复的任务');

    final pendingRun = await store.loadPendingAgentRun();
    expect(controller.isSending, isFalse);
    expect(pendingRun, isNotNull);
    expect(pendingRun!.userPrompt, '需要可靠恢复的任务');
  });

  test('model prompt uses structured system sections', () async {
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: '找到 Flutter 来源。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );
    await controller.sendPrompt('帮我搜索 Flutter 最新信息');

    final systemPrompt = chatClient.capturedMessages.first.first['content'];
    expect(systemPrompt, isA<String>());
    final text = systemPrompt! as String;
    expect(text, contains('<role>'));
    expect(text, contains('<capability_index>'));
    expect(text, contains('本轮路由模型只暴露以下工具 schema'));
    expect(text, contains('web_search / web_fetch'));
    expect(text, contains('<workflow_contracts>'));
    expect(text, isNot(contains('<jsbridge_skill>')));
    expect(text, contains('<current_context>'));
  });

  test('model prompt includes JSBridge skill only for web app work', () async {
    final chatClient = _FakeChatClient([
      [
        ChatStreamEvent(
          toolCallDeltas: [
            ToolCallDelta(
              index: 0,
              id: 'call-jsbridge-app',
              name: 'project_create_web_app',
              argumentsDelta: jsonEncode({
                'title': '设备信息 Web App',
                'summary': '用于验证 JSBridge 指南注入。',
                'entry_path': 'apps/device-info/index.html',
                'files': [
                  {
                    'path': 'apps/device-info/index.html',
                    'content':
                        '<!doctype html><html><body><main>Device</main></body></html>',
                  },
                ],
                'permissions': ['device.info'],
              }),
            ),
          ],
        ),
      ],
      [const ChatStreamEvent(contentDelta: '已创建。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('创建一个能读取设备信息的 Web App');

    final systemPrompt = chatClient.capturedMessages.first.first['content'];
    expect(systemPrompt, isA<String>());
    final text = systemPrompt! as String;
    expect(text, contains('<jsbridge_skill>'));
    expect(text, contains('Phone Agent Runtime injects window.PhoneAgent'));
    expect(
      text,
      contains('permissions: [\'device.info\', \'time.get_current\']'),
    );
  });

  test('web app creation shows live process before final answer', () async {
    final chatClient = _BlockingWebAppToolChatClient();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    final sendFuture = controller.sendPrompt('创建一个本地 Web App');
    await chatClient.firstStreamStarted.future;

    expect(controller.isSending, isTrue);
    expect(
      _allBlocks(controller.messages).where(
        (block) =>
            block.type == MessageBlockType.markdownText &&
            block.data['intermediate'] == true &&
            (block.data['text'] as String).contains('正在分析请求'),
      ),
      isNotEmpty,
    );

    chatClient.releaseToolCall.complete();
    await chatClient.secondStreamStarted.future;
    await chatClient.finalAnswerDeltaApplied.future;

    final blocksBeforeFinal = _allBlocks(controller.messages);
    expect(
      blocksBeforeFinal.any(
        (block) =>
            block.type == MessageBlockType.toolCall &&
            block.data['capabilityId'] == 'project_create_web_app',
      ),
      isTrue,
    );
    expect(
      blocksBeforeFinal.any(
        (block) =>
            block.type == MessageBlockType.toolResult &&
            block.data['capabilityId'] == 'project.create_web_app',
      ),
      isTrue,
    );
    expect(controller.messages.last.blocks.first.data['text'], '已');
    expect(
      controller.messages.last.blocks.any(
        (block) => block.type == MessageBlockType.taskProgress,
      ),
      isTrue,
    );

    chatClient.releaseFinalAnswer.complete();
    await sendFuture;

    expect(controller.messages.last.blocks.first.data['text'], '已创建。');
  });

  test('slow web app tool arguments explain generation status', () async {
    final chatClient = _SlowWebAppArgumentsChatClient();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    final sendFuture = controller.sendPrompt('创建一个慢速 Web App');
    await chatClient.firstDeltaApplied.future;

    expect(controller.currentRun!.phase, AgentRunPhase.waitingForToolCall);
    expect(controller.currentRun!.detail, contains('正在生成 Web App 文件内容'));
    expect(controller.currentRun!.detail, isNot(contains('已接收约')));
    expect(
      _allBlocks(controller.messages).where(
        (block) =>
            block.type == MessageBlockType.markdownText &&
            block.data['intermediate'] == true &&
            (block.data['text'] as String).contains('正在生成 Web App 文件内容'),
      ),
      isNotEmpty,
    );

    chatClient.releaseRemainingArguments.complete();
    await sendFuture;

    expect(controller.messages.last.blocks.first.data['text'], '已创建。');
  });

  test('retries transient failure after partial tool arguments', () async {
    final chatClient = _RetryAfterPartialToolArgumentsChatClient();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('创建一个本地 Web App');

    expect(chatClient.callCount, 3);
    expect(controller.messages.last.blocks.first.data['text'], '已创建。');
    expect(
      controller.workspaceArtifacts.where(
        (artifact) => artifact.type == ArtifactType.webApp,
      ),
      isNotEmpty,
    );
    final allErrorTitles = _allBlocks(controller.messages)
        .where((block) => block.type == MessageBlockType.errorCard)
        .map((block) => block.data['title']);
    expect(allErrorTitles, isNot(contains('模型连接中断')));
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

    await controller.sendPrompt('测试持久化');

    final restored = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore(null),
      workbenchStore: store,
    );
    await restored.stateReady;

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
    final workbenchStore = InMemoryWorkbenchStore();
    final chatClient = _SlowChatClient();
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
      workbenchStore: workbenchStore,
    );

    final sendFuture = controller.sendPrompt('创建一个俄罗斯方块 Web App');
    await _waitFor(
      () => controller.messages.any(
        (message) =>
            message.role == MessageRole.assistant &&
            message.blocks.any(
              (block) =>
                  block.type == MessageBlockType.markdownText &&
                  block.data['intermediate'] == true,
            ),
      ),
    );

    expect(controller.isSending, isTrue);
    expect(controller.currentRun, isNotNull);

    controller.cancelCurrentRun();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isSending, isFalse);
    expect(controller.currentRun, isNull);
    expect(await workbenchStore.loadPendingAgentRun(), isNull);
    final stoppedProgress = controller.messages
        .expand((message) => message.blocks)
        .where((block) => block.type == MessageBlockType.taskProgress)
        .last;
    expect(stoppedProgress.data['status'], 'stopped');

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
    'invalid streamed tool arguments are sent back for model correction',
    () async {
      final chatClient = _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-memory-invalid-json',
                name: 'memory_create',
                argumentsDelta: '{"content":"半截',
              ),
            ],
          ),
        ],
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-memory-fixed-json',
                name: 'memory_create',
                argumentsDelta: '{"content":"修正后的记忆"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已记住。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('记住一个新偏好');

      expect(chatClient.callCount, 3);
      expect(
        controller.visibleMemories.where(
          (memory) => memory.content == '修正后的记忆',
        ),
        hasLength(1),
      );
      expect(
        controller.visibleMemories.any((memory) => memory.content == '半截'),
        isFalse,
      );
      final invalidArgumentResults = _allBlocks(controller.messages).where(
        (block) =>
            block.type == MessageBlockType.toolResult &&
            (block.data['output']! as Map<String, Object?>)['error'] ==
                'invalid_tool_arguments',
      );
      expect(invalidArgumentResults, isNotEmpty);
      expect(controller.messages.last.blocks.first.data['text'], '已记住。');
    },
  );

  test(
    'default permission mode pauses high risk tool call for approval',
    () async {
      final chatClient = _FakeChatClient([
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
        [const ChatStreamEvent(contentDelta: '不应继续生成。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('忘记第一条记忆');

      expect(chatClient.callCount, 1);
      expect(
        controller.visibleMemories.any((memory) => memory.id == 'mem-global-1'),
        isTrue,
      );
      final deleteResultBlocks = _allBlocks(controller.messages).where(
        (block) =>
            block.type == MessageBlockType.toolResult &&
            block.data['capabilityId'] == 'memory.delete',
      );
      expect(deleteResultBlocks, isNotEmpty);
      final output =
          deleteResultBlocks.first.data['output']! as Map<String, Object?>;
      expect(output['error'], 'permission_confirmation_required');
      expect(
        _allBlocks([
          controller.messages.last,
        ]).any((block) => block.type == MessageBlockType.approvalRequest),
        isTrue,
      );
    },
  );

  test(
    'approved high risk tool result continues original agent task',
    () async {
      final chatClient = _FakeChatClient([
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
        [const ChatStreamEvent(contentDelta: '已删除这条记忆。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('忘记第一条记忆');
      final approvalBlock = _allBlocks(
        controller.messages,
      ).firstWhere((block) => block.type == MessageBlockType.approvalRequest);
      expect(approvalBlock.data['userPrompt'], '忘记第一条记忆');

      final approveFuture = controller.approveCapabilityRequest(
        approvalBlock.data,
      );
      expect(controller.isSending, isTrue);
      expect(controller.currentRun!.phase, AgentRunPhase.executingTool);
      expect(controller.currentRun!.currentToolName, 'memory_delete');
      await approveFuture;

      expect(chatClient.callCount, 2);
      expect(
        controller.visibleMemories.any((memory) => memory.id == 'mem-global-1'),
        isFalse,
      );
      expect(controller.messages.last.blocks.first.data['text'], '已删除这条记忆。');
    },
  );

  test(
    'pending approval can continue original task after controller restart',
    () async {
      final store = InMemoryWorkbenchStore();
      final firstChatClient = _FakeChatClient([
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
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: firstChatClient,
        workbenchStore: store,
      );

      await controller.sendPrompt('忘记第一条记忆');
      final storedApprovalMessage = (await store.loadMessages('default'))
          .firstWhere(
            (message) => _allBlocks([
              message,
            ]).any((block) => block.type == MessageBlockType.approvalRequest),
          );
      final storedApprovalBlock = storedApprovalMessage.blocks.firstWhere(
        (block) => block.type == MessageBlockType.approvalRequest,
      );
      expect(storedApprovalBlock.data['userPrompt'], '忘记第一条记忆');
      controller.dispose();

      final restoredChatClient = _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '已删除这条记忆。')],
      ]);
      final restoredController = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: restoredChatClient,
        workbenchStore: store,
      );
      await _waitFor(
        () => restoredController.messages.any(
          (message) => _allBlocks([
            message,
          ]).any((block) => block.type == MessageBlockType.approvalRequest),
        ),
      );
      final restoredApprovalBlock = _allBlocks(
        restoredController.messages,
      ).firstWhere((block) => block.type == MessageBlockType.approvalRequest);

      await restoredController.approveCapabilityRequest(
        restoredApprovalBlock.data,
      );

      expect(restoredChatClient.callCount, 1);
      expect(
        restoredChatClient.capturedMessages.single.last['content'],
        contains('用户原始请求是：忘记第一条记忆。'),
      );
      expect(restoredChatClient.capturedTools.single, isEmpty);
      expect(
        restoredController.visibleMemories.any(
          (memory) => memory.id == 'mem-global-1',
        ),
        isFalse,
      );
      final updatedApprovalBlock = _allBlocks(
        await store.loadMessages('default'),
      ).firstWhere((block) => block.type == MessageBlockType.approvalRequest);
      expect(updatedApprovalBlock.data['status'], 'approved');
    },
  );

  test('denied high risk tool result continues original agent task', () async {
    final chatClient = _FakeChatClient([
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
      [const ChatStreamEvent(contentDelta: '已取消删除，这条记忆仍然保留。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('忘记第一条记忆');
    final approvalBlock = _allBlocks(
      controller.messages,
    ).firstWhere((block) => block.type == MessageBlockType.approvalRequest);

    await controller.denyCapabilityRequest(approvalBlock.data);

    expect(chatClient.callCount, 2);
    expect(
      controller.visibleMemories.any((memory) => memory.id == 'mem-global-1'),
      isTrue,
    );
    final deniedResults = _allBlocks(controller.messages).where(
      (block) =>
          block.type == MessageBlockType.toolResult &&
          (block.data['output']! as Map<String, Object?>)['error'] ==
              'permission_denied',
    );
    expect(deniedResults, isNotEmpty);
    expect(
      controller.messages.last.blocks.first.data['text'],
      '已取消删除，这条记忆仍然保留。',
    );
  });

  test(
    'tool budget applies to multiple tool calls in the same model round',
    () async {
      final chatClient = _FakeChatClient([
        [
          const ChatStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call-memory-a',
                name: 'memory_create',
                argumentsDelta: '{"content":"第一条"}',
              ),
              ToolCallDelta(
                index: 1,
                id: 'call-memory-b',
                name: 'memory_create',
                argumentsDelta: '{"content":"第二条"}',
              ),
            ],
          ),
        ],
        [const ChatStreamEvent(contentDelta: '已按预算停止。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
        agentLoopBudget: const AgentLoopBudget(
          maxModelRounds: 3,
          maxToolCalls: 1,
        ),
      );

      await controller.sendPrompt('记住两条信息');

      expect(
        controller.visibleMemories.where(
          (memory) => memory.content == '第一条' || memory.content == '第二条',
        ),
        hasLength(1),
      );
      expect(
        controller.visibleMemories.any((memory) => memory.content == '第一条'),
        isTrue,
      );
      final budgetResults = _allBlocks(controller.messages).where(
        (block) =>
            block.type == MessageBlockType.toolResult &&
            (block.data['output']! as Map<String, Object?>)['error'] ==
                'tool_budget_exceeded',
      );
      expect(budgetResults, isNotEmpty);
      expect(chatClient.capturedTools[1], isEmpty);
      expect(controller.messages.last.blocks.first.data['text'], '已按预算停止。');
    },
  );

  test(
    'model round exhaustion returns visible failure instead of silent completion',
    () async {
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: _FakeChatClient([
          [
            const ChatStreamEvent(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call-memory-loop',
                  name: 'memory_create',
                  argumentsDelta: '{"content":"循环中的记忆"}',
                ),
              ],
            ),
          ],
        ]),
        agentLoopBudget: const AgentLoopBudget(maxModelRounds: 1),
      );

      await controller.sendPrompt('记住循环中的记忆');

      final lastBlock = controller.messages.last.blocks.single;
      expect(lastBlock.type, MessageBlockType.errorCard);
      expect(lastBlock.data['title'], '模型调用失败');
      expect(lastBlock.data['detail'], contains('最大模型轮次'));
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
    final toolBlocks = _allBlocks(
      controller.messages,
    ).where((block) => block.data['capabilityId'] == 'web.search');
    expect(toolBlocks, isNotEmpty);
    expect(
      controller.messages.last.blocks.first.data['text'],
      '找到 Flutter 来源。',
    );
  });

  test('required web search prevents latest answer without search', () async {
    final chatClient = _FakeChatClient([
      [const ChatStreamEvent(contentDelta: 'Flutter 最新版本是 X。')],
      [const ChatStreamEvent(contentDelta: 'Flutter 最新版本是 X。')],
      [const ChatStreamEvent(contentDelta: 'Flutter 最新版本是 X。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('搜索 Flutter 最新信息并给出来源');

    expect(chatClient.callCount, 3);
    final toolNames = _capturedToolNames(chatClient.capturedTools.first);
    expect(toolNames, contains('web_search'));
    final finalBlock = controller.messages.last.blocks.single;
    expect(finalBlock.type, MessageBlockType.errorCard);
    expect(finalBlock.data['title'], '必需动作未完成');
    expect(finalBlock.data['detail'], contains('联网搜索'));
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
    final blocks = controller.messages.last.blocks;
    expect(blocks.first.data['text'], '已记录到当前工作区。');
    final progressBlock = blocks.singleWhere(
      (block) => block.type == MessageBlockType.taskProgress,
    );
    expect(progressBlock.data['status'], 'completed');
    final processBlocks = progressBlock.data['blocks']! as List<MessageBlock>;
    expect(
      processBlocks.any(
        (block) =>
            block.type == MessageBlockType.toolResult &&
            block.data['capabilityId'] == 'db.note.create',
      ),
      isTrue,
    );
  });

  test(
    'required multi segment tool name is matched to capability id',
    () async {
      final chatClient = _RequiredNoteToolChatClient();
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('必须记录一个待办：映射检查');

      expect(chatClient.callCount, 2);
      expect(
        controller.workspaceNotes.any(
          (note) => note.title == '待办' && note.content == '映射检查',
        ),
        isTrue,
      );
      expect(controller.messages.last.blocks.first.data['text'], '已记录。');
      expect(
        _allBlocks(
          controller.messages,
        ).where((block) => block.type == MessageBlockType.errorCard),
        isEmpty,
      );
    },
  );

  test('raw structured tool final answer is regenerated for users', () async {
    final chatClient = _FakeChatClient([
      [
        const ChatStreamEvent(
          toolCallDeltas: [
            ToolCallDelta(
              index: 0,
              id: 'call-note-raw-final',
              name: 'db_note_create',
              argumentsDelta: '{"title":"待办","content":"检查最终回答"}',
            ),
          ],
        ),
      ],
      [
        const ChatStreamEvent(
          contentDelta:
              '{ok: true, title: 待办, workspaceId: default, output: 已记录}',
        ),
      ],
      [const ChatStreamEvent(contentDelta: '已记录到当前工作区。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('记录一个待办：检查最终回答');

    expect(chatClient.callCount, 3);
    expect(
      controller.workspaceNotes.any(
        (note) => note.title == '待办' && note.content == '检查最终回答',
      ),
      isTrue,
    );
    expect(controller.messages.last.blocks.first.data['text'], '已记录到当前工作区。');
    expect(
      chatClient.capturedMessages.last.last['content'],
      contains('不要出现工具调用、工具结果、原始 JSON、Map 或 capability 字段'),
    );
  });

  test('pseudo tool call text is corrected into a real tool call', () async {
    final chatClient = _FakeChatClient([
      [
        const ChatStreamEvent(
          contentDelta:
              '<tool_call><function=db.note.create><parameter=title>待办</parameter>'
              '<parameter=content>修复伪工具调用</parameter></function></tool_call>',
        ),
      ],
      [
        const ChatStreamEvent(
          toolCallDeltas: [
            ToolCallDelta(
              index: 0,
              id: 'call-note-after-pseudo',
              name: 'db_note_create',
              argumentsDelta: '{"title":"待办","content":"修复伪工具调用"}',
            ),
          ],
        ),
      ],
      [const ChatStreamEvent(contentDelta: '已记录到当前工作区。')],
    ]);
    final controller = WorkbenchController(
      apiKeyStore: _FakeApiKeyStore('test-key'),
      chatClient: chatClient,
    );

    await controller.sendPrompt('记录一个待办：修复伪工具调用');

    expect(chatClient.callCount, 3);
    expect(
      controller.workspaceNotes.any(
        (note) => note.title == '待办' && note.content == '修复伪工具调用',
      ),
      isTrue,
    );
    final finalText = controller.messages.last.blocks.first.data['text'];
    expect(finalText, '已记录到当前工作区。');
    expect(finalText, isNot(contains('<tool_call>')));
    expect(
      chatClient.capturedMessages[1].last['content'],
      contains('正文里的伪工具标签不会被系统执行'),
    );
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
    final artifactCards = _allBlocks(
      controller.messages,
    ).where((block) => block.type == MessageBlockType.artifactCard);
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
    final webAppCards = _allBlocks(
      controller.messages,
    ).where((block) => block.type == MessageBlockType.webAppCard);
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

    final fileBlocks = _allBlocks(controller.messages).where(
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
      'games/gold-miner/.phone-agent/versions/v0001.json',
      'games/gold-miner/index.html',
    ]);
    expect(controller.workspaceArtifacts.last.title, '黄金矿工小游戏');
    final webAppCards = _allBlocks(
      controller.messages,
    ).where((block) => block.type == MessageBlockType.webAppCard);
    expect(webAppCards, isNotEmpty);
  });

  test(
    'web app update adds a chat preview card for the same artifact',
    () async {
      final chatClient = _CreateThenUpdateWebAppChatClient();
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
      );

      await controller.sendPrompt('创建一个本地 Web App');
      final artifactId = controller.workspaceArtifacts.last.id;
      final artifactCountAfterCreate = controller.workspaceArtifacts.length;

      await controller.sendPrompt('修复应用按钮文案');

      expect(
        controller.workspaceArtifacts,
        hasLength(artifactCountAfterCreate),
      );
      final updatedArtifact = controller.workspaceArtifacts.singleWhere(
        (artifact) => artifact.id == artifactId,
      );
      expect(updatedArtifact.metadata['currentVersion'], 2);
      final matchingCards = _allBlocks(controller.messages)
          .where(
            (block) =>
                block.type == MessageBlockType.webAppCard &&
                block.data['artifactId'] == artifactId,
          )
          .toList(growable: false);
      expect(matchingCards, hasLength(2));
      expect(matchingCards.last.data['title'], '联动测试 Web App');
    },
  );

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
        'personal-site/.phone-agent/versions/v0001.json',
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
      expect(finalBlock.data['title'], '必需动作未完成');
      expect(finalBlock.data['detail'], contains('必需工具没有成功完成'));
    },
  );

  test(
    'failed required note tool reports generic required action error',
    () async {
      final chatClient = _FakeChatClient([
        [const ChatStreamEvent(contentDelta: '已记录这个待办。')],
        [const ChatStreamEvent(contentDelta: '已记录这个待办。')],
        [const ChatStreamEvent(contentDelta: '已记录这个待办。')],
      ]);
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        chatClient: chatClient,
        noteStore: InMemoryAgentNoteStore([]),
      );

      await controller.sendPrompt('记录一个待办：整理需求清单');

      expect(chatClient.callCount, 3);
      expect(
        controller.workspaceNotes.where((n) => n.content.contains('需求清单')),
        isEmpty,
      );
      final finalBlock = controller.messages.last.blocks.single;
      expect(finalBlock.type, MessageBlockType.errorCard);
      expect(finalBlock.data['title'], '必需动作未完成');
      expect(finalBlock.data['detail'], contains('记录笔记'));
      expect(finalBlock.data['detail'], isNot(contains('未创建真实产物')));
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

    final clipboardBlocks = _allBlocks(controller.messages).where(
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

    final locationBlocks = _allBlocks(controller.messages).where(
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

    final timeBlocks = _allBlocks(controller.messages).where(
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

    final notificationBlocks = _allBlocks(controller.messages).where(
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

    final calendarBlocks = _allBlocks(controller.messages).where(
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
    expect(result['error'], 'permission_denied');
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

  test(
    'web app local api server actions use isolated file namespace',
    () async {
      final fileStore = InMemoryAppFileStore();
      final controller = WorkbenchController(
        apiKeyStore: _FakeApiKeyStore('test-key'),
        fileStore: fileStore,
        chatClient: _FakeChatClient([
          [
            ChatStreamEvent(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call-webapp-file-api',
                  name: 'project_create_web_app',
                  argumentsDelta: jsonEncode({
                    'title': '文件 API Web App',
                    'summary': '验证本地服务端文件读写。',
                    'entry_path': 'apps/file-api/index.html',
                    'permissions': [
                      'file.write_app_file',
                      'file.read_app_file',
                    ],
                    'server': {
                      'routes': [
                        {
                          'method': 'POST',
                          'path': '/api/files/write',
                          'handlerPath': 'server/write-file.json',
                        },
                        {
                          'method': 'GET',
                          'path': '/api/files/read',
                          'handlerPath': 'server/read-file.json',
                        },
                      ],
                    },
                    'files': [
                      {
                        'path': 'apps/file-api/index.html',
                        'content':
                            '<!doctype html><html><body>File API</body></html>',
                      },
                      {
                        'path': 'apps/file-api/server/write-file.json',
                        'content': jsonEncode({
                          'steps': [
                            {
                              'id': 'write',
                              'capability': 'file.write_app_file',
                              'input': {
                                'path': r'$request.path',
                                'content': r'$request.content',
                                'overwrite': true,
                              },
                            },
                          ],
                          'response': {
                            'ok': r'$steps.write.ok',
                            'path': r'$steps.write.output.path',
                          },
                        }),
                      },
                      {
                        'path': 'apps/file-api/server/read-file.json',
                        'content': jsonEncode({
                          'steps': [
                            {
                              'id': 'read',
                              'capability': 'file.read_app_file',
                              'input': {'path': r'$request.path'},
                            },
                          ],
                          'response': {
                            'ok': r'$steps.read.ok',
                            'content': r'$steps.read.output.content',
                          },
                        }),
                      },
                    ],
                  }),
                ),
              ],
            ),
          ],
          [const ChatStreamEvent(contentDelta: '已生成 Web App。')],
        ]),
      );
      final webApp = await _createWebApp(controller);
      final server = WebAppLocalServer(
        webApp: webApp,
        resourceReader: controller.readWebAppResource,
        htmlHeadInjection: '',
        fallbackHtml: '<main>Fallback</main>',
        apiRouteCaller:
            ({
              required String capabilityId,
              required Map<String, Object?> input,
            }) {
              return controller.callCapabilityFromWebApp(
                webApp: webApp,
                capabilityId: capabilityId,
                input: input,
              );
            },
      );
      final url = await server.start();
      addTearDown(server.close);

      final write = await _postJson(
        Uri(
          scheme: url.scheme,
          host: url.host,
          port: url.port,
          path: '/api/files/write',
        ),
        const {'path': 'data/profile.json', 'content': '{"name":"local"}'},
      );
      expect(write.statusCode, HttpStatus.ok);
      final writeBody = jsonDecode(write.body) as Map<String, Object?>;
      expect(writeBody['ok'], isTrue);
      expect(writeBody['path'], 'data/profile.json');

      final read = await _get(
        Uri(
          scheme: url.scheme,
          host: url.host,
          port: url.port,
          path: '/api/files/read',
          queryParameters: {'path': 'data/profile.json'},
        ),
      );
      expect(read.statusCode, HttpStatus.ok);
      final readBody = jsonDecode(read.body) as Map<String, Object?>;
      expect(readBody['ok'], isTrue);
      expect(readBody['content'], '{"name":"local"}');

      await expectLater(
        fileStore.readText(
          workspaceId: controller.workspaceId,
          path: 'data/profile.json',
          maxChars: 12000,
        ),
        throwsA(isA<AppFileStoreException>()),
      );
      final fileNamespace = webApp.metadata['fileNamespace']! as String;
      final stored = await fileStore.readText(
        workspaceId: fileNamespace,
        path: 'data/profile.json',
        maxChars: 12000,
      );
      expect(stored.content, '{"name":"local"}');
    },
  );

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
    final workspaceBlocks = _allBlocks(controller.messages).where(
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
    final workspaceBlocks = _allBlocks(controller.messages).where(
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

    final memoryQueryBlocks = _allBlocks(
      controller.messages,
    ).where((block) => block.data['capabilityId'] == 'memory.query');
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

Future<_HttpTextResponse> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    return _HttpTextResponse(statusCode: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

Future<_HttpTextResponse> _postJson(Uri uri, Map<String, Object?> body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    final bytes = utf8.encode(jsonEncode(body));
    request.headers.contentType = ContentType.json;
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    return _HttpTextResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  } finally {
    client.close(force: true);
  }
}

class _HttpTextResponse {
  const _HttpTextResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class _FakeApiKeyStore extends ModelApiKeyStore {
  _FakeApiKeyStore(this.apiKey);

  final String? apiKey;

  @override
  Future<String?> readApiKey(String providerId) async {
    return apiKey;
  }
}

class _RecordingBackgroundService implements AgentRunBackgroundService {
  final started = <AgentRunBackgroundTask>[];
  final stopped = <String?>[];

  @override
  Future<void> start(AgentRunBackgroundTask task) async {
    started.add(task);
  }

  @override
  Future<void> stop({String? runId}) async {
    stopped.add(runId);
  }
}

class _FailingCompletionPersistStore extends InMemoryWorkbenchStore {
  bool failMessageWrites = false;

  @override
  Future<void> savePendingAgentRun(PendingAgentRun run) async {
    await super.savePendingAgentRun(run);
    failMessageWrites = true;
  }

  @override
  Future<void> upsertMessage({
    required String workspaceId,
    required AgentMessage message,
  }) async {
    if (failMessageWrites) {
      throw StateError('message persist failed');
    }
    await super.upsertMessage(workspaceId: workspaceId, message: message);
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

class _CreateThenUpdateWebAppChatClient extends OpenAiCompatibleChatClient {
  int callCount = 0;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    final content = messages.last['content'];
    final payload = content is String
        ? jsonDecode(content) as Map<String, Object?>
        : <String, Object?>{};
    final latest = payload['latest_user_message'] as String? ?? '';
    final isUpdate = latest.contains('修复');
    return ChatCompletionResult(
      ok: true,
      content: jsonEncode({
        'selected_tool_names': isUpdate
            ? [
                'artifact_query',
                'file_read_app_file',
                'file_search_app_files',
                'project_update_web_app',
              ]
            : [
                'artifact_query',
                'file_write_app_file',
                'project_create_web_app',
              ],
        'required_tool_names': isUpdate
            ? const <String>[]
            : ['project_create_web_app'],
        'uses_context': isUpdate,
        'reason': isUpdate
            ? 'test update existing web app route'
            : 'test create web app route',
      }),
    );
  }

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    final index = callCount;
    callCount += 1;
    if (index == 0) {
      yield ChatStreamEvent(
        toolCallDeltas: [
          ToolCallDelta(
            index: 0,
            id: 'call-create-linked-webapp',
            name: 'project_create_web_app',
            argumentsDelta: jsonEncode({
              'title': '联动测试 Web App',
              'summary': '用于验证创建和更新后都能在对话中打开。',
              'entry_path': 'apps/linked/index.html',
              'files': [
                {
                  'path': 'apps/linked/index.html',
                  'content':
                      '<!doctype html><html><body><button>旧按钮</button></body></html>',
                },
              ],
            }),
          ),
        ],
      );
      return;
    }
    if (index == 1) {
      yield const ChatStreamEvent(contentDelta: '已创建。');
      return;
    }
    if (index == 2) {
      final artifactId = _artifactIdFromModelMessages(messages);
      yield ChatStreamEvent(
        toolCallDeltas: [
          ToolCallDelta(
            index: 0,
            id: 'call-update-linked-webapp',
            name: 'project_update_web_app',
            argumentsDelta: jsonEncode({
              'artifact_id': artifactId,
              'summary': '修复按钮文案',
              'patches': [
                {
                  'path': 'apps/linked/index.html',
                  'old_text': '旧按钮',
                  'new_text': '新按钮',
                },
              ],
            }),
          ),
        ],
      );
      return;
    }
    yield const ChatStreamEvent(contentDelta: '已更新。');
  }

  String _artifactIdFromModelMessages(List<Map<String, Object?>> messages) {
    final joined = messages.map((message) => message['content']).join('\n');
    final match = RegExp(
      r'Artifact [^:\n]+: (artifact-[^\s\n]+)',
    ).firstMatch(joined);
    return match?.group(1) ?? '';
  }
}

class _FakeChatClient extends OpenAiCompatibleChatClient {
  _FakeChatClient(this.rounds);

  final List<List<ChatStreamEvent>> rounds;
  final List<List<Map<String, Object?>>> capturedMessages = [];
  final List<List<Map<String, Object?>>> capturedTools = [];
  final List<String> capturedModels = [];
  final List<String> capturedApiKeys = [];
  int callCount = 0;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    final content = messages.last['content'];
    final payload = content is String
        ? jsonDecode(content) as Map<String, Object?>
        : <String, Object?>{};
    final latest = payload['latest_user_message'] as String? ?? '';
    final context = payload['recent_context'] as String? ?? '';
    return ChatCompletionResult(
      ok: true,
      content: jsonEncode(_routeDecisionForTest(latest, context)),
    );
  }

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
    capturedApiKeys.add(apiKey);
    final events = rounds[callCount];
    callCount += 1;
    for (final event in events) {
      yield event;
    }
  }
}

class _RequiredNoteToolChatClient extends OpenAiCompatibleChatClient {
  int callCount = 0;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    return ChatCompletionResult(
      ok: true,
      content: jsonEncode(
        _routeDecision({'db_note_create', 'db_note_query'}, {'db_note_create'}),
      ),
    );
  }

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    final index = callCount;
    callCount += 1;
    if (index == 0) {
      yield const ChatStreamEvent(
        toolCallDeltas: [
          ToolCallDelta(
            index: 0,
            id: 'call-required-note',
            name: 'db_note_create',
            argumentsDelta: '{"title":"待办","content":"映射检查"}',
          ),
        ],
      );
      return;
    }
    yield const ChatStreamEvent(contentDelta: '已记录。');
  }
}

class _BlockingWebAppToolChatClient extends OpenAiCompatibleChatClient {
  final firstStreamStarted = Completer<void>();
  final secondStreamStarted = Completer<void>();
  final finalAnswerDeltaApplied = Completer<void>();
  final releaseToolCall = Completer<void>();
  final releaseFinalAnswer = Completer<void>();
  int callCount = 0;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    return ChatCompletionResult(
      ok: true,
      content: jsonEncode(
        _routeDecision(
          {'project_create_web_app', 'artifact_query', 'file_write_app_file'},
          {'project_create_web_app'},
        ),
      ),
    );
  }

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    final index = callCount;
    callCount += 1;
    if (index == 0) {
      firstStreamStarted.complete();
      await releaseToolCall.future;
      yield _webAppToolCallRound(0);
      return;
    }
    secondStreamStarted.complete();
    yield const ChatStreamEvent(contentDelta: '已');
    finalAnswerDeltaApplied.complete();
    await releaseFinalAnswer.future;
    yield const ChatStreamEvent(contentDelta: '创建。');
  }
}

class _SlowWebAppArgumentsChatClient extends OpenAiCompatibleChatClient {
  final firstDeltaApplied = Completer<void>();
  final releaseRemainingArguments = Completer<void>();
  int callCount = 0;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    return ChatCompletionResult(
      ok: true,
      content: jsonEncode(
        _routeDecision(
          {'project_create_web_app', 'artifact_query', 'file_write_app_file'},
          {'project_create_web_app'},
        ),
      ),
    );
  }

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    final index = callCount;
    callCount += 1;
    if (index == 0) {
      yield const ChatStreamEvent(
        toolCallDeltas: [
          ToolCallDelta(
            index: 0,
            id: 'call-slow-webapp',
            name: 'project_create_web_app',
            argumentsDelta: '{"title":"慢速 Web App","summary":"',
          ),
        ],
      );
      firstDeltaApplied.complete();
      await releaseRemainingArguments.future;
      yield ChatStreamEvent(
        toolCallDeltas: [
          const ToolCallDelta(
            index: 0,
            argumentsDelta:
                '用于验证慢速工具参数状态。","entry_path":"apps/slow/index.html",'
                '"files":[{"path":"apps/slow/index.html",'
                '"content":"<!doctype html><html><body>Slow</body></html>"}]}',
          ),
        ],
      );
      return;
    }
    yield const ChatStreamEvent(contentDelta: '已创建。');
  }
}

class _RetryAfterPartialToolArgumentsChatClient
    extends OpenAiCompatibleChatClient {
  int callCount = 0;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    return ChatCompletionResult(
      ok: true,
      content: jsonEncode(
        _routeDecision(
          {'project_create_web_app', 'artifact_query', 'file_write_app_file'},
          {'project_create_web_app'},
        ),
      ),
    );
  }

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    final index = callCount;
    callCount += 1;
    if (index == 0) {
      yield const ChatStreamEvent(
        toolCallDeltas: [
          ToolCallDelta(
            index: 0,
            id: 'call-interrupted-webapp',
            name: 'project_create_web_app',
            argumentsDelta: '{"title":"半截',
          ),
        ],
      );
      throw const ModelRequestException('工具参数流中断', isRetryable: true);
    }
    if (index == 1) {
      yield _webAppToolCallRound(0);
      return;
    }
    yield const ChatStreamEvent(contentDelta: '已创建。');
  }
}

class _BlockingSecondRouteChatClient extends _FakeChatClient {
  _BlockingSecondRouteChatClient(super.rounds);

  final secondRouteStarted = Completer<void>();
  final releaseSecondRoute = Completer<void>();
  int _routeCallCount = 0;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    _routeCallCount += 1;
    if (_routeCallCount == 2) {
      secondRouteStarted.complete();
      await releaseSecondRoute.future;
    }
    return super.completeText(
      provider: provider,
      apiKey: apiKey,
      messages: messages,
    );
  }
}

Map<String, Object?> _routeDecisionForTest(String latest, String context) {
  final selected = <String>{};
  final required = <String>{};

  void add(Iterable<String> names) => selected.addAll(names);

  if (latest.startsWith('用户已批准并执行了刚才的能力请求') ||
      latest.contains('继续处理已批准的能力结果')) {
    return _routeDecision(selected, required);
  }

  if (latest == '你好' ||
      latest == '你是' ||
      latest == '我叫张三' ||
      latest == '我叫什么？') {
    return _routeDecision(selected, required);
  }
  if (latest.contains('搜索') ||
      latest.contains('天气') ||
      context.contains('天气')) {
    add(['web_search', 'web_fetch']);
  }
  if (latest.contains('位置') ||
      latest.contains('我在哪') ||
      context.contains('位置')) {
    add(['location_get_current']);
  }
  if (latest.contains('记住')) {
    add(['memory_create', 'memory_query', 'memory_delete']);
  }
  if (latest.contains('忘记')) {
    add(['memory_create', 'memory_query', 'memory_delete']);
  }
  if (latest.contains('待办') || latest.contains('记录')) {
    add(['db_note_create', 'db_note_query']);
  }
  if (latest.contains('报告') ||
      latest.contains('Artifact') ||
      latest.contains('可复用')) {
    add(['artifact_create', 'artifact_query']);
  }
  if (latest.contains('文件') || latest.contains('读取') || latest.contains('保存')) {
    add([
      'file_write_app_file',
      'file_read_app_file',
      'file_search_app_files',
      'file_apply_text_patch',
    ]);
  }
  if (latest.contains('网页') ||
      latest.contains('Web App') ||
      latest.contains('小游戏') ||
      latest.contains('本地 Web App')) {
    add([
      'project_create_web_app',
      'artifact_create',
      'artifact_query',
      'file_write_app_file',
      'file_read_app_file',
      'file_search_app_files',
      'file_apply_text_patch',
    ]);
    required.add('project_create_web_app');
  }
  if (latest.contains('复制')) {
    add(['clipboard_read', 'clipboard_write']);
  }
  if (latest.contains('几点') || latest.contains('提醒') || latest.contains('日历')) {
    add(['time_get_current', 'notification_schedule', 'calendar_event_create']);
  }
  if (latest.contains('工作区') || latest.contains('切换')) {
    add(['workspace_create', 'workspace_switch']);
  }
  if (latest.contains('连续查询记忆')) {
    add(['memory_create', 'memory_query', 'memory_delete']);
  }
  return _routeDecision(selected, required);
}

Map<String, Object?> _routeDecision(
  Set<String> selected,
  Set<String> required,
) {
  return {
    'selected_tool_names': selected.toList(growable: false)..sort(),
    'required_tool_names': required.toList(growable: false)..sort(),
    'uses_context': false,
    'reason': 'test route decision',
  };
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
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    return _emptyRouteDecision();
  }

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
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    return _emptyRouteDecision();
  }

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
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    return _emptyRouteDecision();
  }

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

ChatCompletionResult _emptyRouteDecision() {
  return ChatCompletionResult(
    ok: true,
    content: jsonEncode({
      'selected_tool_names': <String>[],
      'required_tool_names': <String>[],
      'uses_context': false,
      'reason': 'test empty route',
    }),
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}

Iterable<MessageBlock> _allBlocks(List<AgentMessage> messages) {
  return messages.expand((message) => message.blocks).expand((block) {
    if (block.type == MessageBlockType.taskProgress) {
      final inner = block.data['blocks'];
      if (inner is Iterable) {
        return [block, ...inner.cast<MessageBlock>()];
      }
    }
    return [block];
  });
}
