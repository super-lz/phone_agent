import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/conversation/message_block.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/models/model_provider_config.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/permissions/permission_policy.dart';
import '../../domain/workbench/workbench_store.dart';
import '../../domain/workspace/workspace.dart';
import '../capabilities/capability_execution_result.dart';
import '../capabilities/capability_runtime.dart';
import '../capabilities/mcp_manager.dart';
import 'agent_loop_budget.dart';
import 'agent_run_state.dart';
import 'conversation_context_builder.dart';
import 'tool_call_accumulator.dart';
import 'tool_router.dart';

typedef AddAgentMessage = void Function(AgentMessage message);
typedef ReplaceAgentMessage =
    void Function(String messageId, AgentMessage message);
typedef NotifyAgentLoopChange = void Function();
typedef SwitchAgentWorkspace = void Function(String workspaceId);
typedef IsAgentAppForeground = bool Function();
typedef WaitUntilAgentAppForeground = Future<void> Function();
typedef ReportAgentRunSnapshot = void Function(AgentRunSnapshot snapshot);

class AgentLoop {
  AgentLoop({
    required OpenAiCompatibleChatClient chatClient,
    required CapabilityRuntime capabilityRuntime,
    this.budget = const AgentLoopBudget(),
  }) : _chatClient = chatClient,
       _capabilityRuntime = capabilityRuntime;

  final OpenAiCompatibleChatClient _chatClient;
  final CapabilityRuntime _capabilityRuntime;
  final AgentLoopBudget budget;
  final AgentToolRouter _toolRouter = const AgentToolRouter();

  CapabilityRuntime get capabilityRuntime => _capabilityRuntime;

  Future<CapabilityExecutionResult> executeApprovedTool({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required List<AgentMemory> allMemories,
    required List<AgentNote> allNotes,
    required List<AgentArtifact> allArtifacts,
    required List<AgentWorkspace> allWorkspaces,
    required List<AgentSkill> allSkills,
    required List<CapabilityDefinition> allCapabilities,
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
    required WorkbenchStore workbenchStore,
    required String? apiKey,
    required PermissionMode permissionMode,
    required SwitchAgentWorkspace switchWorkspace,
  }) async {
    final result = await _capabilityRuntime.execute(
      toolCall: toolCall,
      workspaceId: workspaceId,
      memories: allMemories,
      notes: allNotes,
      artifacts: allArtifacts,
      workspaces: allWorkspaces,
      skills: allSkills,
      capabilities: allCapabilities,
      noteStore: noteStore,
      fileStore: fileStore,
      workbenchStore: workbenchStore,
      apiKey: apiKey,
      permissionMode: permissionMode,
      skipPermissionCheck: true,
    );
    _switchWorkspaceIfNeeded(
      result: result,
      fallbackWorkspaceId: workspaceId,
      switchWorkspace: switchWorkspace,
    );
    return result;
  }

  Future<void> run({
    required ModelProviderConfig provider,
    required String apiKey,
    required Object prompt,
    required AgentWorkspace workspace,
    required String workspaceId,
    required List<AgentMemory> visibleMemories,
    required List<AgentMemory> allMemories,
    required List<AgentNote> allNotes,
    required List<AgentArtifact> allArtifacts,
    required List<AgentWorkspace> allWorkspaces,
    required List<AgentSkill> allSkills,
    required List<CapabilityDefinition> allCapabilities,
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
    required WorkbenchStore workbenchStore,
    required PermissionMode permissionMode,
    required List<AgentMessage> priorMessages,
    required AddAgentMessage addMessage,
    required ReplaceAgentMessage replaceMessage,
    required NotifyAgentLoopChange notifyChange,
    required SwitchAgentWorkspace switchWorkspace,
    IsAgentAppForeground? isForeground,
    WaitUntilAgentAppForeground? waitUntilForeground,
    AgentRunControl? runControl,
    ReportAgentRunSnapshot? reportRunSnapshot,
  }) async {
    final startedAt = DateTime.now();
    final runState = AgentLoopRunState(budget);
    var activeWorkspaceId = workspaceId;

    void report(AgentRunPhase phase, String detail, {String? currentToolName}) {
      reportRunSnapshot?.call(
        AgentRunSnapshot(
          phase: phase,
          detail: detail,
          toolCallsUsed: runState.toolCallsUsed,
          maxToolCalls: budget.maxToolCalls,
          startedAt: startedAt,
          currentToolName: currentToolName,
        ),
      );
    }

    void throwIfCancelled() {
      runControl?.throwIfCancelled();
    }

    report(AgentRunPhase.thinking, '正在处理您的请求...');
    final latestRoutingPrompt = _extractTextForRouting(prompt);
    final routingContext = _routingContextText(
      priorMessages: priorMessages,
      allSkills: allSkills,
    );

    report(AgentRunPhase.routing, '正在选择本轮需要暴露的工具集合。');
    final toolRoute = await _toolRouter.route(
      prompt: latestRoutingPrompt,
      context: routingContext,
      allTools: _capabilityRuntime.toolDefinitions,
      chatClient: _chatClient,
      provider: provider,
      apiKey: apiKey,
    );

    final modelMessages = await _buildModelMessages(
      prompt: prompt,
      workspace: workspace,
      visibleMemories: visibleMemories,
      priorMessages: priorMessages,
      toolIndex: toolRoute.index,
      chatClient: _chatClient,
      provider: provider,
      apiKey: apiKey,
    );

    final currentTurnToolResults = <CapabilityExecutionResult>[];
    var requiredToolCorrectionAttempts = 0;
    var rawFinalCorrectionAttempts = 0;

    for (var round = 0; round < budget.maxModelRounds; round += 1) {
      throwIfCancelled();

      // Turn message IDs
      final assistantMessageId =
          'msg-model-${DateTime.now().microsecondsSinceEpoch}-$round';
      final contentBuffer = StringBuffer();
      final toolCalls = ToolCallAccumulator();
      var isPreparingToolCall = false;
      var retryAttempts = 0;
      var hasReceivedModelDelta = false;

      // START MODEL STREAMING
      while (true) {
        throwIfCancelled();
        report(AgentRunPhase.modelStreaming, '正在思考...');

        try {
          await for (final event in _chatClient.streamChat(
            provider: provider,
            apiKey: apiKey,
            messages: modelMessages,
            tools: runState.canUseTools ? toolRoute.tools : const [],
          )) {
            throwIfCancelled();

            if (event.toolCallDeltas.isNotEmpty) {
              hasReceivedModelDelta = true;
              isPreparingToolCall = true;
              report(AgentRunPhase.waitingForToolCall, '准备调用工具...');
              toolCalls.applyAll(event.toolCallDeltas);
            }

            if (event.contentDelta.isNotEmpty) {
              hasReceivedModelDelta = true;
              contentBuffer.write(event.contentDelta);

              if (!isPreparingToolCall) {
                replaceMessage(
                  assistantMessageId,
                  _assistantMarkdownMessage(
                    assistantMessageId,
                    contentBuffer.toString(),
                  ),
                );
                notifyChange();
              }
            }
          }
          break;
        } on ModelRequestException catch (error) {
          throwIfCancelled();
          if (_shouldRetryModelStream(
            error: error,
            retryAttempts: retryAttempts,
            hasReceivedModelDelta: hasReceivedModelDelta,
          )) {
            retryAttempts += 1;
            await _waitForForegroundBeforeRetryIfNeeded(
              isForeground: isForeground,
              waitUntilForeground: waitUntilForeground,
              messageId: assistantMessageId,
              replaceMessage: replaceMessage,
              notifyChange: notifyChange,
              report: report,
            );
            continue;
          }
          if (contentBuffer.isNotEmpty) {
            replaceMessage(
              assistantMessageId,
              _assistantInterruptedMessage(
                assistantMessageId,
                contentBuffer.toString(),
                error.message,
              ),
            );
            notifyChange();
            report(AgentRunPhase.completed, '模型连接中断');
            return;
          }
          rethrow;
        }
      }

      final requests = toolCalls.toRequests();

      // CASE 1: NO TOOL CALLS -> WE ARE DONE
      if (requests.isEmpty) {
        if (contentBuffer.isEmpty) {
          replaceMessage(
            assistantMessageId,
            _modelErrorResponse('模型没有返回任何内容。'),
          );
          notifyChange();
        } else {
          final finalText = contentBuffer.toString();
          if (!_requiredToolsSatisfied(toolRoute, currentTurnToolResults)) {
            if (requiredToolCorrectionAttempts < 2) {
              requiredToolCorrectionAttempts += 1;
              replaceMessage(
                assistantMessageId,
                _assistantIntermediateMessage(assistantMessageId, finalText),
              );
              modelMessages
                ..add({'role': 'assistant', 'content': finalText})
                ..add({
                  'role': 'user',
                  'content':
                      '本轮存在必需工具：${toolRoute.requiredToolNames.join('、')}。'
                      '在必需工具成功执行前，不能声称产物已经创建、已保存或可预览。'
                      '请立即调用缺失的必需工具；如果无法调用，请明确说明未创建。',
                });
              notifyChange();
              continue;
            }
            replaceMessage(
              assistantMessageId,
              _requiredToolErrorResponse(
                assistantMessageId,
                toolRoute.requiredToolNames,
              ),
            );
            notifyChange();
            report(AgentRunPhase.completed, '必需工具没有成功完成');
            return;
          }

          if (_looksLikeRawToolProcess(finalText) &&
              rawFinalCorrectionAttempts < 1) {
            rawFinalCorrectionAttempts += 1;
            replaceMessage(
              assistantMessageId,
              _assistantIntermediateMessage(assistantMessageId, finalText),
            );
            modelMessages
              ..add({'role': 'assistant', 'content': finalText})
              ..add({
                'role': 'user',
                'content':
                    '上一条回复复述了工具调用过程或原始结构化结果，不能作为最终回答。'
                    '请基于已有 observation 重新生成面向用户的自然语言结论，'
                    '不要出现工具调用、工具结果、原始 JSON、Map 或 capability 字段。',
              });
            notifyChange();
            continue;
          }

          replaceMessage(
            assistantMessageId,
            _assistantMarkdownMessage(assistantMessageId, finalText),
          );
          notifyChange();
        }
        report(AgentRunPhase.completed, '已完成');
        return;
      }

      // CASE 2: TOOL CALLS -> EXECUTE THEM
      report(AgentRunPhase.executingTool, '正在执行工具...');

      modelMessages.add({
        'role': 'assistant',
        'content': contentBuffer.toString(),
        'tool_calls': requests
            .map((r) => r.toAssistantMessageToolCall())
            .toList(growable: false),
      });

      final turnBlocks = <MessageBlock>[
        if (contentBuffer.isNotEmpty)
          MessageBlock.markdown(contentBuffer.toString()),
      ];

      for (final request in requests) {
        throwIfCancelled();
        report(
          AgentRunPhase.executingTool,
          '正在执行 ${request.name}...',
          currentToolName: request.name,
        );

        turnBlocks.add(MessageBlock.toolCall(request.name, request.arguments));

        final result = await _capabilityRuntime.execute(
          toolCall: request,
          workspaceId: activeWorkspaceId,
          memories: allMemories,
          notes: allNotes,
          artifacts: allArtifacts,
          workspaces: allWorkspaces,
          skills: allSkills,
          capabilities: allCapabilities,
          noteStore: noteStore,
          fileStore: fileStore,
          workbenchStore: workbenchStore,
          apiKey: apiKey,
          permissionMode: permissionMode,
        );

        runState.recordToolResult(result.output['ok'] == true);
        currentTurnToolResults.add(result);

        activeWorkspaceId = _switchWorkspaceIfNeeded(
          result: result,
          fallbackWorkspaceId: activeWorkspaceId,
          switchWorkspace: switchWorkspace,
        );

        turnBlocks.add(
          MessageBlock.toolResult(result.capabilityId, result.output),
        );

        if (result.output['error'] == 'permission_confirmation_required') {
          turnBlocks.add(
            MessageBlock.approvalRequest(
              requestId: '$assistantMessageId-${request.id}',
              toolName: request.name,
              capabilityId: result.capabilityId,
              workspaceId: activeWorkspaceId,
              input: request.arguments,
              detail: result.output['detail'] as String? ?? '需要授权',
            ),
          );
        }

        turnBlocks.addAll(_artifactBlocksFor(result));

        modelMessages.add({
          'role': 'tool',
          'tool_call_id': request.id,
          'name': request.name,
          'content': result.encodedModelObservation,
        });
      }

      final processMessageId = '$assistantMessageId-process';
      replaceMessage(
        processMessageId,
        AgentMessage(
          id: processMessageId,
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
          blocks: turnBlocks,
        ),
      );
      notifyChange();
    }

    report(AgentRunPhase.completed, '已完成');
  }

  String _routingContextText({
    required List<AgentMessage> priorMessages,
    required List<AgentSkill>? allSkills,
  }) {
    final recentMessages = priorMessages
        .where((message) => message.id != 'msg-welcome')
        .toList(growable: false);
    final history = recentMessages.reversed
        .take(6)
        .toList(growable: false)
        .reversed
        .map(_messageTextForRouting)
        .where((text) => text.trim().isNotEmpty)
        .join('\n');

    final skillInfo = allSkills == null || allSkills.isEmpty
        ? ''
        : '\n\n当前已安装 Skill：\n${allSkills.map((s) => '- ${s.id}: ${s.description}').join('\n')}';

    final mcpInfo = _capabilityRuntime.mcpManager.allTools.isEmpty
        ? ''
        : '\n\n当前已连接 MCP 工具：\n${_capabilityRuntime.mcpManager.allTools.map((McpToolDefinition t) => '- ${t.name}').join('\n')}';

    return '$history$skillInfo$mcpInfo';
  }

  String _messageTextForRouting(AgentMessage message) {
    final role = _modelRole(message.role);
    final text = message.blocks
        .where((block) => block.type == MessageBlockType.markdownText)
        .map((block) => block.data['text'])
        .whereType<String>()
        .join('\n')
        .trim();
    return text.isEmpty ? '' : '$role: $text';
  }

  String _extractTextForRouting(Object prompt) {
    if (prompt is String) {
      return prompt;
    }
    if (prompt is Iterable<Object?>) {
      return prompt.map(_extractPromptPartText).join('\n');
    }
    return prompt.toString();
  }

  String _extractPromptPartText(Object? part) {
    if (part is String) {
      return part;
    }
    if (part is Map<String, Object?>) {
      if (part['type'] == 'image_url' || part.containsKey('image_url')) {
        return '[image_url]';
      }
      final text = part['text'];
      if (text is String) {
        return text;
      }
      return part.values.map(_extractPromptPartText).join('\n');
    }
    if (part is Iterable<Object?>) {
      return part.map(_extractPromptPartText).join('\n');
    }
    return '';
  }

  Future<List<Map<String, Object?>>> _buildModelMessages({
    required Object prompt,
    required AgentWorkspace workspace,
    required List<AgentMemory> visibleMemories,
    required List<AgentMessage> priorMessages,
    required String toolIndex,
    OpenAiCompatibleChatClient? chatClient,
    ModelProviderConfig? provider,
    String? apiKey,
  }) async {
    final memories = visibleMemories
        .map((memory) => '- ${memory.content}')
        .join('\n');
    final currentTime = _currentTimeContext(DateTime.now());
    final conversationContext = await const ConversationContextBuilder().build(
      messages: priorMessages,
      chatClient: chatClient,
      provider: provider,
      apiKey: apiKey,
    );
    final messages = <Map<String, Object?>>[
      {
        'role': 'system',
        'content': _buildSystemPrompt(
          workspace: workspace,
          currentTime: currentTime,
          memories: memories,
          toolIndex: toolIndex,
        ),
      },
    ];
    if (conversationContext.summary.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content':
            '以下是更早会话的压缩摘要，只作为上下文参考；如果和用户最新消息冲突，以最新消息为准。\n'
            '${conversationContext.summary}',
      });
    }
    for (final entry in conversationContext.recentEntries) {
      messages.add({'role': _modelRole(entry.role), 'content': entry.content});
    }
    messages.add({'role': 'user', 'content': prompt});
    return messages;
  }

  String _buildSystemPrompt({
    required AgentWorkspace workspace,
    required String currentTime,
    required String memories,
    required String toolIndex,
  }) {
    final memoryBlock = memories.isEmpty ? '- 暂无' : memories;
    return [
      '<role>',
      '你是 Phone Agent，运行在移动端 Agent 工作台，帮助用户在手机上完成学习、工作、生活和创作任务。',
      '使用中文回答。优先给出可执行、结构化、直接有用的结果。',
      '</role>',
      '',
      '<operating_principles>',
      '- 先判断用户要的是普通回答、信息查询、数据读写、文件/项目维护，还是创建可复用产物。',
      '- 能通过工具完成的真实动作必须调用工具；不要用自然语言假装已经创建、保存、打开或执行。',
      '- 只使用 <capability_index> 中本轮暴露的工具。未暴露的工具组视为不可用，不要臆造调用。',
      '- 工具结果是内部观察。最终回答不要直接展示原始 JSON、字段名、tool_call、tool_result 或 capability 元数据。',
      '- 如果工具结果包含 summary 或 userMessage，优先把它转成用户能理解的结论和下一步。',
      '- 可以连续调用工具完成复杂任务，但证据足够后要及时总结，避免重复调用。',
      '</operating_principles>',
      '',
      '<capability_index>',
      toolIndex,
      '',
      '能力分组与触发规则：',
      '- memory: memory_create / memory_query / memory_delete。仅在用户明确要求记住、忘记、查看或管理长期记忆时使用；普通回答直接使用 <current_context> 中已注入的长期记忆。',
      '- notes: db_note_create / db_note_query。记录备忘、保存信息、整理事项或查询已保存笔记时使用。',
      '- workspace: workspace_create / workspace_switch。创建或切换工作区时使用；创建成功后当前 Workspace 必须切换到新工作区。',
      '- files: file_write_app_file / file_read_app_file / file_search_app_files / file_apply_text_patch。只访问当前工作区沙箱内的相对路径。',
      '- artifacts: artifact_create / artifact_query / artifact_inspect_logs。报告、文档、任务清单、文件摘要、Web App 卡片或其它可复用产物必须保存为 Artifact。',
      '- projects: project_create_web_app / project_update_web_app / project_test_web_app / project_version_history / project_revert_web_app。创建 Web App 用 create；反馈、修复或迭代已有 Web App 时更新原项目，不创建新卡片；创建或更新后用 test 做受控静态检查。',
      '- office: document_* / spreadsheet_* / presentation_* / pdf_*。用于 Office/PDF 的提取、生成和受控局部文本替换。',
      '- native: device_info / time_get_current / battery_status / network_status / clipboard_* / camera_capture_* / flashlight_* / media_pick_* / file_pick_system_file / audio_record_* / contacts_pick / barcode_scan_* / share_text / system_* / permission_open_settings / url_open_external / screen_* / sensor_* / location_get_current / notification_* / calendar_event_create。',
      '- web: web_search / web_fetch。需要最新信息、网页资料、来源引用或读取具体网页正文时使用。',
      '- extensions: skill_install / skill_invoke / mcp_connect。仅在用户明确要求 Skill/MCP 或外部工具扩展时使用。',
      '</capability_index>',
      '',
      '<workflow_contracts>',
      '1. 普通对话：没有暴露工具时直接回答；不要为了使用已注入记忆而调用 memory_query。',
      '2. 相对时间：处理今天、明天、今晚、几分钟后等表达时，以 <current_context> 的本地时间为准；需要校准时调用 time_get_current。',
      '3. 文件维护：先 file_search_app_files 定位，再 file_read_app_file 读局部内容，最后 file_apply_text_patch 精确修改；补丁不唯一或目标不存在时返回错误。',
      '4. Web App 维护：用户反馈已有 Web App/网页/小游戏问题时，先 artifact_query 定位原 Artifact，必要时 artifact_inspect_logs 读运行日志，再读取相关项目文件，最后用 project_update_web_app 更新原项目；更新后调用 project_test_web_app 做静态检查，检查失败时继续修复或说明剩余问题；不要调用 project_create_web_app 复制新项目。',
      '5. 可复用产物：生成报告、文档、任务清单、文件摘要或 Web App 时，必须调用 artifact_create 或更专用的创建工具。',
      '6. Office/PDF：上传或处理 Word、Excel、PPT、PDF 时先提取；生成新文件时写入当前 Workspace 文件区；局部替换不承诺保留复杂原格式。',
      '7. 本地能力：手机设备、位置、电量、网络、权限等能力执行后，最终回答优先展示可读摘要，不展示底层结构化元数据。',
      '</workflow_contracts>',
      '',
      '<web_app_contract>',
      '- 创建小游戏、交互网页、Web App、原型或本地可维护项目时，必须调用 project_create_web_app 写入真实工程文件并创建 Web App Artifact。',
      '- project_create_web_app 或 project_update_web_app 成功后，若本轮暴露了 project_test_web_app，先调用它检查项目；检查未通过时不要声称完全完成。',
      '- project_create_web_app 成功前，不得说“已创建”“可预览”“文件已保存”或提示用户点击不存在的卡片。',
      '- Web App 默认按本地工程组织；除极小页面外，入口 HTML、样式、脚本应拆成可维护文件。',
      '- 默认按手机竖屏、触摸交互、360-430px 宽度、安全区域和移动端性能设计；不要生成桌面优先、多列侧栏、依赖 hover 或密集小字号的布局。',
      '- 大段 HTML/CSS/JS 放入 project_create_web_app 或 file_write_app_file 的工具参数，不要先在聊天正文中流式输出完整源码。',
      '- Web App 需要手机能力时，必须在 permissions 中声明精确 capability id，并通过 window.PhoneAgent.getManifest() / window.PhoneAgent.callCapability(id, input) 调用。',
      '- JSBridge 当前可用能力：db.note.create, db.note.query, file.read_app_file, file.write_app_file, file.search_app_files, artifact.create, artifact.query, device.info, time.get_current, battery.status, network.status, clipboard.read, clipboard.write, camera.capture_photo, camera.capture_video, flashlight.set, flashlight.status, media.pick_image, media.pick_images, media.pick_video, file.pick_system_file, audio.record_start, audio.record_stop, audio.record_cancel, contacts.pick, barcode.scan_camera, barcode.scan_image, share.text, system.haptic_feedback, system.sound_alert, system.ui.set, system.ui.status, permission.open_settings, url.open_external, screen.keep_awake, screen.keep_awake_status, screen.orientation.set, screen.orientation.status, sensor.accelerometer.read, sensor.gyroscope.read, sensor.magnetometer.read, location.get_current, notification.schedule, notification.pending, notification.cancel, notification.cancel_all, calendar.event.create, web.search, web.fetch, memory.query, workspace.switch。',
      '- 用户反馈已生成 Web App 的问题时，先读取 .phone-agent/runtime.log 和相关项目文件，再定位并修复。',
      '</web_app_contract>',
      '',
      '<current_context>',
      'Workspace: ${workspace.name}',
      'Local time: $currentTime',
      'Long-term memory:',
      memoryBlock,
      '</current_context>',
    ].join('\n');
  }

  String _currentTimeContext(DateTime now) {
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absoluteOffset = offset.abs();
    final hours = absoluteOffset.inHours.toString().padLeft(2, '0');
    final minutes = absoluteOffset.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '${now.toIso8601String()} '
        '(UTC$sign$hours:$minutes, ${now.timeZoneName}, weekday=${now.weekday})';
  }

  String _modelRole(MessageRole role) {
    switch (role) {
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
      case MessageRole.system:
        return 'system';
    }
  }

  bool _shouldRetryModelStream({
    required ModelRequestException error,
    required int retryAttempts,
    required bool hasReceivedModelDelta,
  }) {
    return error.isRetryable && retryAttempts < 1 && !hasReceivedModelDelta;
  }

  Future<void> _waitForForegroundBeforeRetryIfNeeded({
    required IsAgentAppForeground? isForeground,
    required WaitUntilAgentAppForeground? waitUntilForeground,
    required String messageId,
    required ReplaceAgentMessage replaceMessage,
    required NotifyAgentLoopChange notifyChange,
    required void Function(
      AgentRunPhase phase,
      String detail, {
      String? currentToolName,
    })
    report,
  }) async {
    if (isForeground?.call() != false || waitUntilForeground == null) {
      return;
    }
    report(AgentRunPhase.waitingForeground, '应用在后台，等待回到前台后重试模型连接。');
    replaceMessage(
      messageId,
      _assistantIntermediateMessage(
        messageId,
        '应用已进入后台，模型流式连接可能被系统中断；回到前台后会自动重试一次。',
      ),
    );
    notifyChange();
    await waitUntilForeground();
  }

  String _switchWorkspaceIfNeeded({
    required CapabilityExecutionResult result,
    required String fallbackWorkspaceId,
    required SwitchAgentWorkspace switchWorkspace,
  }) {
    if (result.output['ok'] != true) {
      return fallbackWorkspaceId;
    }
    if (result.capabilityId != 'workspace.create' &&
        result.capabilityId != 'workspace.switch') {
      return fallbackWorkspaceId;
    }
    final workspaceId = result.output['activeWorkspaceId'];
    if (workspaceId is! String || workspaceId.isEmpty) {
      return fallbackWorkspaceId;
    }
    switchWorkspace(workspaceId);
    return workspaceId;
  }

  List<MessageBlock> _artifactBlocksFor(CapabilityExecutionResult result) {
    if (result.output['ok'] != true ||
        result.capabilityId != 'artifact.create' &&
            result.capabilityId != 'project.create_web_app' &&
            result.capabilityId != 'project.update_web_app' &&
            result.capabilityId != 'project.revert_web_app') {
      return const [];
    }
    final artifactId = result.output['artifactId'];
    final title = result.output['title'];
    final type = result.output['type'];
    if (artifactId is! String || title is! String) {
      return const [];
    }
    if (_isWebAppArtifactType(type)) {
      return [MessageBlock.webAppCard(artifactId, title)];
    }
    return [MessageBlock.artifactCard(artifactId, title)];
  }

  bool _isWebAppArtifactType(Object? type) {
    return type is String &&
        type.trim().replaceAll('_', '').replaceAll('-', '').toLowerCase() ==
            'webapp';
  }

  bool _requiredToolsSatisfied(
    ToolRoute toolRoute,
    List<CapabilityExecutionResult> results,
  ) {
    if (toolRoute.requiredToolNames.isEmpty) {
      return true;
    }
    final successfulCapabilityIds = results
        .where((result) => result.output['ok'] == true)
        .map((result) => result.capabilityId)
        .toSet();
    return toolRoute.requiredToolNames.every((toolName) {
      final capabilityId = _capabilityIdForToolName(toolName);
      return capabilityId != null &&
          successfulCapabilityIds.contains(capabilityId);
    });
  }

  String? _capabilityIdForToolName(String toolName) {
    switch (toolName) {
      case 'project_create_web_app':
        return 'project.create_web_app';
      case 'artifact_create':
        return 'artifact.create';
      case 'file_write_app_file':
        return 'file.write_app_file';
      default:
        return toolName.replaceFirst('_', '.');
    }
  }

  bool _looksLikeRawToolProcess(String text) {
    final normalized = text.toLowerCase();
    return text.contains('工具调用') ||
        text.contains('工具结果') ||
        normalized.contains('tool_call') ||
        normalized.contains('tool result') ||
        normalized.contains('capability') ||
        normalized.contains('{ok:') ||
        normalized.contains('"ok":');
  }

  AgentMessage _assistantMarkdownMessage(String id, String text) {
    return AgentMessage(
      id: id,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.markdown(text)],
    );
  }

  AgentMessage _assistantIntermediateMessage(String id, String text) {
    final content = text.trim().isEmpty ? '正在准备工具调用。' : text;
    return AgentMessage(
      id: id,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.intermediateMarkdown(content)],
    );
  }

  AgentMessage _assistantInterruptedMessage(
    String id,
    String partialText,
    String detail,
  ) {
    return AgentMessage(
      id: id,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.markdown(partialText),
        MessageBlock.error('模型连接中断', detail),
      ],
    );
  }

  AgentMessage _requiredToolErrorResponse(
    String id,
    List<String> requiredToolNames,
  ) {
    return AgentMessage(
      id: id,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.error(
          '未创建真实产物',
          '必需工具没有成功完成：${requiredToolNames.join('、')}。'
              '系统已阻止模型把未完成的创建、保存或预览操作当作成功结果展示。',
        ),
      ],
    );
  }

  AgentMessage _modelErrorResponse(String detail) {
    return AgentMessage(
      id: 'msg-model-error-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.error('模型调用失败', detail)],
    );
  }
}
