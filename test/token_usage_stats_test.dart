import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/usage/token_usage.dart';

void main() {
  test('aggregates token usage records into profile stats', () {
    final now = DateTime(2026, 6, 12, 10);
    final records = [
      _record(
        id: '1',
        modelName: 'qwen-flash',
        inputTokens: 1000,
        reservedOutputTokens: 500,
        startedAt: DateTime(2026, 6, 10, 9),
        endedAt: DateTime(2026, 6, 10, 9, 3),
      ),
      _record(
        id: '2',
        modelName: 'qwen-flash',
        inputTokens: 2000,
        reservedOutputTokens: 500,
        startedAt: DateTime(2026, 6, 11, 9),
        endedAt: DateTime(2026, 6, 11, 9, 9),
      ),
      _record(
        id: '3',
        modelName: 'gemma-local',
        inputTokens: 500,
        reservedOutputTokens: 300,
        startedAt: DateTime(2026, 6, 12, 9),
        endedAt: DateTime(2026, 6, 12, 9, 1),
        conservative: false,
      ),
    ];

    final stats = TokenUsageStats.fromRecords(records, now: now);

    expect(stats.totalTokens, 4800);
    expect(stats.peakRunTokens, 2500);
    expect(stats.longestDuration, const Duration(minutes: 9));
    expect(stats.currentStreakDays, 3);
    expect(stats.longestStreakDays, 3);
    expect(stats.averageTokensPerRun, 1600);
    expect(stats.conservativeEstimateRatio, closeTo(2 / 3, 0.001));
    expect(stats.modelBuckets.first.name, 'qwen-flash');
    expect(stats.modelBuckets.first.runCount, 2);
  });
}

TokenUsageRecord _record({
  required String id,
  required String modelName,
  required int inputTokens,
  required int reservedOutputTokens,
  required DateTime startedAt,
  required DateTime endedAt,
  bool conservative = true,
}) {
  return TokenUsageRecord(
    id: id,
    workspaceId: 'default',
    runId: 'run-$id',
    providerId: 'provider',
    modelName: modelName,
    inputTokens: inputTokens,
    reservedOutputTokens: reservedOutputTokens,
    maxContextTokens: 32768,
    isConservativeEstimate: conservative,
    startedAt: startedAt,
    endedAt: endedAt,
  );
}
