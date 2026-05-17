import '../../core/logging/app_logger.dart';
import '../../data/capabilities/web_capability_adapter.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import 'artifact_capability_handler.dart';
import 'capability_execution_result.dart';
import 'capability_tool_definitions.dart';
import 'file_capability_handler.dart';
import 'memory_capability_handler.dart';
import 'note_capability_handler.dart';
import 'web_capability_handler.dart';

class CapabilityRuntime {
  CapabilityRuntime({WebCapabilityAdapter? webAdapter})
    : _webHandler = WebCapabilityHandler(webAdapter: webAdapter);

  final MemoryCapabilityHandler _memoryHandler =
      const MemoryCapabilityHandler();
  final NoteCapabilityHandler _noteHandler = const NoteCapabilityHandler();
  final FileCapabilityHandler _fileHandler = const FileCapabilityHandler();
  final ArtifactCapabilityHandler _artifactHandler =
      const ArtifactCapabilityHandler();
  final WebCapabilityHandler _webHandler;
  final CapabilityToolDefinitions _toolDefinitions =
      const CapabilityToolDefinitions();

  Future<CapabilityExecutionResult> execute({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
    String? apiKey,
  }) async {
    AppLogger.info('capability.execute.start', {
      'tool': toolCall.name,
      'workspaceId': workspaceId,
    });
    switch (toolCall.name) {
      case 'memory_create':
        return _memoryHandler.create(
          arguments: toolCall.arguments,
          memories: memories,
        );
      case 'memory_query':
        return _memoryHandler.query(
          arguments: toolCall.arguments,
          memories: memories,
        );
      case 'memory_delete':
        return _memoryHandler.delete(
          arguments: toolCall.arguments,
          memories: memories,
        );
      case 'db_note_create':
        return await _noteHandler.create(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          notes: notes,
          noteStore: noteStore,
        );
      case 'db_note_query':
        return await _noteHandler.query(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          notes: notes,
          noteStore: noteStore,
        );
      case 'file_write_app_file':
        return await _fileHandler.write(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'file_read_app_file':
        return await _fileHandler.read(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'artifact_create':
        return _artifactHandler.create(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          artifacts: artifacts,
        );
      case 'artifact_query':
        return _artifactHandler.query(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          artifacts: artifacts,
        );
      case 'web_search':
        return await _webHandler.search(
          arguments: toolCall.arguments,
          apiKey: apiKey,
        );
      case 'web_fetch':
        return await _webHandler.fetch(
          arguments: toolCall.arguments,
          apiKey: apiKey,
        );
      default:
        return CapabilityExecutionResult(
          capabilityId: toolCall.name,
          output: {'ok': false, 'error': 'Unsupported tool: ${toolCall.name}'},
        );
    }
  }

  List<Map<String, Object?>> get toolDefinitions {
    return _toolDefinitions.all;
  }
}
