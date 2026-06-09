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
    final decision = _withWebAppMaintenanceTools(
      decision: decoded,
      latestPrompt: latestPrompt,
      recentContext: routingContext,
      allTools: allTools,
    );
    return routeFromDecision(
      decision: decision,
      allTools: allTools,
      latestPromptLength: latestPrompt.length,
      contextLength: routingContext.length,
    );
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
      '如果用户最新消息是在反馈、修复或迭代已有 Web App/网页/小游戏的问题，必须暴露 artifact_query、artifact_inspect_logs、file_search_app_files、file_read_app_file、project_update_web_app、project_version_history、project_revert_web_app；让 Agent 先读运行日志和项目文件，再用项目级更新能力修改原项目。',
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
