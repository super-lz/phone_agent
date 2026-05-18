import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/app/phone_agent_app.dart';
import 'package:phone_agent/data/models/model_api_key_store.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

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

  testWidgets('clears local workspace data from the app bar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PhoneAgentApp());

    expect(find.textContaining('用户偏好中文回答'), findsOneWidget);

    await tester.tap(find.byTooltip('清理本地数据'));
    await tester.pumpAndSettle();
    expect(find.text('清理本地数据'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '清理'));
    await tester.pumpAndSettle();

    expect(find.textContaining('用户偏好中文回答'), findsNothing);
    expect(find.textContaining('本地工作区内容已清理'), findsWidgets);
  });

  testWidgets('prompt can create a web app artifact', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(_appWithWebAppModel());

    await tester.enterText(find.byType(TextField), '帮我创建一个备忘录应用');
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已生成 Web App'), findsOneWidget);
    expect(find.textContaining('测试备忘录 Web App'), findsWidgets);
  });

  testWidgets('chat web app card opens preview page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(_appWithWebAppModel());

    await tester.enterText(find.byType(TextField), '帮我创建一个备忘录应用');
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('点击预览').first);
    await tester.pumpAndSettle();

    expect(find.text('权限确认'), findsOneWidget);
    expect(find.text('允许并打开'), findsOneWidget);
  });
}

PhoneAgentApp _appWithWebAppModel() {
  return PhoneAgentApp(
    apiKeyStore: _FakeApiKeyStore('test-key'),
    chatClient: _FakeChatClient([
      [_webAppToolCallRound()],
      [const ChatStreamEvent(contentDelta: '已生成 Web App。')],
    ]),
  );
}

ChatStreamEvent _webAppToolCallRound() {
  return ChatStreamEvent(
    toolCallDeltas: [
      ToolCallDelta(
        index: 0,
        id: 'call-webapp-widget',
        name: 'project_create_web_app',
        argumentsDelta: jsonEncode({
          'title': '测试备忘录 Web App',
          'summary': '用于验证聊天卡片可以打开预览。',
          'entry_path': 'memo-app/index.html',
          'files': [
            {
              'path': 'memo-app/index.html',
              'content': '<main><h1>测试备忘录</h1></main>',
            },
          ],
          'permissions': ['db.note.create', 'db.note.query'],
        }),
      ),
    ],
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

class _FakeChatClient extends OpenAiCompatibleChatClient {
  _FakeChatClient(this.rounds);

  final List<List<ChatStreamEvent>> rounds;
  int callCount = 0;

  @override
  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    final events = rounds[callCount];
    callCount += 1;
    for (final event in events) {
      yield event;
    }
  }
}
