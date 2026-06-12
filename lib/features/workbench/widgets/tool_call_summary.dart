import '../../../domain/conversation/message_block.dart';

String toolCallSummary(String capabilityId, Object? rawInput) {
  final input = _stringKeyMap(rawInput);
  return switch (capabilityId) {
    'project_create_web_app' => _webAppCreateSummary(input),
    'project_update_web_app' => _webAppUpdateSummary(input),
    'file_write_app_file' => _fileWriteSummary(input),
    _ => _genericToolSummary(input),
  };
}

String _webAppCreateSummary(Map<String, Object?> input) {
  final parts = <String>['创建 Web App：${_stringValue(input['title']) ?? '未命名'}'];
  final summary = _stringValue(input['summary']);
  if (summary != null) {
    parts.add('说明：${_truncate(summary, 80)}');
  }
  final entryPath = _stringValue(input['entry_path'] ?? input['entryPath']);
  if (entryPath != null) {
    parts.add('入口：$entryPath');
  }
  final files = _filePaths(input['files']);
  if (files.isNotEmpty) {
    parts.add('文件：${_formatList(files)}');
  }
  final permissions = MessageBlock.stringList(input['permissions']);
  if (permissions.isNotEmpty) {
    parts.add('权限：${_formatList(permissions)}');
  }
  return parts.join('\n');
}

String _webAppUpdateSummary(Map<String, Object?> input) {
  final parts = <String>['更新 Web App：${_artifactLabel(input)}'];
  final files = _filePaths(input['files']);
  if (files.isNotEmpty) {
    parts.add('写入文件：${_formatList(files)}');
  }
  final patches = _patchPaths(input['patches']);
  if (patches.isNotEmpty) {
    parts.add('补丁文件：${_formatList(patches)}');
  }
  final summary = _stringValue(input['summary']);
  if (summary != null) {
    parts.add('说明：${_truncate(summary, 80)}');
  }
  return parts.join('\n');
}

String _fileWriteSummary(Map<String, Object?> input) {
  final path = _stringValue(input['path']) ?? '未指定路径';
  final overwrite = input['overwrite'];
  return [
    '写入文件：$path',
    if (overwrite is bool) '覆盖：${overwrite ? '是' : '否'}',
  ].join('\n');
}

String _genericToolSummary(Map<String, Object?> input) {
  if (input.isEmpty) {
    return '无参数';
  }
  return input.entries
      .map(
        (entry) => '${entry.key}: ${_safeValuePreview(entry.key, entry.value)}',
      )
      .join('\n');
}

String _artifactLabel(Map<String, Object?> input) =>
    _stringValue(input['artifact_id'] ?? input['artifactId']) ?? '未指定 Artifact';

Map<String, Object?> _stringKeyMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

String? _stringValue(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

List<String> _filePaths(Object? value) {
  if (value is! Iterable<Object?>) {
    return const [];
  }
  final paths = <String>[];
  for (final item in value) {
    if (item is Map<Object?, Object?>) {
      final path = _stringValue(item['path']);
      if (path != null) {
        paths.add(path);
      }
    }
  }
  return paths;
}

List<String> _patchPaths(Object? value) {
  if (value is! Iterable<Object?>) {
    return const [];
  }
  final paths = <String>[];
  for (final item in value) {
    if (item is Map<Object?, Object?>) {
      final path = _stringValue(item['path']);
      if (path != null) {
        paths.add(path);
      }
    }
  }
  return paths;
}

String _formatList(List<String> values) {
  const visibleCount = 4;
  final visible = values.take(visibleCount).join('、');
  final remaining = values.length - visibleCount;
  return remaining > 0 ? '$visible 等 $remaining 项' : visible;
}

String _safeValuePreview(String key, Object? value) {
  final normalizedKey = key.toLowerCase();
  if (normalizedKey.contains('content') ||
      normalizedKey == 'html' ||
      normalizedKey == 'code') {
    return '<内容已隐藏>';
  }
  if (value is String) {
    return _truncate(value, 120);
  }
  if (value is Iterable<Object?>) {
    final items = value
        .take(4)
        .map((item) {
          if (item is Map<Object?, Object?> && item.containsKey('path')) {
            return _stringValue(item['path']) ?? '<对象>';
          }
          return _truncate(item.toString(), 60);
        })
        .toList(growable: false);
    final remaining = value.length - items.length;
    return remaining > 0
        ? '[${items.join(', ')}, ...$remaining]'
        : '[${items.join(', ')}]';
  }
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.take(6).map((key) => key.toString()).join(', ');
    return keys.isEmpty ? '{}' : '{$keys}';
  }
  return _truncate(value.toString(), 120);
}

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) {
    return value;
  }
  return '${value.substring(0, maxChars)}...';
}
