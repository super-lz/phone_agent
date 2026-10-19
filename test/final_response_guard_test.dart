import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/final_response_guard.dart';

void main() {
  test('detects raw tool and structured capability output', () {
    expect(looksLikeRawToolProcess('工具结果：{ok: true, title: 待办清单}'), isTrue);
    expect(
      looksLikePseudoToolCallText(
        '<tool_call><function=file.read_app_file>'
        '<parameter=path>apps/city-3d/app.js</parameter></function></tool_call>',
      ),
      isTrue,
    );
    expect(
      looksLikeRawToolProcess(
        '<tool_call><function=artifact.inspect_logs>'
        '<parameter=artifactId>artifact-1</parameter></function></tool_call>',
      ),
      isTrue,
    );
    expect(
      looksLikeRawToolProcess(
        '{ok: true, artifactId: artifact-1, workspaceId: default}',
      ),
      isTrue,
    );
    expect(
      looksLikeRawToolProcess(
        '{"ok":true,"output":{"summary":"已创建"},"capabilityId":"db.note.create"}',
      ),
      isTrue,
    );
    expect(
      looksLikeRawToolProcess(
        '{title: 待办清单, summary: 移动端待办事项应用, entry_path: apps/todo/index.html, files: [{path: apps/todo/index.html}]}',
      ),
      isTrue,
    );
  });

  test('does not flag normal user-facing answer', () {
    expect(looksLikeRawToolProcess('已帮你创建待办清单，可以从上方卡片打开预览。'), isFalse);
    expect(
      looksLikeRawToolProcess('下面是一个示例 JSON：{"name":"Phone Agent"}'),
      isFalse,
    );
    expect(
      looksLikeRawToolProcess(
        '我可以解释工具调用、Capability 和 tool_result 的协议含义，但不会执行它们。',
      ),
      isFalse,
    );
    expect(
      looksLikeRawToolProcess(
        '例如，JSON 响应可包含 {"tool_call_id":"example"}；这只是教学示例。',
      ),
      isFalse,
    );
  });

  test('strips internal tool argument progress from visible text', () {
    const progress = '正在生成 Web App 文件内容，已接收约 117 字符；参数完整后会立即创建。';

    expect(looksLikeInternalToolProgressText(progress), isTrue);
    expect(stripInternalToolProgressText(progress), isEmpty);
    expect(
      stripInternalToolProgressText('正在生成文件写入内容，已接收约 1.5K 字符；参数完整后会立即写入。'),
      isEmpty,
    );
    expect(stripInternalToolProgressText('我来创建待办应用。\n$progress'), '我来创建待办应用。');
    expect(
      stripInternalToolProgressText('已创建待办清单，可以从上方卡片打开预览。'),
      '已创建待办清单，可以从上方卡片打开预览。',
    );
  });

  test('detects mid-sentence truncated assistant replies', () {
    expect(looksLikeTruncatedAssistantText('我看到'), isTrue);
    expect(looksLikeTruncatedAssistantText('我认为'), isTrue);
    expect(looksLikeTruncatedAssistantText('我在'), isTrue);
    expect(looksLikeTruncatedAssistantText('我需要'), isTrue);
    expect(looksLikeTruncatedAssistantText('抱歉，刚才可能是我的'), isTrue);
    expect(looksLikeTruncatedAssistantText('I think it was my'), isTrue);
    expect(looksLikeTruncatedAssistantText('我现在暂时没办法直接为您搜索美食。'), isFalse);
    expect(looksLikeTruncatedAssistantText('我现在暂时没办法直接为您搜索美食'), isFalse);
    expect(looksLikeTruncatedAssistantText('好的'), isFalse);
    expect(looksLikeTruncatedAssistantText('知道了'), isFalse);
    expect(looksLikeTruncatedAssistantText('明白了'), isFalse);
    expect(looksLikeTruncatedAssistantText('上海'), isFalse);
    expect(looksLikeTruncatedAssistantText('42'), isFalse);
    expect(looksLikeTruncatedAssistantText(''), isFalse);
  });

  test(
    'joins continuation without dropping prefix, whitespace or Markdown',
    () {
      expect(mergeAssistantContinuation('我看到', '你在看屏幕。'), '我看到你在看屏幕。');
      expect(mergeAssistantContinuation('我看到', '我看到你在看屏幕。'), '我看到你在看屏幕。');
      expect(mergeAssistantContinuation('我看到', '看到你在看屏幕。'), '我看到你在看屏幕。');
      expect(
        mergeAssistantContinuation('Here is ', 'the answer.'),
        'Here is the answer.',
      );
      expect(mergeAssistantContinuation('这是 **重点', '内容**。'), '这是 **重点内容**。');
      expect(mergeAssistantContinuation('保留前文', ''), '保留前文');
      expect(mergeAssistantContinuation('', '完整回答。'), '完整回答。');
      expect(mergeAssistantContinuation('哈', '哈'), '哈哈');
      expect(mergeAssistantContinuation('**重点**', '**结论**'), '**重点****结论**');
    },
  );
}
