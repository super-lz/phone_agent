import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';

class WebCapabilityAdapter {
  WebCapabilityAdapter({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration requestTimeout;

  Future<Map<String, Object?>> search(
    Map<String, Object?> arguments, {
    String? apiKey,
  }) async {
    final query = _requiredString(arguments, 'query');
    if (query == null) {
      return const {'ok': false, 'error': 'query is required'};
    }

    return _callWebSearchMcp(
      apiKey: apiKey,
      input: query,
      action: 'web.search',
      extraOutput: {'query': query},
    );
  }

  Future<Map<String, Object?>> fetch(
    Map<String, Object?> arguments, {
    String? apiKey,
  }) async {
    final url = _requiredString(arguments, 'url');
    if (url == null) {
      return const {'ok': false, 'error': 'url is required'};
    }
    final target = Uri.tryParse(url);
    if (target == null || !target.hasScheme || target.host.isEmpty) {
      return {'ok': false, 'error': 'invalid url', 'url': url};
    }

    return _callWebSearchMcp(
      apiKey: apiKey,
      input: '请抓取并解析这个网页，返回标题、正文要点和可引用来源：${target.toString()}',
      action: 'web.fetch',
      extraOutput: {'url': target.toString()},
    );
  }

  Future<Map<String, Object?>> _callWebSearchMcp({
    required String? apiKey,
    required String input,
    required String action,
    required Map<String, Object?> extraOutput,
  }) async {
    final normalizedApiKey = apiKey?.trim();
    AppLogger.info('$action.start', {
      'provider': _provider,
      'inputLength': input.length,
      'hasApiKey': normalizedApiKey != null && normalizedApiKey.isNotEmpty,
    });
    if (normalizedApiKey == null || normalizedApiKey.isEmpty) {
      return {'ok': false, 'provider': _provider, 'error': 'api_key_required'};
    }

    try {
      final sessionId = await _initialize(normalizedApiKey);
      if (sessionId == null) {
        return {
          'ok': false,
          'provider': _provider,
          'error': 'initialize_failed',
          ...extraOutput,
        };
      }
      await _notifyInitialized(apiKey: normalizedApiKey, sessionId: sessionId);
      final toolName = await _resolveToolName(
        apiKey: normalizedApiKey,
        sessionId: sessionId,
      );
      final response = await _postMcp(
        apiKey: normalizedApiKey,
        sessionId: sessionId,
        body: {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {'name': toolName, 'arguments': _toolArguments(input)},
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'ok': false,
          'provider': _provider,
          'error': 'HTTP ${response.statusCode}',
          if (response.body.isNotEmpty) 'body': response.body,
          ...extraOutput,
        };
      }

      final payload = _decodePayload(response.body);
      final result = payload?['result'];
      if (result is! Map<String, Object?>) {
        return {
          'ok': false,
          'provider': _provider,
          'error': payload?['error']?.toString() ?? 'missing_result',
          ...extraOutput,
        };
      }

      final content = _extractText(result);
      AppLogger.info('$action.completed', {
        'provider': _provider,
        'tool': toolName,
        'contentLength': content.length,
      });
      return {
        'ok': content.isNotEmpty,
        'provider': _provider,
        'content': content,
        if (content.isEmpty) 'error': 'empty_result',
        ...extraOutput,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('$action.exception', error, stackTrace);
      return {
        'ok': false,
        'provider': _provider,
        'error': error.toString(),
        ...extraOutput,
      };
    }
  }

  Future<String?> _initialize(String apiKey) async {
    final response = await _postMcp(
      apiKey: apiKey,
      body: const {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-03-26',
          'capabilities': <String, Object?>{},
          'clientInfo': {'name': 'PhoneAgent', 'version': '0.1.0'},
        },
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AppLogger.warning('web.search.mcp.initialize_http_error', {
        'statusCode': response.statusCode,
        'body': response.body,
      });
      return null;
    }
    return response.headers['mcp-session-id'] ??
        response.headers['Mcp-Session-Id'] ??
        '';
  }

  Future<void> _notifyInitialized({
    required String apiKey,
    required String sessionId,
  }) async {
    try {
      await _postMcp(
        apiKey: apiKey,
        sessionId: sessionId,
        body: const {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'web.search.mcp.initialized_exception',
        error,
        stackTrace,
      );
    }
  }

  Future<String> _resolveToolName({
    required String apiKey,
    required String sessionId,
  }) async {
    try {
      final response = await _postMcp(
        apiKey: apiKey,
        sessionId: sessionId,
        body: const {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'web_search';
      }
      final payload = _decodePayload(response.body);
      final result = payload?['result'];
      if (result is! Map<String, Object?>) {
        return 'web_search';
      }
      final tools = result['tools'];
      if (tools is! List<Object?> || tools.isEmpty) {
        return 'web_search';
      }
      final names = tools
          .whereType<Map<String, Object?>>()
          .map((tool) => tool['name'])
          .whereType<String>()
          .toList(growable: false);
      for (final candidate in const ['web_search', 'search', 'websearch']) {
        if (names.contains(candidate)) {
          return candidate;
        }
      }
      return names.isEmpty ? 'web_search' : names.first;
    } on Object catch (error, stackTrace) {
      AppLogger.error('web.search.mcp.tools_list_exception', error, stackTrace);
      return 'web_search';
    }
  }

  Future<http.Response> _postMcp({
    required String apiKey,
    required Map<String, Object?> body,
    String? sessionId,
  }) {
    return _httpClient
        .post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2025-03-26',
            if (sessionId != null && sessionId.isNotEmpty)
              'Mcp-Session-Id': sessionId,
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
  }

  Map<String, Object?>? _decodePayload(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('data:')) {
      for (final line in const LineSplitter().convert(trimmed)) {
        final data = line.trim();
        if (!data.startsWith('data:')) {
          continue;
        }
        final jsonText = data.substring(5).trim();
        if (jsonText.isEmpty || jsonText == '[DONE]') {
          continue;
        }
        final decoded = jsonDecode(jsonText);
        return decoded is Map<String, Object?> ? decoded : null;
      }
      return null;
    }
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  Map<String, Object?> _toolArguments(String input) {
    return {'query': input, 'q': input, 'keyword': input, 'input': input};
  }

  String _extractText(Map<String, Object?> result) {
    final content = result['content'];
    if (content is! List<Object?>) {
      return '';
    }
    return content
        .whereType<Map<String, Object?>>()
        .map((block) => block['text'])
        .whereType<String>()
        .join('\n')
        .trim();
  }

  String? _requiredString(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  static const _provider = 'aliyun_bailian_websearch_mcp';
  static final _endpoint = Uri.parse(
    'https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp',
  );
}
