import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/context_budget.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  test('uses conservative context window when provider has no known limit', () {
    final planner = ContextBudgetPlanner();
    final snapshot = planner.snapshotForParts(
      provider: ModelProviders.openAi.copyWith(model: 'unknown-custom'),
      prompt: '你好',
      systemPrompt: 'system',
      toolIndex: '',
      summary: '',
      recentHistory: '',
    );

    expect(snapshot.maxContextTokens, conservativeContextWindowTokens);
    expect(snapshot.isConservativeFallback, isTrue);
  });

  test('dynamic plan shrinks recent history budget for large fixed prompt', () {
    final planner = ContextBudgetPlanner();
    final shortPlan = planner.plan(
      provider: ModelProviders.moonshotKimi.copyWith(model: 'moonshot-v1-8k'),
      systemPrompt: 'system',
      toolIndex: '',
      prompt: '短问题',
      priorMessages: const [],
    );
    final longPlan = planner.plan(
      provider: ModelProviders.moonshotKimi.copyWith(model: 'moonshot-v1-8k'),
      systemPrompt: 'system',
      toolIndex: '',
      prompt: '长问题' * 3000,
      priorMessages: [
        AgentMessage(
          id: 'old',
          role: MessageRole.user,
          createdAt: DateTime(2026),
          blocks: [MessageBlock.markdown('历史上下文' * 2000)],
        ),
      ],
    );

    expect(shortPlan.maxContextTokens, 8192);
    expect(longPlan.maxRecentChars, lessThan(shortPlan.maxRecentChars));
    expect(longPlan.maxRecentChars, greaterThanOrEqualTo(1200));
  });
}
