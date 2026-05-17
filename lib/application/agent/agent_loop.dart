import '../../core/logging/app_logger.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/conversation/message_block.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/models/model_provider_config.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/workspace/workspace.dart';
import '../capabilities/capability_execution_result.dart';
import '../capabilities/capability_runtime.dart';
import 'agent_loop_budget.dart';
import 'conversation_context_builder.dart';
import 'tool_call_accumulator.dart';

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

  Future<void> run({
    required ModelProviderConfig provider,
    required String apiKey,
    required String prompt,
    required AgentWorkspace workspace,
    required String workspaceId,
    required List<AgentMemory> visibleMemories,
    required List<AgentMemory> allMemories,
    required List<AgentNote> allNotes,
    required List<AgentArtifact> allArtifacts,
    required List<AgentWorkspace> allWorkspaces,
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
    required List<AgentMessage> priorMessages,
    required AddAgentMessage addMessage,
    required ReplaceAgentMessage replaceMessage,
    required NotifyAgentLoopChange notifyChange,
    required SwitchAgentWorkspace switchWorkspace,
  }) async {
    final runState = AgentLoopRunState(budget);
    var activeWorkspaceId = workspaceId;
    final modelMessages = _buildModelMessages(
      prompt: prompt,
      workspace: workspace,
      visibleMemories: visibleMemories,
      priorMessages: priorMessages,
    );

    for (var round = 0; round < budget.maxModelRounds; round += 1) {
      final assistantMessageId =
          'msg-model-${DateTime.now().microsecondsSinceEpoch}-$round';
      addMessage(_emptyAssistantMessage(assistantMessageId));
      notifyChange();

      final contentBuffer = StringBuffer();
      final toolCalls = ToolCallAccumulator();
      try {
        AppLogger.info('agent_loop.model_stream.start', {
          'round': round,
          'workspaceId': activeWorkspaceId,
          'toolCallsUsed': runState.toolCallsUsed,
          'maxToolCalls': budget.maxToolCalls,
        });
        await for (final event in _chatClient.streamChat(
          provider: provider,
          apiKey: apiKey,
          messages: modelMessages,
          tools: runState.canUseTools
              ? _capabilityRuntime.toolDefinitions
              : const [],
        )) {
          if (event.contentDelta.isNotEmpty) {
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
          toolCalls.applyAll(event.toolCallDeltas);
        }
      } on Object catch (error) {
        replaceMessage(
          assistantMessageId,
          _modelErrorResponse(error.toString()),
        );
        notifyChange();
        return;
      }

      final requests = toolCalls.toRequests();
      if (requests.isEmpty) {
        if (contentBuffer.isEmpty) {
          replaceMessage(
            assistantMessageId,
            _modelErrorResponse('模型没有返回文本内容。'),
          );
          notifyChange();
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
            noteStore: noteStore,
            fileStore: fileStore,
            apiKey: apiKey,
            runState: runState,
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
    );
  }

  List<Map<String, Object?>> _buildModelMessages({
    required String prompt,
    required AgentWorkspace workspace,
    required List<AgentMemory> visibleMemories,
    required List<AgentMessage> priorMessages,
  }) {
    final memories = visibleMemories
        .map((memory) => '- ${memory.content}')
        .join('\n');
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
            '当用户要求创建、保存、读取或修改当前工作区文件时，使用 file_write_app_file 或 file_read_app_file；'
            '文件路径必须是当前工作区沙箱内的相对路径。'
            '当用户要求查看设备环境、读取剪贴板、复制内容或使用当前位置时，使用 device_info、clipboard_read、clipboard_write 或 location_get_current。'
            '稍后提醒使用 notification_schedule；加入日历、创建日程或安排会议使用 calendar_event_create。'
            '当你生成报告、文档、任务清单、文件摘要或 Web App 等可复用产物时，使用 artifact_create 保存为 Artifact；'
            '创建 Web App 时必须提供 content_html，写入完整可运行页面、内联样式和内联脚本，不能只写摘要。'
            '当你需要引用当前工作区已有产物时，使用 artifact_query。'
            '当用户问题需要最新信息、网页资料或来源引用时，必须优先调用 web_search；'
            '需要读取具体网页正文时调用 web_fetch。'
            '你可以连续调用工具完成复杂任务，但要在有足够证据后及时总结，避免重复调用。'
            '\n当前 Workspace：${workspace.name}'
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
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
    required String apiKey,
    required AgentLoopRunState runState,
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
              noteStore: noteStore,
              fileStore: fileStore,
              apiKey: apiKey,
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
      activeWorkspaceId = _switchWorkspaceIfNeeded(
        result: result,
        fallbackWorkspaceId: activeWorkspaceId,
        switchWorkspace: switchWorkspace,
      );
      blocks.add(MessageBlock.toolResult(result.capabilityId, result.output));
      blocks.addAll(_artifactBlocksFor(result));
      toolResultMessages.add({
        'role': 'tool',
        'tool_call_id': request.id,
        'name': request.name,
        'content': result.encodedOutput,
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
    if (result.capabilityId != 'artifact.create' ||
        result.output['ok'] != true) {
      return const [];
    }
    final artifactId = result.output['artifactId'];
    final title = result.output['title'];
    final type = result.output['type'];
    if (artifactId is! String || title is! String) {
      return const [];
    }
    if (type == ArtifactType.webApp.name) {
      return [MessageBlock.webAppCard(artifactId, title)];
    }
    return [MessageBlock.artifactCard(artifactId, title)];
  }

  Future<void> _appendFinalAnswerAfterBudgetStop({
    required String reason,
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> modelMessages,
    required AddAgentMessage addMessage,
    required ReplaceAgentMessage replaceMessage,
    required NotifyAgentLoopChange notifyChange,
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
    try {
      AppLogger.info('agent_loop.final_answer.start', {'reason': reason});
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
    } on Object catch (error) {
      replaceMessage(
        assistantMessageId,
        _modelErrorResponse('工具预算耗尽后生成最终回答失败：$error'),
      );
      notifyChange();
      return;
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
    }
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

  AgentMessage _modelErrorResponse(String detail) {
    return AgentMessage(
      id: 'msg-model-error-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.error('模型调用失败', detail)],
    );
  }
}
