import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/logging/app_logger.dart';

class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toToolMap() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': inputSchema,
      },
    };
  }
}

class McpSession {
  McpSession({
    required this.url,
    required this.transport,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String url;
  final String transport;
  final http.Client _httpClient;

  String? _sessionId;
  List<McpToolDefinition> _tools = [];

  List<McpToolDefinition> get tools => List.unmodifiable(_tools);
  bool get isInitialized => _sessionId != null;

  Future<void> initialize() async {
    AppLogger.info('mcp.session.initialize.start', {'url': url});
    
    final response = await _post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'PhoneAgent', 'version': '0.1.0'},
      },
    });

    if (response.statusCode != 200) {
      throw Exception('MCP initialize failed: ${response.statusCode} ${response.body}');
    }

    _sessionId = response.headers['mcp-session-id'] ?? 
                 response.headers['Mcp-Session-Id'] ?? 
                 '';

    await _post({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }, sessionId: _sessionId);

    await refreshTools();
    
    AppLogger.info('mcp.session.initialize.completed', {
      'url': url,
      'toolsCount': _tools.length,
    });
  }

  Future<void> refreshTools() async {
    final response = await _post({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    }, sessionId: _sessionId);

    if (response.statusCode != 200) {
      throw Exception('MCP list tools failed: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, Object?>) {
      throw Exception('MCP list tools returned invalid payload');
    }
    final result = payload['result'];
    if (result is! Map<String, Object?>) {
      throw Exception('MCP list tools returned invalid result');
    }

    final rawTools = result['tools'];
    if (rawTools is! List<Object?>) {
      _tools = [];
      return;
    }

    _tools = rawTools.whereType<Map<String, Object?>>().map((t) {
      return McpToolDefinition(
        name: t['name'] as String? ?? 'unnamed',
        description: t['description'] as String? ?? '',
        inputSchema: t['inputSchema'] as Map<String, Object?>? ?? {'type': 'object'},
      );
    }).toList();
  }

  Future<Map<String, Object?>> callTool(String name, Map<String, Object?> arguments) async {
    final response = await _post({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': name,
        'arguments': arguments,
      },
    }, sessionId: _sessionId);

    if (response.statusCode != 200) {
      return {'ok': false, 'error': 'HTTP ${response.statusCode}', 'body': response.body};
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, Object?>) {
      return {'ok': false, 'error': 'Invalid JSON response'};
    }
    final result = payload['result'];
    if (result is! Map<String, Object?>) {
      return {'ok': false, 'error': payload['error']?.toString() ?? 'missing_result'};
    }

    return {'ok': true, 'result': result};
  }

  Future<http.Response> _post(Map<String, Object?> body, {String? sessionId}) {
    return _httpClient.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (sessionId != null && sessionId.isNotEmpty) 'Mcp-Session-Id': sessionId,
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
  }
}

class McpManager {
  final Map<String, McpSession> _sessions = {};

  Future<McpSession> connect(String url, String transport) async {
    if (_sessions.containsKey(url)) {
      return _sessions[url]!;
    }

    final session = McpSession(url: url, transport: transport);
    await session.initialize();
    _sessions[url] = session;
    return session;
  }

  List<McpToolDefinition> get allTools {
    return _sessions.values.expand((s) => s.tools).toList();
  }

  Future<Map<String, Object?>> callTool(String name, Map<String, Object?> arguments) async {
    for (final session in _sessions.values) {
      if (session.tools.any((t) => t.name == name)) {
        return await session.callTool(name, arguments);
      }
    }
    return {'ok': false, 'error': 'Tool $name not found in any active MCP session'};
  }
}
