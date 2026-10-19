bool looksLikeRawToolProcess(String text) {
  if (looksLikePseudoToolCallText(text)) {
    return true;
  }

  if (_hasRawStructuredKey(text)) {
    return true;
  }

  return _structuredKeyCount(text) >= 3 && _hasStructuredContainer(text);
}

bool looksLikePseudoToolCallText(String text) {
  final normalized = text.toLowerCase();
  if (!normalized.contains('<') ||
      !normalized.contains('>') ||
      (!normalized.contains('tool_call') &&
          !normalized.contains('function=') &&
          !normalized.contains('parameter='))) {
    return false;
  }
  return _pseudoToolCallPatterns.any((pattern) => pattern.hasMatch(text));
}

String stripInternalToolProgressText(String text) {
  var cleaned = text;
  for (final pattern in _internalToolProgressPatterns) {
    cleaned = cleaned.replaceAll(pattern, '');
  }
  return cleaned
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .join('\n')
      .trim();
}

bool looksLikeInternalToolProgressText(String text) =>
    text.contains('已接收约') &&
    text.contains('字符') &&
    (text.contains('正在生成 Web App 文件内容') ||
        text.contains('正在生成 Web App 修改内容') ||
        text.contains('正在生成文件写入内容') ||
        text.contains('正在接收工具参数'));

bool looksLikeTruncatedAssistantText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  const completeShortReplies = {
    '好的',
    '是的',
    '可以',
    '不行',
    '谢谢',
    '收到',
    '知道了',
    '明白了',
    'okay',
    'yes',
    'no',
  };
  if (completeShortReplies.contains(trimmed.toLowerCase())) {
    return false;
  }
  // A subject plus a verb that still requires an object is unfinished even
  // when it is only a few characters long. Length alone is not completeness.
  if (_unfinishedClause.hasMatch(trimmed)) {
    return true;
  }
  if (RegExp(r'[。！？!?…]$').hasMatch(trimmed)) {
    return false;
  }
  const tails = [
    '的',
    '了',
    '是',
    '和',
    '与',
    '在',
    '把',
    '被',
    '从',
    '对',
    '为',
    '而',
    '但',
    '或',
    '以及',
    '因为',
    '所以',
    '可能',
    '应该',
    '会',
    '能',
    '要',
    '就',
    '才',
    '也',
    '还',
    '再',
    '并',
    '且',
    '，',
    ',',
    '：',
    ':',
    '、',
    ' the',
    ' a',
    ' an',
    ' to',
    ' of',
    ' and',
    ' or',
    ' my',
  ];
  final lower = trimmed.toLowerCase();
  return tails.any(lower.endsWith);
}

final _unfinishedClause = RegExp(
  r'(?:^|[。！？!?\n])\s*(?:我(?:们)?|你(?:们)?|您|他(?:们)?|她(?:们)?)'
  r'(?:刚刚|刚才|已经|正在|可以|能够|还|也|会|能|想|要)*'
  r'(?:看到|看见|发现|认为|觉得|需要|准备|想要|希望|建议)\s*[。.!！?？]*$',
);

const assistantContinuationPrompt =
    '上一条回复没有说完。请从中断处继续，输出完整的面向用户回答；'
    '不要重复已经说过的句子开头，也不要解释这次续写。';

/// Join actual model text, preserving whitespace and Markdown across the cut.
/// A provider may repeat the prefix or the last few characters when continuing.
String mergeAssistantContinuation(String prefix, String continuation) {
  if (prefix.isEmpty) return continuation;
  if (continuation.isEmpty) return prefix;
  final maxOverlap = prefix.length < continuation.length
      ? prefix.length
      : continuation.length;
  // Linear overlap matching keeps large, streamed answers from allocating a
  // substring for every possible boundary on every incoming delta.
  final borders = List<int>.filled(maxOverlap, 0);
  for (var i = 1, matched = 0; i < maxOverlap; i++) {
    while (matched > 0 &&
        continuation.codeUnitAt(i) != continuation.codeUnitAt(matched)) {
      matched = borders[matched - 1];
    }
    if (continuation.codeUnitAt(i) == continuation.codeUnitAt(matched)) {
      matched++;
    }
    borders[i] = matched;
  }
  var matched = 0;
  for (var i = prefix.length - maxOverlap; i < prefix.length; i++) {
    while (matched > 0 &&
        (matched == maxOverlap ||
            prefix.codeUnitAt(i) != continuation.codeUnitAt(matched))) {
      matched = borders[matched - 1];
    }
    if (prefix.codeUnitAt(i) == continuation.codeUnitAt(matched)) matched++;
  }
  if (matched >= 2 &&
      _continuationOverlapContent.hasMatch(
        continuation.substring(0, matched),
      )) {
    return prefix + continuation.substring(matched);
  }
  return prefix + continuation;
}

final _continuationOverlapContent = RegExp(r'[\p{L}\p{N}]', unicode: true);

final _internalToolProgressPatterns = [
  RegExp(
    r'正在生成\s*Web\s*App\s*文件内容[，,；;\s]*已接收约\s*\d+(?:\.\d+)?\s*[Kk]?\s*字符[，,；;。\.\s]*(?:参数完整后会(?:立即创建|创建项目并自动检查)[。\.]?)?',
  ),
  RegExp(
    r'正在生成\s*Web\s*App\s*修改内容[，,；;\s]*已接收约\s*\d+(?:\.\d+)?\s*[Kk]?\s*字符[，,；;。\.\s]*(?:参数完整后会(?:更新项目并自动检查|立即更新)[。\.]?)?',
  ),
  RegExp(
    r'正在生成文件写入内容[，,；;\s]*已接收约\s*\d+(?:\.\d+)?\s*[Kk]?\s*字符[，,；;。\.\s]*(?:参数完整后会立即写入[。\.]?)?',
  ),
  RegExp(
    r'正在接收工具参数[，,；;\s]*已接收约\s*\d+(?:\.\d+)?\s*[Kk]?\s*字符[，,；;。\.\s]*(?:参数完整后会立即执行[。\.]?)?',
  ),
];

final _pseudoToolCallPatterns = [
  RegExp(r'<\s*/?\s*tool_call\b', caseSensitive: false),
  RegExp(r'<\s*function\s*=\s*[^>]+>', caseSensitive: false),
  RegExp(r'</\s*function\s*>', caseSensitive: false),
  RegExp(r'<\s*parameter\s*=\s*[^>]+>', caseSensitive: false),
  RegExp(r'</\s*parameter\s*>', caseSensitive: false),
];

bool _hasStructuredContainer(String text) {
  return text.contains('{') ||
      text.contains('}') ||
      text.contains('[') ||
      text.contains(']');
}

bool _hasRawStructuredKey(String text) {
  final rawKeyPattern = RegExp(
    r'''[\{\[,]\s*["']?(ok|error|output|artifactId|artifact_id|workspaceId|workspace_id|activeWorkspaceId|active_workspace_id|capabilityId|capability_id|toolName|tool_name)["']?\s*:''',
    caseSensitive: false,
  );
  return rawKeyPattern.hasMatch(text);
}

int _structuredKeyCount(String text) {
  const keys = {
    'ok',
    'error',
    'output',
    'summary',
    'title',
    'entry_path',
    'entrypath',
    'artifactid',
    'artifact_id',
    'workspaceid',
    'workspace_id',
    'activeworkspaceid',
    'active_workspace_id',
    'capabilityid',
    'capability_id',
    'projectid',
    'project_id',
    'files',
    'path',
    'content',
    'metadata',
    'permissions',
  };
  final keyPattern = RegExp(r'''["']?([A-Za-z_][A-Za-z0-9_]*)["']?\s*:''');
  final matched = <String>{};
  for (final match in keyPattern.allMatches(text)) {
    final key = match.group(1);
    if (key == null) {
      continue;
    }
    final normalizedKey = key.toLowerCase();
    if (keys.contains(normalizedKey)) {
      matched.add(normalizedKey);
    }
  }
  return matched.length;
}
