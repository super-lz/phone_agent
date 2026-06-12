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
import '../capabilities/capability_runtime.dart';
import '../capabilities/mcp_manager.dart';
import '../capabilities/tool_prompt_registry.dart';
import 'agent_loop_budget.dart';
import 'agent_run_state.dart';
import 'context_budget.dart';
import 'conversation_context_builder.dart';
import 'final_response_guard.dart';
import 'tool_call_accumulator.dart';
import 'tool_display_names.dart';
import 'tool_router.dart';
import 'web_app_jsbridge_guide.dart';

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
  final ContextBudgetPlanner _contextBudgetPlanner =
      const ContextBudgetPlanner();

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
    ContextBudgetSnapshot? contextBudget;

    void report(AgentRunPhase phase, String detail, {String? currentToolName}) {
      reportRunSnapshot?.call(
        AgentRunSnapshot(
          phase: phase,
          detail: detail,
          toolCallsUsed: runState.toolCallsUsed,
          maxToolCalls: budget.maxToolCalls,
          startedAt: startedAt,
          currentToolName: currentToolName,
          contextBudget: contextBudget,
        ),
      );
    }

    void throwIfCancelled() {
      runControl?.throwIfCancelled();
    }

    final firstAssistantMessageId =
        'msg-model-${DateTime.now().microsecondsSinceEpoch}-0';

    void publishInitialProcess() {
      replaceMessage(
        firstAssistantMessageId,
        AgentMessage(
          id: firstAssistantMessageId,
          role: MessageRole.assistant,
          createdAt: DateTime.now(),
          blocks: [MessageBlock.intermediateMarkdown('正在分析请求并规划下一步。')],
        ),
      );
      notifyChange();
    }

    report(AgentRunPhase.thinking, '正在处理您的请求...');
    publishInitialProcess();
    final latestRoutingPrompt = _extractTextForRouting(prompt);
    final routingContext = _routingContextText(
      priorMessages: priorMessages,
      allSkills: allSkills,
    );

    report(AgentRunPhase.routing, '正在分析这次请求。');
    final routingStopwatch = Stopwatch()..start();
    final toolRoute = await _toolRouter.route(
      prompt: latestRoutingPrompt,
      context: routingContext,
      allTools: _capabilityRuntime.toolDefinitions,
      chatClient: _chatClient,
      provider: provider,
      apiKey: apiKey,
    );
    routingStopwatch.stop();
    AppLogger.info('agent_loop.routing.completed', {
      'durationMs': routingStopwatch.elapsedMilliseconds,
      'selectedTools': toolRoute.selectedToolNames,
      'requiredTools': toolRoute.requiredToolNames,
    });

    final buildMessagesStopwatch = Stopwatch()..start();
    final modelMessageResult = await _buildModelMessages(
      prompt: prompt,
      workspace: workspace,
      visibleMemories: visibleMemories,
      priorMessages: priorMessages,
      toolIndex: toolRoute.index,
      toolSchema: toolRoute.tools,
      chatClient: _chatClient,
      provider: provider,
      apiKey: apiKey,
    );
    buildMessagesStopwatch.stop();
    AppLogger.info('agent_loop.build_messages.completed', {
      'durationMs': buildMessagesStopwatch.elapsedMilliseconds,
      'messageCount': modelMessageResult.messages.length,
      'usedSummary': modelMessageResult.usedSummary,
    });

    final modelMessages = modelMessageResult.messages;
    contextBudget = modelMessageResult.contextBudget;
    if (contextBudget.exceedsWindow) {
      throw ContextBudgetExceededException(contextBudget);
    }
    report(
      AgentRunPhase.routing,
      modelMessageResult.usedSummary ? '已压缩早期上下文，正在组织回答。' : '已整理上下文，正在组织回答。',
    );

    final currentTurnToolResults = <CapabilityExecutionResult>[];
    var requiredToolCorrectionAttempts = 0;
    var rawFinalCorrectionAttempts = 0;
    var accumulatedProcessBlocks = <MessageBlock>[];

    for (var round = 0; round < budget.maxModelRounds; round += 1) {
      throwIfCancelled();

      final assistantMessageId = firstAssistantMessageId;
      final contentBuffer = StringBuffer();
      final toolCalls = ToolCallAccumulator();
      final processBlocks = <MessageBlock>[
        ...accumulatedProcessBlocks,
        MessageBlock.intermediateMarkdown(
          round == 0 ? '正在分析请求并规划下一步。' : '正在根据工具结果继续处理。',
        ),
      ];
      var isPreparingToolCall = false;
      var preparingToolName = '';
      var toolArgumentChars = 0;
      var retryAttempts = 0;
      var hasReceivedContentDelta = false;
      var hasReceivedToolCallDelta = false;

      void publishProcessBlocks() {
        replaceMessage(
          assistantMessageId,
          AgentMessage(
            id: assistantMessageId,
            role: MessageRole.assistant,
            createdAt: DateTime.now(),
            blocks: List<MessageBlock>.of(processBlocks),
          ),
        );
        notifyChange();
      }

      void publishToolPreparation(String detail) {
        processBlocks
          ..clear()
          ..addAll(accumulatedProcessBlocks);
        final content = stripInternalToolProgressText(
          contentBuffer.toString(),
        ).trim();
        if (content.isNotEmpty) {
          processBlocks.add(MessageBlock.intermediateMarkdown(content));
        }
        processBlocks.add(MessageBlock.intermediateMarkdown(detail));
        publishProcessBlocks();
      }

      publishProcessBlocks();

      // START MODEL STREAMING
      final streamStopwatch = Stopwatch()..start();
      var firstTokenLatency = 0;
      var hasReceivedFirstToken = false;

      while (true) {
        throwIfCancelled();
        report(AgentRunPhase.modelStreaming, '正在思考...');

        try {
          await for (final event in _chatClient.streamChat(
            provider: provider,
            apiKey: apiKey,
            messages: modelMessages,
            tools: provider.supportsTools && runState.canUseTools
                ? toolRoute.tools
                : const [],
          )) {
            throwIfCancelled();

            if (!hasReceivedFirstToken &&
                (event.contentDelta.isNotEmpty ||
                    event.toolCallDeltas.isNotEmpty)) {
              hasReceivedFirstToken = true;
              firstTokenLatency = streamStopwatch.elapsedMilliseconds;
              AppLogger.info('agent_loop.stream.first_token', {
                'latencyMs': firstTokenLatency,
                'round': round,
              });
            }

            if (event.toolCallDeltas.isNotEmpty) {
              hasReceivedToolCallDelta = true;
              isPreparingToolCall = true;
              for (final delta in event.toolCallDeltas) {
                final name = delta.name;
                if (name != null && name.trim().isNotEmpty) {
                  preparingToolName = name.trim();
                }
                toolArgumentChars += delta.argumentsDelta?.length ?? 0;
              }
              final detail = _toolPreparationDetail(
                preparingToolName,
                toolArgumentChars,
              );
              report(
                AgentRunPhase.waitingForToolCall,
                detail,
                currentToolName: preparingToolName.isEmpty
                    ? null
                    : preparingToolName,
              );
              toolCalls.applyAll(event.toolCallDeltas);
              publishToolPreparation(detail);
            }

            if (event.contentDelta.isNotEmpty) {
              hasReceivedContentDelta = true;
              contentBuffer.write(event.contentDelta);

              if (!isPreparingToolCall) {
                final visibleText = stripInternalToolProgressText(
                  contentBuffer.toString(),
                );
                if (toolRoute.tools.isNotEmpty &&
                    looksLikePseudoToolCallText(visibleText)) {
                  replaceMessage(
                    assistantMessageId,
                    _assistantIntermediateMessage(
                      assistantMessageId,
                      '模型正在输出内部工具调用格式，系统已拦截，正在要求改用真实工具调用。',
                    ),
                  );
                  notifyChange();
                  continue;
                }
                if (visibleText.trim().isEmpty &&
                    looksLikeInternalToolProgressText(
                      contentBuffer.toString(),
                    )) {
                  report(
                    AgentRunPhase.waitingForToolCall,
                    '正在接收工具参数，参数完整后会立即执行。',
                  );
                  continue;
                }
                replaceMessage(
                  assistantMessageId,
                  _assistantFinalMessage(
                    assistantMessageId,
                    visibleText,
                    processBlocks,
                  ),
                );
                notifyChange();
              } else {
                final detail = _toolPreparationDetail(
                  preparingToolName,
                  toolArgumentChars,
                );
                publishToolPreparation(detail);
              }
            }
          }
          streamStopwatch.stop();
          AppLogger.info('agent_loop.stream.completed', {
            'durationMs': streamStopwatch.elapsedMilliseconds,
            'firstTokenLatencyMs': firstTokenLatency,
            'round': round,
            'contentLength': contentBuffer.length,
            'toolCallCount': toolCalls.toRequests().length,
          });
          break;
        } on ModelRequestException catch (error) {
          throwIfCancelled();
          if (_shouldRetryModelStream(
            error: error,
            retryAttempts: retryAttempts,
            hasReceivedContentDelta: hasReceivedContentDelta,
          )) {
            retryAttempts += 1;
            if (hasReceivedToolCallDelta) {
              toolCalls.clear();
              isPreparingToolCall = false;
              preparingToolName = '';
              toolArgumentChars = 0;
              hasReceivedToolCallDelta = false;
              publishToolPreparation('工具参数流连接中断，正在重新发起模型请求。');
            }
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
                stripInternalToolProgressText(contentBuffer.toString()),
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
          final finalText = stripInternalToolProgressText(
            contentBuffer.toString(),
          );
          final looksLikePseudoToolCall = looksLikePseudoToolCallText(
            finalText,
          );
          if (finalText.trim().isEmpty &&
              _requiredToolsSatisfied(toolRoute, currentTurnToolResults)) {
            replaceMessage(
              assistantMessageId,
              _modelErrorResponse('模型只返回了内部工具参数进度，没有返回可展示内容。请重试本轮请求。'),
            );
            notifyChange();
            report(AgentRunPhase.failed, '模型没有返回可展示内容');
            return;
          }
          if (!_requiredToolsSatisfied(toolRoute, currentTurnToolResults)) {
            if (looksLikePseudoToolCallText(finalText) &&
                toolRoute.tools.isNotEmpty &&
                provider.supportsTools &&
                runState.canUseTools &&
                rawFinalCorrectionAttempts < 1) {
              rawFinalCorrectionAttempts += 1;
              replaceMessage(
                assistantMessageId,
                _assistantIntermediateMessage(
                  assistantMessageId,
                  '模型输出了不会执行的伪工具调用标签，系统已拦截，正在要求改用真实工具调用。',
                ),
              );
              modelMessages
                ..add({
                  'role': 'assistant',
                  'content': '[上一轮把伪工具调用标签作为正文输出，系统未执行这些标签。]',
                })
                ..add({
                  'role': 'user',
                  'content':
                      '你刚才把 <tool_call>、<function=...> 或 <parameter=...> '
                      '当作普通正文输出了。正文里的伪工具标签不会被系统执行。'
                      '请立即使用当前 tools schema 发起真实 tool call；'
                      '不要再输出伪工具标签、原始参数或工具调用文本。'
                      '如果无法调用真实工具，请明确说明哪些动作尚未执行。',
                });
              notifyChange();
              continue;
            }
            if (requiredToolCorrectionAttempts < 2) {
              requiredToolCorrectionAttempts += 1;
              replaceMessage(
                assistantMessageId,
                _assistantIntermediateMessage(
                  assistantMessageId,
                  looksLikePseudoToolCall
                      ? '模型输出了不会执行的伪工具调用标签，系统已拦截。'
                      : finalText,
                ),
              );
              modelMessages
                ..add({
                  'role': 'assistant',
                  'content': looksLikePseudoToolCall
                      ? '[上一轮把伪工具调用标签作为正文输出，系统未执行这些标签。]'
                      : finalText,
                })
                ..add({
                  'role': 'user',
                  'content': looksLikePseudoToolCall
                      ? '本轮存在必须完成的工具动作：'
                            '${_requiredToolDisplayNames(toolRoute.requiredToolNames)}。'
                            '你刚才把工具调用写成了正文里的伪标签，这些标签没有被执行。'
                            '请使用当前 tools schema 发起真实 tool call；'
                            '如果无法调用，请明确说明哪些动作尚未完成。'
                      : '本轮存在必须完成的工具动作：'
                            '${_requiredToolDisplayNames(toolRoute.requiredToolNames)}。'
                            '在这些动作成功执行前，不能声称任务已经完成、内容已经保存、'
                            '产物已经创建或可以预览。请立即调用缺失的必需工具；'
                            '如果无法调用，请明确说明哪些动作尚未完成。',
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

          if ((currentTurnToolResults.isNotEmpty ||
                  looksLikePseudoToolCall && toolRoute.tools.isNotEmpty) &&
              looksLikeRawToolProcess(finalText) &&
              rawFinalCorrectionAttempts < 1) {
            rawFinalCorrectionAttempts += 1;
            replaceMessage(
              assistantMessageId,
              _assistantIntermediateMessage(
                assistantMessageId,
                looksLikePseudoToolCall
                    ? '模型输出了不会执行的伪工具调用标签，系统已拦截，正在要求改用真实工具调用或给出可读结论。'
                    : finalText,
              ),
            );
            modelMessages
              ..add({
                'role': 'assistant',
                'content': looksLikePseudoToolCall
                    ? '[上一轮把伪工具调用标签作为正文输出，系统未执行这些标签。]'
                    : finalText,
              })
              ..add({
                'role': 'user',
                'content': looksLikePseudoToolCall
                    ? '上一条回复输出了 <tool_call>、<function=...> 或 <parameter=...> '
                          '这类伪工具标签。正文里的伪工具标签不会被执行，不能作为最终回答。'
                          '如果还需要执行动作，请使用当前 tools schema 发起真实 tool call；'
                          '如果不需要执行动作，请生成面向用户的自然语言结论。'
                          '不要出现伪工具标签、工具调用文本、原始 JSON、Map 或 capability 字段。'
                    : '上一条回复复述了工具调用过程或原始结构化结果，不能作为最终回答。'
                          '请基于已有 observation 重新生成面向用户的自然语言结论，'
                          '不要出现工具调用、工具结果、原始 JSON、Map 或 capability 字段。',
              });
            notifyChange();
            continue;
          }

          if (looksLikePseudoToolCall && toolRoute.tools.isNotEmpty) {
            replaceMessage(
              assistantMessageId,
              _modelErrorResponse('模型把工具调用标签输出成了普通正文，系统没有执行这些标签。请重试本轮请求。'),
            );
            notifyChange();
            report(AgentRunPhase.failed, '模型输出了未执行的伪工具调用');
            return;
          }

          replaceMessage(
            assistantMessageId,
            _assistantFinalMessage(
              assistantMessageId,
              finalText,
              processBlocks,
            ),
          );
          notifyChange();
        }
        report(AgentRunPhase.completed, '已完成');
        return;
      }

      // CASE 2: TOOL CALLS -> EXECUTE THEM
      report(AgentRunPhase.executingTool, '正在执行工具...');
      final visibleContent = stripInternalToolProgressText(
        contentBuffer.toString(),
      );

      modelMessages.add({
        'role': 'assistant',
        'content': visibleContent,
        'tool_calls': requests
            .map((r) => r.toAssistantMessageToolCall())
            .toList(growable: false),
      });

      processBlocks
        ..clear()
        ..addAll(accumulatedProcessBlocks);
      if (visibleContent.trim().isNotEmpty) {
        processBlocks.add(MessageBlock.intermediateMarkdown(visibleContent));
      } else {
        processBlocks.add(MessageBlock.intermediateMarkdown('已确定执行步骤，开始调用工具。'));
      }
      publishProcessBlocks();

      void publishToolProcess() {
        replaceMessage(
          assistantMessageId,
          AgentMessage(
            id: assistantMessageId,
            role: MessageRole.assistant,
            createdAt: DateTime.now(),
            blocks: List<MessageBlock>.of(processBlocks),
          ),
        );
        notifyChange();
      }

      for (final request in requests) {
        throwIfCancelled();
        report(
          AgentRunPhase.executingTool,
          '正在执行 ${request.name}...',
          currentToolName: request.name,
        );

        processBlocks.add(
          MessageBlock.toolCall(request.name, request.arguments),
        );
        publishToolProcess();

        if (_hasInvalidToolArguments(request)) {
          final result = _invalidToolArgumentsResult(request);
          runState.recordToolResult(false);
          currentTurnToolResults.add(result);
          processBlocks.add(
            MessageBlock.toolResult(result.capabilityId, result.output),
          );
          publishToolProcess();
          modelMessages.add({
            'role': 'tool',
            'tool_call_id': request.id,
            'name': request.name,
            'content': result.encodedModelObservation,
          });
          continue;
        }

        if (!runState.canStartToolCall) {
          final result = _toolBudgetExceededResult(request, runState);
          currentTurnToolResults.add(result);
          processBlocks.add(
            MessageBlock.toolResult(result.capabilityId, result.output),
          );
          publishToolProcess();
          modelMessages.add({
            'role': 'tool',
            'tool_call_id': request.id,
            'name': request.name,
            'content': result.encodedModelObservation,
          });
          continue;
        }

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

        processBlocks.add(
          MessageBlock.toolResult(result.capabilityId, result.output),
        );

        if (result.output['error'] == 'permission_confirmation_required') {
          processBlocks.add(
            MessageBlock.approvalRequest(
              requestId: '$assistantMessageId-${request.id}',
              toolName: request.name,
              capabilityId: result.capabilityId,
              workspaceId: activeWorkspaceId,
              input: request.arguments,
              detail: result.output['detail'] as String? ?? '需要授权',
              userPrompt: latestRoutingPrompt,
            ),
          );
        }

        processBlocks.addAll(_artifactBlocksFor(result));
        publishToolProcess();

        if (result.output['error'] == 'permission_confirmation_required') {
          report(AgentRunPhase.completed, '等待用户授权');
          return;
        }

        modelMessages.add({
          'role': 'tool',
          'tool_call_id': request.id,
          'name': request.name,
          'content': result.encodedModelObservation,
        });
      }
      accumulatedProcessBlocks = List<MessageBlock>.of(processBlocks);
    }

    addMessage(
      _modelErrorResponse(
        '任务已达到本轮最大模型轮次 ${budget.maxModelRounds} 轮，'
        '系统已停止继续自动调用，避免无限循环。请根据上方执行过程调整请求后重试。',
      ),
    );
    notifyChange();
    report(AgentRunPhase.failed, '任务轮次已达上限');
  }

  bool _hasInvalidToolArguments(ToolCallRequest request) {
    return request.arguments['_parseError'] == 'invalid_json';
  }

  CapabilityExecutionResult _invalidToolArgumentsResult(
    ToolCallRequest request,
  ) {
    return CapabilityExecutionResult(
      capabilityId: CapabilityRuntime.capabilityIdForToolNameOrFallback(
        request.name,
      ),
      output: {
        'ok': false,
        'error': 'invalid_tool_arguments',
        'detail': '工具参数不是有效 JSON，未执行真实能力；请重新生成完整参数后再调用。',
        'tool': request.name,
      },
    );
  }

  CapabilityExecutionResult _toolBudgetExceededResult(
    ToolCallRequest request,
    AgentLoopRunState runState,
  ) {
    final detail = runState.stopReason.isEmpty
        ? '已达到本轮任务预算，系统停止继续执行工具。'
        : runState.stopReason;
    return CapabilityExecutionResult(
      capabilityId: CapabilityRuntime.capabilityIdForToolNameOrFallback(
        request.name,
      ),
      output: {
        'ok': false,
        'error': 'tool_budget_exceeded',
        'detail': detail,
        'tool': request.name,
      },
    );
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
        .where(
          (text) =>
              message.role != MessageRole.assistant ||
              !looksLikeRawToolProcess(text),
        )
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

  Future<_ModelMessagesBuildResult> _buildModelMessages({
    required Object prompt,
    required AgentWorkspace workspace,
    required List<AgentMemory> visibleMemories,
    required List<AgentMessage> priorMessages,
    required String toolIndex,
    required List<Map<String, Object?>> toolSchema,
    OpenAiCompatibleChatClient? chatClient,
    ModelProviderConfig? provider,
    String? apiKey,
  }) async {
    final memories = visibleMemories
        .map((memory) => '- ${memory.content}')
        .join('\n');
    final currentTime = _currentTimeContext(DateTime.now());
    final systemPrompt = _buildSystemPrompt(
      workspace: workspace,
      currentTime: currentTime,
      memories: memories,
      toolIndex: toolIndex,
    );
    final budgetPlan = _contextBudgetPlanner.plan(
      provider: provider ?? ModelProviders.aliyunBailianQwenFlash,
      systemPrompt: systemPrompt,
      toolIndex: toolIndex,
      toolSchema: toolSchema,
      prompt: prompt,
      priorMessages: priorMessages,
    );
    final conversationContext =
        await ConversationContextBuilder(
          maxRecentChars: budgetPlan.maxRecentChars,
          maxSummaryChars: budgetPlan.maxSummaryChars,
        ).build(
          messages: priorMessages,
          chatClient: chatClient,
          provider: provider,
          apiKey: apiKey,
        );
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': systemPrompt},
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
    final contextBudget = _contextBudgetPlanner.snapshotForParts(
      provider: provider ?? ModelProviders.aliyunBailianQwenFlash,
      prompt: prompt,
      systemPrompt: systemPrompt,
      toolIndex: toolIndex,
      toolSchema: toolSchema,
      summary: conversationContext.summary,
      recentHistory: conversationContext.recentEntries
          .map((entry) => entry.content)
          .join('\n'),
    );
    return _ModelMessagesBuildResult(
      messages: messages,
      contextBudget: contextBudget,
      usedSummary: conversationContext.summary.isNotEmpty,
    );
  }

  String _buildSystemPrompt({
    required AgentWorkspace workspace,
    required String currentTime,
    required String memories,
    required String toolIndex,
  }) {
    final memoryBlock = memories.isEmpty ? '- 暂无' : memories;
    final shouldIncludeJsBridgeSkill =
        toolIndex.contains('project_create_web_app') ||
        toolIndex.contains('project_update_web_app') ||
        toolIndex.contains('project_test_web_app') ||
        toolIndex.contains('artifact_create');
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
      '- 工具参数生成进度是系统内部状态，不要在正文里说“已接收约 N 字符”或复述参数接收进度。',
      '- 如果工具结果包含 summary 或 userMessage，优先把它转成用户能理解的结论和下一步。',
      '- 可以连续调用工具完成复杂任务，但证据足够后要及时总结，避免重复调用。',
      '</operating_principles>',
      '',
      '<capability_index>',
      toolIndex,
      '',
      ToolPromptRegistry.generateCapabilityIndex(toolIndex),
      '</capability_index>',
      '',
      '<workflow_contracts>',
      ToolPromptRegistry.generateWorkflowContracts(toolIndex),
      '</workflow_contracts>',
      '',
      '<web_app_contract>',
      '- 创建小游戏、交互网页、Web App、原型或本地可维护项目时，必须调用 project_create_web_app 写入真实工程文件并创建 Web App Artifact。',
      '- project_create_web_app 和 project_update_web_app 会自动执行受控静态检查，并在工具结果 test 中返回结论；刚创建或刚更新同一项目后，不要为了同一结果立刻重复调用 project_test_web_app。',
      '- 只有用户明确要求复测，或维护已有 Web App 且需要单独确认当前状态时，才调用 project_test_web_app；优先使用工具结果返回的 artifactId。',
      '- project_create_web_app 成功前，不得说“已创建”“可预览”“文件已保存”或提示用户点击不存在的卡片。',
      '- Web App 默认按本地工程组织；除极小页面外，入口 HTML、样式、脚本应拆成可维护文件。',
      '- 默认按手机竖屏、触摸交互、360-430px 宽度、安全区域和移动端性能设计；不要生成桌面优先、多列侧栏、依赖 hover 或密集小字号的布局。',
      '- 大段 HTML/CSS/JS 放入 project_create_web_app 或 file_write_app_file 的工具参数，不要先在聊天正文中流式输出完整源码。',
      '- Web App 需要手机能力时，必须在 permissions 中声明精确 capability id，并通过 window.PhoneAgent.getManifest() / window.PhoneAgent.callCapability(id, input) 调用。',
      ToolPromptRegistry.generateJsBridgeApis(),
      '- 用户反馈已生成 Web App 的问题时，先读取 .phone-agent/runtime.log 和相关项目文件，再定位并修复。',
      '</web_app_contract>',
      '',
      if (shouldIncludeJsBridgeSkill) ...[
        '<jsbridge_skill>',
        webAppJsBridgeGuide,
        '</jsbridge_skill>',
        '',
      ],
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
    required bool hasReceivedContentDelta,
  }) {
    return error.isRetryable && retryAttempts < 1 && !hasReceivedContentDelta;
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

  String _toolPreparationDetail(String toolName, int argumentChars) {
    final sizeStr = _formatChars(argumentChars);
    final progress = argumentChars > 0 ? '（已生成 $sizeStr）' : '';
    return switch (toolName) {
      'project_create_web_app' => '正在生成 Web App 文件内容$progress，参数完整后会创建项目并自动检查。',
      'project_update_web_app' => '正在生成 Web App 修改内容$progress，参数完整后会更新项目并自动检查。',
      'file_write_app_file' => '正在生成文件写入内容$progress，参数完整后会立即写入。',
      '' => '正在接收工具参数$progress，参数完整后会立即执行。',
      _ => '正在生成 ${agentToolDisplayName(toolName)} 的调用参数$progress。',
    };
  }

  String _formatChars(int chars) {
    if (chars >= 1024) {
      return '${(chars / 1024).toStringAsFixed(1)} KB';
    }
    return '$chars 字符';
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
      final capabilityId = CapabilityRuntime.capabilityIdForToolName(toolName);
      return capabilityId != null &&
          successfulCapabilityIds.contains(capabilityId);
    });
  }

  AgentMessage _assistantFinalMessage(
    String id,
    String text,
    List<MessageBlock> processBlocks,
  ) {
    final blocks = <MessageBlock>[];
    if (text.trim().isNotEmpty) {
      blocks.add(MessageBlock.markdown(text));
    }
    final foldedProcessBlocks = processBlocks
        .where(_isFoldedProcessBlock)
        .toList(growable: false);
    if (foldedProcessBlocks.any(_isMeaningfulProcessBlock)) {
      blocks.add(
        MessageBlock(
          type: MessageBlockType.taskProgress,
          data: {'blocks': foldedProcessBlocks, 'status': 'completed'},
        ),
      );
    }
    blocks.addAll(processBlocks.where(_isVisibleProcessArtifact));
    return AgentMessage(
      id: id,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: blocks,
    );
  }

  bool _isFoldedProcessBlock(MessageBlock block) {
    if (block.type == MessageBlockType.markdownText &&
        block.data['intermediate'] == true) {
      return true;
    }
    switch (block.type) {
      case MessageBlockType.toolCall:
      case MessageBlockType.toolResult:
      case MessageBlockType.approvalRequest:
      case MessageBlockType.citation:
        return true;
      case MessageBlockType.markdownText:
      case MessageBlockType.codeBlock:
      case MessageBlockType.image:
      case MessageBlockType.fileAttachment:
      case MessageBlockType.taskProgress:
      case MessageBlockType.todoList:
      case MessageBlockType.artifactCard:
      case MessageBlockType.webAppCard:
      case MessageBlockType.errorCard:
        return false;
    }
  }

  bool _isMeaningfulProcessBlock(MessageBlock block) {
    return switch (block.type) {
      MessageBlockType.toolCall ||
      MessageBlockType.toolResult ||
      MessageBlockType.approvalRequest ||
      MessageBlockType.citation => true,
      MessageBlockType.markdownText ||
      MessageBlockType.codeBlock ||
      MessageBlockType.image ||
      MessageBlockType.fileAttachment ||
      MessageBlockType.taskProgress ||
      MessageBlockType.todoList ||
      MessageBlockType.artifactCard ||
      MessageBlockType.webAppCard ||
      MessageBlockType.errorCard => false,
    };
  }

  bool _isVisibleProcessArtifact(MessageBlock block) {
    return block.type == MessageBlockType.artifactCard ||
        block.type == MessageBlockType.webAppCard;
  }

  AgentMessage _assistantIntermediateMessage(String id, String text) {
    final content = text.trim().isEmpty ? '正在继续处理。' : text;
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
    final visibleText = partialText.trim();
    return AgentMessage(
      id: id,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        if (visibleText.isNotEmpty) MessageBlock.markdown(visibleText),
        MessageBlock.error('模型连接中断', detail),
      ],
    );
  }

  AgentMessage _requiredToolErrorResponse(
    String id,
    List<String> requiredToolNames,
  ) {
    final requiredTools = _requiredToolDisplayNames(requiredToolNames);
    return AgentMessage(
      id: id,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.error(
          '必需动作未完成',
          '必需工具没有成功完成：$requiredTools。'
              '系统已阻止模型把未完成的创建、保存、切换、预览或其它必须执行动作当作成功结果展示。',
        ),
      ],
    );
  }

  String _requiredToolDisplayNames(List<String> requiredToolNames) {
    return requiredToolNames.map(agentToolDisplayName).join('、');
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

class _ModelMessagesBuildResult {
  const _ModelMessagesBuildResult({
    required this.messages,
    required this.contextBudget,
    required this.usedSummary,
  });

  final List<Map<String, Object?>> messages;
  final ContextBudgetSnapshot contextBudget;
  final bool usedSummary;
}
