import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../data/capabilities/native_capability_adapter.dart';
import '../../data/capabilities/web_capability_adapter.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/permissions/permission_policy.dart';
import '../../domain/workbench/workbench_store.dart';
import '../../domain/workspace/workspace.dart';
import 'artifact_capability_handler.dart';
import 'capability_execution_result.dart';
import 'capability_tool_definitions.dart';
import 'file_capability_handler.dart';
import 'mcp_manager.dart';
import 'memory_capability_handler.dart';
import 'native_capability_handler.dart';
import 'note_capability_handler.dart';
import 'office_capability_handler.dart';
import 'project_capability_handler.dart';
import 'skill_sandbox.dart';
import 'web_capability_handler.dart';
import 'workspace_capability_handler.dart';

class CapabilityRuntime {
  static const Map<String, String> _capabilityIdsByToolName = {
    'memory_create': 'memory.create',
    'memory_query': 'memory.query',
    'memory_delete': 'memory.delete',
    'db_note_create': 'db.note.create',
    'db_note_query': 'db.note.query',
    'file_write_app_file': 'file.write_app_file',
    'file_read_app_file': 'file.read_app_file',
    'file_search_app_files': 'file.search_app_files',
    'file_apply_text_patch': 'file.apply_text_patch',
    'artifact_create': 'artifact.create',
    'artifact_query': 'artifact.query',
    'artifact_inspect_logs': 'artifact.inspect_logs',
    'project_create_web_app': 'project.create_web_app',
    'project_update_web_app': 'project.update_web_app',
    'project_test_web_app': 'project.test_web_app',
    'project_version_history': 'project.version_history',
    'project_revert_web_app': 'project.revert_web_app',
    'workspace_create': 'workspace.create',
    'workspace_switch': 'workspace.switch',
    'device_info': 'device.info',
    'time_get_current': 'time.get_current',
    'clipboard_read': 'clipboard.read',
    'battery_status': 'battery.status',
    'network_status': 'network.status',
    'clipboard_write': 'clipboard.write',
    'camera_capture_photo': 'camera.capture_photo',
    'camera_capture_video': 'camera.capture_video',
    'flashlight_set': 'flashlight.set',
    'flashlight_status': 'flashlight.status',
    'media_pick_image': 'media.pick_image',
    'media_pick_images': 'media.pick_images',
    'media_pick_video': 'media.pick_video',
    'file_pick_system_file': 'file.pick_system_file',
    'audio_record_start': 'audio.record_start',
    'audio_record_stop': 'audio.record_stop',
    'audio_record_cancel': 'audio.record_cancel',
    'contacts_pick': 'contacts.pick',
    'barcode_scan_camera': 'barcode.scan_camera',
    'barcode_scan_image': 'barcode.scan_image',
    'share_text': 'share.text',
    'system_haptic_feedback': 'system.haptic_feedback',
    'system_sound_alert': 'system.sound_alert',
    'system_ui_set': 'system.ui.set',
    'system_ui_status': 'system.ui.status',
    'permission_open_settings': 'permission.open_settings',
    'url_open_external': 'url.open_external',
    'screen_keep_awake': 'screen.keep_awake',
    'screen_keep_awake_status': 'screen.keep_awake_status',
    'screen_brightness_set': 'screen.brightness.set',
    'screen_brightness_status': 'screen.brightness.status',
    'screen_orientation_set': 'screen.orientation.set',
    'screen_orientation_status': 'screen.orientation.status',
    'sensor_accelerometer_read': 'sensor.accelerometer.read',
    'sensor_gyroscope_read': 'sensor.gyroscope.read',
    'sensor_magnetometer_read': 'sensor.magnetometer.read',
    'location_get_current': 'location.get_current',
    'notification_schedule': 'notification.schedule',
    'notification_pending': 'notification.pending',
    'notification_cancel': 'notification.cancel',
    'notification_cancel_all': 'notification.cancel_all',
    'calendar_event_create': 'calendar.event.create',
    'document_extract': 'document.extract',
    'document_generate': 'document.generate',
    'document_apply_text_patch': 'document.apply_text_patch',
    'spreadsheet_extract': 'spreadsheet.extract',
    'spreadsheet_generate': 'spreadsheet.generate',
    'presentation_extract': 'presentation.extract',
    'presentation_generate': 'presentation.generate',
    'pdf_extract': 'pdf.extract',
    'pdf_generate': 'pdf.generate',
    'web_search': 'web.search',
    'web_fetch': 'web.fetch',
    'skill_install': 'skill.install',
    'skill_invoke': 'skill.invoke',
    'mcp_connect': 'mcp.connect',
  };

  static final Map<String, String> _toolNamesByCapabilityId = {
    for (final entry in _capabilityIdsByToolName.entries)
      entry.value: entry.key,
  };

  CapabilityRuntime({
    WebCapabilityAdapter? webAdapter,
    NativeCapabilityAdapter? nativeAdapter,
  }) : _webHandler = WebCapabilityHandler(webAdapter: webAdapter),
       _nativeHandler = NativeCapabilityHandler(
         adapter: nativeAdapter ?? NativeCapabilityAdapter(),
       ) {
    _initSkillSandbox();
  }

  final MemoryCapabilityHandler _memoryHandler =
      const MemoryCapabilityHandler();
  final NoteCapabilityHandler _noteHandler = const NoteCapabilityHandler();
  final FileCapabilityHandler _fileHandler = const FileCapabilityHandler();
  final ArtifactCapabilityHandler _artifactHandler =
      const ArtifactCapabilityHandler();
  final ProjectCapabilityHandler _projectHandler =
      const ProjectCapabilityHandler();
  final WorkspaceCapabilityHandler _workspaceHandler =
      const WorkspaceCapabilityHandler();
  final WebCapabilityHandler _webHandler;
  final NativeCapabilityHandler _nativeHandler;
  final OfficeCapabilityHandler _officeHandler =
      const OfficeCapabilityHandler();
  final McpManager _mcpManager = McpManager();
  final CapabilityToolDefinitions _toolDefinitions =
      const CapabilityToolDefinitions();

  McpManager get mcpManager => _mcpManager;

  void _initSkillSandbox() {
    SkillSandbox.instance.onCallCapability = (capabilityId, input) async {
      AppLogger.info('capability.skill_bridge.callback', {'id': capabilityId});
      return {'ok': false, 'error': 'Background bridge not fully implemented'};
    };
  }

  Future<CapabilityExecutionResult> execute({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    List<AgentWorkspace>? workspaces,
    List<AgentSkill>? skills,
    List<CapabilityDefinition>? capabilities,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
    WorkbenchStore? workbenchStore,
    String? apiKey,
    PermissionMode permissionMode = PermissionMode.fullAccess,
    bool skipPermissionCheck = false,
  }) async {
    AppLogger.info('capability.execute.start', {
      'tool': toolCall.name,
      'workspaceId': workspaceId,
    });
    final permissionBlocked = skipPermissionCheck
        ? null
        : _permissionBlockedResult(
            toolCall: toolCall,
            capabilities: capabilities,
            permissionMode: permissionMode,
          );
    final result =
        permissionBlocked ??
        await _executeAllowed(
          toolCall: toolCall,
          workspaceId: workspaceId,
          memories: memories,
          notes: notes,
          artifacts: artifacts,
          workspaces: workspaces,
          skills: skills,
          noteStore: noteStore,
          fileStore: fileStore,
          workbenchStore: workbenchStore,
          apiKey: apiKey,
          permissionMode: permissionMode,
        );
    await _persistResultSideEffects(
      result: result,
      memories: memories,
      artifacts: artifacts,
      workspaces: workspaces,
      workbenchStore: workbenchStore,
    );
    await _recordInvocation(
      toolCall: toolCall,
      workspaceId: workspaceId,
      result: result,
      workbenchStore: workbenchStore,
      permissionMode: permissionMode,
      skippedPermissionCheck: skipPermissionCheck,
    );
    return result;
  }

  Future<CapabilityExecutionResult> _executeAllowed({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    List<AgentWorkspace>? workspaces,
    List<AgentSkill>? skills,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
    WorkbenchStore? workbenchStore,
    String? apiKey,
    required PermissionMode permissionMode,
  }) async {
    final toolName = _toolNameForCapabilityId(toolCall.name) ?? toolCall.name;
    switch (toolName) {
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
      case 'file_search_app_files':
        return await _fileHandler.search(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'file_apply_text_patch':
        return await _fileHandler.applyTextPatch(
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
      case 'project_create_web_app':
        return await _projectHandler.createWebApp(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
          artifacts: artifacts,
        );
      case 'project_update_web_app':
        return await _projectHandler.updateWebApp(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
          artifacts: artifacts,
        );
      case 'project_test_web_app':
        return await _projectHandler.testWebApp(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
          artifacts: artifacts,
        );
      case 'project_version_history':
        return await _projectHandler.versionHistory(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
          artifacts: artifacts,
        );
      case 'project_revert_web_app':
        return await _projectHandler.revertWebApp(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
          artifacts: artifacts,
        );
      case 'artifact_query':
        return _artifactHandler.query(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          artifacts: artifacts,
        );
      case 'artifact_inspect_logs':
        return await _artifactHandler.inspectLogs(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          artifacts: artifacts,
          fileStore: fileStore,
        );
      case 'workspace_create':
        return _workspaceHandler.create(
          arguments: toolCall.arguments,
          workspaces: workspaces,
        );
      case 'workspace_switch':
        return _workspaceHandler.switchWorkspace(
          arguments: toolCall.arguments,
          workspaces: workspaces,
        );
      case 'device_info':
        return await _nativeHandler.deviceInfo();
      case 'time_get_current':
        return await _nativeHandler.getCurrentTime();
      case 'clipboard_read':
        return await _nativeHandler.readClipboard();
      case 'battery_status':
        return await _nativeHandler.getBatteryStatus();
      case 'network_status':
        return await _nativeHandler.getNetworkStatus();
      case 'clipboard_write':
        return await _nativeHandler.writeClipboard(
          arguments: toolCall.arguments,
        );
      case 'camera_capture_photo':
        return await _nativeHandler.capturePhoto(arguments: toolCall.arguments);
      case 'camera_capture_video':
        return await _nativeHandler.captureVideo(arguments: toolCall.arguments);
      case 'flashlight_set':
        return await _nativeHandler.setFlashlight(
          arguments: toolCall.arguments,
        );
      case 'flashlight_status':
        return await _nativeHandler.getFlashlightStatus();
      case 'media_pick_image':
        return await _nativeHandler.pickImage(arguments: toolCall.arguments);
      case 'media_pick_images':
        return await _nativeHandler.pickImages(arguments: toolCall.arguments);
      case 'media_pick_video':
        return await _nativeHandler.pickVideo();
      case 'file_pick_system_file':
        return await _nativeHandler.pickSystemFile(
          arguments: toolCall.arguments,
        );
      case 'audio_record_start':
        return await _nativeHandler.startAudioRecording();
      case 'audio_record_stop':
        return await _nativeHandler.stopAudioRecording();
      case 'audio_record_cancel':
        return await _nativeHandler.cancelAudioRecording();
      case 'contacts_pick':
        return await _nativeHandler.pickContact();
      case 'barcode_scan_camera':
        return await _nativeHandler.scanBarcodeFromCamera(
          arguments: toolCall.arguments,
        );
      case 'barcode_scan_image':
        return await _nativeHandler.scanBarcodeFromImage(
          arguments: toolCall.arguments,
        );
      case 'share_text':
        return await _nativeHandler.shareText(arguments: toolCall.arguments);
      case 'system_haptic_feedback':
        return await _nativeHandler.hapticFeedback(
          arguments: toolCall.arguments,
        );
      case 'system_sound_alert':
        return await _nativeHandler.playSystemSound(
          arguments: toolCall.arguments,
        );
      case 'system_ui_set':
        return await _nativeHandler.setSystemUiMode(
          arguments: toolCall.arguments,
        );
      case 'system_ui_status':
        return await _nativeHandler.getSystemUiMode();
      case 'permission_open_settings':
        return await _nativeHandler.openPermissionSettings();
      case 'url_open_external':
        return await _nativeHandler.openExternalUrl(
          arguments: toolCall.arguments,
        );
      case 'screen_keep_awake':
        return await _nativeHandler.setKeepScreenAwake(
          arguments: toolCall.arguments,
        );
      case 'screen_keep_awake_status':
        return await _nativeHandler.getKeepScreenAwake();
      case 'screen_brightness_set':
        return await _nativeHandler.setScreenBrightness(
          arguments: toolCall.arguments,
        );
      case 'screen_brightness_status':
        return await _nativeHandler.getScreenBrightness();
      case 'screen_orientation_set':
        return await _nativeHandler.setScreenOrientation(
          arguments: toolCall.arguments,
        );
      case 'screen_orientation_status':
        return await _nativeHandler.getScreenOrientation();
      case 'sensor_accelerometer_read':
        return await _nativeHandler.readAccelerometer();
      case 'sensor_gyroscope_read':
        return await _nativeHandler.readGyroscope();
      case 'sensor_magnetometer_read':
        return await _nativeHandler.readMagnetometer();
      case 'location_get_current':
        return await _nativeHandler.getCurrentLocation();
      case 'notification_schedule':
        return await _nativeHandler.scheduleNotification(
          arguments: toolCall.arguments,
        );
      case 'notification_pending':
        return await _nativeHandler.listPendingNotifications();
      case 'notification_cancel':
        return await _nativeHandler.cancelNotification(
          arguments: toolCall.arguments,
        );
      case 'notification_cancel_all':
        return await _nativeHandler.cancelAllNotifications();
      case 'calendar_event_create':
        return await _nativeHandler.createCalendarEvent(
          arguments: toolCall.arguments,
        );
      case 'document_extract':
        return await _officeHandler.extract(
          workspaceId: workspaceId,
          capabilityId: 'document.extract',
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'document_generate':
        return await _officeHandler.generateDocument(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'document_apply_text_patch':
        return await _officeHandler.applyTextPatch(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'spreadsheet_extract':
        return await _officeHandler.extract(
          workspaceId: workspaceId,
          capabilityId: 'spreadsheet.extract',
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'spreadsheet_generate':
        return await _officeHandler.generateSpreadsheet(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'presentation_extract':
        return await _officeHandler.extract(
          workspaceId: workspaceId,
          capabilityId: 'presentation.extract',
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'presentation_generate':
        return await _officeHandler.generatePresentation(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'pdf_extract':
        return await _officeHandler.extract(
          workspaceId: workspaceId,
          capabilityId: 'pdf.extract',
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'pdf_generate':
        return await _officeHandler.generatePdf(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
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
      case 'skill_install':
        return await _installSkill(toolCall.arguments);
      case 'skill_invoke':
        return await _invokeSkill(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          memories: memories,
          notes: notes,
          artifacts: artifacts,
          workspaces: workspaces,
          skills: skills,
          noteStore: noteStore,
          fileStore: fileStore,
          workbenchStore: workbenchStore,
          apiKey: apiKey,
          permissionMode: permissionMode,
        );
      case 'mcp_connect':
        return await _connectMcp(toolCall.arguments);
      default:
        // Try MCP tools
        final mcpResult = await _mcpManager.callTool(
          toolCall.name,
          toolCall.arguments,
        );
        if (mcpResult['ok'] == true) {
          return CapabilityExecutionResult(
            capabilityId: toolCall.name,
            output: mcpResult['result'] as Map<String, Object?>,
          );
        }

        return CapabilityExecutionResult(
          capabilityId: toolCall.name,
          output: {'ok': false, 'error': 'Unsupported tool: ${toolCall.name}'},
        );
    }
  }

  Future<CapabilityExecutionResult> _installSkill(
    Map<String, Object?> arguments,
  ) async {
    final source = arguments['source'];
    if (source is! String || source.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {'ok': false, 'error': 'source is required'},
      );
    }
    final normalized = source.trim();
    if (normalized.endsWith('.zip') ||
        normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('git@')) {
      return CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {
          'ok': false,
          'error': 'skill_source_unavailable',
          'detail': '当前移动端安全执行后端尚未接入，暂不安装 zip 或 Git URL Skill。',
          'source': normalized,
        },
      );
    }
    final directory = Directory(normalized);
    if (!directory.existsSync()) {
      return CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {
          'ok': false,
          'error': 'not_found',
          'detail': 'Skill 目录不存在。',
          'source': normalized,
        },
      );
    }
    final manifest = File('${directory.path}/SKILL.md');
    if (!manifest.existsSync()) {
      return CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {
          'ok': false,
          'error': 'invalid_skill',
          'detail': 'Skill 目录缺少 SKILL.md。',
          'source': normalized,
        },
      );
    }
    final name = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;

    String script = '';
    final scriptFile = File('${directory.path}/index.js');
    if (scriptFile.existsSync()) {
      script = scriptFile.readAsStringSync();
    }

    return CapabilityExecutionResult(
      capabilityId: 'skill.install',
      output: {
        'ok': true,
        'skill': {
          'id': name,
          'name': name,
          'source': normalized,
          'manifest': manifest.path,
          'script': script,
          'status': 'installed',
        },
      },
    );
  }

  Future<CapabilityExecutionResult> _invokeSkill({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    List<AgentWorkspace>? workspaces,
    List<AgentSkill>? skills,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
    WorkbenchStore? workbenchStore,
    String? apiKey,
    required PermissionMode permissionMode,
  }) async {
    final skillId = arguments['skill_id'] ?? arguments['skillId'];
    final input = arguments['input'] as Map<String, Object?>? ?? {};

    if (skillId is! String || skillId.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'skill.invoke',
        output: {'ok': false, 'error': 'skill_id is required'},
      );
    }

    var script = arguments['script'] as String?;
    if (script == null || script.trim().isEmpty) {
      final skill = skills?.firstWhere(
        (s) => s.id == skillId,
        orElse: () => throw StateError('Skill not found: $skillId'),
      );
      script = skill?.script;
    }

    if (script == null || script.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'skill.invoke',
        output: {
          'ok': false,
          'error': 'script_required',
          'detail': 'Skill does not have a script and none was provided.',
        },
      );
    }

    // Update the callback with current state before execution
    SkillSandbox.instance.onCallCapability = (cid, input) async {
      final res = await execute(
        toolCall: ToolCallRequest(
          id: 'skill-callback-${DateTime.now().microsecondsSinceEpoch}',
          name: _capabilityIdForToolName(cid),
          arguments: input,
        ),
        workspaceId: workspaceId,
        memories: memories,
        notes: notes,
        artifacts: artifacts,
        workspaces: workspaces,
        skills: skills,
        noteStore: noteStore,
        fileStore: fileStore,
        workbenchStore: workbenchStore,
        apiKey: apiKey,
        permissionMode: permissionMode,
        skipPermissionCheck:
            true, // Callback is pre-approved by the skill execution
      );
      return res.output;
    };

    try {
      final result = await SkillSandbox.instance.execute(
        script,
        context: input,
      );

      return CapabilityExecutionResult(
        capabilityId: 'skill.invoke',
        output: result,
      );
    } catch (e) {
      return CapabilityExecutionResult(
        capabilityId: 'skill.invoke',
        output: {
          'ok': false,
          'error': 'execution_failed',
          'detail': e.toString(),
        },
      );
    }
  }

  Future<CapabilityExecutionResult> _connectMcp(
    Map<String, Object?> arguments,
  ) async {
    final rawUrl = arguments['url'];
    final rawTransport = arguments['transport'];
    final transport = rawTransport is String && rawTransport.trim().isNotEmpty
        ? rawTransport.trim().toLowerCase()
        : 'http';
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {'ok': false, 'error': 'url is required'},
      );
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {
          'ok': false,
          'error': 'invalid_url',
          'detail': '第一版 MCP 仅支持 HTTP/SSE URL。',
          'url': rawUrl.trim(),
        },
      );
    }
    if (transport != 'http' && transport != 'sse') {
      return CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {
          'ok': false,
          'error': 'unsupported_transport',
          'detail': '第一版仅支持 http 或 sse；stdio 暂不执行本机进程。',
          'transport': transport,
        },
      );
    }

    try {
      final session = await _mcpManager.connect(uri.toString(), transport);
      return CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {
          'ok': true,
          'connection': {
            'url': uri.toString(),
            'transport': transport,
            'status': 'connected',
            'toolsCount': session.tools.length,
          },
        },
      );
    } catch (e) {
      return CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {
          'ok': false,
          'error': 'connection_failed',
          'detail': e.toString(),
        },
      );
    }
  }

  Future<void> _persistResultSideEffects({
    required CapabilityExecutionResult result,
    required List<AgentMemory> memories,
    required List<AgentArtifact> artifacts,
    required List<AgentWorkspace>? workspaces,
    required WorkbenchStore? workbenchStore,
  }) async {
    if (workbenchStore == null || result.output['ok'] != true) {
      return;
    }
    switch (result.capabilityId) {
      case 'memory.create':
        final memoryId = result.output['memoryId'];
        if (memoryId is String) {
          final index = memories.indexWhere((memory) => memory.id == memoryId);
          if (index >= 0) {
            await workbenchStore.upsertMemory(memories[index]);
          }
        }
        return;
      case 'memory.delete':
        final memoryId = result.output['memoryId'];
        if (memoryId is String) {
          await workbenchStore.deleteMemory(memoryId);
        }
        return;
      case 'artifact.create':
      case 'project.create_web_app':
      case 'project.update_web_app':
      case 'project.revert_web_app':
        final artifactId = result.output['artifactId'];
        if (artifactId is String) {
          final index = artifacts.indexWhere(
            (artifact) => artifact.id == artifactId,
          );
          if (index >= 0) {
            await workbenchStore.upsertArtifact(artifacts[index]);
          }
        }
        return;
      case 'workspace.create':
        final workspaceId = result.output['activeWorkspaceId'];
        if (workspaceId is String && workspaces != null) {
          final index = workspaces.indexWhere(
            (workspace) => workspace.id == workspaceId,
          );
          if (index >= 0) {
            await workbenchStore.upsertWorkspace(workspaces[index]);
            await workbenchStore.saveCurrentWorkspaceId(workspaceId);
          }
        }
        return;
      case 'workspace.switch':
        final workspaceId = result.output['activeWorkspaceId'];
        if (workspaceId is String) {
          await workbenchStore.saveCurrentWorkspaceId(workspaceId);
        }
        return;
    }
  }

  Future<void> _recordInvocation({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required CapabilityExecutionResult result,
    required WorkbenchStore? workbenchStore,
    required PermissionMode permissionMode,
    required bool skippedPermissionCheck,
  }) async {
    if (workbenchStore == null) {
      return;
    }
    final error = result.output['error'];
    final permissionDecision = result.output['permissionDecision'];
    final status = _statusForResult(result);
    await workbenchStore.recordInvocation(
      CapabilityInvocation(
        id: 'invocation-${DateTime.now().microsecondsSinceEpoch}',
        workspaceId: workspaceId,
        capabilityId: result.capabilityId,
        input: toolCall.arguments,
        status: status,
        permissionDecision: skippedPermissionCheck
            ? 'approved'
            : permissionDecision is String
            ? permissionDecision
            : permissionMode.name,
        output: result.output,
        error: error is String ? error : null,
        createdAt: DateTime.now(),
      ),
    );
  }

  CapabilityInvocationStatus _statusForResult(
    CapabilityExecutionResult result,
  ) {
    if (result.output['error'] == 'permission_confirmation_required') {
      return CapabilityInvocationStatus.pending;
    }
    if (result.output['error'] == 'permission_denied') {
      return CapabilityInvocationStatus.denied;
    }
    if (result.output['ok'] == true) {
      return CapabilityInvocationStatus.completed;
    }
    return CapabilityInvocationStatus.failed;
  }

  List<Map<String, Object?>> get toolDefinitions {
    final staticTools = _toolDefinitions.all;
    final dynamicTools = _mcpManager.allTools.map((t) => t.toToolMap());
    return [...staticTools, ...dynamicTools];
  }

  CapabilityExecutionResult? _permissionBlockedResult({
    required ToolCallRequest toolCall,
    required List<CapabilityDefinition>? capabilities,
    required PermissionMode permissionMode,
  }) {
    final definition = _definitionForToolName(toolCall.name, capabilities);
    if (definition == null) {
      return null;
    }
    final decision = PermissionPolicy(permissionMode).decide(definition);
    switch (decision) {
      case PermissionDecision.allow:
        return null;
      case PermissionDecision.ask:
        return CapabilityExecutionResult(
          capabilityId: definition.id,
          output: {
            'ok': false,
            'error': 'permission_confirmation_required',
            'detail': 'Capability ${definition.id} requires user confirmation.',
            'capabilityId': definition.id,
            'permissionDecision': decision.name,
            'permissionMode': permissionMode.name,
          },
        );
      case PermissionDecision.deny:
        return CapabilityExecutionResult(
          capabilityId: definition.id,
          output: {
            'ok': false,
            'error': 'permission_denied',
            'detail':
                'Capability ${definition.id} is denied by permission policy.',
            'capabilityId': definition.id,
            'permissionDecision': decision.name,
            'permissionMode': permissionMode.name,
          },
        );
    }
  }

  CapabilityDefinition? _definitionForToolName(
    String toolName,
    List<CapabilityDefinition>? capabilities,
  ) {
    if (capabilities == null || capabilities.isEmpty) {
      return null;
    }
    final capabilityId = _capabilityIdForToolName(toolName);
    for (final capability in capabilities) {
      if (capability.id == capabilityId) {
        return capability;
      }
    }
    return null;
  }

  String? _toolNameForCapabilityId(String capabilityId) {
    return _toolNamesByCapabilityId[capabilityId];
  }

  String _capabilityIdForToolName(String toolName) {
    return _capabilityIdsByToolName[toolName] ?? toolName;
  }
}
