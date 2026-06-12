class ToolPromptConfig {
  const ToolPromptConfig({
    required this.toolName,
    required this.groupName,
    required this.triggeringRule,
    this.contracts = const [],
    this.jsBridgeApi,
  });

  final String toolName;
  final String groupName;
  final String triggeringRule;
  final List<String> contracts;
  final String? jsBridgeApi;
}

class ToolPromptRegistry {
  const ToolPromptRegistry._();

  static const List<ToolPromptConfig> _configs = [
    // memory
    ToolPromptConfig(
      toolName: 'memory_create',
      groupName: 'memory',
      triggeringRule: '仅在用户明确要求记住长期偏好、事实或规则时使用；普通回答直接使用 <current_context> 中已注入的长期记忆。',
      jsBridgeApi: 'memory.query',
    ),
    ToolPromptConfig(
      toolName: 'memory_query',
      groupName: 'memory',
      triggeringRule: '仅在用户明确要求查看或管理长期记忆时使用；普通回答直接使用 <current_context> 中已注入的长期记忆。',
      contracts: ['普通对话：没有暴露工具时直接回答；不要为了使用已注入记忆而调用 memory_query。'],
      jsBridgeApi: 'memory.query',
    ),
    ToolPromptConfig(
      toolName: 'memory_delete',
      groupName: 'memory',
      triggeringRule: '仅在用户明确要求删除/忘记某条长期记忆时使用。',
    ),

    // notes
    ToolPromptConfig(
      toolName: 'db_note_create',
      groupName: 'notes',
      triggeringRule: '记录备忘、保存信息、整理事项时使用。',
      jsBridgeApi: 'db.note.create',
    ),
    ToolPromptConfig(
      toolName: 'db_note_query',
      groupName: 'notes',
      triggeringRule: '查询已保存笔记时使用。',
      jsBridgeApi: 'db.note.query',
    ),

    // workspace
    ToolPromptConfig(
      toolName: 'workspace_create',
      groupName: 'workspace',
      triggeringRule: '创建工作区时使用；创建成功后当前 Workspace 必须切换到新工作区。',
    ),
    ToolPromptConfig(
      toolName: 'workspace_switch',
      groupName: 'workspace',
      triggeringRule: '切换工作区时使用。',
      jsBridgeApi: 'workspace.switch',
    ),

    // files
    ToolPromptConfig(
      toolName: 'file_write_app_file',
      groupName: 'files',
      triggeringRule: '只访问当前工作区沙箱内的相对路径。',
      jsBridgeApi: 'file.write_app_file',
    ),
    ToolPromptConfig(
      toolName: 'file_read_app_file',
      groupName: 'files',
      triggeringRule: '只访问当前工作区沙箱内的相对路径。',
      jsBridgeApi: 'file.read_app_file',
    ),
    ToolPromptConfig(
      toolName: 'file_search_app_files',
      groupName: 'files',
      triggeringRule: '只访问当前工作区沙箱内的相对路径。',
      jsBridgeApi: 'file.search_app_files',
    ),
    ToolPromptConfig(
      toolName: 'file_apply_text_patch',
      groupName: 'files',
      triggeringRule: '精确修改当前工作区沙箱内的相对路径文件。',
      contracts: ['文件维护：先 file_search_app_files 定位，再 file_read_app_file 读局部内容，最后 file_apply_text_patch 精确修改；补丁不唯一或目标不存在时返回错误。'],
    ),

    // artifacts
    ToolPromptConfig(
      toolName: 'artifact_create',
      groupName: 'artifacts',
      triggeringRule: '报告、文档、任务清单、文件摘要、Web App 卡片或其它可复用产物必须保存为 Artifact。',
      contracts: ['可复用产物：生成报告、文档、任务清单、文件摘要或 Web App 时，必须调用 artifact_create 或更专用的创建工具。'],
      jsBridgeApi: 'artifact.create',
    ),
    ToolPromptConfig(
      toolName: 'artifact_query',
      groupName: 'artifacts',
      triggeringRule: '查询 Artifact 时使用。',
      jsBridgeApi: 'artifact.query',
    ),
    ToolPromptConfig(
      toolName: 'artifact_inspect_logs',
      groupName: 'artifacts',
      triggeringRule: '读运行日志时使用。',
    ),

    // projects
    ToolPromptConfig(
      toolName: 'project_create_web_app',
      groupName: 'projects',
      triggeringRule: '创建 Web App 用；创建会在结果中返回受控静态检查结论。',
    ),
    ToolPromptConfig(
      toolName: 'project_update_web_app',
      groupName: 'projects',
      triggeringRule: '反馈、修复或迭代已有 Web App 时更新原项目，不创建新卡片；更新会在结果中返回受控静态检查结论。',
      contracts: [
        'Web App 维护：用户反馈已有 Web App/网页/小游戏问题时，先 artifact_query 定位原 Artifact，必要时 artifact_inspect_logs 读运行日志，再读取相关项目文件，最后用 project_update_web_app 更新原项目；更新结果中的 test 未通过时继续修复或说明剩余问题；用户明确要求复测时再调用 project_test_web_app；不要调用 project_create_web_app 复制新项目。'
      ],
    ),
    ToolPromptConfig(
      toolName: 'project_test_web_app',
      groupName: 'projects',
      triggeringRule: '对已有本地 Web App 项目做受控静态复测。',
    ),
    ToolPromptConfig(
      toolName: 'project_version_history',
      groupName: 'projects',
      triggeringRule: '查看 Web App 版本历史。',
    ),
    ToolPromptConfig(
      toolName: 'project_revert_web_app',
      groupName: 'projects',
      triggeringRule: '回滚 Web App。',
    ),

    // office
    ToolPromptConfig(
      toolName: 'document_extract',
      groupName: 'office',
      triggeringRule: '用于 Word 的内容提取。',
      contracts: ['Office/PDF：上传或处理 Word、Excel、PPT、PDF 时先提取；生成新文件时写入当前 Workspace 文件区；局部替换不承诺保留复杂原格式。'],
    ),
    ToolPromptConfig(
      toolName: 'document_generate',
      groupName: 'office',
      triggeringRule: '生成 Word 文档。',
    ),
    ToolPromptConfig(
      toolName: 'document_apply_text_patch',
      groupName: 'office',
      triggeringRule: '修改 Word 文档。',
    ),
    ToolPromptConfig(
      toolName: 'spreadsheet_extract',
      groupName: 'office',
      triggeringRule: 'Excel 提取。',
    ),
    ToolPromptConfig(
      toolName: 'spreadsheet_generate',
      groupName: 'office',
      triggeringRule: '生成 Excel。',
    ),
    ToolPromptConfig(
      toolName: 'presentation_extract',
      groupName: 'office',
      triggeringRule: 'PPT 提取。',
    ),
    ToolPromptConfig(
      toolName: 'presentation_generate',
      groupName: 'office',
      triggeringRule: '生成 PPT。',
    ),
    ToolPromptConfig(
      toolName: 'pdf_extract',
      groupName: 'office',
      triggeringRule: 'PDF 文本提取。',
    ),
    ToolPromptConfig(
      toolName: 'pdf_generate',
      groupName: 'office',
      triggeringRule: '生成 PDF。',
    ),

    // native
    ToolPromptConfig(
      toolName: 'app_info',
      groupName: 'native',
      triggeringRule: '获取应用环境信息。',
      jsBridgeApi: 'app.info',
    ),
    ToolPromptConfig(
      toolName: 'device_info',
      groupName: 'native',
      triggeringRule: '获取手机设备信息。',
      contracts: ['本地能力：手机设备、位置、电量、网络、权限等能力执行后，最终回答优先展示可读摘要，不展示底层结构化元数据。'],
      jsBridgeApi: 'device.info',
    ),
    ToolPromptConfig(
      toolName: 'time_get_current',
      groupName: 'native',
      triggeringRule: '获取手机当前本地时间。',
      contracts: ['相对时间：处理今天、明天、今晚、几分钟后等表达时，以 <current_context> 的本地时间为准；需要校准时调用 time_get_current。'],
      jsBridgeApi: 'time.get_current',
    ),
    ToolPromptConfig(
      toolName: 'clipboard_read',
      groupName: 'native',
      triggeringRule: '读取剪贴板。',
      jsBridgeApi: 'clipboard.read',
    ),
    ToolPromptConfig(
      toolName: 'clipboard_write',
      groupName: 'native',
      triggeringRule: '写入剪贴板。',
      jsBridgeApi: 'clipboard.write',
    ),
    ToolPromptConfig(
      toolName: 'battery_status',
      groupName: 'native',
      triggeringRule: '查询电量状态。',
      jsBridgeApi: 'battery.status',
    ),
    ToolPromptConfig(
      toolName: 'network_status',
      groupName: 'native',
      triggeringRule: '查询网络连接状态。',
      jsBridgeApi: 'network.status',
    ),
    ToolPromptConfig(
      toolName: 'camera_capture_photo',
      groupName: 'native',
      triggeringRule: '调用相机拍照。',
      jsBridgeApi: 'camera.capture_photo',
    ),
    ToolPromptConfig(
      toolName: 'camera_capture_video',
      groupName: 'native',
      triggeringRule: '调用录像功能。',
      jsBridgeApi: 'camera.capture_video',
    ),
    ToolPromptConfig(
      toolName: 'flashlight_set',
      groupName: 'native',
      triggeringRule: '开关手电筒。',
      jsBridgeApi: 'flashlight.set',
    ),
    ToolPromptConfig(
      toolName: 'flashlight_status',
      groupName: 'native',
      triggeringRule: '查询手电筒开关状态。',
      jsBridgeApi: 'flashlight.status',
    ),
    ToolPromptConfig(
      toolName: 'media_pick_image',
      groupName: 'native',
      triggeringRule: '从系统相册选取单张照片。',
      jsBridgeApi: 'media.pick_image',
    ),
    ToolPromptConfig(
      toolName: 'media_pick_images',
      groupName: 'native',
      triggeringRule: '从相册选取多张照片。',
      jsBridgeApi: 'media.pick_images',
    ),
    ToolPromptConfig(
      toolName: 'media_pick_video',
      groupName: 'native',
      triggeringRule: '从相册选取视频。',
      jsBridgeApi: 'media.pick_video',
    ),
    ToolPromptConfig(
      toolName: 'file_pick_system_file',
      groupName: 'native',
      triggeringRule: '从手机系统文件管理器中选择文件。',
      jsBridgeApi: 'file.pick_system_file',
    ),
    ToolPromptConfig(
      toolName: 'audio_record_start',
      groupName: 'native',
      triggeringRule: '启动手机录音。',
      jsBridgeApi: 'audio.record_start',
    ),
    ToolPromptConfig(
      toolName: 'audio_record_stop',
      groupName: 'native',
      triggeringRule: '结束录音并保存。',
      jsBridgeApi: 'audio.record_stop',
    ),
    ToolPromptConfig(
      toolName: 'audio_record_cancel',
      groupName: 'native',
      triggeringRule: '取消录音。',
      jsBridgeApi: 'audio.record_cancel',
    ),
    ToolPromptConfig(
      toolName: 'contacts_pick',
      groupName: 'native',
      triggeringRule: '选取手机联系人。',
      jsBridgeApi: 'contacts.pick',
    ),
    ToolPromptConfig(
      toolName: 'barcode_scan_camera',
      groupName: 'native',
      triggeringRule: '调用后置摄像头扫码（二维码、条形码）。',
      jsBridgeApi: 'barcode.scan_camera',
    ),
    ToolPromptConfig(
      toolName: 'barcode_scan_image',
      groupName: 'native',
      triggeringRule: '解析已有图片上的二维码。',
      jsBridgeApi: 'barcode.scan_image',
    ),
    ToolPromptConfig(
      toolName: 'share_text',
      groupName: 'native',
      triggeringRule: '调用手机系统分享文字。',
      jsBridgeApi: 'share.text',
    ),
    ToolPromptConfig(
      toolName: 'system_haptic_feedback',
      groupName: 'native',
      triggeringRule: '触发手机振动反馈。',
      jsBridgeApi: 'system.haptic_feedback',
    ),
    ToolPromptConfig(
      toolName: 'system_sound_alert',
      groupName: 'native',
      triggeringRule: '触发手机提示音。',
      jsBridgeApi: 'system.sound_alert',
    ),
    ToolPromptConfig(
      toolName: 'system_volume_set',
      groupName: 'native',
      triggeringRule: '设置手机系统音量。',
      jsBridgeApi: 'system.volume.set',
    ),
    ToolPromptConfig(
      toolName: 'system_volume_status',
      groupName: 'native',
      triggeringRule: '查询手机音量大小。',
      jsBridgeApi: 'system.volume.status',
    ),
    ToolPromptConfig(
      toolName: 'system_ui_set',
      groupName: 'native',
      triggeringRule: '配置系统 UI（暗黑模式等）。',
      jsBridgeApi: 'system.ui.set',
    ),
    ToolPromptConfig(
      toolName: 'system_ui_status',
      groupName: 'native',
      triggeringRule: '查询系统 UI 配置。',
      jsBridgeApi: 'system.ui.status',
    ),
    ToolPromptConfig(
      toolName: 'permission_open_settings',
      groupName: 'native',
      triggeringRule: '打开手机系统设置以开启权限。',
      jsBridgeApi: 'permission.open_settings',
    ),
    ToolPromptConfig(
      toolName: 'url_open_external',
      groupName: 'native',
      triggeringRule: '在系统浏览器中打开外部 URL。',
      jsBridgeApi: 'url.open_external',
    ),
    ToolPromptConfig(
      toolName: 'screen_keep_awake',
      groupName: 'native',
      triggeringRule: '保持手机屏幕常亮状态。',
      jsBridgeApi: 'screen.keep_awake',
    ),
    ToolPromptConfig(
      toolName: 'screen_keep_awake_status',
      groupName: 'native',
      triggeringRule: '查询屏幕常亮开关状态。',
      jsBridgeApi: 'screen.keep_awake_status',
    ),
    ToolPromptConfig(
      toolName: 'screen_brightness_set',
      groupName: 'native',
      triggeringRule: '调整手机屏幕亮度。',
      jsBridgeApi: 'screen.brightness.set',
    ),
    ToolPromptConfig(
      toolName: 'screen_brightness_status',
      groupName: 'native',
      triggeringRule: '查询屏幕亮度。',
      jsBridgeApi: 'screen.brightness.status',
    ),
    ToolPromptConfig(
      toolName: 'screen_metrics',
      groupName: 'native',
      triggeringRule: '获取手机屏幕物理参数（分辨率等）。',
      jsBridgeApi: 'screen.metrics',
    ),
    ToolPromptConfig(
      toolName: 'screen_orientation_set',
      groupName: 'native',
      triggeringRule: '强制调整手机屏幕方向（横屏或竖屏）。',
      jsBridgeApi: 'screen.orientation.set',
    ),
    ToolPromptConfig(
      toolName: 'screen_orientation_status',
      groupName: 'native',
      triggeringRule: '查询屏幕显示方向。',
      jsBridgeApi: 'screen.orientation.status',
    ),
    ToolPromptConfig(
      toolName: 'sensor_accelerometer_read',
      groupName: 'native',
      triggeringRule: '读取重力加速度传感器数据。',
      jsBridgeApi: 'sensor.accelerometer.read',
    ),
    ToolPromptConfig(
      toolName: 'sensor_gyroscope_read',
      groupName: 'native',
      triggeringRule: '读取陀螺仪传感器数据。',
      jsBridgeApi: 'sensor.gyroscope.read',
    ),
    ToolPromptConfig(
      toolName: 'sensor_magnetometer_read',
      groupName: 'native',
      triggeringRule: '读取磁力计传感器数据。',
      jsBridgeApi: 'sensor.magnetometer.read',
    ),
    ToolPromptConfig(
      toolName: 'location_get_current',
      groupName: 'native',
      triggeringRule: '获取手机 GPS 当前定位。',
      jsBridgeApi: 'location.get_current',
    ),
    ToolPromptConfig(
      toolName: 'notification_schedule',
      groupName: 'native',
      triggeringRule: '配置和推送系统日程通知。',
      jsBridgeApi: 'notification.schedule',
    ),
    ToolPromptConfig(
      toolName: 'notification_pending',
      groupName: 'native',
      triggeringRule: '查询未读通知。',
      jsBridgeApi: 'notification.pending',
    ),
    ToolPromptConfig(
      toolName: 'notification_cancel',
      groupName: 'native',
      triggeringRule: '撤回指定通知。',
      jsBridgeApi: 'notification.cancel',
    ),
    ToolPromptConfig(
      toolName: 'notification_cancel_all',
      groupName: 'native',
      triggeringRule: '清空所有通知。',
      jsBridgeApi: 'notification.cancel_all',
    ),
    ToolPromptConfig(
      toolName: 'calendar_event_create',
      groupName: 'native',
      triggeringRule: '创建手机系统日程表日历事件。',
      jsBridgeApi: 'calendar.event.create',
    ),

    // web
    ToolPromptConfig(
      toolName: 'web_search',
      groupName: 'web',
      triggeringRule: '需要最新信息、网页资料、来源引用时使用。',
      jsBridgeApi: 'web.search',
    ),
    ToolPromptConfig(
      toolName: 'web_fetch',
      groupName: 'web',
      triggeringRule: '读取具体网页正文时使用。',
      jsBridgeApi: 'web.fetch',
    ),

    // extensions
    ToolPromptConfig(
      toolName: 'skill_install',
      groupName: 'extensions',
      triggeringRule: '仅在用户明确要求安装 Skill 扩展工具时使用。',
    ),
    ToolPromptConfig(
      toolName: 'skill_invoke',
      groupName: 'extensions',
      triggeringRule: '仅在用户明确要求执行已安装的 Skill 扩展工具时使用。',
    ),
    ToolPromptConfig(
      toolName: 'mcp_connect',
      groupName: 'extensions',
      triggeringRule: '仅在用户明确要求连接 MCP 外部工具源时使用。',
    ),
  ];

  static String generateCapabilityIndex(String toolIndex) {
    final buffer = StringBuffer();
    final activeGroups = <String>{};

    for (final config in _configs) {
      if (toolIndex.contains(config.toolName)) {
        activeGroups.add(config.groupName);
      }
    }

    // 处理通配符情况 (例如 document_*, spreadsheet_*, pdf_*, presentation_*)
    if (toolIndex.contains('document_') ||
        toolIndex.contains('spreadsheet_') ||
        toolIndex.contains('presentation_') ||
        toolIndex.contains('pdf_')) {
      activeGroups.add('office');
    }

    if (activeGroups.isEmpty) {
      return '';
    }

    buffer.writeln('能力层级架构（Capability Layering）：');

    final layers = [
      ('L1 基础交互与感知层（无副作用通用基础能力）', ['web', 'native']),
      ('L2 沙箱与工作区数据层（沙箱内状态管理与增删改查）', ['memory', 'notes', 'workspace', 'files']),
      ('L3 进阶产物与工程协同层（具备高度业务复合特征的复合输出能力）', ['artifacts', 'projects', 'office']),
      ('L4 系统扩展层（第三方接口集成与自定义脚本扩展）', ['extensions']),
    ];

    for (final layer in layers) {
      final layerTitle = layer.$1;
      final groups = layer.$2;

      final activeGroupsInLayer = groups.where((g) => activeGroups.contains(g)).toList();
      if (activeGroupsInLayer.isEmpty) {
        continue;
      }

      buffer.writeln('\n$layerTitle:');

      for (final group in activeGroupsInLayer) {
        final groupConfigs = _configs.where((c) => c.groupName == group).toList();
        String triggeringRule = '';
        final tools = <String>{};

        if (group == 'office') {
          triggeringRule = '用于 Office/PDF 的提取、生成和受控局部文本替换。';
          tools.addAll(['document_*', 'spreadsheet_*', 'presentation_*', 'pdf_*']);
        } else {
          triggeringRule = groupConfigs.isNotEmpty ? groupConfigs.first.triggeringRule : '';
          tools.addAll(groupConfigs.map((c) => c.toolName));
        }

        // 仅保留在当前 toolIndex 中有的工具
        final activeTools = tools.where((t) {
          if (t.contains('*')) {
            return true; // 通配符保留
          }
          return toolIndex.contains(t);
        }).join(' / ');

        if (activeTools.isNotEmpty) {
          buffer.writeln('  - $group: $activeTools。$triggeringRule');
        }
      }
    }

    return buffer.toString().trim();
  }

  static String generateWorkflowContracts(String toolIndex) {
    final buffer = StringBuffer();
    final contracts = <String>{};

    // 默认全局通用契约
    contracts.add('1. 普通对话：没有暴露工具时直接回答；不要为了使用已注入记忆而调用 memory_query。');
    
    // 检查其他特定工具，拉取对应的契约
    final activeContracts = <String>{};
    for (final config in _configs) {
      if (toolIndex.contains(config.toolName)) {
        activeContracts.addAll(config.contracts);
      }
    }

    // 通配符情况
    if (toolIndex.contains('document_') ||
        toolIndex.contains('spreadsheet_') ||
        toolIndex.contains('presentation_') ||
        toolIndex.contains('pdf_')) {
      activeContracts.add('Office/PDF：上传或处理 Word、Excel、PPT、PDF 时先提取；生成新文件时写入当前 Workspace 文件区；局部替换不承诺保留复杂原格式。');
    }

    int index = 2;
    for (final contract in activeContracts) {
      buffer.writeln('$index. $contract');
      index++;
    }

    return '${contracts.join("\n")}\n${buffer.toString()}'.trim();
  }

  static String generateJsBridgeApis() {
    final apis = _configs
        .map((c) => c.jsBridgeApi)
        .where((api) => api != null && api.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    
    return '- JSBridge 当前可用能力：${apis.join(", ")}。';
  }
}
