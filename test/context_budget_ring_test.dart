import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/context_budget.dart';
import 'package:phone_agent/features/workbench/widgets/context_budget_ring.dart';

void main() {
  testWidgets('empty context budget shows neutral idle state without numbers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ContextBudgetRing(budget: null))),
    );

    expect(find.text('--'), findsNothing);
    expect(find.text('0%'), findsNothing);
    expect(find.byIcon(Icons.donut_large_outlined), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.donut_large_outlined));
    expect(icon.size, 22);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('context budget ring shows percent with a full track painter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextBudgetRing(
            budget: const ContextBudgetSnapshot(
              providerId: 'test',
              modelName: 'test-model',
              maxContextTokens: 1000,
              isConservativeFallback: false,
              reservedOutputTokens: 100,
              systemTokens: 100,
              toolTokens: 100,
              summaryTokens: 0,
              recentHistoryTokens: 100,
              promptTokens: 100,
              inputTokens: 400,
            ),
          ),
        ),
      ),
    );

    expect(find.text('50%'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('tiny non-zero usage is shown as less than one percent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextBudgetRing(
            budget: const ContextBudgetSnapshot(
              providerId: 'test',
              modelName: 'huge-window-model',
              maxContextTokens: 1000000,
              isConservativeFallback: false,
              reservedOutputTokens: 0,
              systemTokens: 1000,
              toolTokens: 1000,
              summaryTokens: 0,
              recentHistoryTokens: 1000,
              promptTokens: 1000,
              inputTokens: 4000,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0%'), findsNothing);
    expect(find.text('<1%'), findsOneWidget);
  });
}
