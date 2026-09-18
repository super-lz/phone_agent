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
        latestPromptLength: latestPrompt.length,
        contextLength: routingContext.length,
      );
    }
    final decoded = _decodeRouteDecision(result.content);
    return routeFromDecision(
      decision: decoded,
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
    final selectedTools = [
      for (final name in selectedNames.toList(growable: false)..sort())
        toolByName[name]!,
    ];

    final logData = <String, Object?>{
      'selectedToolCount': selectedTools.length,
      'availableToolCount': allTools.length,
      'usesContext': decision['uses_context'] == true,
      'selectedTools': selectedNames.toList(growable: false)..sort(),
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
      index: _toolIndexFor(selectedTools),
      selectedToolNames: selectedNames.toList(growable: false)..sort(),
    );
  }

  String _routingSystemPrompt() {
    return [
      '你是 Phone Agent 的工具路由器，只做工具 schema 选择，不回答用户、不执行任务。',
      '根据 latest_user_message 和 available_tools 里的能力描述，选择本轮需要暴露的最小工具集合。',
      'recent_context 只用于判断当前消息是否在承接上一轮尚未完成的任务；若是承接，保留完成该任务所需的工具。',
      '不要因为 recent_context 或 assistant 自我介绍里出现工具、能力、Web App、创建等字样就选择工具。',
      '按能力语义选择：网上查找信息、图片或来源用联网搜索；只有用户要从本机相册或文件里选出内容时，才用本地选择器。',
      '普通聊天、问候、身份追问、闲聊应返回空工具列表。',
      '如果用户最新消息要求创建、保存、写入、修改、查询、搜索、读取、调用手机能力或生成可复用产物，选择能完成真实动作的最小工具集合。',
      '选择的工具只是候选，不会强制执行。工具结果与 execution receipt 才能支持完成声明；需要更多能力时，选择能让 Agent 在后续步骤继续发现的最小集合。',
      '只输出一个 JSON 对象，不要 Markdown，不要代码围栏，不要解释。',
    ].join('\n');
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

  String _toolIndexFor(List<Map<String, Object?>> selectedTools) {
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
    return '本轮路由模型只暴露以下工具 schema：\n$toolLines\n'
        '未暴露的工具视为本轮暂不可用，不要臆造调用；需要其它能力时在后续步骤请求发现。';
  }
}

class ToolRoute {
  const ToolRoute({
    required this.tools,
    required this.index,
    required this.selectedToolNames,
  });

  final List<Map<String, Object?>> tools;
  final String index;
  final List<String> selectedToolNames;

  factory ToolRoute.fromSnapshot({
    required List<Map<String, Object?>> tools,
    required String index,
  }) {
    final names = <String>[];
    for (final tool in tools) {
      final function = tool['function'];
      final name = function is Map ? function['name'] : null;
      if (name is String && name.isNotEmpty) {
        names.add(name);
      }
    }
    return ToolRoute(tools: tools, index: index, selectedToolNames: names);
  }
}
