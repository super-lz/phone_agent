import '../../core/logging/app_logger.dart';
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
import '../capabilities/capability_result_presentation.dart';
import '../capabilities/capability_runtime.dart';
import 'agent_loop_budget.dart';
import 'conversation_context_builder.dart';
import 'tool_call_accumulator.dart';
import 'tool_router.dart';

typedef AddAgentMessage = void Function(AgentMessage message);
typedef ReplaceAgentMessage =
    void Function(String messageId, AgentMessage message);
typedef NotifyAgentLoopChange = void Function();
typedef SwitchAgentWorkspace = void Function(String workspaceId);

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

  Future<CapabilityExecutionResult> executeApprovedTool({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required List<AgentMemory> allMemories,
    required List<AgentNote> allNotes,
    required List<AgentArtifact> allArtifacts,
    required List<AgentWorkspace> allWorkspaces,
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
  }) async {
    final runState = AgentLoopRunState(budget);
    var activeWorkspaceId = workspaceId;
    final toolRoute = _toolRouter.route(
      prompt: prompt,
      allTools: _capabilityRuntime.toolDefinitions,
    );
    final modelMessages = _buildModelMessages(
      prompt: prompt,
      workspace: workspace,
      visibleMemories: visibleMemories,
      priorMessages: priorMessages,
      toolIndex: toolRoute.index,
    );
    final currentTurnToolResults = <CapabilityExecutionResult>[];

    for (var round = 0; round < budget.maxModelRounds; round += 1) {
      final assistantMessageId =
          'msg-model-${DateTime.now().microsecondsSinceEpoch}-$round';
      addMessage(_emptyAssistantMessage(assistantMessageId));
      notifyChange();

      final contentBuffer = StringBuffer();
      final toolCalls = ToolCallAccumulator();
      var isPreparingToolCall = false;
      var retryAttempts = 0;
      var hasReceivedModelDelta = false;
      while (true) {
        AppLogger.info('agent_loop.model_stream.start', {
          'round': round,
          'workspaceId': activeWorkspaceId,
          'toolCallsUsed': runState.toolCallsUsed,
          'maxToolCalls': budget.maxToolCalls,
          'retryAttempts': retryAttempts,
        });
        try {
          await for (final event in _chatClient.streamChat(
            provider: provider,
            apiKey: apiKey,
            messages: modelMessages,
            tools: runState.canUseTools ? toolRoute.tools : const [],
          )) {
            if (event.toolCallDeltas.isNotEmpty) {
              hasReceivedModelDelta = true;
              isPreparingToolCall = true;
              toolCalls.applyAll(event.toolCallDeltas);
              replaceMessage(
                assistantMessageId,
                _assistantIntermediateMessage(
                  assistantMessageId,
                  contentBuffer.toString(),
                ),
              );
              notifyChange();
              continue;
            }
            if (event.contentDelta.isNotEmpty) {
              hasReceivedModelDelta = true;
              contentBuffer.write(event.contentDelta);
              replaceMessage(
                assistantMessageId,
                isPreparingToolCall
                    ? _assistantIntermediateMessage(
                        assistantMessageId,
                        contentBuffer.toString(),
                      )
                    : _assistantMarkdownMessage(
                        assistantMessageId,
                        contentBuffer.toString(),
                      ),
              );
              notifyChange();
            }
          }
          break;
        } on ModelRequestException catch (error) {
          if (_shouldRetryModelStream(
            error: error,
            retryAttempts: retryAttempts,
            hasReceivedModelDelta: hasReceivedModelDelta,
          )) {
            retryAttempts += 1;
            AppLogger.warning('agent_loop.model_stream.retry', {
              'round': round,
              'workspaceId': activeWorkspaceId,
              'reason': error.message,
              'retryAttempts': retryAttempts,
            });
            continue;
          }
          replaceMessage(
            assistantMessageId,
            _modelErrorResponse(error.message),
          );
          notifyChange();
          return;
        } on Object catch (error) {
          replaceMessage(
            assistantMessageId,
            _modelErrorResponse(error.toString()),
          );
          notifyChange();
          return;
        }
      }

      final requests = toolCalls.toRequests();
      if (requests.isEmpty) {
        if (contentBuffer.isEmpty) {
          replaceMessage(
            assistantMessageId,
            _modelErrorResponse('模型没有返回文本内容。'),
          );
          notifyChange();
        } else {
          _replaceIfToolTranscriptEcho(
            messageId: assistantMessageId,
            content: contentBuffer.toString(),
            toolResults: currentTurnToolResults,
            replaceMessage: replaceMessage,
            notifyChange: notifyChange,
          );
        }
        return;
      }

      activeWorkspaceId =
          await _appendAssistantToolMessage(
            messageId: assistantMessageId,
            content: contentBuffer.toString(),
            requests: requests,
            modelMessages: modelMessages,
            workspaceId: activeWorkspaceId,
            allMemories: allMemories,
            allNotes: allNotes,
            allArtifacts: allArtifacts,
            allWorkspaces: allWorkspaces,
            allCapabilities: allCapabilities,
            noteStore: noteStore,
            fileStore: fileStore,
            workbenchStore: workbenchStore,
            apiKey: apiKey,
            permissionMode: permissionMode,
            runState: runState,
            currentTurnToolResults: currentTurnToolResults,
            replaceMessage: replaceMessage,
            switchWorkspace: switchWorkspace,
          ) ??
          activeWorkspaceId;
      notifyChange();

      if (!runState.canUseTools) {
        await _appendFinalAnswerAfterBudgetStop(
          reason: runState.stopReason,
          provider: provider,
          apiKey: apiKey,
          modelMessages: modelMessages,
          addMessage: addMessage,
          replaceMessage: replaceMessage,
          notifyChange: notifyChange,
          toolResults: currentTurnToolResults,
        );
        return;
      }
    }

    await _appendFinalAnswerAfterBudgetStop(
      reason: '已达到本轮对话的最大模型轮次，避免无限循环。',
      provider: provider,
      apiKey: apiKey,
      modelMessages: modelMessages,
      addMessage: addMessage,
      replaceMessage: replaceMessage,
      notifyChange: notifyChange,
      toolResults: currentTurnToolResults,
    );
  }

  List<Map<String, Object?>> _buildModelMessages({
    required Object prompt,
    required AgentWorkspace workspace,
    required List<AgentMemory> visibleMemories,
    required List<AgentMessage> priorMessages,
    required String toolIndex,
  }) {
    final memories = visibleMemories
        .map((memory) => '- ${memory.content}')
        .join('\n');
    final currentTime = _currentTimeContext(DateTime.now());
    final conversationContext = const ConversationContextBuilder().build(
      priorMessages,
    );
    final messages = <Map<String, Object?>>[
      {
        'role': 'system',
        'content':
            '你是 Phone Agent，运行在移动端 Agent 工作台。'
            '请用中文回答，优先给出可执行、结构化、直接有用的结果。'
            '长期记忆已经自动提供在上下文中；普通回答应直接使用这些记忆，不要为了使用记忆而调用 memory_query。'
            '只有当用户明确要求记住、忘记、查看或管理记忆时，才调用记忆工具。'
            '当用户要求记录备忘、保存信息、整理事项或查询已保存笔记时，使用 db_note_create 或 db_note_query。'
            '当用户要求创建或切换工作区时，使用 workspace_create 或 workspace_switch。'
            '当用户要求创建、保存、读取或修改当前工作区文件时，使用 file_write_app_file、file_read_app_file 或 file_search_app_files；'
            '文件路径必须是当前工作区沙箱内的相对路径。'
            '当用户要求修改、维护或迭代已生成的本地项目文件时，先用 file_search_app_files 定位关键词或错误片段，'
            '再用 file_read_app_file 读取相关行范围，最后使用 file_apply_text_patch 做精确补丁。'
            '当用户要求查看设备环境、当前时间、电量、网络、读取剪贴板、复制内容、系统分享、触感反馈、提示音、权限设置、打开外部链接、屏幕常亮、传感器或使用当前位置时，'
            '使用 device_info、time_get_current、battery_status、network_status、clipboard_read、clipboard_write、share_text、system_haptic_feedback、system_sound_alert、'
            'permission_open_settings、url_open_external、screen_keep_awake、screen_keep_awake_status、sensor_accelerometer_read、sensor_gyroscope_read、sensor_magnetometer_read 或 location_get_current。'
            '工具结果是内部观察，不要把原始 JSON、字段名或工具元数据当成最终回答直接展示给用户；'
            '设备、位置、电量、网络、权限等本地能力优先使用工具返回的 summary 或 userMessage，再转成人话说明下一步。'
            '处理今天、明天、今晚、几分钟后等相对时间时，必须以系统提供的当前本地时间为准；不确定时先调用 time_get_current 校准。'
            '稍后提醒使用 notification_schedule；加入日历、创建日程或安排会议使用 calendar_event_create；所有绝对时间参数必须使用带时区语义的 ISO 8601。'
            '当你生成报告、文档、任务清单、文件摘要或 Web App 等可复用产物时，使用 artifact_create 保存为 Artifact；'
            '创建 Web App 时必须提供 content_html，写入完整可运行页面、内联样式和内联脚本，不能只写摘要。'
            '当用户上传或要求处理 Word、Excel、PPT、PDF 时，使用 document_extract、spreadsheet_extract、presentation_extract 或 pdf_extract 提取内容；'
            '需要生成新文件时使用 document_generate、spreadsheet_generate、presentation_generate 或 pdf_generate；'
            '需要做局部文字修改时使用 document_apply_text_patch，并说明第一版不保留复杂 Office 格式。'
            '当用户要求创建小游戏、交互网页、Web App、原型或本地可维护项目时，必须使用 project_create_web_app 写入真实工程文件并创建 Web App Artifact；'
            '不要只输出代码块或说“已在下面创建”。'
            'Web App 默认应按本地工程组织，入口 HTML、样式和脚本应拆成可维护文件；只有非常小的单页才允许全部内联。'
            '生成 Web App 时默认按手机竖屏设计，优先适配 360-430px 宽度、触摸操作、安全区域和移动端性能；'
            '不要生成桌面大屏优先、依赖 hover、密集小字号、多列侧栏或需要键鼠才能操作的布局。'
            '大段 HTML/CSS/JS 或项目源码应放入 project_create_web_app 或 file_write_app_file 的工具参数中，'
            '不要先在聊天正文中流式输出完整代码；完成后只给用户总结、入口和后续维护方式。'
            '需要给用户展示可点击卡片或 Web App 预览入口时，必须调用 artifact_create 或 project_create_web_app；'
            '禁止在 Markdown 正文里伪造 Artifact/Web App 链接或提示用户点击并不存在的卡片。'
            'Web App 页面需要手机能力时，必须在 artifact_create.metadata.permissions 或 project_create_web_app.permissions 声明精确 capability id，'
            '并在网页脚本里通过 window.PhoneAgent.getManifest() 和 window.PhoneAgent.callCapability(id, input) 调用，'
            '不要直接假设浏览器能访问手机原生 API。'
            '页面可通过 window.PhoneAgent.getRuntimeInfo() 获取 WebView 运行环境和视口信息；'
            '设备信息可声明 device.info 后调用 await window.PhoneAgent.getDeviceInfo()，也可直接调用 window.PhoneAgent.callCapability("device.info", {})。'
            'Web App 运行时会把 console.warn、console.error、window.error 和 unhandledrejection 写入项目目录下的 .phone-agent/runtime.log；'
            '用户反馈网页问题时，先读取该日志和相关项目文件，再用 file_apply_text_patch 修复。'
            '\n$toolIndex\n'
            'Web App JSBridge 当前支持：db.note.create、db.note.query、file.read_app_file、file.write_app_file、file.search_app_files、'
            'artifact.create、artifact.query、device.info、time.get_current、battery.status、network.status、clipboard.read、clipboard.write、share.text、'
            'system.haptic_feedback、system.sound_alert、permission.open_settings、url.open_external、screen.keep_awake、screen.keep_awake_status、sensor.accelerometer.read、sensor.gyroscope.read、'
            'sensor.magnetometer.read、location.get_current、notification.schedule、calendar.event.create、web.search、web.fetch、memory.query、workspace.switch。'
            '当你需要引用当前工作区已有产物时，使用 artifact_query。'
            '当用户问题需要最新信息、网页资料或来源引用时，必须优先调用 web_search；'
            '需要读取具体网页正文时调用 web_fetch。'
            '你可以连续调用工具完成复杂任务，但要在有足够证据后及时总结，避免重复调用。'
            '\n当前 Workspace：${workspace.name}'
            '\n当前本地时间：$currentTime'
            '\n长期记忆：\n${memories.isEmpty ? '- 暂无' : memories}',
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

  Future<String?> _appendAssistantToolMessage({
    required String messageId,
    required String content,
    required List<ToolCallRequest> requests,
    required List<Map<String, Object?>> modelMessages,
    required String workspaceId,
    required List<AgentMemory> allMemories,
    required List<AgentNote> allNotes,
    required List<AgentArtifact> allArtifacts,
    required List<AgentWorkspace> allWorkspaces,
    required List<CapabilityDefinition> allCapabilities,
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
    required WorkbenchStore workbenchStore,
    required String apiKey,
    required PermissionMode permissionMode,
    required AgentLoopRunState runState,
    required List<CapabilityExecutionResult> currentTurnToolResults,
    required ReplaceAgentMessage replaceMessage,
    required SwitchAgentWorkspace switchWorkspace,
  }) async {
    final blocks = <MessageBlock>[
      if (content.trim().isNotEmpty) MessageBlock.markdown(content),
    ];
    final toolResultMessages = <Map<String, Object?>>[];
    var activeWorkspaceId = workspaceId;

    for (final request in requests) {
      blocks.add(MessageBlock.toolCall(request.name, request.arguments));
      final result = runState.canStartToolCall
          ? await _capabilityRuntime.execute(
              toolCall: request,
              workspaceId: activeWorkspaceId,
              memories: allMemories,
              notes: allNotes,
              artifacts: allArtifacts,
              workspaces: allWorkspaces,
              capabilities: allCapabilities,
              noteStore: noteStore,
              fileStore: fileStore,
              workbenchStore: workbenchStore,
              apiKey: apiKey,
              permissionMode: permissionMode,
            )
          : CapabilityExecutionResult(
              capabilityId: request.name,
              output: {
                'ok': false,
                'error': 'tool budget exhausted',
                'reason': runState.stopReason,
              },
            );
      runState.recordToolResult(result.output['ok'] == true);
      currentTurnToolResults.add(result);
      activeWorkspaceId = _switchWorkspaceIfNeeded(
        result: result,
        fallbackWorkspaceId: activeWorkspaceId,
        switchWorkspace: switchWorkspace,
      );
      blocks.add(MessageBlock.toolResult(result.capabilityId, result.output));
      if (result.output['error'] == 'permission_confirmation_required') {
        blocks.add(
          MessageBlock.approvalRequest(
            requestId: '$messageId-${request.id}',
            toolName: request.name,
            capabilityId: result.capabilityId,
            workspaceId: activeWorkspaceId,
            input: request.arguments,
            detail: result.output['detail'] as String? ?? '该能力需要用户确认。',
          ),
        );
      }
      blocks.addAll(_artifactBlocksFor(result));
      toolResultMessages.add({
        'role': 'tool',
        'tool_call_id': request.id,
        'name': request.name,
        'content': result.encodedModelObservation,
      });
    }

    replaceMessage(
      messageId,
      AgentMessage(
        id: messageId,
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        blocks: blocks,
      ),
    );

    modelMessages.add({
      'role': 'assistant',
      'content': content,
      'tool_calls': requests
          .map((request) => request.toAssistantMessageToolCall())
          .toList(growable: false),
    });
    modelMessages.addAll(toolResultMessages);
    modelMessages.add({
      'role': 'system',
      'content':
          '请基于刚才的工具结果给用户一个自然语言最终回答。不要逐字输出工具 JSON、字段名、capabilityId、permissionDecision 等元数据；'
          '如果工具结果包含 summary 或 userMessage，优先使用它。工具失败时，说明失败原因、用户能做什么、以及你能继续提供的替代方案。',
    });
    return activeWorkspaceId;
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
            result.capabilityId != 'project.create_web_app') {
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

  Future<void> _appendFinalAnswerAfterBudgetStop({
    required String reason,
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> modelMessages,
    required AddAgentMessage addMessage,
    required ReplaceAgentMessage replaceMessage,
    required NotifyAgentLoopChange notifyChange,
    required List<CapabilityExecutionResult> toolResults,
  }) async {
    modelMessages.add({
      'role': 'system',
      'content': '工具继续调用已停止：$reason。请基于已经得到的工具结果，给用户一个完整、诚实、可执行的最终回答；不要再请求工具。',
    });

    final assistantMessageId =
        'msg-final-${DateTime.now().microsecondsSinceEpoch}';
    addMessage(_emptyAssistantMessage(assistantMessageId));
    notifyChange();

    final contentBuffer = StringBuffer();
    var retryAttempts = 0;
    while (true) {
      AppLogger.info('agent_loop.final_answer.start', {'reason': reason});
      try {
        await for (final event in _chatClient.streamChat(
          provider: provider,
          apiKey: apiKey,
          messages: modelMessages,
          tools: const [],
        )) {
          if (event.contentDelta.isEmpty) {
            continue;
          }
          contentBuffer.write(event.contentDelta);
          replaceMessage(
            assistantMessageId,
            _assistantMarkdownMessage(
              assistantMessageId,
              contentBuffer.toString(),
            ),
          );
          notifyChange();
        }
        break;
      } on ModelRequestException catch (error) {
        if (_shouldRetryModelStream(
          error: error,
          retryAttempts: retryAttempts,
          hasReceivedModelDelta: contentBuffer.isNotEmpty,
        )) {
          retryAttempts += 1;
          AppLogger.warning('agent_loop.final_answer.retry', {
            'reason': error.message,
            'retryAttempts': retryAttempts,
          });
          continue;
        }
        replaceMessage(
          assistantMessageId,
          _modelErrorResponse('工具预算耗尽后生成最终回答失败：${error.message}'),
        );
        notifyChange();
        return;
      } on Object catch (error) {
        replaceMessage(
          assistantMessageId,
          _modelErrorResponse('工具预算耗尽后生成最终回答失败：$error'),
        );
        notifyChange();
        return;
      }
    }

    if (contentBuffer.isEmpty) {
      replaceMessage(
        assistantMessageId,
        AgentMessage(
          id: assistantMessageId,
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
          blocks: [MessageBlock.error('工具调用已停止', '$reason\n模型没有生成最终回答。')],
        ),
      );
      notifyChange();
    } else {
      _replaceIfToolTranscriptEcho(
        messageId: assistantMessageId,
        content: contentBuffer.toString(),
        toolResults: toolResults,
        replaceMessage: replaceMessage,
        notifyChange: notifyChange,
      );
    }
  }

  void _replaceIfToolTranscriptEcho({
    required String messageId,
    required String content,
    required List<CapabilityExecutionResult> toolResults,
    required ReplaceAgentMessage replaceMessage,
    required NotifyAgentLoopChange notifyChange,
  }) {
    if (!_looksLikeToolTranscriptEcho(content) || toolResults.isEmpty) {
      return;
    }
    replaceMessage(
      messageId,
      _assistantMarkdownMessage(messageId, _fallbackFinalAnswer(toolResults)),
    );
    notifyChange();
  }

  bool _looksLikeToolTranscriptEcho(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return false;
    }
    final lower = normalized.toLowerCase();
    return normalized.contains('工具调用') && normalized.contains('工具结果') ||
        lower.contains('tool call') && lower.contains('tool result') ||
        lower.contains('capabilityid') ||
        normalized.contains('{ok:') ||
        normalized.contains('"ok":');
  }

  String _fallbackFinalAnswer(List<CapabilityExecutionResult> toolResults) {
    final visibleResults = toolResults
        .where(
          (result) => result.output['ok'] == true || result.output.isNotEmpty,
        )
        .toList(growable: false);
    if (visibleResults.isEmpty) {
      return '工具已经执行完成，但模型没有生成可用的最终回答。';
    }
    if (visibleResults.length == 1) {
      final presentation = presentCapabilityResult(
        capabilityId: visibleResults.single.capabilityId,
        output: visibleResults.single.output,
      );
      return presentation.summary;
    }
    final lines = visibleResults
        .map((result) {
          final presentation = presentCapabilityResult(
            capabilityId: result.capabilityId,
            output: result.output,
          );
          return '- ${presentation.title}：${presentation.summary}';
        })
        .join('\n');
    return '我已经处理完这些步骤：\n$lines';
  }

  AgentMessage _emptyAssistantMessage(String id) {
    return _assistantMarkdownMessage(id, '');
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

  AgentMessage _modelErrorResponse(String detail) {
    return AgentMessage(
      id: 'msg-model-error-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.error('模型调用失败', detail)],
    );
  }
}
