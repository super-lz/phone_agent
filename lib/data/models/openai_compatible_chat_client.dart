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
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration requestTimeout;

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
    AppLogger.info('model.stream_chat.start', {
      'provider': provider.id,
      'model': provider.model,
      'messageCount': messages.length,
      'toolCount': tools.length,
    });
    final request = http.Request('POST', provider.chatCompletionsEndpoint)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'model': provider.model,
        'messages': messages,
        ...provider.defaultParameters,
        'stream': true,
        if (tools.isNotEmpty) 'tools': tools,
        if (tools.isNotEmpty) 'tool_choice': 'auto',
      });

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

    try {
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final chunk = _parseSseDataLine(line);
        if (chunk == null) {
          continue;
        }
        if (chunk == '[DONE]') {
          return;
        }

        final event = _extractStreamEvent(chunk);
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

  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
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
        ? '模型请求超时，请检查网络后重试。'
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
