import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/agent_run_state.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/domain/workspace/workspace.dart';
import 'package:phone_agent/features/workbench/widgets/chat_panel.dart';

void main() {
  testWidgets('composer only shows send-area stop button while sending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: const [],
            composerController: controller,
            isSending: true,
            currentRun: AgentRunSnapshot(
              phase: AgentRunPhase.executingTool,
              detail: '正在执行 web_search。',
              toolCallsUsed: 3,
              maxToolCalls: 48,
              startedAt: DateTime(2026),
            ),
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('停止'), findsOneWidget);
    expect(find.byTooltip('停止本轮任务'), findsNothing);
    expect(find.textContaining('3/48'), findsNothing);
    expect(find.textContaining('正在执行 web_search'), findsOneWidget);
    expect(find.textContaining('执行工具'), findsNothing);
  });

  testWidgets('routing state is presented as thinking instead of tool prep', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: const [],
            composerController: controller,
            isSending: true,
            currentRun: AgentRunSnapshot(
              phase: AgentRunPhase.routing,
              detail: '正在分析这次请求。',
              toolCallsUsed: 0,
              maxToolCalls: 48,
              startedAt: DateTime(2026),
            ),
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('正在分析这次请求'), findsOneWidget);
    expect(find.textContaining('正在思考'), findsNothing);
    expect(find.textContaining('准备工具'), findsNothing);
  });

  testWidgets('tool argument streaming explains parameter generation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: const [],
            composerController: controller,
            isSending: true,
            currentRun: AgentRunSnapshot(
              phase: AgentRunPhase.waitingForToolCall,
              detail: '正在生成 Web App 文件内容，参数完整后会创建项目并自动检查。',
              toolCallsUsed: 0,
              maxToolCalls: 48,
              startedAt: DateTime(2026),
              currentToolName: 'project_create_web_app',
            ),
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('正在生成 Web App 文件内容'), findsOneWidget);
    expect(find.text('正在生成 Web App 文件内容，参数完整后会创建项目并自动检查。'), findsNothing);
    expect(find.text('正在生成 Web App 文件内容，参数完整后会创建项目并自动检查'), findsOneWidget);
    expect(find.textContaining('生成参数'), findsNothing);
    expect(find.textContaining('调用工具'), findsNothing);

    final statusText = tester.widget<Text>(
      find.textContaining('正在生成 Web App 文件内容'),
    );
    expect(statusText.maxLines, 2);
    expect(statusText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('idle composer suggestions copy text into the input', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: const [],
            composerController: controller,
            isSending: false,
            currentRun: null,
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('帮我创建一个待办 Web App'));
    await tester.pump();

    expect(controller.text, '帮我创建一个待办 Web App');
  });

  testWidgets('shows jump to bottom button when user leaves bottom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: [
              for (var index = 0; index < 40; index += 1)
                AgentMessage(
                  id: 'msg-$index',
                  role: MessageRole.assistant,
                  createdAt: DateTime(2026),
                  blocks: [
                    MessageBlock.markdown('消息 $index\n\n这是一段用于撑高列表的内容。'),
                  ],
                ),
            ],
            composerController: controller,
            isSending: false,
            currentRun: null,
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byTooltip('滚动到底部'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.byTooltip('滚动到底部'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 460));
    await tester.pumpAndSettle();
    expect(find.byTooltip('滚动到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('滚动到底部'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('滚动到底部'), findsNothing);
  });

  testWidgets('attachment menu dispatches the picked action once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    var addFileCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: const [],
            composerController: controller,
            isSending: false,
            currentRun: null,
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {
              addFileCalls += 1;
            },
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('上传文件'));
    await tester.pumpAndSettle();

    expect(addFileCalls, 1);
    expect(find.text('上传文件'), findsNothing);
  });

  testWidgets('pending image attachment is visible above the composer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    var removedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: const [],
            composerController: controller,
            isSending: false,
            currentRun: null,
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: [
              MessageBlock.image(
                name: 'photo.png',
                uri: Uri.file('/tmp/photo.png').toString(),
                bytes: 2048,
                mimeType: 'image/png',
              ),
            ],
            onAddFile: () {},
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (index) {
              removedIndex = index;
            },
          ),
        ),
      ),
    );

    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);

    await tester.tap(find.byTooltip('移除附件'));
    await tester.pump();

    expect(removedIndex, 0);
  });

  testWidgets(
    'loads recent messages first and prepends older messages on top',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanel(
              workspace: AgentWorkspace(
                id: 'default',
                name: '默认',
                description: '测试工作区',
                createdAt: DateTime(2026),
              ),
              messages: [
                for (var index = 0; index < 70; index += 1)
                  AgentMessage(
                    id: 'msg-$index',
                    role: index.isEven
                        ? MessageRole.user
                        : MessageRole.assistant,
                    createdAt: DateTime(2026),
                    blocks: [MessageBlock.markdown('分页消息 $index')],
                  ),
              ],
              composerController: controller,
              isSending: false,
              currentRun: null,
              contextBudget: null,
              onCancelRun: () {},
              onSendPrompt: () {},
              onOpenWebAppArtifact: (_) {},
              onApproveCapability: (_) {},
              onDenyCapability: (_) {},
              pendingAttachments: const [],
              onAddFile: () {},
              onAddImage: () {},
              onTakePhoto: () {},
              onRemovePendingAttachment: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('分页消息 0'), findsNothing);
      expect(find.text('分页消息 69'), findsOneWidget);

      for (var i = 0; i < 8; i += 1) {
        await tester.drag(find.byType(ListView), const Offset(0, 900));
        await tester.pumpAndSettle();
        if (find.text('分页消息 0').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.text('分页消息 0'), findsOneWidget);
    },
  );

  testWidgets('does not force bottom while user reads during streaming', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    var messages = _longConversation();
    late StateSetter refresh;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return ChatPanel(
                workspace: AgentWorkspace(
                  id: 'default',
                  name: '默认',
                  description: '测试工作区',
                  createdAt: DateTime(2026),
                ),
                messages: messages,
                composerController: controller,
                isSending: true,
                currentRun: null,
                contextBudget: null,
                onCancelRun: () {},
                onSendPrompt: () {},
                onOpenWebAppArtifact: (_) {},
                onApproveCapability: (_) {},
                onDenyCapability: (_) {},
                pendingAttachments: const [],
                onAddFile: () {},
                onAddImage: () {},
                onTakePhoto: () {},
                onRemovePendingAttachment: (_) {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(ListView), const Offset(0, 460));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('滚动到底部'), findsOneWidget);

    refresh(() {
      messages = [
        ...messages,
        AgentMessage(
          id: 'streaming-update',
          role: MessageRole.assistant,
          createdAt: DateTime(2026),
          blocks: [MessageBlock.markdown('流式新增内容' * 40)],
        ),
      ];
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('滚动到底部'), findsOneWidget);
  });

  testWidgets('coalesces consecutive assistant rounds into one bubble', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            workspace: AgentWorkspace(
              id: 'default',
              name: '默认',
              description: '测试工作区',
              createdAt: DateTime(2026),
            ),
            messages: [
              AgentMessage(
                id: 'user',
                role: MessageRole.user,
                createdAt: DateTime(2026),
                blocks: [MessageBlock.markdown('查一下天气')],
              ),
              AgentMessage(
                id: 'assistant-tools',
                role: MessageRole.assistant,
                createdAt: DateTime(2026),
                blocks: [
                  MessageBlock.toolCall('web_search', {'query': '天气'}),
                  MessageBlock.toolResult('web.search', const {
                    'ok': true,
                    'provider': 'test',
                    'query': '天气',
                    'content': '搜索结果',
                  }),
                ],
              ),
              AgentMessage(
                id: 'assistant-final',
                role: MessageRole.assistant,
                createdAt: DateTime(2026),
                blocks: [MessageBlock.markdown('今天适合出门。')],
              ),
            ],
            composerController: controller,
            isSending: false,
            currentRun: null,
            contextBudget: null,
            onCancelRun: () {},
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
            onTakePhoto: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Agent'), findsOneWidget);
    expect(find.text('已完成 联网搜索'), findsOneWidget);
    expect(find.text('今天适合出门。'), findsOneWidget);
    expect(find.text('联网搜索结果'), findsNothing);
  });
}

List<AgentMessage> _longConversation() {
  return [
    for (var index = 0; index < 24; index += 1) ...[
      AgentMessage(
        id: 'user-$index',
        role: MessageRole.user,
        createdAt: DateTime(2026),
        blocks: [MessageBlock.markdown('用户消息 $index')],
      ),
      AgentMessage(
        id: 'assistant-$index',
        role: MessageRole.assistant,
        createdAt: DateTime(2026),
        blocks: [MessageBlock.markdown('助手回复 $index\n\n这是一段用于撑高列表的内容。')],
      ),
    ],
  ];
}
