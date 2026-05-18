import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/domain/workspace/workspace.dart';
import 'package:phone_agent/features/workbench/widgets/chat_panel.dart';

void main() {
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
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
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
              onSendPrompt: () {},
              onOpenWebAppArtifact: (_) {},
              onApproveCapability: (_) {},
              onDenyCapability: (_) {},
              pendingAttachments: const [],
              onAddFile: () {},
              onAddImage: () {},
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
                onSendPrompt: () {},
                onOpenWebAppArtifact: (_) {},
                onApproveCapability: (_) {},
                onDenyCapability: (_) {},
                pendingAttachments: const [],
                onAddFile: () {},
                onAddImage: () {},
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
            onSendPrompt: () {},
            onOpenWebAppArtifact: (_) {},
            onApproveCapability: (_) {},
            onDenyCapability: (_) {},
            pendingAttachments: const [],
            onAddFile: () {},
            onAddImage: () {},
            onRemovePendingAttachment: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('已处理'), findsOneWidget);
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
