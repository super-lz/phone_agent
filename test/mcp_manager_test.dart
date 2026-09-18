import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/mcp_manager.dart';

void main() {
  test('MCP tool schema is namespaced by server identity', () {
    const first = McpToolDefinition(
      serverId: 'weather_a',
      name: 'forecast',
      description: 'Forecast from A',
      inputSchema: {'type': 'object'},
    );
    const second = McpToolDefinition(
      serverId: 'weather_b',
      name: 'forecast',
      description: 'Forecast from B',
      inputSchema: {'type': 'object'},
    );

    expect(first.qualifiedName, 'mcp_weather_a__forecast');
    expect(second.qualifiedName, 'mcp_weather_b__forecast');
    expect(first.toToolMap()['function'], isA<Map<String, Object?>>());
  });

  test('MCP schema normalizes invalid remote tool characters', () {
    const tool = McpToolDefinition(
      serverId: 'catalog',
      name: 'read/file.v2',
      description: 'Read a file.',
      inputSchema: {'type': 'object'},
    );

    expect(tool.qualifiedName, 'mcp_catalog__read_file_v2');
  });
}
