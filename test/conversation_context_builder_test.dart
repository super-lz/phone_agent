import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/conversation_context_builder.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  test('keeps recent conversation entries verbatim', () async {
    final context = await const ConversationContextBuilder(maxRecentChars: 1000)
        .build(
          messages: [
            AgentMessage(
              id: 'user-1',
              role: MessageRole.user,
              createdAt: DateTime(2026),
              blocks: [MessageBlock.markdown('我叫张三')],
            ),
            AgentMessage(
              id: 'assistant-1',
              role: MessageRole.assistant,
              createdAt: DateTime(2026),
              blocks: [MessageBlock.markdown('你好，张三。')],
            ),
          ],
        );

    expect(context.summary, isEmpty);
    expect(context.recentEntries.map((entry) => entry.content), [
      '我叫张三',
      '你好，张三。',
    ]);
  });

  test('keeps todo list restored from json in transcript context', () async {
    final restoredItems = <dynamic>['补齐本地会话', '切换工作区'];
    final context = await const ConversationContextBuilder(maxRecentChars: 1000)
        .build(
          messages: [
            AgentMessage(
              id: 'assistant-todo',
              role: MessageRole.assistant,
              createdAt: DateTime(2026),
              blocks: [
                MessageBlock(
                  type: MessageBlockType.todoList,
                  data: {'items': restoredItems},
                ),
              ],
            ),
          ],
        );

    expect(context.recentEntries.single.content, contains('- 补齐本地会话'));
    expect(context.recentEntries.single.content, contains('- 切换工作区'));
  });

  test('keeps safe tool result summary in transcript context', () async {
    final context = await const ConversationContextBuilder(maxRecentChars: 1000)
        .build(
          messages: [
            AgentMessage(
              id: 'assistant-tool',
              role: MessageRole.assistant,
              createdAt: DateTime(2026),
              blocks: [
                MessageBlock.toolCall('location_get_current', const {}),
                MessageBlock.toolResult('location.get_current', const {
                  'ok': true,
                  'summary': '当前位置：纬度 31.298900，经度 120.585300，精度约 30 米。',
                  'latitude': 31.2989,
                  'longitude': 120.5853,
                  'path': 'reports/location.md',
                  'artifactId': 'artifact-location',
                  'hiddenRaw': '不应该进入模型历史',
                }),
              ],
            ),
          ],
        );

    expect(
      context.recentEntries.single.content,
      contains('location.get_current'),
    );
    expect(context.recentEntries.single.content, contains('当前位置'));
    expect(
      context.recentEntries.single.content,
      contains('reports/location.md'),
    );
    expect(context.recentEntries.single.content, contains('artifact-location'));
    expect(context.recentEntries.single.content, isNot(contains('hiddenRaw')));
    expect(context.recentEntries.single.content, isNot(contains('latitude=')));
  });

  test(
    'drops intermediate assistant process text from transcript context',
    () async {
      final context =
          await const ConversationContextBuilder(maxRecentChars: 1000).build(
            messages: [
              AgentMessage(
                id: 'assistant-intermediate',
                role: MessageRole.assistant,
                createdAt: DateTime(2026),
                blocks: [
                  MessageBlock.intermediateMarkdown('正在分析请求并规划下一步。'),
                  MessageBlock.intermediateMarkdown('已确定执行步骤，开始调用工具。'),
                  MessageBlock.markdown('已经为你创建待办应用。'),
                ],
              ),
            ],
          );

      expect(context.recentEntries.single.content, '已经为你创建待办应用。');
      expect(context.recentEntries.single.content, isNot(contains('正在分析')));
      expect(context.recentEntries.single.content, isNot(contains('开始调用工具')));
    },
  );

  test(
    'drops leaked assistant pseudo tool calls from transcript context',
    () async {
      final context =
          await const ConversationContextBuilder(maxRecentChars: 1000).build(
            messages: [
              AgentMessage(
                id: 'assistant-pseudo-tool-call',
                role: MessageRole.assistant,
                createdAt: DateTime(2026),
                blocks: [
                  MessageBlock.markdown(
                    '<tool_call><function=file.read_app_file>'
                    '<parameter=path>apps/city-3d/app.js</parameter>'
                    '</function></tool_call>',
                  ),
                ],
              ),
              AgentMessage(
                id: 'user-after-pseudo-tool-call',
                role: MessageRole.user,
                createdAt: DateTime(2026),
                blocks: [MessageBlock.markdown('继续修复这个 Web App')],
              ),
            ],
          );

      expect(context.recentEntries, hasLength(1));
      expect(context.recentEntries.single.role, MessageRole.user);
      expect(context.recentEntries.single.content, '继续修复这个 Web App');
    },
  );

  test(
    'keeps nested process tool result summary in transcript context',
    () async {
      final context =
          await const ConversationContextBuilder(maxRecentChars: 1000).build(
            messages: [
              AgentMessage(
                id: 'assistant-process',
                role: MessageRole.assistant,
                createdAt: DateTime(2026),
                blocks: [
                  MessageBlock(
                    type: MessageBlockType.taskProgress,
                    data: {
                      'blocks': [
                        MessageBlock.toolResult('device.info', const {
                          'ok': true,
                          'summary': '设备信息已读取完成。',
                          'artifactId': 'artifact-device',
                          'rawDevice': {'brand': '不应该进入历史'},
                        }),
                        MessageBlock.intermediateMarkdown('正在读取设备信息。'),
                      ],
                    },
                  ),
                  MessageBlock.markdown('你的手机信息已经读取完成。'),
                ],
              ),
            ],
          );

      final content = context.recentEntries.single.content;
      expect(content, contains('你的手机信息已经读取完成。'));
      expect(content, contains('工具结果 device.info'));
      expect(content, contains('设备信息已读取完成'));
      expect(content, contains('artifact-device'));
      expect(content, isNot(contains('rawDevice')));
      expect(content, isNot(contains('正在读取设备信息')));
    },
  );

  test('keeps restored nested process tool result summary', () async {
    final context = await const ConversationContextBuilder(maxRecentChars: 1000)
        .build(
          messages: [
            AgentMessage(
              id: 'assistant-restored-process',
              role: MessageRole.assistant,
              createdAt: DateTime(2026),
              blocks: [
                MessageBlock(
                  type: MessageBlockType.taskProgress,
                  data: {
                    'blocks': [
                      {
                        'type': 'toolResult',
                        'data': {
                          'capabilityId': 'project.create_web_app',
                          'output': {
                            'ok': true,
                            'summary': '已创建待办 Web App。',
                            'artifactId': 'artifact-todo',
                            'html': '<main>不应该进入历史</main>',
                          },
                        },
                      },
                    ],
                  },
                ),
              ],
            ),
          ],
        );

    final content = context.recentEntries.single.content;
    expect(content, contains('project.create_web_app'));
    expect(content, contains('已创建待办 Web App'));
    expect(content, contains('artifact-todo'));
    expect(content, isNot(contains('<main>')));
  });

  test('compacts older entries when recent context budget is full', () async {
    final messages = List.generate(8, (index) {
      return AgentMessage(
        id: 'msg-$index',
        role: index.isEven ? MessageRole.user : MessageRole.assistant,
        createdAt: DateTime(2026),
        blocks: [MessageBlock.markdown('第 $index 条消息 ${'内容' * 20}')],
      );
    });

    final context = await const ConversationContextBuilder(
      maxRecentChars: 90,
      maxSummaryChars: 300,
    ).build(messages: messages);

    expect(context.summary, contains('第 0 条消息'));
    expect(context.recentEntries.last.content, contains('第 7 条消息'));
    expect(context.summary.length, lessThanOrEqualTo(303));
  });

  test(
    'summarizes oversized history instead of forcing it into recent',
    () async {
      final context =
          await const ConversationContextBuilder(
            maxRecentChars: 30,
            maxSummaryChars: 120,
          ).build(
            messages: [
              AgentMessage(
                id: 'oversized',
                role: MessageRole.assistant,
                createdAt: DateTime(2026),
                blocks: [MessageBlock.markdown('上一轮生成了大量内容 ${'源码片段' * 40}')],
              ),
            ],
          );

      expect(context.recentEntries, isEmpty);
      expect(context.summary, contains('上一轮生成了大量内容'));
      expect(context.summary.length, lessThanOrEqualTo(123));
    },
  );

  test(
    'semantic summary input is not pre-truncated to final summary size',
    () async {
      final chatClient = _SummaryCapturingChatClient();
      final messages = [
        AgentMessage(
          id: 'old',
          role: MessageRole.user,
          createdAt: DateTime(2026),
          blocks: [MessageBlock.markdown('${'早期背景' * 120} 尾部关键事实：用户选择方案 B')],
        ),
        AgentMessage(
          id: 'recent',
          role: MessageRole.user,
          createdAt: DateTime(2026),
          blocks: [MessageBlock.markdown('最新问题')],
        ),
      ];

      final context =
          await const ConversationContextBuilder(
            maxRecentChars: 20,
            maxSummaryChars: 120,
          ).build(
            messages: messages,
            chatClient: chatClient,
            provider: ModelProviders.aliyunBailianQwenFlash,
            apiKey: 'test-key',
          );

      expect(context.summary, '压缩摘要');
      expect(chatClient.prompts.single, contains('尾部关键事实'));
    },
  );
}

class _SummaryCapturingChatClient extends OpenAiCompatibleChatClient {
  final prompts = <String>[];

  @override
  Future<String> generateResponse({
    required ModelProviderConfig provider,
    required String apiKey,
    required String prompt,
    String? systemPrompt,
  }) async {
    prompts.add(prompt);
    return '压缩摘要';
  }
}
