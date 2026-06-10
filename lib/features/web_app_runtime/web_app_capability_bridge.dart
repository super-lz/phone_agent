import 'dart:async';
import 'dart:convert';

import '../../application/capabilities/capability_runtime.dart';
import '../../data/models/model_api_key_store.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/models/model_provider_config.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/permissions/permission_policy.dart';
import '../../domain/workbench/workbench_store.dart';
import '../../domain/workspace/workspace.dart';

class WebAppRuntimeDefaults {
  const WebAppRuntimeDefaults._();

  static const permissions = [
    'db.note.create',
    'db.note.query',
    'file.read_app_file',
    'file.write_app_file',
    'file.search_app_files',
    'artifact.create',
    'artifact.query',
    'device.info',
    'time.get_current',
    'battery.status',
    'network.status',
    'clipboard.read',
    'clipboard.write',
    'camera.capture_photo',
    'camera.capture_video',
    'flashlight.set',
    'flashlight.status',
    'media.pick_image',
    'media.pick_images',
    'media.pick_video',
    'file.pick_system_file',
    'audio.record_start',
    'audio.record_stop',
    'audio.record_cancel',
    'contacts.pick',
    'barcode.scan_camera',
    'barcode.scan_image',
    'share.text',
    'system.haptic_feedback',
    'system.sound_alert',
    'system.volume.set',
    'system.volume.status',
    'system.ui.set',
    'system.ui.status',
    'permission.open_settings',
    'url.open_external',
    'screen.keep_awake',
    'screen.keep_awake_status',
    'screen.brightness.set',
    'screen.brightness.status',
    'screen.metrics',
    'screen.orientation.set',
    'screen.orientation.status',
    'sensor.accelerometer.read',
    'sensor.gyroscope.read',
    'sensor.magnetometer.read',
    'location.get_current',
    'notification.schedule',
    'notification.pending',
    'notification.cancel',
    'notification.cancel_all',
    'calendar.event.create',
    'web.search',
    'web.fetch',
    'memory.query',
    'workspace.switch',
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
  <p>可用能力：<code id="capabilities"></code></p>
  <p>WebView 视口可通过 <code>window.PhoneAgent.getRuntimeInfo()</code> 读取；设备信息、时间和定位可通过 <code>window.PhoneAgent.getDeviceInfo()</code> 等 helper 读取。</p>
  <button onclick="saveNote()">保存一条 Note</button>
  <button onclick="deviceInfo()">读取设备信息</button>
  <pre id="out">等待操作...</pre>
  <script>
    document.getElementById('capabilities').textContent =
      window.PhoneAgent.getAvailableCapabilities().join(', ');

    async function saveNote() {
      const result = await window.PhoneAgent.callCapability('db.note.create', {
        title: 'Web App Note',
        content: '来自本地 Web App 的记录'
      });
      document.getElementById('out').textContent = JSON.stringify(result, null, 2);
    }
    async function deviceInfo() {
      const result = await window.PhoneAgent.getDeviceInfo();
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
        capabilityId == 'file.write_app_file' ||
        capabilityId == 'file.search_app_files') {
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
    required WorkbenchStore workbenchStore,
  }) : _capabilityRuntime = capabilityRuntime,
       _apiKeyStore = apiKeyStore,
       _noteStore = noteStore,
       _fileStore = fileStore,
       _workbenchStore = workbenchStore;

  final CapabilityRuntime _capabilityRuntime;
  final ModelApiKeyStore _apiKeyStore;
  final AgentNoteStore _noteStore;
  final AppFileStore _fileStore;
  final WorkbenchStore _workbenchStore;

  Future<Map<String, Object?>> callCapability({
    required AgentArtifact webApp,
    required String capabilityId,
    required Map<String, Object?> input,
    required String currentWorkspaceId,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    required List<AgentWorkspace> workspaces,
    required List<CapabilityDefinition> capabilities,
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
    if (!await _allowsCapability(webApp, capabilityId, currentWorkspaceId)) {
      return {
        'ok': false,
        'error': 'permission_denied',
        'detail': '该 Web App 未在 manifest.json 中声明 "$capabilityId" 权限。',
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
      capabilities: capabilities,
      noteStore: _noteStore,
      fileStore: _fileStore,
      workbenchStore: _workbenchStore,
      apiKey: await _apiKeyStore.readApiKey(
        ModelProviders.aliyunBailianQwenFlash.id,
      ),
      permissionMode: PermissionMode.defaultMode,
    );
    return {
      'ok': result.output['ok'] == true,
      'capabilityId': result.capabilityId,
      'output': result.output,
    };
  }

  Future<bool> _allowsCapability(
    AgentArtifact webApp,
    String capabilityId,
    String workspaceId,
  ) async {
    final permissions = await _getEffectivePermissions(webApp, workspaceId);
    return permissions.contains(capabilityId);
  }

  Future<List<String>> _getEffectivePermissions(
    AgentArtifact webApp,
    String workspaceId,
  ) async {
    // 1. Try metadata first (cached)
    final metaPermissions = webApp.metadata['permissions'];
    if (metaPermissions is List<Object?> && metaPermissions.isNotEmpty) {
      return metaPermissions.whereType<String>().toList();
    }

    // 2. Try manifest.json on disk (source of truth for projects)
    final manifestPath = webApp.metadata['manifestPath'];
    if (manifestPath is String) {
      try {
        final result = await _fileStore.readText(
          workspaceId: workspaceId,
          path: manifestPath,
          maxChars: 1024 * 1024,
        );
        final manifest = jsonDecode(result.content);
        if (manifest is Map<String, Object?>) {
          final permissions = manifest['permissions'];
          if (permissions is List<Object?>) {
            return permissions.whereType<String>().toList();
          }
        }
      } on Object {
        // Fallback to empty if manifest is missing or invalid
      }
    }

    return const [];
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
      case 'file.search_app_files':
        return 'file_search_app_files';
      case 'artifact.create':
        return 'artifact_create';
      case 'artifact.query':
        return 'artifact_query';
      case 'device.info':
        return 'device_info';
      case 'time.get_current':
        return 'time_get_current';
      case 'battery.status':
        return 'battery_status';
      case 'network.status':
        return 'network_status';
      case 'clipboard.read':
        return 'clipboard_read';
      case 'clipboard.write':
        return 'clipboard_write';
      case 'camera.capture_photo':
        return 'camera_capture_photo';
      case 'camera.capture_video':
        return 'camera_capture_video';
      case 'flashlight.set':
        return 'flashlight_set';
      case 'flashlight.status':
        return 'flashlight_status';
      case 'media.pick_image':
        return 'media_pick_image';
      case 'media.pick_images':
        return 'media_pick_images';
      case 'media.pick_video':
        return 'media_pick_video';
      case 'file.pick_system_file':
        return 'file_pick_system_file';
      case 'audio.record_start':
        return 'audio_record_start';
      case 'audio.record_stop':
        return 'audio_record_stop';
      case 'audio.record_cancel':
        return 'audio_record_cancel';
      case 'share.text':
        return 'share_text';
      case 'system.haptic_feedback':
        return 'system_haptic_feedback';
      case 'system.sound_alert':
        return 'system_sound_alert';
      case 'system.volume.set':
        return 'system_volume_set';
      case 'system.volume.status':
        return 'system_volume_status';
      case 'system.ui.set':
        return 'system_ui_set';
      case 'system.ui.status':
        return 'system_ui_status';
      case 'permission.open_settings':
        return 'permission_open_settings';
      case 'url.open_external':
        return 'url_open_external';
      case 'screen.keep_awake':
        return 'screen_keep_awake';
      case 'screen.keep_awake_status':
        return 'screen_keep_awake_status';
      case 'screen.brightness.set':
        return 'screen_brightness_set';
      case 'screen.brightness.status':
        return 'screen_brightness_status';
      case 'screen.metrics':
        return 'screen_metrics';
      case 'screen.orientation.set':
        return 'screen_orientation_set';
      case 'screen.orientation.status':
        return 'screen_orientation_status';
      case 'sensor.accelerometer.read':
        return 'sensor_accelerometer_read';
      case 'sensor.gyroscope.read':
        return 'sensor_gyroscope_read';
      case 'sensor.magnetometer.read':
        return 'sensor_magnetometer_read';
      case 'location.get_current':
        return 'location_get_current';
      case 'notification.schedule':
        return 'notification_schedule';
      case 'notification.pending':
        return 'notification_pending';
      case 'notification.cancel':
        return 'notification_cancel';
      case 'notification.cancel_all':
        return 'notification_cancel_all';
      case 'contacts.pick':
        return 'contacts_pick';
      case 'barcode.scan_camera':
        return 'barcode_scan_camera';
      case 'barcode.scan_image':
        return 'barcode_scan_image';
      case 'calendar.event.create':
        return 'calendar_event_create';
      case 'web.search':
        return 'web_search';
      case 'web.fetch':
        return 'web_fetch';
      case 'memory.query':
        return 'memory_query';
      case 'workspace.switch':
        return 'workspace_switch';
      default:
        return null;
    }
  }
}
