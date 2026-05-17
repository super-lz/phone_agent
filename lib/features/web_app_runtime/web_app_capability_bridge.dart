import '../../application/capabilities/capability_runtime.dart';
import '../../data/models/model_api_key_store.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/models/model_provider_config.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/workspace/workspace.dart';

class WebAppRuntimeDefaults {
  const WebAppRuntimeDefaults._();

  static const permissions = [
    'db.note.create',
    'db.note.query',
    'file.read_app_file',
    'file.write_app_file',
    'device.info',
  ];

  static const html = '''
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; color: #17211b; }
  button { padding: 12px 14px; border: 0; border-radius: 8px; background: #1c7c54; color: white; font-size: 15px; }
  pre { white-space: pre-wrap; background: #eef4ef; border-radius: 8px; padding: 12px; }
</style>
<main>
  <h1>Phone Agent Web App</h1>
  <p>这个本地 Web App 可以通过 JSBridge 调用允许的手机能力。</p>
  <button onclick="saveNote()">保存一条 Note</button>
  <button onclick="deviceInfo()">读取设备信息</button>
  <pre id="out">等待操作...</pre>
  <script>
    async function saveNote() {
      const result = await window.PhoneAgent.callCapability('db.note.create', {
        title: 'Web App Note',
        content: '来自本地 Web App 的记录'
      });
      document.getElementById('out').textContent = JSON.stringify(result, null, 2);
    }
    async function deviceInfo() {
      const result = await window.PhoneAgent.callCapability('device.info', {});
      document.getElementById('out').textContent = JSON.stringify(result, null, 2);
    }
  </script>
</main>
''';
}

class WebAppDataNamespace {
  const WebAppDataNamespace._();

  static String database({
    required String workspaceId,
    required AgentArtifact webApp,
  }) {
    final declared = webApp.metadata['databaseNamespace'];
    if (declared is String && declared.trim().isNotEmpty) {
      return declared.trim();
    }
    return databaseForId(workspaceId: workspaceId, webAppId: webApp.id);
  }

  static String files({
    required String workspaceId,
    required AgentArtifact webApp,
  }) {
    final declared = webApp.metadata['fileNamespace'];
    if (declared is String && declared.trim().isNotEmpty) {
      return declared.trim();
    }
    return filesForId(workspaceId: workspaceId, webAppId: webApp.id);
  }

  static String databaseForId({
    required String workspaceId,
    required String webAppId,
  }) {
    return '$workspaceId::webapp::${_safeSegment(webAppId)}::db';
  }

  static String filesForId({
    required String workspaceId,
    required String webAppId,
  }) {
    return '$workspaceId::webapp::${_safeSegment(webAppId)}::files';
  }

  static String forCapability({
    required String capabilityId,
    required String workspaceId,
    required AgentArtifact webApp,
  }) {
    if (capabilityId == 'db.note.create' || capabilityId == 'db.note.query') {
      return database(workspaceId: workspaceId, webApp: webApp);
    }
    if (capabilityId == 'file.read_app_file' ||
        capabilityId == 'file.write_app_file') {
      return files(workspaceId: workspaceId, webApp: webApp);
    }
    return workspaceId;
  }

  static String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}

class WebAppCapabilityBridge {
  WebAppCapabilityBridge({
    required CapabilityRuntime capabilityRuntime,
    required ModelApiKeyStore apiKeyStore,
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
  }) : _capabilityRuntime = capabilityRuntime,
       _apiKeyStore = apiKeyStore,
       _noteStore = noteStore,
       _fileStore = fileStore;

  final CapabilityRuntime _capabilityRuntime;
  final ModelApiKeyStore _apiKeyStore;
  final AgentNoteStore _noteStore;
  final AppFileStore _fileStore;

  Future<Map<String, Object?>> callCapability({
    required AgentArtifact webApp,
    required String capabilityId,
    required Map<String, Object?> input,
    required String currentWorkspaceId,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    required List<AgentWorkspace> workspaces,
  }) async {
    if (webApp.type != ArtifactType.webApp) {
      return const {'ok': false, 'error': 'artifact is not a web app'};
    }
    if (webApp.workspaceId != currentWorkspaceId) {
      return const {
        'ok': false,
        'error': 'web app is not in current workspace',
      };
    }
    if (!_allowsCapability(webApp, capabilityId)) {
      return {
        'ok': false,
        'error': 'permission denied',
        'capabilityId': capabilityId,
      };
    }

    final toolName = _toolNameForCapability(capabilityId);
    if (toolName == null) {
      return {
        'ok': false,
        'error': 'unsupported capability',
        'capabilityId': capabilityId,
      };
    }

    final executionWorkspaceId = WebAppDataNamespace.forCapability(
      capabilityId: capabilityId,
      workspaceId: currentWorkspaceId,
      webApp: webApp,
    );
    final result = await _capabilityRuntime.execute(
      toolCall: ToolCallRequest(
        id: 'webapp-${DateTime.now().microsecondsSinceEpoch}',
        name: toolName,
        arguments: input,
      ),
      workspaceId: executionWorkspaceId,
      memories: memories,
      notes: notes,
      artifacts: artifacts,
      workspaces: workspaces,
      noteStore: _noteStore,
      fileStore: _fileStore,
      apiKey: await _apiKeyStore.readApiKey(
        ModelProviders.aliyunBailianGlm5.id,
      ),
    );
    return {
      'ok': result.output['ok'] == true,
      'capabilityId': result.capabilityId,
      'output': result.output,
    };
  }

  bool _allowsCapability(AgentArtifact webApp, String capabilityId) {
    final permissions = webApp.metadata['permissions'];
    if (permissions is! List<Object?>) {
      return false;
    }
    return permissions.whereType<String>().contains(capabilityId);
  }

  String? _toolNameForCapability(String capabilityId) {
    switch (capabilityId) {
      case 'db.note.create':
        return 'db_note_create';
      case 'db.note.query':
        return 'db_note_query';
      case 'file.read_app_file':
        return 'file_read_app_file';
      case 'file.write_app_file':
        return 'file_write_app_file';
      case 'artifact.create':
        return 'artifact_create';
      case 'artifact.query':
        return 'artifact_query';
      case 'device.info':
        return 'device_info';
      case 'clipboard.write':
        return 'clipboard_write';
      case 'location.get_current':
        return 'location_get_current';
      case 'notification.schedule':
        return 'notification_schedule';
      default:
        return null;
    }
  }
}
