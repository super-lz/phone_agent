import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/agent_run_state.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/features/workbench/widgets/agent_process_entries.dart';
import 'package:phone_agent/features/workbench/widgets/message_view.dart';
import 'package:phone_agent/features/workbench/widgets/tool_step_view.dart';

void main() {
  test('pairs repeated calls once in emission order across tool aliases', () {
    final first = MessageBlock.toolCall('db_note_create', {'title': '一'});
    final second = MessageBlock.toolCall('db_note_create', {'title': '二'});
    final result = MessageBlock.toolResult('db.note.create', {'ok': true});
    final steps = agentProcessEntries([
      first,
      result,
      second,
    ]).whereType<ToolStepEntry>().toList();
    expect(steps, hasLength(2));
    expect(steps.first.call, same(first));
    expect(steps.first.result, same(result));
    expect(steps.last.result, isNull);
    expect(steps.last.status('processing'), ToolStepStatus.running);
    expect(steps.last.status('completed'), ToolStepStatus.unknown);
    expect(steps.last.status('stopped'), ToolStepStatus.stopped);
  });

  test('preserves orphan results and intermediate content', () {
    final result = MessageBlock.toolResult('web.fetch', {'ok': true});
    final text = MessageBlock.intermediateMarkdown('检查资料');
    final entries = agentProcessEntries([result, text]);
    expect((entries.first as ToolStepEntry).result, same(result));
    expect((entries.last as ProcessContentEntry).block, same(text));
  });

  for (final (decision, expected) in [
    ('approved', ToolStepStatus.authorized),
    ('denied', ToolStepStatus.denied),
  ]) {
    test('restored $decision approval no longer reports waiting', () {
      final entries = agentProcessEntries([
        MessageBlock.toolCall('file_write_app_file', {'path': 'docs/a.txt'}),
        MessageBlock.toolResult('file.write_app_file', {
          'ok': false,
          'error': 'permission_confirmation_required',
        }),
        MessageBlock(
          type: MessageBlockType.approvalRequest,
          data: {'toolName': 'file_write_app_file', 'status': decision},
        ),
      ]);
      expect(
        entries.whereType<ToolStepEntry>().single.status('completed'),
        expected,
      );
    });
  }

  testWidgets(
    'continuation after a folded checkpoint still uses unified steps',
    (tester) async {
      await _pumpMessage(tester, [
        MessageBlock(
          type: MessageBlockType.taskProgress,
          data: {
            'status': 'completed',
            'blocks': [
              MessageBlock.toolCall('web_search', {'query': '资料'}),
              MessageBlock.toolResult('web.search', {'ok': true}),
            ],
          },
        ),
        MessageBlock.toolCall('file_write_app_file', {'path': 'docs/a.txt'}),
      ]);
      expect(find.text('已完成 联网搜索'), findsOneWidget);
      expect(find.text('正在执行 写入文件'), findsOneWidget);
      expect(find.byType(ToolStepView), findsOneWidget);
    },
  );

  testWidgets('second call remains running after first result', (tester) async {
    await _pumpMessage(tester, [
      MessageBlock.toolCall('db_note_create', {'title': '第一条'}),
      MessageBlock.toolResult('db.note.create', {'ok': true}),
      MessageBlock.toolCall('db_note_create', {'title': '第二条'}),
    ]);
    expect(find.text('正在执行 记录笔记'), findsOneWidget);
    expect(find.byType(ToolStepView), findsNWidgets(2));
    expect(find.text('执行中'), findsOneWidget);
  });

  for (final (output, label) in <(Map<String, Object?>, String)>[
    ({'ok': false, 'error': 'permission_confirmation_required'}, '等待授权'),
    ({'ok': false, 'error': 'permission_denied'}, '已拒绝'),
    ({'ok': false, 'error': 'network_error'}, '执行失败'),
    ({'ok': false, 'error': 'action_result_unknown'}, '结果未知'),
    (
      {
        'ok': true,
        'receipt': {'status': 'result_unknown'},
      },
      '结果未知',
    ),
  ]) {
    testWidgets('terminal trace reports $label without a success claim', (
      tester,
    ) async {
      await _pumpMessage(tester, [
        MessageBlock.toolCall('file_write_app_file', {
          'path': 'docs/report.txt',
        }),
        MessageBlock.toolResult('file.write_app_file', output),
        MessageBlock.markdown('请查看执行状态。'),
      ]);
      expect(find.text('执行过程 · $label'), findsOneWidget);
      expect(find.textContaining('已完成'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('执行过程 · $label'));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets(
    'pending approval stays accessible in a collapsed restored trace',
    (tester) async {
      final approval = MessageBlock.approvalRequest(
        requestId: 'request-1',
        toolName: 'file_write_app_file',
        capabilityId: 'file.write_app_file',
        workspaceId: 'default',
        input: {'path': 'docs/report.html', 'content': '<private source>'},
        detail: '将覆盖该文件，请确认目标。',
      );
      Map<String, Object?>? approved;
      Map<String, Object?>? denied;
      await _pumpMessage(
        tester,
        [
          MessageBlock(
            type: MessageBlockType.taskProgress,
            data: {
              'status': 'completed',
              'blocks': [
                MessageBlock.toolCall('file_write_app_file', {
                  'path': 'docs/report.html',
                }),
                MessageBlock.toolResult('file.write_app_file', {
                  'ok': false,
                  'error': 'permission_confirmation_required',
                }),
                approval,
              ].map((block) => block.toJson()).toList(),
            },
          ),
        ],
        onApprove: (value) => approved = value,
        onDeny: (value) => denied = value,
      );
      expect(find.byType(ToolStepView), findsNothing);
      expect(find.text('允许执行'), findsOneWidget);
      expect(find.textContaining('<private source>'), findsNothing);
      await tester.tap(find.text('允许执行'));
      expect(approved, equals(approval.data));
      await tester.tap(find.text('拒绝'));
      expect(denied, equals(approval.data));
      await tester.tap(find.text('等待授权'));
      await tester.pumpAndSettle();
      expect(find.text('允许执行'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
    },
  );

  testWidgets(
    'final body and artifacts remain visible outside collapsed trace',
    (tester) async {
      String? opened;
      await _pumpMessage(tester, [
        MessageBlock.toolCall('project_create_web_app', {'title': '旅行清单'}),
        MessageBlock.toolResult('project.create_web_app', {'ok': true}),
        MessageBlock.markdown('清单已经准备好了。'),
        MessageBlock.webAppCard('app-1', '旅行清单'),
        MessageBlock.artifactCard('artifact-1', '参考资料'),
      ], onOpen: (id) => opened = id);
      expect(find.byType(ToolStepView), findsNothing);
      expect(find.text('清单已经准备好了。'), findsOneWidget);
      expect(find.text('参考资料'), findsOneWidget);
      expect(find.textContaining('Artifact ID'), findsNothing);
      await tester.tap(find.text('旅行清单'));
      expect(opened, 'app-1');
    },
  );

  testWidgets('real parameter phase is distinct from executing a tool', (
    tester,
  ) async {
    await _pumpMessage(
      tester,
      [MessageBlock.intermediateMarkdown('准备页面')],
      run: AgentRunSnapshot(
        phase: AgentRunPhase.waitingForToolCall,
        detail: '正在接收工具参数',
        currentToolName: 'project_create_web_app',
        toolCallsUsed: 0,
        maxToolCalls: null,
        startedAt: DateTime(2026),
      ),
    );
    expect(find.text('正在生成参数 · 创建 Web App'), findsOneWidget);
    expect(find.textContaining('正在执行'), findsNothing);
  });

  testWidgets('narrow large text layout keeps tool and approval actions usable', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpMessage(tester, [
      MessageBlock.toolCall('file_write_app_file', {
        'path':
            'documents/very-long-directory-name/reports/very-long-report-name.html',
        'content': 'hidden generated source',
      }),
      MessageBlock.approvalRequest(
        requestId: 'narrow',
        toolName: 'file_write_app_file',
        capabilityId: 'file.write_app_file',
        workspaceId: 'default',
        input: {'path': 'documents/report.html'},
        detail: '将写入文件。',
      ),
      MessageBlock.webAppCard('long-app', '这是一份标题很长且需要自然换行的应用清单'),
    ], textScale: 1.6);
    await tester.tap(find.text('执行过程 · 结果未知'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolStepView), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('允许执行'), findsOneWidget);
    expect(find.textContaining('hidden generated source'), findsNothing);
  });
}

Future<void> _pumpMessage(
  WidgetTester tester,
  List<MessageBlock> blocks, {
  ValueChanged<Map<String, Object?>>? onApprove,
  ValueChanged<Map<String, Object?>>? onDeny,
  ValueChanged<String>? onOpen,
  AgentRunSnapshot? run,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: MessageView(
              message: AgentMessage(
                id: 'test',
                role: MessageRole.assistant,
                createdAt: DateTime(2026),
                blocks: blocks,
              ),
              currentRun: run,
              onOpenWebAppArtifact: onOpen ?? (_) {},
              onApproveCapability: onApprove,
              onDenyCapability: onDeny,
            ),
          ),
        ),
      ),
    ),
  ),
);
