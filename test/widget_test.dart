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

  testWidgets('prompt can create a memory', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PhoneAgentApp());

    await tester.enterText(find.byType(TextField), '记住我喜欢先看第一性原理');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.textContaining('已写入'), findsOneWidget);
    expect(find.textContaining('我喜欢先看第一性原理'), findsWidgets);
  });
}
