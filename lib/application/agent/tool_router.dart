import '../../core/logging/app_logger.dart';

class AgentToolRouter {
  const AgentToolRouter();

  ToolRoute route({
    required Object prompt,
    required List<Map<String, Object?>> allTools,
  }) {
    final promptText = _extractPromptText(prompt).toLowerCase();
    final selectedNames = <String>{};
    final requiredNames = <String>{};

    void add(Iterable<String> names) {
      selectedNames.addAll(names);
    }

    if (_matchesAny(promptText, _memoryTerms)) {
      add(_memoryTools);
    }
    if (_matchesAny(promptText, _noteTerms)) {
      add(_noteTools);
    }
    if (_matchesAny(promptText, _workspaceTerms)) {
      add(_workspaceTools);
    }
    if (_matchesAny(promptText, _webTerms) || _hasUrl(promptText)) {
      add(_webTools);
    }
    final hasProjectIntent = _matchesAny(promptText, _projectTerms);
    final hasCreationIntent = _matchesAny(promptText, _creationTerms);
    final hasAppCreationIntent =
        hasCreationIntent && _matchesAny(promptText, _appTerms);
    if (hasProjectIntent || hasAppCreationIntent) {
      add(_projectTools);
      if (hasCreationIntent &&
          _matchesAny(promptText, _projectCreationTargetTerms)) {
        requiredNames.add('project_create_web_app');
      }
    }
    if (_matchesAny(promptText, _fileTerms)) {
      add(_fileTools);
    }
    if (_matchesAny(promptText, _artifactTerms)) {
      add(_artifactTools);
    }
    if (_matchesAny(promptText, _officeTerms)) {
      add(_officeTools);
    }
    if (_matchesAny(promptText, _deviceTerms)) {
      add(_deviceTools);
    }
    if (_matchesAny(promptText, _timeTerms)) {
      add(_timeTools);
    }
    if (_matchesAny(promptText, _locationTerms)) {
      add(_locationTools);
    }
    if (_matchesAny(promptText, _clipboardTerms)) {
      add(_clipboardTools);
    }
    if (_matchesAny(promptText, _shareTerms)) {
      add(_shareTools);
    }
    if (_matchesAny(promptText, _feedbackTerms)) {
      add(_feedbackTools);
    }
    if (_matchesAny(promptText, _urlTerms)) {
      add(_urlTools);
    }
    if (_matchesAny(promptText, _screenTerms)) {
      add(_screenTools);
    }
    if (_matchesAny(promptText, _sensorTerms)) {
      add(_sensorTools);
    }
    if (_matchesAny(promptText, _extensionTerms)) {
      add(_extensionTools);
    }

    final selectedTools = _toolsByName(allTools, selectedNames);
    AppLogger.info('agent_tool_router.route', {
      'promptLength': promptText.length,
      'selectedToolCount': selectedTools.length,
      'availableToolCount': allTools.length,
      'selectedTools': selectedNames.toList(growable: false)..sort(),
      'requiredTools': requiredNames.toList(growable: false)..sort(),
    });
    return ToolRoute(
      tools: selectedTools,
      index: _toolIndexFor(selectedNames, requiredNames),
      selectedToolNames: selectedNames.toList(growable: false)..sort(),
      requiredToolNames: requiredNames.toList(growable: false)..sort(),
    );
  }

  List<Map<String, Object?>> _toolsByName(
    List<Map<String, Object?>> allTools,
    Set<String> names,
  ) {
    if (names.isEmpty) {
      return const [];
    }
    final tools = <Map<String, Object?>>[];
    for (final tool in allTools) {
      final name = _toolName(tool);
      if (name != null && names.contains(name)) {
        tools.add(tool);
      }
    }
    return tools;
  }

  String? _toolName(Map<String, Object?> tool) {
    final function = tool['function'];
    if (function is! Map<String, Object?>) {
      return null;
    }
    final name = function['name'];
    return name is String ? name : null;
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

  bool _matchesAny(String text, List<String> terms) {
    return terms.any(text.contains);
  }

  bool _hasUrl(String text) {
    return text.contains('http://') || text.contains('https://');
  }

  String _toolIndexFor(Set<String> selectedNames, Set<String> requiredNames) {
    if (selectedNames.isEmpty) {
      return '本轮未暴露工具 schema；如果用户只是普通聊天，直接回答。';
    }
    final groups = <String>[];
    void addGroup(String label, Iterable<String> names) {
      if (names.any(selectedNames.contains)) {
        groups.add(label);
      }
    }

    addGroup('记忆', _memoryTools);
    addGroup('笔记', _noteTools);
    addGroup('工作区', _workspaceTools);
    addGroup('联网搜索/网页读取', _webTools);
    addGroup('文件/项目维护', _fileTools.followedBy(_projectTools));
    addGroup('Artifact', _artifactTools);
    addGroup('Office/PDF 文档', _officeTools);
    addGroup(
      '设备/时间/位置/传感器',
      _deviceTools
          .followedBy(_timeTools)
          .followedBy(_locationTools)
          .followedBy(_sensorTools),
    );
    addGroup(
      '剪贴板/分享/系统交互',
      _clipboardTools
          .followedBy(_shareTools)
          .followedBy(_feedbackTools)
          .followedBy(_urlTools)
          .followedBy(_screenTools),
    );
    addGroup('Skill/MCP', _extensionTools);
    final requiredText = requiredNames.isEmpty
        ? ''
        : ' 本轮用户请求需要真实产物，必须成功调用这些工具后才能声称完成：${requiredNames.join('、')}。';
    return '本轮按用户意图只暴露以下工具组：${groups.join('、')}。'
        '未暴露的工具组视为本轮不可用，不要臆造调用。$requiredText';
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

const _memoryTools = ['memory_create', 'memory_query', 'memory_delete'];
const _noteTools = ['db_note_create', 'db_note_query'];
const _workspaceTools = ['workspace_create', 'workspace_switch'];
const _webTools = ['web_search', 'web_fetch'];
const _fileTools = [
  'file_write_app_file',
  'file_read_app_file',
  'file_search_app_files',
  'file_apply_text_patch',
];
const _projectTools = [
  'project_create_web_app',
  'artifact_create',
  'artifact_query',
  ..._fileTools,
];
const _artifactTools = ['artifact_create', 'artifact_query'];
const _officeTools = [
  'document_extract',
  'document_generate',
  'document_apply_text_patch',
  'spreadsheet_extract',
  'spreadsheet_generate',
  'presentation_extract',
  'presentation_generate',
  'pdf_extract',
  'pdf_generate',
];
const _deviceTools = ['device_info', 'battery_status', 'network_status'];
const _timeTools = [
  'time_get_current',
  'notification_schedule',
  'calendar_event_create',
];
const _locationTools = ['location_get_current'];
const _clipboardTools = ['clipboard_read', 'clipboard_write'];
const _shareTools = ['share_text'];
const _feedbackTools = ['system_haptic_feedback', 'system_sound_alert'];
const _urlTools = ['url_open_external'];
const _screenTools = ['screen_keep_awake', 'screen_keep_awake_status'];
const _sensorTools = [
  'sensor_accelerometer_read',
  'sensor_gyroscope_read',
  'sensor_magnetometer_read',
];
const _extensionTools = ['skill_install', 'skill_invoke', 'mcp_connect'];

const _memoryTerms = ['记住', '忘记', '记忆', '偏好', '你记得', '长期'];
const _noteTerms = ['备忘', '笔记', '记录一下', '记一条', '保存信息', '待办'];
const _workspaceTerms = ['工作区', '空间', '切换到', '新建工作', '创建工作'];
const _webTerms = [
  '搜索',
  '联网',
  '查一下',
  '最新',
  '新闻',
  '网页内容',
  '网页读取',
  '网页解析',
  '网址',
  '来源',
  '资料',
  '价格',
  '官网',
  '天气',
];
const _projectTerms = [
  'web app',
  'webapp',
  '网页',
  '网站',
  '小游戏',
  '原型',
  'html',
  'css',
  'javascript',
  'jsbridge',
  '预览',
  '页面',
  '样式',
  '修复bug',
  '修 bug',
];
const _creationTerms = [
  '创建',
  '生成',
  '做一个',
  '做个',
  '开发',
  '实现',
  '写一个',
  '写个',
  '写一',
  '制作',
  '搭建',
  '设计一个',
  '设计个',
];
const _appTerms = ['应用', 'app', '小程序'];
const _projectCreationTargetTerms = [
  'web app',
  'webapp',
  '网页',
  '网站',
  '小游戏',
  '原型',
  '页面',
  '应用',
  'app',
  '小程序',
];
const _fileTerms = [
  '文件',
  '读取',
  '写入',
  '修改',
  '补丁',
  '代码',
  'bug',
  '日志',
  '目录',
  '源码',
];
const _artifactTerms = ['artifact', '卡片', '报告', '文档', '表格', '产物', '复用'];
const _officeTerms = [
  'office',
  'word',
  'docx',
  'excel',
  'xlsx',
  'ppt',
  'pptx',
  'pdf',
  '简历',
  '合同',
  '论文',
  '财报',
  '演示文稿',
  '幻灯片',
  '表格',
  '文档',
];
const _deviceTerms = [
  '手机',
  '设备',
  '型号',
  '系统版本',
  '电量',
  '电池',
  '网络',
  'wifi',
  'wi-fi',
];
const _timeTerms = [
  '现在几点',
  '当前时间',
  '今天',
  '明天',
  '后天',
  '今晚',
  '提醒',
  '通知',
  '日历',
  '日程',
  '会议',
  '分钟后',
  '小时后',
];
const _locationTerms = ['位置', '定位', '附近', '经纬度', '地图', '导航'];
const _clipboardTerms = ['剪贴板', '复制', '粘贴'];
const _shareTerms = ['分享', '发给'];
const _feedbackTerms = ['震动', '振动', '触感', '提示音', '声音'];
const _urlTerms = ['打开链接', '打开网址', '打电话', '短信', '邮件', 'mailto', 'tel:'];
const _screenTerms = ['常亮', '熄屏', '屏幕保持', '不要锁屏'];
const _sensorTerms = ['传感器', '加速度', '陀螺仪', '磁力计', '罗盘', '姿态', '方向'];
const _extensionTerms = ['skill', 'mcp', '插件', '外部工具'];
