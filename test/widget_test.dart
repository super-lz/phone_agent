import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/app/phone_agent_app.dart';

void main() {
  testWidgets('renders Phone Agent workbench', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PhoneAgentApp());

    expect(find.text('Phone Agent'), findsWidgets);
    expect(find.text('默认'), findsWidgets);
    expect(find.text('Runtime'), findsOneWidget);
    expect(find.textContaining('移动端 Agent 工作台基座'), findsOneWidget);
  });

  testWidgets('creates workspace from the workbench', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PhoneAgentApp());

    await tester.tap(find.byTooltip('创建工作区'));
    await tester.pumpAndSettle();

    expect(find.text('新工作区 4'), findsWidgets);
    expect(find.textContaining('已创建并切换'), findsOneWidget);
  });

  testWidgets('creates and deletes a visible memory', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PhoneAgentApp());

    await tester.tap(find.byTooltip('新增记忆'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '测试记忆：喜欢短答案');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('测试记忆：喜欢短答案'), findsOneWidget);

    await tester.ensureVisible(find.text('测试记忆：喜欢短答案'));
    await tester.pumpAndSettle();
    final memoryTile = find.ancestor(
      of: find.text('测试记忆：喜欢短答案'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: memoryTile, matching: find.byTooltip('删除记忆')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('测试记忆：喜欢短答案'), findsNothing);
  });

  testWidgets('prompt can create a web app artifact', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PhoneAgentApp());

    await tester.enterText(find.byType(TextField), '帮我创建一个备忘录应用');
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已创建 Web App Artifact'), findsOneWidget);
    expect(find.textContaining('AI 生成的本地 Web 小应用'), findsWidgets);
  });

  testWidgets('chat web app card opens preview page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PhoneAgentApp());

    await tester.enterText(find.byType(TextField), '帮我创建一个备忘录应用');
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('点击预览').first);
    await tester.pumpAndSettle();

    expect(find.text('权限确认'), findsOneWidget);
    expect(find.text('允许并打开'), findsOneWidget);
  });
}
