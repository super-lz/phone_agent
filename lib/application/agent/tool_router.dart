import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/models/model_provider_config.dart';

class AgentToolRouter {
  const AgentToolRouter();

  Future<ToolRoute> route({
    required Object prompt,
    Object? context,
    required List<Map<String, Object?>> allTools,
    required OpenAiCompatibleChatClient chatClient,
    required ModelProviderConfig provider,
    required String apiKey,
  }) async {
    final latestPrompt = _extractPromptText(prompt);
    final routingContext = context == null ? '' : _extractPromptText(context);
    final toolCatalog = _toolCatalogForModel(allTools);
    final messages = [
      {'role': 'system', 'content': _routingSystemPrompt()},
      {
        'role': 'user',
        'content': jsonEncode({
          'latest_user_message': latestPrompt,
          'recent_context': routingContext,
          'available_tools': toolCatalog,
          'response_schema': {
            'selected_tool_names': ['tool_name'],
            'required_tool_names': ['tool_name'],
            'uses_context': false,
            'reason': 'short reason',
          },
        }),
      },
    ];

    AppLogger.info('agent_tool_router.model.start', {
      'promptLength': latestPrompt.length,
      'contextLength': routingContext.length,
      'availableToolCount': allTools.length,
    });
    final result = await chatClient.completeText(
      provider: provider,
      apiKey: apiKey,
      messages: messages,
    );
    if (!result.ok) {
      AppLogger.warning('agent_tool_router.model.failed', {
        'message': result.content,
      });
      return routeFromDecision(
        decision: const {},
        allTools: allTools,
        reason: '工具路由模型失败：${result.content}',
      );
    }
    final decoded = _decodeRouteDecision(result.content);
    final creationDecision = _withWebAppCreationTools(
      decision: decoded,
      latestPrompt: latestPrompt,
      allTools: allTools,
    );
    final maintenanceDecision = _withWebAppMaintenanceTools(
      decision: creationDecision,
      latestPrompt: latestPrompt,
      recentContext: routingContext,
      allTools: allTools,
    );
    final decision = _withNativeCapabilityTools(
      decision: maintenanceDecision,
      latestPrompt: latestPrompt,
      allTools: allTools,
    );
    return routeFromDecision(
      decision: decision,
      allTools: allTools,
      latestPromptLength: latestPrompt.length,
      contextLength: routingContext.length,
    );
  }

  Map<String, Object?> _withNativeCapabilityTools({
    required Map<String, Object?> decision,
    required String latestPrompt,
    required List<Map<String, Object?>> allTools,
  }) {
    final prompt = latestPrompt.toLowerCase();
    final selected = _stringList(decision['selected_tool_names']).toSet();
    final availableNames = {
      for (final tool in allTools)
        if (_toolName(tool) case final String name) name,
    };

    void addIfAvailable(String name) {
      if (availableNames.contains(name)) {
        selected.add(name);
      }
    }

    final wantsCaptureVideo = _containsAny(prompt, const [
      '拍视频',
      '录视频',
      '录像',
      '摄像',
    ]);
    final wantsPickVideo =
        _containsAny(prompt, const ['选视频', '选择视频', '上传视频', '从相册选视频']) ||
        (prompt.contains('相册') && prompt.contains('视频')) ||
        (!wantsCaptureVideo && _containsAny(prompt, const ['视频', 'video']));
    final wantsPickMultipleImages = _containsAny(prompt, const [
      '多张图片',
      '多张照片',
      '几张图片',
      '几张照片',
      '一组图片',
      '一组照片',
      '批量图片',
      '批量照片',
      '选择多图',
      '多选图片',
      '多选照片',
      'multiple images',
      'multiple photos',
    ]);
    final wantsCancelAudio = _containsAny(prompt, const ['取消录音', '放弃录音']);
    final wantsStopAudio = _containsAny(prompt, const ['停止录音', '结束录音', '完成录音']);
    final wantsStartAudio =
        !wantsCancelAudio &&
        !wantsStopAudio &&
        _containsAny(prompt, const ['开始录音', '录音', '录一段声音', '录语音', '麦克风']);
    final wantsCancelAllNotifications =
        _containsAny(prompt, const ['取消全部提醒', '清空提醒', '删除所有提醒']) ||
        (_containsAny(prompt, const ['取消全部', '清空全部', '全部取消']) &&
            _containsAny(prompt, const ['提醒', '通知']));
    final wantsCancelNotification = _containsAny(prompt, const [
      '取消提醒',
      '取消通知',
      '删除提醒',
      '删掉提醒',
    ]);
    final wantsListNotifications = _containsAny(prompt, const [
      '查看提醒',
      '提醒列表',
      '待提醒',
      '有哪些提醒',
      '通知列表',
      '已安排通知',
    ]);
    final wantsScheduleNotification = _containsAny(prompt, const [
      '提醒我',
      '稍后提醒',
      '定个提醒',
      '安排提醒',
      '发个通知',
    ]);
    final wantsCalendarEvent = _containsAny(prompt, const [
      '加入日历',
      '加到日历',
      '创建日程',
      '安排日程',
      '保存日历',
      '日历事件',
      '安排会议',
    ]);
    final wantsCurrentTime = _containsAny(prompt, const [
      '现在几点',
      '当前时间',
      '本地时间',
      '今天几号',
      '设备时间',
    ]);
    final wantsDeviceInfo = _containsAny(prompt, const [
      '设备信息',
      '手机信息',
      '系统版本',
      '手机型号',
      '机型',
      'device info',
    ]);
    final wantsAppInfo = _containsAny(prompt, const [
      '应用信息',
      'app 信息',
      '当前版本',
      '应用版本',
      'app版本',
      '版本号',
      '构建号',
      'build number',
      '包名',
      'bundle id',
      'package name',
      'app info',
    ]);
    final wantsBattery = _containsAny(prompt, const [
      '电量',
      '电池',
      '充电',
      '省电模式',
      'battery',
    ]);
    final wantsNetwork = _containsAny(prompt, const [
      '网络状态',
      '联网状态',
      '网络连接',
      'wifi',
      'wi-fi',
      '蜂窝',
      'vpn',
      '断网',
      'network status',
    ]);
    final wantsFlashlightStatus = _containsAny(prompt, const [
      '手电筒状态',
      '闪光灯状态',
      '手电筒开着吗',
      '手电筒是否开启',
      'flashlight status',
      'torch status',
    ]);
    final wantsFlashlightSet =
        !wantsFlashlightStatus &&
        _containsAny(prompt, const [
          '打开手电筒',
          '开启手电筒',
          '关掉手电筒',
          '关闭手电筒',
          '开手电筒',
          '关手电筒',
          '打开闪光灯',
          '关闭闪光灯',
          '开闪光灯',
          '关闪光灯',
          'toggle torch',
          'flashlight',
          'torch',
        ]);
    final wantsClipboardRead = _containsAny(prompt, const [
      '读取剪贴板',
      '看看剪贴板',
      '剪贴板内容',
      '粘贴板内容',
    ]);
    final wantsClipboardWrite = _containsAny(prompt, const [
      '复制到剪贴板',
      '写入剪贴板',
      '放到剪贴板',
      '拷贝到剪贴板',
    ]);
    final wantsShareText = _containsAny(prompt, const [
      '系统分享',
      '分享这段',
      '分享文本',
      '调起分享',
      '分享给',
    ]);
    final wantsHaptic = _containsAny(prompt, const [
      '震动',
      '振动',
      '触感',
      'haptic',
    ]);
    final wantsSound = _containsAny(prompt, const [
      '提示音',
      '响一下',
      '播放声音',
      '播放提示',
      '点击音',
    ]);
    final wantsVolumeStatus = _containsAny(prompt, const [
      '音量状态',
      '当前音量',
      '媒体音量是多少',
      '音量是多少',
      'volume status',
    ]);
    final wantsVolumeSet =
        !wantsVolumeStatus &&
        _containsAny(prompt, const [
          '调高音量',
          '调低音量',
          '调大音量',
          '调小音量',
          '设置音量',
          '媒体音量',
          '静音',
          '取消静音',
          'volume',
        ]);
    final wantsSystemUiStatus = _containsAny(prompt, const [
      '系统栏状态',
      '状态栏状态',
      '导航栏状态',
      '全屏状态',
      '沉浸状态',
    ]);
    final wantsSystemUiSet = _containsAny(prompt, const [
      '全屏',
      '退出全屏',
      '沉浸式',
      '沉浸模式',
      '隐藏状态栏',
      '显示状态栏',
      '隐藏导航栏',
      '显示导航栏',
      'edge-to-edge',
      'edge to edge',
      'immersive',
      'fullscreen',
    ]);
    final wantsPermissionSettings = _containsAny(prompt, const [
      '权限设置',
      '打开设置',
      '系统设置',
      '去设置',
      '授权设置',
    ]);
    final wantsOpenExternalUrl =
        _containsAny(prompt, const ['打开链接', '打开网址', '外部打开', '浏览器打开']) ||
        prompt.startsWith('打开 http://') ||
        prompt.startsWith('打开 https://') ||
        prompt.startsWith('打开 tel:') ||
        prompt.startsWith('打开 mailto:') ||
        prompt.startsWith('打开 sms:') ||
        prompt.startsWith('打开 geo:');
    final wantsKeepAwakeStatus = _containsAny(prompt, const [
      '常亮状态',
      '是否常亮',
      '屏幕常亮状态',
    ]);
    final wantsKeepAwake = _containsAny(prompt, const [
      '屏幕常亮',
      '保持常亮',
      '不要熄屏',
      '禁止熄屏',
      '取消常亮',
      '恢复熄屏',
    ]);
    final wantsBrightnessStatus = _containsAny(prompt, const [
      '亮度状态',
      '当前亮度',
      '屏幕亮度是多少',
      '亮度是多少',
      'brightness status',
    ]);
    final wantsBrightnessSet =
        !wantsBrightnessStatus &&
        _containsAny(prompt, const [
          '调亮',
          '调暗',
          '调高亮度',
          '调低亮度',
          '屏幕亮一点',
          '屏幕暗一点',
          '设置亮度',
          '调整亮度',
          '屏幕亮度',
          'brightness',
        ]);
    final wantsScreenMetrics = _containsAny(prompt, const [
      '屏幕尺寸',
      '屏幕大小',
      '屏幕分辨率',
      '安全区',
      '刘海',
      '像素比',
      '设备像素比',
      '深色模式',
      '暗色模式',
      '文字缩放',
      '字体缩放',
      'screen metrics',
      'screen size',
      'device pixel ratio',
      'safe area',
    ]);
    final wantsOrientationStatus = _containsAny(prompt, const [
      '方向状态',
      '旋转状态',
      '是否锁定方向',
      '屏幕方向状态',
    ]);
    final wantsOrientationSet = _containsAny(prompt, const [
      '横屏',
      '竖屏',
      '屏幕方向',
      '方向锁定',
      '锁定方向',
      '解锁方向',
      '自动旋转',
      '恢复旋转',
      'orientation',
      'rotate',
      'rotation',
    ]);
    final wantsAccelerometer = _containsAny(prompt, const [
      '加速度计',
      '加速度',
      '摇晃',
      '运动传感器',
    ]);
    final wantsGyroscope = _containsAny(prompt, const ['陀螺仪', '旋转传感器', '姿态变化']);
    final wantsMagnetometer = _containsAny(prompt, const [
      '磁力计',
      '指南针',
      '罗盘',
      '磁场',
    ]);
    final wantsBarcodeFromImage =
        _containsAny(prompt, const ['截图', '相册', '图片', '照片']) &&
        _containsAny(prompt, const ['二维码', '条码', '扫码', 'barcode', 'qr']);
    final wantsBarcodeScan = _containsAny(prompt, const [
      '扫描二维码',
      '扫二维码',
      '扫码',
      '扫条码',
      '扫描条码',
      '识别二维码',
      '识别条码',
      'barcode',
      'qr code',
      'qrcode',
    ]);

    if (_containsAny(prompt, const ['拍照', '拍一张', '相机', 'camera'])) {
      addIfAvailable('camera_capture_photo');
    }
    if (wantsDeviceInfo) {
      addIfAvailable('device_info');
    }
    if (wantsAppInfo) {
      addIfAvailable('app_info');
    }
    if (wantsCurrentTime || wantsScheduleNotification || wantsCalendarEvent) {
      addIfAvailable('time_get_current');
    }
    if (wantsBattery) {
      addIfAvailable('battery_status');
    }
    if (wantsNetwork) {
      addIfAvailable('network_status');
    }
    if (wantsFlashlightStatus) {
      addIfAvailable('flashlight_status');
    }
    if (wantsFlashlightSet) {
      addIfAvailable('flashlight_set');
    }
    if (wantsClipboardRead) {
      addIfAvailable('clipboard_read');
    }
    if (wantsClipboardWrite) {
      addIfAvailable('clipboard_write');
    }
    if (wantsCaptureVideo) {
      addIfAvailable('camera_capture_video');
    }
    if (wantsPickMultipleImages) {
      addIfAvailable('media_pick_images');
    } else if (_containsAny(prompt, const [
      '选图',
      '选一张图',
      '相册',
      '图片',
      '照片',
      'image',
    ])) {
      addIfAvailable('media_pick_image');
    }
    if (wantsPickVideo) {
      addIfAvailable('media_pick_video');
    }
    if (_containsAny(prompt, const [
      '选文件',
      '选择文件',
      '导入文件',
      '上传文件',
      '本地文件',
      '系统文件',
      'pdf 文件',
      'pdf文件',
      '上传一个',
      'file',
    ])) {
      addIfAvailable('file_pick_system_file');
    }
    if (wantsStartAudio) {
      addIfAvailable('audio_record_start');
    }
    if (wantsStopAudio) {
      addIfAvailable('audio_record_stop');
    }
    if (wantsCancelAudio) {
      addIfAvailable('audio_record_cancel');
    }
    if (_containsAny(prompt, const [
      '选择联系人',
      '选联系人',
      '联系人',
      '通讯录',
      '电话联系人',
      '联系人输入',
    ])) {
      addIfAvailable('contacts_pick');
    }
    if (wantsBarcodeFromImage) {
      addIfAvailable('barcode_scan_image');
    } else if (wantsBarcodeScan) {
      addIfAvailable('barcode_scan_camera');
    }
    if (wantsScheduleNotification) {
      addIfAvailable('notification_schedule');
    }
    if (wantsCalendarEvent) {
      addIfAvailable('calendar_event_create');
    }
    if (wantsListNotifications || wantsCancelNotification) {
      addIfAvailable('notification_pending');
    }
    if (wantsCancelNotification) {
      addIfAvailable('notification_cancel');
    }
    if (wantsCancelAllNotifications) {
      addIfAvailable('notification_cancel_all');
    }
    if (wantsShareText) {
      addIfAvailable('share_text');
    }
    if (wantsHaptic) {
      addIfAvailable('system_haptic_feedback');
    }
    if (wantsSound) {
      addIfAvailable('system_sound_alert');
    }
    if (wantsVolumeSet) {
      addIfAvailable('system_volume_set');
    }
    if (wantsVolumeStatus || wantsVolumeSet) {
      addIfAvailable('system_volume_status');
    }
    if (wantsSystemUiSet) {
      addIfAvailable('system_ui_set');
    }
    if (wantsSystemUiStatus || wantsSystemUiSet) {
      addIfAvailable('system_ui_status');
    }
    if (wantsPermissionSettings) {
      addIfAvailable('permission_open_settings');
    }
    if (wantsOpenExternalUrl) {
      addIfAvailable('url_open_external');
    }
    if (wantsKeepAwake) {
      addIfAvailable('screen_keep_awake');
    }
    if (wantsKeepAwakeStatus) {
      addIfAvailable('screen_keep_awake_status');
    }
    if (wantsBrightnessSet) {
      addIfAvailable('screen_brightness_set');
    }
    if (wantsBrightnessStatus || wantsBrightnessSet) {
      addIfAvailable('screen_brightness_status');
    }
    if (wantsScreenMetrics) {
      addIfAvailable('screen_metrics');
    }
    if (wantsOrientationSet) {
      addIfAvailable('screen_orientation_set');
    }
    if (wantsOrientationStatus || wantsOrientationSet) {
      addIfAvailable('screen_orientation_status');
    }
    if (wantsAccelerometer) {
      addIfAvailable('sensor_accelerometer_read');
    }
    if (wantsGyroscope) {
      addIfAvailable('sensor_gyroscope_read');
    }
    if (wantsMagnetometer) {
      addIfAvailable('sensor_magnetometer_read');
    }

    if (selected.length ==
        _stringList(decision['selected_tool_names']).length) {
      return decision;
    }
    return {
      ...decision,
      'selected_tool_names': selected.toList(growable: false)..sort(),
      'reason': [
        if (decision['reason'] is String) decision['reason'],
        'native_capability_request_requires_phone_tools',
      ].whereType<String>().join('; '),
    };
  }

  ToolRoute routeFromModelOutput(
    String output, {
    required List<Map<String, Object?>> allTools,
    int? latestPromptLength,
    int? contextLength,
  }) {
    final decoded = _decodeRouteDecision(output);
    return routeFromDecision(
      decision: decoded,
      allTools: allTools,
      latestPromptLength: latestPromptLength,
      contextLength: contextLength,
    );
  }

  ToolRoute routeFromDecision({
    required Map<String, Object?> decision,
    required List<Map<String, Object?>> allTools,
    String? reason,
    int? latestPromptLength,
    int? contextLength,
  }) {
    final toolByName = <String, Map<String, Object?>>{};
    for (final tool in allTools) {
      final name = _toolName(tool);
      if (name != null) {
        toolByName[name] = tool;
      }
    }

    final selectedNames = _stringList(
      decision['selected_tool_names'],
    ).where(toolByName.containsKey).toSet();
    final requiredNames = _stringList(
      decision['required_tool_names'],
    ).where(selectedNames.contains).toSet();
    final selectedTools = [
      for (final name in selectedNames.toList(growable: false)..sort())
        toolByName[name]!,
    ];

    final logData = <String, Object?>{
      'selectedToolCount': selectedTools.length,
      'availableToolCount': allTools.length,
      'usesContext': decision['uses_context'] == true,
      'selectedTools': selectedNames.toList(growable: false)..sort(),
      'requiredTools': requiredNames.toList(growable: false)..sort(),
      'reason': reason ?? decision['reason'],
    };
    if (latestPromptLength != null) {
      logData['promptLength'] = latestPromptLength;
    }
    if (contextLength != null) {
      logData['contextLength'] = contextLength;
    }
    AppLogger.info('agent_tool_router.route', logData);
    return ToolRoute(
      tools: selectedTools,
      index: _toolIndexFor(selectedTools, requiredNames),
      selectedToolNames: selectedNames.toList(growable: false)..sort(),
      requiredToolNames: requiredNames.toList(growable: false)..sort(),
    );
  }

  String _routingSystemPrompt() {
    return [
      '你是 Phone Agent 的工具路由器，只做工具 schema 选择，不回答用户、不执行任务。',
      '根据 latest_user_message 判断本轮需要暴露哪些工具；recent_context 只用于语义上确实承接上一轮任务的短跟进。',
      '不要因为 recent_context 或 assistant 自我介绍里出现工具、能力、Web App、创建等字样就选择工具。',
      '普通聊天、问候、身份追问、闲聊应返回空工具列表。',
      '如果用户最新消息要求创建、保存、写入、修改、查询、搜索、读取、调用手机能力或生成可复用产物，选择能完成真实动作的最小工具集合。',
      '如果用户最新消息要求创建真实本地 Web 工程、网页、网站、小游戏、Web App 或原型，project_create_web_app 必须同时出现在 selected_tool_names 和 required_tool_names。',
      '如果用户最新消息是在反馈、修复或迭代已有 Web App/网页/小游戏的问题，必须暴露 artifact_query、artifact_inspect_logs、file_search_app_files、file_read_app_file、project_update_web_app、project_test_web_app、project_version_history、project_revert_web_app；让 Agent 先读运行日志和项目文件，再用项目级更新能力修改原项目，更新后调用项目测试能力。',
      'required_tool_names 只用于“未成功调用就不能声称完成”的真实产物创建工具；没有这种硬性完成条件时返回空数组。',
      '只输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要解释。',
    ].join('\n');
  }

  Map<String, Object?> _withWebAppMaintenanceTools({
    required Map<String, Object?> decision,
    required String latestPrompt,
    required String recentContext,
    required List<Map<String, Object?>> allTools,
  }) {
    if (!_looksLikeWebAppMaintenance(latestPrompt, recentContext)) {
      return decision;
    }
    final availableNames = {
      for (final tool in allTools)
        if (_toolName(tool) case final String name) name,
    };
    final selected = _stringList(decision['selected_tool_names']).toSet();
    for (final name in const [
      'artifact_query',
      'artifact_inspect_logs',
      'file_search_app_files',
      'file_read_app_file',
      'file_apply_text_patch',
      'project_update_web_app',
      'project_test_web_app',
      'project_version_history',
      'project_revert_web_app',
    ]) {
      if (availableNames.contains(name)) {
        selected.add(name);
      }
    }
    return {
      ...decision,
      'selected_tool_names': selected.toList(growable: false)..sort(),
      'reason': [
        if (decision['reason'] is String) decision['reason'],
        'web_app_maintenance_requires_log_and_file_tools',
      ].whereType<String>().join('; '),
    };
  }

  Map<String, Object?> _withWebAppCreationTools({
    required Map<String, Object?> decision,
    required String latestPrompt,
    required List<Map<String, Object?>> allTools,
  }) {
    if (!_looksLikeWebAppCreation(latestPrompt)) {
      return decision;
    }
    final availableNames = {
      for (final tool in allTools)
        if (_toolName(tool) case final String name) name,
    };
    final selected = _stringList(decision['selected_tool_names']).toSet();
    final required = _stringList(decision['required_tool_names']).toSet();
    if (availableNames.contains('project_create_web_app')) {
      selected.add('project_create_web_app');
      required.add('project_create_web_app');
    }
    if (availableNames.contains('project_test_web_app')) {
      selected.add('project_test_web_app');
    }
    return {
      ...decision,
      'selected_tool_names': selected.toList(growable: false)..sort(),
      'required_tool_names': required.toList(growable: false)..sort(),
      'reason': [
        if (decision['reason'] is String) decision['reason'],
        'web_app_creation_requires_project_tools',
      ].whereType<String>().join('; '),
    };
  }

  bool _looksLikeWebAppMaintenance(String latestPrompt, String recentContext) {
    final prompt = latestPrompt.toLowerCase();
    final context = recentContext.toLowerCase();
    final mentionsWebApp = _containsAny(prompt, const [
      'web app',
      'webapp',
      '网页',
      '页面',
      '小游戏',
      '原型',
      '预览',
      '卡片',
      '本地应用',
    ]);
    final followsWebAppContext =
        _containsAny(prompt, const ['这个', '刚才', '上面', '它', '那个']) &&
        _containsAny(context, const [
          'web app',
          'webapp',
          'web_app_card',
          'project_create_web_app',
          '网页',
          '小游戏',
          'artifact',
        ]);
    if (!mentionsWebApp && !followsWebAppContext) {
      return false;
    }
    return _containsAny(prompt, const [
      '修',
      '改',
      '问题',
      '报错',
      '错误',
      '异常',
      '打不开',
      '打开不了',
      '空白',
      '崩',
      '失败',
      '不能',
      '没反应',
      'bug',
      'error',
      'fix',
      'broken',
      'blank',
      'crash',
      'failed',
    ]);
  }

  bool _looksLikeWebAppCreation(String latestPrompt) {
    final prompt = latestPrompt.toLowerCase();
    final mentionsWebArtifact = _containsAny(prompt, const [
      'web app',
      'webapp',
      '网页',
      '网站',
      '小游戏',
      '原型',
      '页面',
      '本地应用',
    ]);
    if (!mentionsWebArtifact) {
      return false;
    }
    return _containsAny(prompt, const [
      '创建',
      '新建',
      '生成',
      '做一个',
      '写一个',
      '搞一个',
      '给我一个',
      'build',
      'create',
      'make',
    ]);
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }

  List<Map<String, Object?>> _toolCatalogForModel(
    List<Map<String, Object?>> allTools,
  ) {
    return [
      for (final tool in allTools)
        if (_toolName(tool) != null)
          {'name': _toolName(tool), 'description': _toolDescription(tool)},
    ];
  }

  Map<String, Object?> _decodeRouteDecision(String output) {
    final trimmed = output.trim();
    final jsonText = _stripCodeFence(trimmed);
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map<Object?, Object?>) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on Object catch (error) {
      AppLogger.warning('agent_tool_router.parse.failed', {
        'error': error.toString(),
        'output': output,
      });
    }
    return const {};
  }

  String _stripCodeFence(String text) {
    if (!text.startsWith('```')) {
      return text;
    }
    final withoutPrefix = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    return withoutPrefix.replaceFirst(RegExp(r'\s*```$'), '').trim();
  }

  List<String> _stringList(Object? value) {
    if (value is! List<Object?>) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }

  String? _toolName(Map<String, Object?> tool) {
    final function = tool['function'];
    if (function is! Map<String, Object?>) {
      return null;
    }
    final name = function['name'];
    return name is String ? name : null;
  }

  String _toolDescription(Map<String, Object?> tool) {
    final function = tool['function'];
    if (function is! Map<String, Object?>) {
      return '';
    }
    final description = function['description'];
    return description is String ? description : '';
  }

  String _extractPromptText(Object prompt) {
    if (prompt is String) {
      return prompt;
    }
    if (prompt is Iterable<Object?>) {
      return prompt.map(_extractPartText).join('\n');
    }
    return prompt.toString();
  }

  String _extractPartText(Object? part) {
    if (part is String) {
      return part;
    }
    if (part is Map<String, Object?>) {
      if (part['type'] == 'image_url' || part.containsKey('image_url')) {
        return '[image_url]';
      }
      final text = part['text'];
      if (text is String) {
        return text;
      }
      return part.values.map(_extractPartText).join('\n');
    }
    if (part is Iterable<Object?>) {
      return part.map(_extractPartText).join('\n');
    }
    return '';
  }

  String _toolIndexFor(
    List<Map<String, Object?>> selectedTools,
    Set<String> requiredNames,
  ) {
    if (selectedTools.isEmpty) {
      return '本轮未暴露工具 schema；如果用户只是普通聊天，直接回答。';
    }
    final toolLines = selectedTools
        .map((tool) {
          final name = _toolName(tool) ?? 'unknown_tool';
          final description = _toolDescription(tool);
          return '- $name: $description';
        })
        .join('\n');
    final requiredText = requiredNames.isEmpty
        ? ''
        : '\n本轮存在必需工具，必须成功调用后才能声称完成：${requiredNames.join('、')}。';
    return '本轮路由模型只暴露以下工具 schema：\n$toolLines\n'
        '未暴露的工具视为本轮不可用，不要臆造调用。$requiredText';
  }
}

class ToolRoute {
  const ToolRoute({
    required this.tools,
    required this.index,
    required this.selectedToolNames,
    required this.requiredToolNames,
  });

  final List<Map<String, Object?>> tools;
  final String index;
  final List<String> selectedToolNames;
  final List<String> requiredToolNames;
}
