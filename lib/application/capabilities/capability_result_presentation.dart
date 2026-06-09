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
        'address': output['address'],
        'provider': output['provider'],
        'coordinateSystem': output['coordinateSystem'],
        'isMocked': output['isMocked'],
        'isCurrent': output['isCurrent'],
        'locationSource': output['locationSource'],
        'warning': output['warning'],
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
    case 'notification.pending':
      observation.addAll({
        'count': output['count'],
        'notifications': output['notifications'],
      });
      return observation;
    case 'notification.cancel':
      observation.addAll({
        'notificationId': output['notificationId'],
        'cancelled': output['cancelled'],
      });
      return observation;
    case 'notification.cancel_all':
      observation['cancelledAll'] = output['cancelledAll'];
      return observation;
    case 'contacts.pick':
      observation.addAll({
        'contactId': output['contactId'],
        'displayName': output['displayName'],
        'primaryPhone': output['primaryPhone'],
        'primaryEmail': output['primaryEmail'],
        'phones': output['phones'],
        'emails': output['emails'],
      });
      return observation;
    case 'barcode.scan_camera':
    case 'barcode.scan_image':
      observation.addAll({
        'rawValue': output['rawValue'],
        'displayValue': output['displayValue'],
        'format': output['format'],
        'type': output['type'],
        'count': output['count'],
        'barcodes': output['barcodes'],
      });
      return observation;
    case 'camera.capture_photo':
    case 'camera.capture_video':
    case 'media.pick_image':
    case 'media.pick_video':
    case 'file.pick_system_file':
    case 'audio.record_start':
    case 'audio.record_stop':
      observation.addAll({
        'name': output['name'],
        'uri': output['uri'],
        'mimeType': output['mimeType'],
        'bytes': output['bytes'],
        'source': output['source'],
        'mediaType': output['mediaType'],
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
    case 'camera.capture_photo':
      return '拍照';
    case 'camera.capture_video':
      return '拍视频';
    case 'media.pick_image':
      return '选择图片';
    case 'media.pick_video':
      return '选择视频';
    case 'file.pick_system_file':
      return '选择文件';
    case 'audio.record_start':
      return '开始录音';
    case 'audio.record_stop':
      return '停止录音';
    case 'audio.record_cancel':
      return '取消录音';
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
    case 'notification.pending':
      return '待触发通知';
    case 'notification.cancel':
      return '取消通知';
    case 'notification.cancel_all':
      return '清空通知';
    case 'contacts.pick':
      return '选择联系人';
    case 'barcode.scan_camera':
    case 'barcode.scan_image':
      return '扫码';
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
    case 'camera.capture_photo':
      return _pickedFileSummary(output, fallback: '已拍摄照片。');
    case 'camera.capture_video':
      return _pickedFileSummary(output, fallback: '已拍摄视频。');
    case 'media.pick_image':
      return _pickedFileSummary(output, fallback: '已选择图片。');
    case 'media.pick_video':
      return _pickedFileSummary(output, fallback: '已选择视频。');
    case 'file.pick_system_file':
      return _pickedFileSummary(output, fallback: '已选择文件。');
    case 'audio.record_start':
      return '已开始录音。';
    case 'audio.record_stop':
      return _pickedFileSummary(output, fallback: '已停止录音并保存音频。');
    case 'audio.record_cancel':
      return '已取消当前录音。';
    case 'location.get_current':
      return _locationSummary(output);
    case 'notification.schedule':
      return _notificationSummary(output);
    case 'notification.pending':
      return _pendingNotificationSummary(output);
    case 'notification.cancel':
      return '已取消本地通知 ${output['notificationId']}。';
    case 'notification.cancel_all':
      return '已清空全部待触发本地通知。';
    case 'contacts.pick':
      return _contactSummary(output);
    case 'barcode.scan_camera':
    case 'barcode.scan_image':
      return _barcodeSummary(output);
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
  if (error == 'user_cancelled') {
    return '用户已取消本次选择。';
  }
  if (error == 'no_active_recording') {
    return '当前没有正在进行的录音。';
  }
  if (error == 'recording_in_progress') {
    return '当前已有录音正在进行。';
  }
  if (error == 'barcode_not_found') {
    return '没有从图片中识别到二维码或条码。';
  }
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
  final manufacturer = _stringValue(device['manufacturer']);
  final brand = _stringValue(device['brand']);
  final platform = _stringValue(device['platform']);
  final version = _stringValue(device['osVersion']);
  final maker = manufacturer == null || manufacturer == brand
      ? brand
      : '$manufacturer/$brand';
  final parts = <String>[?maker, ?model, ?platform, ?version];
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

String _pickedFileSummary(
  Map<String, Object?> output, {
  required String fallback,
}) {
  final name = _stringValue(output['name']);
  final bytes = output['bytes'];
  if (name == null) {
    return fallback;
  }
  final size = bytes is num ? '，${bytes.round()} bytes' : '';
  return '$fallback $name$size。';
}

String _locationSummary(Map<String, Object?> output) {
  final latitude = output['latitude'];
  final longitude = output['longitude'];
  final accuracy = output['accuracy'];
  final address = _stringValue(output['address']);
  if (latitude is! num || longitude is! num) {
    return address == null ? '已获取当前位置。' : '当前位置：$address。';
  }
  final accuracyText = accuracy is num
      ? '，精度约 ${accuracy.toStringAsFixed(0)} 米'
      : '';
  final coordinateText =
      '纬度 ${latitude.toStringAsFixed(6)}，经度 ${longitude.toStringAsFixed(6)}';
  final prefix = output['isCurrent'] == false ? '系统上次定位' : '当前位置';
  return address == null
      ? '$prefix：$coordinateText$accuracyText。'
      : '$prefix：$address（$coordinateText$accuracyText）。';
}

String _notificationSummary(Map<String, Object?> output) {
  final title = _stringValue(output['title']) ?? '提醒';
  final scheduledAt = _stringValue(output['scheduledAt']);
  return scheduledAt == null
      ? '已创建本地通知：$title。'
      : '已创建本地通知：$title，时间 $scheduledAt。';
}

String _pendingNotificationSummary(Map<String, Object?> output) {
  final count = output['count'];
  if (count is! num || count == 0) {
    return '当前没有待触发的本地通知。';
  }
  return '当前有 ${count.round()} 条待触发的本地通知。';
}

String _contactSummary(Map<String, Object?> output) {
  final displayName = _stringValue(output['displayName']) ?? '联系人';
  final primaryPhone = _stringValue(output['primaryPhone']);
  final primaryEmail = _stringValue(output['primaryEmail']);
  final parts = <String>[displayName, ?primaryPhone, ?primaryEmail];
  return '已选择联系人：${parts.join(' · ')}。';
}

String _barcodeSummary(Map<String, Object?> output) {
  final rawValue = _stringValue(output['rawValue']);
  final format = _stringValue(output['format']);
  if (rawValue == null) {
    return '已识别二维码或条码。';
  }
  return '已识别${format ?? '码值'}：$rawValue。';
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
