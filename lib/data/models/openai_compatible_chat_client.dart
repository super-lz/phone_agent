import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../../domain/models/model_provider_config.dart';
import 'gemma_local_runtime.dart';

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
    GemmaLocalRuntime? gemmaLocalRuntime,
    this.requestTimeout = const Duration(seconds: 30),
    this.streamIdleTimeout = const Duration(seconds: 45),
  }) : _httpClient = httpClient ?? http.Client(),
       _gemmaLocalRuntime = gemmaLocalRuntime ?? const GemmaLocalRuntime();

  static Object? diagnosticPayloadForLog(Object? value) {
    return _diagnosticValue(value);
  }

  final http.Client _httpClient;
  final GemmaLocalRuntime _gemmaLocalRuntime;
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
    if (provider.id == 'gemma_local') {
      yield* _streamChatLocal(provider: provider, messages: messages);
      return;
    }
    final requestBody = {
      'model': provider.model,
      'messages': messages,
      ...provider.defaultParameters,
      'stream': true,
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
    };
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

  Stream<ChatStreamEvent> _streamChatLocal({
    required ModelProviderConfig provider,
    required List<Map<String, Object?>> messages,
  }) async* {
    AppLogger.info('model.stream_chat.local.start', {
      'provider': provider.id,
      'model': provider.model,
      'messageCount': messages.length,
    });

    final inferenceModel = await _gemmaLocalRuntime.getInferenceModel(
      provider: provider,
    );

    final chat = await inferenceModel.createChat();
    for (final msg in messages) {
      final content = msg['content'] as String? ?? '';
      final role = msg['role'] as String? ?? '';
      final isUser = role == 'user' || role == 'system';
      await chat.addQueryChunk(Message.text(text: content, isUser: isUser));
    }

    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        yield ChatStreamEvent(contentDelta: response.token);
      } else if (response is ThinkingResponse) {
        yield ChatStreamEvent(contentDelta: response.content);
      }
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

  Future<ChatCompletionResult> _completeTextLocal({
    required ModelProviderConfig provider,
    required List<Map<String, Object?>> messages,
  }) async {
    try {
      final inferenceModel = await _gemmaLocalRuntime.getInferenceModel(
        provider: provider,
      );

      final chat = await inferenceModel.createChat();
      for (final msg in messages) {
        final content = msg['content'] as String? ?? '';
        final role = msg['role'] as String? ?? '';
        final isUser = role == 'user' || role == 'system';
        await chat.addQueryChunk(Message.text(text: content, isUser: isUser));
      }

      final response = await chat.generateChatResponse();
      String textResult = '';
      if (response is TextResponse) {
        textResult = response.token;
      }
      return ChatCompletionResult(
        ok: textResult.isNotEmpty,
        content: textResult.isEmpty ? '本地模型响应文本为空。' : textResult,
      );
    } catch (e) {
      return ChatCompletionResult(ok: false, content: '本地模型执行出错: $e');
    }
  }

  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    if (provider.id == 'gemma_local') {
      return _completeTextLocal(provider: provider, messages: messages);
    }
    try {
      final response = await _postChatCompletion(
        provider: provider,
        apiKey: apiKey,
        body: {
          'model': provider.model,
          'messages': messages,
          ...provider.defaultParameters,
          'stream': false,
        },
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
    if (provider.id == 'gemma_local') {
      try {
        await _gemmaLocalRuntime.ensureActiveModel(provider);
        return const ModelConnectionResult(ok: true, message: '本地模型已激活就绪。');
      } catch (e) {
        return ModelConnectionResult(ok: false, message: '检查或激活本地模型失败: $e');
      }
    }
    AppLogger.info('model.test_connection.start', {
      'provider': provider.id,
      'model': provider.model,
    });
    try {
      final response = await _postChatCompletion(
        provider: provider,
        apiKey: apiKey,
        body: {
          'model': provider.model,
          'messages': [
            {'role': 'user', 'content': '请用一句话回答：Phone Agent 模型连接正常吗？'},
          ],
          ...provider.defaultParameters,
          'stream': false,
          'max_tokens': 128,
        },
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
        message: text.isEmpty ? '连接成功，但响应中没有文本内容。' : text,
      );
    } on Object catch (error) {
      AppLogger.error('model.test_connection.exception', error);
      return ModelConnectionResult(ok: false, message: error.toString());
    }
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
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
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
