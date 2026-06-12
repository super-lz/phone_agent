bool looksLikeRawToolProcess(String text) {
  final normalized = text.toLowerCase();
  if (looksLikePseudoToolCallText(text) ||
      text.contains('工具调用') ||
      text.contains('工具结果') ||
      normalized.contains('tool_call') ||
      normalized.contains('tool result') ||
      normalized.contains('tool_result') ||
      normalized.contains('toolresult') ||
      normalized.contains('capability')) {
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
