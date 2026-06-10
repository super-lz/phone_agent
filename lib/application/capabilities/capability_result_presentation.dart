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
    case 'notification.schedule':
      observation.addAll({
        'notificationId': output['notificationId'],
        'title': output['title'],
        'body': output['body'],
        'scheduledAt': output['scheduledAt'],
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
    case 'audio.record_cancel':
      observation.addAll({
        'name': output['name'],
        'uri': output['uri'],
        'mimeType': output['mimeType'],
        'bytes': output['bytes'],
        'source': output['source'],
        'mediaType': output['mediaType'],
        'recording': output['recording'],
        'cancelled': output['cancelled'],
      });
      return observation;
    case 'media.pick_images':
      observation.addAll({
        'count': output['count'],
        'items': output['items'],
        'source': output['source'],
        'mediaType': output['mediaType'],
      });
      return observation;
    case 'clipboard.write':
      observation['length'] = output['length'];
      return observation;
    case 'share.text':
      observation.addAll({
        'status': output['status'],
        'length': output['length'],
      });
      return observation;
    case 'system.haptic_feedback':
    case 'system.sound_alert':
      observation['type'] = output['type'];
      return observation;
    case 'system.volume.set':
    case 'system.volume.status':
      observation.addAll({
        'level': output['level'],
        'stream': output['stream'],
        'canSet': output['canSet'],
      });
      return observation;
    case 'system.ui.set':
    case 'system.ui.status':
      observation.addAll({
        'mode': output['mode'],
        'overlays': output['overlays'],
        'isFullscreen': output['isFullscreen'],
      });
      return observation;
    case 'permission.open_settings':
      observation['opened'] = output['opened'];
      return observation;
    case 'url.open_external':
      observation.addAll({
        'opened': output['opened'],
        'url': output['url'],
        'scheme': output['scheme'],
      });
      return observation;
    case 'screen.keep_awake':
    case 'screen.keep_awake_status':
      observation['enabled'] = output['enabled'];
      return observation;
    case 'screen.orientation.set':
    case 'screen.orientation.status':
      observation.addAll({
        'mode': output['mode'],
        'locked': output['locked'],
        'preferredOrientations': output['preferredOrientations'],
      });
      return observation;
    case 'sensor.accelerometer.read':
    case 'sensor.gyroscope.read':
    case 'sensor.magnetometer.read':
      observation.addAll({
        'sensor': output['sensor'],
        'x': output['x'],
        'y': output['y'],
        'z': output['z'],
      });
      return observation;
    case 'calendar.event.create':
      observation.addAll({
        'title': output['title'],
        'location': output['location'],
        'startsAt': output['startsAt'],
        'endsAt': output['endsAt'],
        'allDay': output['allDay'],
        'requiresUserConfirmation': output['requiresUserConfirmation'],
        'completionInferred': output['completionInferred'],
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
    case 'system.volume.set':
      return '媒体音量设置';
    case 'system.volume.status':
      return '媒体音量状态';
    case 'permission.open_settings':
      return '权限设置';
    case 'url.open_external':
      return '打开外部链接';
    case 'screen.keep_awake':
      return '屏幕常亮设置';
    case 'screen.keep_awake_status':
      return '屏幕常亮状态';
    case 'screen.brightness.set':
      return '屏幕亮度设置';
    case 'screen.brightness.status':
      return '屏幕亮度状态';
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
    case 'project.test_web_app':
      return 'Web App 测试';
    case 'flashlight.set':
      return '手电筒控制';
    case 'flashlight.status':
      return '手电筒状态';
    case 'media.pick_images':
      return '多图选择';
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
    case 'flashlight.set':
      return output['enabled'] == true ? '已打开手电筒。' : '已关闭手电筒。';
    case 'flashlight.status':
      return output['enabled'] == true ? '手电筒当前已打开。' : '手电筒当前已关闭。';
    case 'media.pick_image':
      return _pickedFileSummary(output, fallback: '已选择图片。');
    case 'media.pick_images':
      return '已选择 ${output['count'] ?? 0} 张图片。';
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
      return _calendarSummary(output);
    case 'share.text':
      return _shareSummary(output);
    case 'system.haptic_feedback':
      return '已触发${_hapticTypeLabel(output['type'])}触感反馈。';
    case 'system.sound_alert':
      return '已播放${_soundTypeLabel(output['type'])}。';
    case 'system.volume.set':
    case 'system.volume.status':
      return _mediaVolumeSummary(output);
    case 'system.ui.set':
    case 'system.ui.status':
      return _systemUiSummary(output);
    case 'url.open_external':
      return output['opened'] == true
          ? '已打开外部链接：${output['url'] ?? ''}。'
          : '未能打开外部链接。';
    case 'screen.keep_awake':
      return output['enabled'] == true ? '已开启当前应用屏幕常亮。' : '已关闭当前应用屏幕常亮。';
    case 'screen.keep_awake_status':
      return output['enabled'] == true ? '当前应用已保持屏幕常亮。' : '当前应用未开启屏幕常亮。';
    case 'screen.brightness.set':
    case 'screen.brightness.status':
      return _screenBrightnessSummary(output);
    case 'screen.orientation.set':
    case 'screen.orientation.status':
      return _screenOrientationSummary(output);
    case 'permission.open_settings':
      return output['opened'] == true ? '已打开系统权限设置。' : '未能打开系统权限设置。';
    case 'sensor.accelerometer.read':
    case 'sensor.gyroscope.read':
    case 'sensor.magnetometer.read':
      return _sensorSummary(output);
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

String _calendarSummary(Map<String, Object?> output) {
  final title = _stringValue(output['title']) ?? '日历事件';
  final startsAt = _stringValue(output['startsAt']);
  final inferred = output['completionInferred'] == true ? '，系统界面打开结果为超时推定' : '';
  return startsAt == null
      ? '已打开系统日历添加流程：$title$inferred，请在系统界面确认保存。'
      : '已打开系统日历添加流程：$title，开始时间 $startsAt$inferred，请在系统界面确认保存。';
}

String _shareSummary(Map<String, Object?> output) {
  final status = _stringValue(output['status']);
  if (status == null) {
    return '已打开系统分享面板。';
  }
  return '系统分享面板已返回：$status。';
}

String _sensorSummary(Map<String, Object?> output) {
  final sensor = _sensorNameLabel(output['sensor']);
  final x = output['x'];
  final y = output['y'];
  final z = output['z'];
  if (x is num && y is num && z is num) {
    return '$sensor 当前读数：x=${x.toStringAsFixed(3)}，y=${y.toStringAsFixed(3)}，z=${z.toStringAsFixed(3)}。';
  }
  return '已读取$sensor数据。';
}

String _screenOrientationSummary(Map<String, Object?> output) {
  final mode = _screenOrientationModeLabel(output['mode']);
  final locked = output['locked'];
  if (locked == true) {
    return '当前应用屏幕方向已锁定为$mode。';
  }
  return '当前应用屏幕方向跟随系统自动旋转。';
}

String _screenBrightnessSummary(Map<String, Object?> output) {
  final level = output['level'];
  if (level is num) {
    final percent = (level.clamp(0, 1) * 100).round();
    final suffix = output['usesSystemDefault'] == true ? '，当前使用系统默认亮度' : '';
    return '当前屏幕亮度约为 $percent%$suffix。';
  }
  return '当前屏幕亮度状态不可用。';
}

String _mediaVolumeSummary(Map<String, Object?> output) {
  final level = output['level'];
  if (level is num) {
    final percent = (level.clamp(0, 1) * 100).round();
    final suffix = output['canSet'] == false ? '，当前平台不支持静默设置' : '';
    return '当前媒体音量约为 $percent%$suffix。';
  }
  return '当前媒体音量状态不可用。';
}

String _systemUiSummary(Map<String, Object?> output) {
  final mode = _systemUiModeLabel(output['mode']);
  if (_stringValue(output['mode']) == 'normal') {
    return '当前应用已恢复显示系统状态栏和导航栏。';
  }
  return '当前应用系统 UI 已切换为$mode模式。';
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

String _hapticTypeLabel(Object? value) {
  switch (_stringValue(value)) {
    case 'selection':
      return '选择';
    case 'medium':
      return '中等';
    case 'heavy':
      return '强';
    case 'vibrate':
      return '震动';
    case 'light':
    default:
      return '轻';
  }
}

String _soundTypeLabel(Object? value) {
  switch (_stringValue(value)) {
    case 'click':
      return '点击音';
    case 'alert':
    default:
      return '系统提示音';
  }
}

String _screenOrientationModeLabel(Object? value) {
  switch (_stringValue(value)) {
    case 'portrait':
      return '竖屏';
    case 'portrait_up':
      return '正向竖屏';
    case 'portrait_down':
      return '倒置竖屏';
    case 'landscape':
      return '横屏';
    case 'landscape_left':
      return '左横屏';
    case 'landscape_right':
      return '右横屏';
    case 'unlocked':
    default:
      return '自动旋转';
  }
}

String _systemUiModeLabel(Object? value) {
  switch (_stringValue(value)) {
    case 'fullscreen':
      return '全屏';
    case 'edge_to_edge':
      return '边到边';
    case 'lean_back':
      return '轻量沉浸';
    case 'immersive':
      return '沉浸';
    case 'immersive_sticky':
      return '粘性沉浸';
    case 'normal':
    default:
      return '正常显示';
  }
}

String _sensorNameLabel(Object? value) {
  switch (_stringValue(value)) {
    case 'accelerometer':
      return '加速度计';
    case 'gyroscope':
      return '陀螺仪';
    case 'magnetometer':
      return '磁力计';
    default:
      return '传感器';
  }
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
