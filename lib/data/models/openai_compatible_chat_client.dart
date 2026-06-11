import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../../domain/models/model_provider_config.dart';

class ModelConnectionResult {
  const ModelConnectionResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class ChatCompletionResult {
  const ChatCompletionResult({required this.ok, required this.content});

  final bool ok;
  final String content;
}

class ToolCallRequest {
  const ToolCallRequest({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  Map<String, Object?> toAssistantMessageToolCall() {
    return {
      'id': id,
      'type': 'function',
      'function': {'name': name, 'arguments': jsonEncode(arguments)},
    };
  }
}

class ToolCallDelta {
  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta,
  });

  final int index;
  final String? id;
  final String? name;
  final String? argumentsDelta;
}

class ChatStreamEvent {
  const ChatStreamEvent({
    this.contentDelta = '',
    this.toolCallDeltas = const [],
  });

  final String contentDelta;
  final List<ToolCallDelta> toolCallDeltas;

  bool get isEmpty => contentDelta.isEmpty && toolCallDeltas.isEmpty;
}

class ModelRequestException implements Exception {
  const ModelRequestException(this.message, {this.isRetryable = false});

  final String message;
  final bool isRetryable;

  @override
  String toString() {
    return message;
  }
}

class OpenAiCompatibleChatClient {
  OpenAiCompatibleChatClient({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 30),
    this.streamIdleTimeout = const Duration(seconds: 45),
  }) : _httpClient = httpClient ?? http.Client();

  static Object? diagnosticPayloadForLog(Object? value) {
    return _diagnosticValue(value);
  }

  final http.Client _httpClient;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;

  Stream<String> streamText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async* {
    await for (final event in streamChat(
      provider: provider,
      apiKey: apiKey,
      messages: messages,
    )) {
      if (event.contentDelta.isNotEmpty) {
        yield event.contentDelta;
      }
    }
  }

  Stream<ChatStreamEvent> streamChat({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) async* {
    if (provider.apiProtocol == ModelApiProtocol.unavailable) {
      throw ModelRequestException(_unavailableProviderMessage(provider));
    }
    if (provider.apiProtocol == ModelApiProtocol.anthropicMessages) {
      yield* _streamAnthropicMessages(
        provider: provider,
        apiKey: apiKey,
        messages: messages,
      );
      return;
    }
    final requestBody = _openAiChatRequestBody(
      provider: provider,
      messages: messages,
      stream: true,
      tools: tools,
    );
    AppLogger.info('model.stream_chat.start', {
      'provider': provider.id,
      'model': provider.model,
      'messageCount': messages.length,
      'toolCount': tools.length,
    });
    AppLogger.info('model.stream_chat.request_prompt', {
      'provider': provider.id,
      'model': provider.model,
      'messageCount': messages.length,
      'toolCount': tools.length,
      'toolNames': _toolNamesForLog(tools),
      'messages': jsonEncode(diagnosticPayloadForLog(messages)),
    });
    final request = http.Request('POST', provider.chatCompletionsEndpoint)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        ...provider.defaultHeaders,
      })
      ..body = jsonEncode(requestBody);

    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(requestTimeout);
    } on Object catch (error, stackTrace) {
      throw _modelRequestExceptionFor(
        error,
        stackTrace,
        provider: provider,
        stage: 'connect',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      AppLogger.warning('model.stream_chat.http_error', {
        'statusCode': response.statusCode,
        'body': body,
      });
      throw ModelRequestException('HTTP ${response.statusCode}: $body');
    }

    var eventCount = 0;
    try {
      await for (final line
          in response.stream
              .timeout(
                streamIdleTimeout,
                onTimeout: (sink) {
                  sink.addError(
                    TimeoutException(
                      '模型流式响应 ${_formatDuration(streamIdleTimeout)} 没有新数据。',
                      streamIdleTimeout,
                    ),
                  );
                  sink.close();
                },
              )
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final chunk = _parseSseDataLine(line);
        if (chunk == null) {
          continue;
        }
        if (chunk == '[DONE]') {
          AppLogger.info('model.stream_chat.completed', {
            'provider': provider.id,
            'model': provider.model,
            'eventCount': eventCount,
          });
          return;
        }

        final event = _extractStreamEvent(chunk);
        if (!event.isEmpty) {
          eventCount += 1;
          yield event;
        }
      }
      AppLogger.warning('model.stream_chat.closed_without_done', {
        'provider': provider.id,
        'model': provider.model,
        'eventCount': eventCount,
      });
    } on Object catch (error, stackTrace) {
      throw _modelRequestExceptionFor(
        error,
        stackTrace,
        provider: provider,
        stage: 'receive',
      );
    }
  }

  Future<String> generateResponse({
    required ModelProviderConfig provider,
    required String apiKey,
    required String prompt,
    String? systemPrompt,
  }) async {
    final messages = [
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final result = await completeText(
      provider: provider,
      apiKey: apiKey,
      messages: messages,
    );

    if (!result.ok) {
      throw ModelRequestException(result.content);
    }

    return result.content;
  }

  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    if (provider.apiProtocol == ModelApiProtocol.unavailable) {
      return ChatCompletionResult(
        ok: false,
        content: _unavailableProviderMessage(provider),
      );
    }
    if (provider.apiProtocol == ModelApiProtocol.anthropicMessages) {
      return _completeAnthropicMessages(
        provider: provider,
        apiKey: apiKey,
        messages: messages,
      );
    }
    try {
      final response = await _postChatCompletion(
        provider: provider,
        apiKey: apiKey,
        body: _openAiChatRequestBody(
          provider: provider,
          messages: messages,
          stream: false,
        ),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ChatCompletionResult(
          ok: false,
          content: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final text = _extractAssistantTextFromBody(response.body);
      return ChatCompletionResult(
        ok: text.isNotEmpty,
        content: text.isEmpty ? '模型响应中没有文本内容。' : text,
      );
    } on Object catch (error) {
      return ChatCompletionResult(ok: false, content: error.toString());
    }
  }

  Future<ModelConnectionResult> testConnection({
    required ModelProviderConfig provider,
    required String apiKey,
  }) async {
    if (provider.apiProtocol == ModelApiProtocol.unavailable) {
      return ModelConnectionResult(
        ok: false,
        message: _unavailableProviderMessage(provider),
      );
    }
    if (provider.apiProtocol == ModelApiProtocol.anthropicMessages) {
      final result = await _completeAnthropicMessages(
        provider: provider,
        apiKey: apiKey,
        messages: const [
          {'role': 'user', 'content': '请用一句话回答：Phone Agent 模型连接正常吗？'},
        ],
      );
      return ModelConnectionResult(
        ok: result.ok,
        message: result.ok
            ? _connectionSuccessMessage(provider)
            : result.content,
      );
    }
    AppLogger.info('model.test_connection.start', {
      'provider': provider.id,
      'model': provider.model,
    });
    try {
      final response = await _postChatCompletion(
        provider: provider,
        apiKey: apiKey,
        body: _openAiChatRequestBody(
          provider: provider,
          messages: const [
            {'role': 'user', 'content': '请用一句话回答：Phone Agent 模型连接正常吗？'},
          ],
          stream: false,
          overrides: const {'max_tokens': 128},
        ),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.warning('model.test_connection.http_error', {
          'statusCode': response.statusCode,
          'body': response.body,
        });
        return ModelConnectionResult(
          ok: false,
          message: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final text = _extractAssistantTextFromBody(response.body);
      AppLogger.info('model.test_connection.completed', {
        'ok': text.isNotEmpty,
      });
      return ModelConnectionResult(
        ok: text.isNotEmpty,
        message: text.isEmpty
            ? 'HTTP 200，但模型响应中没有可用文本内容。'
            : _connectionSuccessMessage(provider),
      );
    } on Object catch (error) {
      AppLogger.error('model.test_connection.exception', error);
      return ModelConnectionResult(ok: false, message: error.toString());
    }
  }

  Stream<ChatStreamEvent> _streamAnthropicMessages({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async* {
    final requestBody = _anthropicRequestBody(
      provider: provider,
      messages: messages,
      stream: true,
    );
    AppLogger.info('model.stream_chat.anthropic.start', {
      'provider': provider.id,
      'model': provider.model,
      'messageCount': messages.length,
    });
    final request = http.Request('POST', provider.anthropicMessagesEndpoint)
      ..headers.addAll(_anthropicHeaders(provider: provider, apiKey: apiKey))
      ..body = jsonEncode(requestBody);

    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(requestTimeout);
    } on Object catch (error, stackTrace) {
      throw _modelRequestExceptionFor(
        error,
        stackTrace,
        provider: provider,
        stage: 'connect',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw ModelRequestException('HTTP ${response.statusCode}: $body');
    }

    try {
      await for (final line
          in response.stream
              .timeout(
                streamIdleTimeout,
                onTimeout: (sink) {
                  sink.addError(
                    TimeoutException(
                      '模型流式响应 ${_formatDuration(streamIdleTimeout)} 没有新数据。',
                      streamIdleTimeout,
                    ),
                  );
                  sink.close();
                },
              )
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final chunk = _parseSseDataLine(line);
        if (chunk == null) {
          continue;
        }
        final event = _extractAnthropicStreamEvent(chunk);
        if (event == null) {
          continue;
        }
        if (!event.isEmpty) {
          yield event;
        }
      }
    } on Object catch (error, stackTrace) {
      throw _modelRequestExceptionFor(
        error,
        stackTrace,
        provider: provider,
        stage: 'receive',
      );
    }
  }

  Future<ChatCompletionResult> _completeAnthropicMessages({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    try {
      final response = await _httpClient
          .post(
            provider.anthropicMessagesEndpoint,
            headers: _anthropicHeaders(provider: provider, apiKey: apiKey),
            body: jsonEncode(
              _anthropicRequestBody(
                provider: provider,
                messages: messages,
                stream: false,
              ),
            ),
          )
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ChatCompletionResult(
          ok: false,
          content: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final text = _extractAnthropicTextFromBody(response.body);
      return ChatCompletionResult(
        ok: text.isNotEmpty,
        content: text.isEmpty ? '模型响应中没有文本内容。' : text,
      );
    } on Object catch (error) {
      return ChatCompletionResult(ok: false, content: error.toString());
    }
  }

  Map<String, String> _anthropicHeaders({
    required ModelProviderConfig provider,
    required String apiKey,
  }) {
    return {
      'x-api-key': apiKey,
      'Content-Type': 'application/json',
      ...provider.defaultHeaders,
    };
  }

  Map<String, Object?> _anthropicRequestBody({
    required ModelProviderConfig provider,
    required List<Map<String, Object?>> messages,
    required bool stream,
  }) {
    final systemParts = <String>[];
    final anthropicMessages = <Map<String, Object?>>[];
    for (final message in messages) {
      final role = message['role'] as String? ?? 'user';
      final content = _messageContentAsText(message['content']);
      if (content.isEmpty) {
        continue;
      }
      if (role == 'system') {
        systemParts.add(content);
        continue;
      }
      anthropicMessages.add({
        'role': role == 'assistant' ? 'assistant' : 'user',
        'content': content,
      });
    }
    return {
      'model': provider.model,
      ...provider.defaultParameters,
      if (systemParts.isNotEmpty) 'system': systemParts.join('\n\n'),
      'messages': anthropicMessages.isEmpty
          ? [
              {'role': 'user', 'content': 'Hello'},
            ]
          : anthropicMessages,
      'stream': stream,
    };
  }

  String _messageContentAsText(Object? content) {
    if (content is String) {
      return content;
    }
    if (content is List<Object?>) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map<String, Object?>) {
          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.write('\n');
            buffer.write(text);
          }
        }
      }
      return buffer.toString();
    }
    return '';
  }

  ChatStreamEvent? _extractAnthropicStreamEvent(String chunk) {
    final decoded = jsonDecode(chunk);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final type = decoded['type'];
    if (type == 'message_stop') {
      return const ChatStreamEvent();
    }
    if (type != 'content_block_delta') {
      return null;
    }
    final delta = decoded['delta'];
    if (delta is! Map<String, Object?>) {
      return null;
    }
    final text = delta['text'];
    return ChatStreamEvent(contentDelta: text is String ? text : '');
  }

  String _extractAnthropicTextFromBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      return '';
    }
    final content = decoded['content'];
    if (content is! List<Object?>) {
      return '';
    }
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map<String, Object?>) {
        final text = item['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }

  String _unavailableProviderMessage(ModelProviderConfig provider) {
    return '${provider.vendorName} 已加入模型列表，但官方 API endpoint 尚未确认；'
        '当前版本可以保存配置，暂不发起连接测试或普通对话调用。';
  }

  String _connectionSuccessMessage(ModelProviderConfig provider) {
    return '连接成功：${provider.vendorName} / ${provider.model} 返回了有效响应。';
  }

  String? _parseSseDataLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('data:')) {
      return null;
    }
    return trimmed.substring(5).trim();
  }

  ChatStreamEvent _extractStreamEvent(String chunk) {
    final decoded = jsonDecode(chunk);
    if (decoded is! Map<String, Object?>) {
      return const ChatStreamEvent();
    }

    final delta = _firstDelta(decoded);
    if (delta == null) {
      return const ChatStreamEvent();
    }

    final content = delta['content'];
    final toolCallDeltas = _extractToolCallDeltas(delta['tool_calls']);
    return ChatStreamEvent(
      contentDelta: content is String ? content : '',
      toolCallDeltas: toolCallDeltas,
    );
  }

  Map<String, Object?>? _firstDelta(Map<String, Object?> decoded) {
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      return null;
    }

    final first = choices.first;
    if (first is! Map<String, Object?>) {
      return null;
    }

    final delta = first['delta'];
    return delta is Map<String, Object?> ? delta : null;
  }

  List<ToolCallDelta> _extractToolCallDeltas(Object? rawToolCalls) {
    if (rawToolCalls is! List<Object?>) {
      return const [];
    }

    final deltas = <ToolCallDelta>[];
    for (final rawToolCall in rawToolCalls) {
      if (rawToolCall is! Map<String, Object?>) {
        continue;
      }

      final rawIndex = rawToolCall['index'];
      final function = rawToolCall['function'];
      final id = rawToolCall['id'];
      String? name;
      String? argumentsDelta;
      if (function is Map<String, Object?>) {
        final rawName = function['name'];
        final rawArguments = function['arguments'];
        name = rawName is String ? rawName : null;
        argumentsDelta = rawArguments is String ? rawArguments : null;
      }

      deltas.add(
        ToolCallDelta(
          index: rawIndex is int ? rawIndex : deltas.length,
          id: id is String ? id : null,
          name: name,
          argumentsDelta: argumentsDelta,
        ),
      );
    }
    return deltas;
  }

  Future<http.Response> _postChatCompletion({
    required ModelProviderConfig provider,
    required String apiKey,
    required Map<String, Object?> body,
  }) {
    return _httpClient
        .post(
          provider.chatCompletionsEndpoint,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            ...provider.defaultHeaders,
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
  }

  Map<String, Object?> _openAiChatRequestBody({
    required ModelProviderConfig provider,
    required List<Map<String, Object?>> messages,
    required bool stream,
    List<Map<String, Object?>> tools = const [],
    Map<String, Object?> overrides = const {},
  }) {
    return {
      'model': provider.model,
      'messages': messages,
      ..._resolvedOpenAiParameters(
        provider,
        stream: stream,
        hasTools: tools.isNotEmpty,
      ),
      'stream': stream,
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
      ...overrides,
    };
  }

  Map<String, Object?> _resolvedOpenAiParameters(
    ModelProviderConfig provider, {
    required bool stream,
    required bool hasTools,
  }) {
    final parameters = Map<String, Object?>.of(provider.defaultParameters);
    if (provider.id == ModelProviders.aliyunBailianQwenFlash.id &&
        _requiresQwenThinking(provider.model)) {
      parameters['enable_thinking'] = true;
    }
    if (stream && hasTools && _supportsBailianToolStream(provider)) {
      parameters['tool_stream'] = true;
    }
    return parameters;
  }

  bool _supportsBailianToolStream(ModelProviderConfig provider) {
    if (provider.id != ModelProviders.aliyunBailianQwenFlash.id) {
      return false;
    }
    final normalized = provider.model.toLowerCase();
    return normalized.contains('qwen') || normalized.contains('glm');
  }

  bool _requiresQwenThinking(String modelName) {
    final normalized = modelName.toLowerCase();
    return normalized.contains('qwen3.7-max') ||
        normalized.contains('qwen3-max-preview') ||
        normalized.contains('qwen-max-preview');
  }

  ModelRequestException _modelRequestExceptionFor(
    Object error,
    StackTrace stackTrace, {
    required ModelProviderConfig provider,
    required String stage,
  }) {
    if (error is ModelRequestException) {
      return error;
    }

    final rawMessage = error.toString();
    final isTimeout = error is TimeoutException;
    final isTransient = isTimeout || _isTransientConnectionError(error);
    final message = isTimeout
        ? '模型流式响应超时，当前连接长时间没有返回新数据。请检查网络后重试，或点停止后重新发起。'
        : isTransient
        ? '模型流式连接中断，可能是应用切到后台、网络切换或系统关闭了连接。请回到前台并保持网络稳定后重试。'
        : '模型请求失败：$rawMessage';

    AppLogger.error('model.stream_chat.$stage.exception', error, stackTrace, {
      'provider': provider.id,
      'model': provider.model,
      'retryable': isTransient,
    });
    return ModelRequestException(message, isRetryable: isTransient);
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds >= 1) {
      return '${duration.inSeconds} 秒';
    }
    return '${duration.inMilliseconds} 毫秒';
  }

  bool _isTransientConnectionError(Object error) {
    if (error is SocketException) {
      return true;
    }
    if (error is http.ClientException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('connection aborted') ||
        message.contains('broken pipe') ||
        message.contains('receive data') ||
        message.contains('receiving data') ||
        message.contains('network is unreachable');
  }

  static Object? _diagnosticValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value.map(
        (key, child) => MapEntry(key.toString(), _diagnosticValue(child)),
      );
    }
    if (value is Iterable<Object?>) {
      return value.map(_diagnosticValue).toList(growable: false);
    }
    if (value is String) {
      return _diagnosticString(value);
    }
    return value;
  }

  static String _diagnosticString(String value) {
    final redactedImages = value.replaceAllMapped(
      RegExp(r'data:image/[^;\s]+;base64,[A-Za-z0-9+/=]+'),
      (match) {
        final token = match.group(0)!;
        final prefixEnd = token.indexOf(';base64,') + ';base64,'.length;
        return '${token.substring(0, prefixEnd)}<redacted ${token.length} chars>';
      },
    );
    const maxChars = 24000;
    if (redactedImages.length <= maxChars) {
      return redactedImages;
    }
    return '${redactedImages.substring(0, maxChars)}...<truncated ${redactedImages.length - maxChars} chars>';
  }

  List<String> _toolNamesForLog(List<Map<String, Object?>> tools) {
    final names = <String>[];
    for (final tool in tools) {
      final function = tool['function'];
      if (function is! Map<String, Object?>) {
        continue;
      }
      final name = function['name'];
      if (name is String) {
        names.add(name);
      }
    }
    return names;
  }

  String _extractAssistantTextFromBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      return '';
    }
    return _extractAssistantText(decoded);
  }

  String _extractAssistantText(Map<String, Object?> decoded) {
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      return '';
    }

    final first = choices.first;
    if (first is! Map<String, Object?>) {
      return '';
    }

    final message = first['message'];
    if (message is! Map<String, Object?>) {
      return '';
    }

    final content = message['content'];
    return content is String ? content : '';
  }
}
