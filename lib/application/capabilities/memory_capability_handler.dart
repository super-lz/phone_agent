import '../../domain/memory/memory.dart';
import 'capability_execution_result.dart';

class MemoryCapabilityHandler {
  const MemoryCapabilityHandler();

  CapabilityExecutionResult create({
    required Map<String, Object?> arguments,
    required List<AgentMemory> memories,
  }) {
    final rawContent = arguments['content'];
    if (rawContent is! String || rawContent.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'memory.create',
        output: {'ok': false, 'error': 'content is required'},
      );
    }

    final memory = AgentMemory(
      id: 'memory-${DateTime.now().microsecondsSinceEpoch}',
      content: rawContent.trim(),
      createdAt: DateTime.now(),
    );
    memories.add(memory);

    return CapabilityExecutionResult(
      capabilityId: 'memory.create',
      output: {'ok': true, 'memoryId': memory.id, 'content': memory.content},
    );
  }

  CapabilityExecutionResult query({
    required Map<String, Object?> arguments,
    required List<AgentMemory> memories,
  }) {
    final query = arguments['query'];
    final keyword = query is String ? query.trim() : '';
    final matched = memories
        .where((memory) {
          if (keyword.isEmpty) {
            return true;
          }
          return memory.content.contains(keyword);
        })
        .map((memory) {
          return {'id': memory.id, 'content': memory.content};
        })
        .toList(growable: false);

    return CapabilityExecutionResult(
      capabilityId: 'memory.query',
      output: {'ok': true, 'items': matched},
    );
  }

  CapabilityExecutionResult delete({
    required Map<String, Object?> arguments,
    required List<AgentMemory> memories,
  }) {
    final rawMemoryId = arguments['memory_id'] ?? arguments['memoryId'];
    if (rawMemoryId is! String || rawMemoryId.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'memory.delete',
        output: {'ok': false, 'error': 'memory_id is required'},
      );
    }

    final memoryId = rawMemoryId.trim();
    final index = memories.indexWhere((memory) => memory.id == memoryId);
    if (index < 0) {
      return CapabilityExecutionResult(
        capabilityId: 'memory.delete',
        output: {
          'ok': false,
          'error': 'memory not found',
          'memoryId': memoryId,
        },
      );
    }

    memories.removeAt(index);
    return CapabilityExecutionResult(
      capabilityId: 'memory.delete',
      output: {'ok': true, 'memoryId': memoryId},
    );
  }
}
