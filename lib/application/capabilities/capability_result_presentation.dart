import 'dart:convert';

class CapabilityResultPresentation {
  const CapabilityResultPresentation({
    required this.title,
    required this.summary,
    required this.detail,
    required this.ok,
  });

  final String title;
  final String summary;
  final String detail;
  final bool ok;
}

CapabilityResultPresentation presentCapabilityResult({
  required String capabilityId,
  required Map<String, Object?> output,
}) {
  final ok = output['ok'] == true;
  return CapabilityResultPresentation(
    title: _titleFor(capabilityId),
    summary: _summaryFor(capabilityId, output, ok: ok),
    detail: _prettyJson(output),
    ok: ok,
  );
}

Map<String, Object?> modelObservationForCapability({
  required String capabilityId,
  required Map<String, Object?> output,
}) {
  final presentation = presentCapabilityResult(
    capabilityId: capabilityId,
    output: output,
  );
  final observation = <String, Object?>{
    'ok': presentation.ok,
    'summary': presentation.summary,
  };
  if (!presentation.ok) {
    observation['error'] = output['error'];
    observation['detail'] = output['userMessage'] ?? output['detail'];
    return observation;
  }

  switch (capabilityId) {
    case 'device.info':
      observation['device'] = output['device'];
      return observation;
    case 'location.get_current':
      observation.addAll({
        'latitude': output['latitude'],
        'longitude': output['longitude'],
        'accuracy': output['accuracy'],
        'timestamp': output['timestamp'],
        'isMocked': output['isMocked'],
        'providerHint': output['providerHint'],
        'mapsUrl': output['mapsUrl'],
      });
      return observation;
    case 'time.get_current':
      observation.addAll({
        'localIso': output['localIso'],
        'utcIso': output['utcIso'],
        'timeZoneName': output['timeZoneName'],
        'timeZoneOffsetMinutes': output['timeZoneOffsetMinutes'],
      });
      return observation;
    case 'battery.status':
      observation.addAll({
        'level': output['level'],
        'state': output['state'],
        'isCharging': output['isCharging'],
        'isInBatterySaveMode': output['isInBatterySaveMode'],
      });
      return observation;
    case 'network.status':
      observation.addAll({
        'connected': output['connected'],
        'types': output['types'],
      });
      return observation;
    case 'clipboard.read':
      observation.addAll({
        'hasText': output['hasText'],
        'text': _truncateString(output['text'], 2000),
      });
      return observation;
    case 'web.search':
    case 'web.fetch':
      observation.addAll({
        'provider': output['provider'],
        'query': output['query'],
        'url': output['url'],
        'content': _truncateString(output['content'], 6000),
      });
      return observation;
    case 'file.read_app_file':
      observation.addAll({
        'path': output['path'],
        'content': _truncateString(output['content'], 6000),
        'truncated': output['truncated'],
      });
      return observation;
    case 'file.search_app_files':
      observation.addAll({
        'query': output['query'],
        'matches': output['matches'],
        'truncated': output['truncated'],
      });
      return observation;
    case 'document.extract':
    case 'spreadsheet.extract':
    case 'presentation.extract':
    case 'pdf.extract':
      observation.addAll({
        'path': output['path'],
        'format': output['format'],
        'content': _truncateString(output['content'], 6000),
        'truncated': output['truncated'],
      });
      return observation;
    case 'document.generate':
    case 'document.apply_text_patch':
    case 'spreadsheet.generate':
    case 'presentation.generate':
    case 'pdf.generate':
      observation.addAll({
        'path': output['path'],
        'bytes': output['bytes'],
        'preservedFormatting': output['preservedFormatting'],
      });
      return observation;
    default:
      return observation;
  }
}

String _titleFor(String capabilityId) {
  switch (capabilityId) {
    case 'device.info':
      return '设备信息';
    case 'time.get_current':
      return '当前时间';
    case 'battery.status':
      return '电量状态';
    case 'network.status':
      return '网络状态';
    case 'clipboard.read':
      return '剪贴板读取';
    case 'clipboard.write':
      return '剪贴板写入';
    case 'share.text':
      return '系统分享';
    case 'system.haptic_feedback':
      return '触感反馈';
    case 'system.sound_alert':
      return '系统提示音';
    case 'permission.open_settings':
      return '权限设置';
    case 'url.open_external':
      return '打开外部链接';
    case 'screen.keep_awake':
      return '屏幕常亮设置';
    case 'screen.keep_awake_status':
      return '屏幕常亮状态';
    case 'sensor.accelerometer.read':
      return '加速度计';
    case 'sensor.gyroscope.read':
      return '陀螺仪';
    case 'sensor.magnetometer.read':
      return '磁力计';
    case 'location.get_current':
      return '当前位置';
    case 'notification.schedule':
      return '本地通知';
    case 'calendar.event.create':
      return '日历事件';
    case 'db.note.create':
      return '备忘创建';
    case 'db.note.query':
      return '备忘查询';
    case 'file.read_app_file':
      return '文件读取';
    case 'file.write_app_file':
      return '文件写入';
    case 'file.search_app_files':
      return '文件搜索';
    case 'file.apply_text_patch':
      return '文件补丁';
    case 'document.extract':
      return '文档提取';
    case 'document.generate':
      return '文档生成';
    case 'document.apply_text_patch':
      return '文档局部修改';
    case 'spreadsheet.extract':
      return '表格提取';
    case 'spreadsheet.generate':
      return '表格生成';
    case 'presentation.extract':
      return '演示文稿提取';
    case 'presentation.generate':
      return '演示文稿生成';
    case 'pdf.extract':
      return 'PDF 提取';
    case 'pdf.generate':
      return 'PDF 生成';
    case 'artifact.create':
      return 'Artifact 创建';
    case 'artifact.query':
      return 'Artifact 查询';
    case 'project.create_web_app':
      return 'Web App 创建';
    case 'memory.create':
      return '记忆创建';
    case 'memory.query':
      return '记忆查询';
    case 'memory.delete':
      return '记忆删除';
    case 'workspace.create':
      return '工作区创建';
    case 'workspace.switch':
      return '工作区切换';
    default:
      return '工具结果';
  }
}

String _summaryFor(
  String capabilityId,
  Map<String, Object?> output, {
  required bool ok,
}) {
  final directSummary = _stringValue(output['summary']);
  if (directSummary != null) {
    return directSummary;
  }
  final userMessage = _stringValue(output['userMessage']);
  if (userMessage != null) {
    return userMessage;
  }
  if (!ok) {
    return _errorSummary(output);
  }
  switch (capabilityId) {
    case 'device.info':
      return _deviceSummary(output);
    case 'time.get_current':
      return _timeSummary(output);
    case 'battery.status':
      return _batterySummary(output);
    case 'network.status':
      return _networkSummary(output);
    case 'clipboard.read':
      return output['hasText'] == true ? '已读取剪贴板文本。' : '剪贴板里没有可读取的纯文本。';
    case 'clipboard.write':
      return '已写入剪贴板。';
    case 'location.get_current':
      return _locationSummary(output);
    case 'notification.schedule':
      return _notificationSummary(output);
    case 'calendar.event.create':
      return '已打开系统日历添加流程，请在系统界面确认保存。';
    case 'share.text':
      return '已打开系统分享面板。';
    case 'screen.keep_awake':
      return output['enabled'] == true ? '已开启当前应用屏幕常亮。' : '已关闭当前应用屏幕常亮。';
    case 'screen.keep_awake_status':
      return output['enabled'] == true ? '当前应用已保持屏幕常亮。' : '当前应用未开启屏幕常亮。';
    case 'permission.open_settings':
      return output['opened'] == true ? '已打开系统权限设置。' : '未能打开系统权限设置。';
    default:
      return '工具已执行完成。';
  }
}

String _errorSummary(Map<String, Object?> output) {
  final error = _stringValue(output['error']) ?? 'unknown_error';
  final detail = _stringValue(output['detail']);
  if (detail == null) {
    return '工具执行失败：$error。';
  }
  return '工具执行失败：$detail';
}

String _deviceSummary(Map<String, Object?> output) {
  final device = output['device'];
  if (device is! Map<Object?, Object?>) {
    return '已读取设备信息。';
  }
  final model = _stringValue(device['model']) ?? _stringValue(device['name']);
  final platform = _stringValue(device['platform']);
  final version = _stringValue(device['osVersion']);
  final parts = <String>[?model, ?platform, ?version];
  return parts.isEmpty ? '已读取设备信息。' : '当前设备：${parts.join(' · ')}。';
}

String _timeSummary(Map<String, Object?> output) {
  final localIso = _stringValue(output['localIso']);
  final zone = _stringValue(output['timeZoneName']);
  if (localIso == null) {
    return '已读取设备当前时间。';
  }
  return '设备当前本地时间：$localIso${zone == null ? '' : '（$zone）'}。';
}

String _batterySummary(Map<String, Object?> output) {
  final level = output['level'];
  final state = _stringValue(output['state']);
  final saveMode = output['isInBatterySaveMode'] == true ? '，省电模式开启' : '';
  return '当前电量 ${level is num ? '${level.round()}%' : '未知'}${state == null ? '' : '，$state'}$saveMode。';
}

String _networkSummary(Map<String, Object?> output) {
  if (output['connected'] != true) {
    return '当前设备未检测到网络连接。';
  }
  final types = output['types'];
  final text = types is Iterable<Object?>
      ? types.whereType<String>().join('、')
      : '';
  return text.isEmpty ? '当前设备已连接网络。' : '当前设备网络连接类型：$text。';
}

String _locationSummary(Map<String, Object?> output) {
  final latitude = output['latitude'];
  final longitude = output['longitude'];
  final accuracy = output['accuracy'];
  if (latitude is! num || longitude is! num) {
    return '已获取当前位置。';
  }
  final accuracyText = accuracy is num
      ? '，精度约 ${accuracy.toStringAsFixed(0)} 米'
      : '';
  return '当前位置：纬度 ${latitude.toStringAsFixed(6)}，经度 ${longitude.toStringAsFixed(6)}$accuracyText。';
}

String _notificationSummary(Map<String, Object?> output) {
  final title = _stringValue(output['title']) ?? '提醒';
  final scheduledAt = _stringValue(output['scheduledAt']);
  return scheduledAt == null
      ? '已创建本地通知：$title。'
      : '已创建本地通知：$title，时间 $scheduledAt。';
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Object? _truncateString(Object? value, int maxChars) {
  if (value is! String || value.length <= maxChars) {
    return value;
  }
  return '${value.substring(0, maxChars)}...';
}

String _prettyJson(Map<String, Object?> output) {
  try {
    return const JsonEncoder.withIndent('  ').convert(output);
  } on Object {
    return output.toString();
  }
}
