class TokenUsageRecord {
  const TokenUsageRecord({
    required this.id,
    required this.workspaceId,
    required this.runId,
    required this.providerId,
    required this.modelName,
    required this.inputTokens,
    required this.reservedOutputTokens,
    required this.maxContextTokens,
    required this.isConservativeEstimate,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final String workspaceId;
  final String runId;
  final String providerId;
  final String modelName;
  final int inputTokens;
  final int reservedOutputTokens;
  final int maxContextTokens;
  final bool isConservativeEstimate;
  final DateTime startedAt;
  final DateTime endedAt;

  int get totalTokens => inputTokens + reservedOutputTokens;

  Duration get duration {
    final value = endedAt.difference(startedAt);
    if (value.isNegative) {
      return Duration.zero;
    }
    return value;
  }
}

class TokenUsageDailyBucket {
  const TokenUsageDailyBucket({
    required this.day,
    required this.tokens,
    required this.runCount,
  });

  final DateTime day;
  final int tokens;
  final int runCount;
}

class TokenUsageModelBucket {
  const TokenUsageModelBucket({
    required this.name,
    required this.tokens,
    required this.runCount,
  });

  final String name;
  final int tokens;
  final int runCount;
}

class TokenUsageStats {
  const TokenUsageStats({
    required this.totalTokens,
    required this.peakRunTokens,
    required this.longestDuration,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.totalRuns,
    required this.averageTokensPerRun,
    required this.conservativeEstimateRatio,
    required this.dailyBuckets,
    required this.modelBuckets,
  });

  final int totalTokens;
  final int peakRunTokens;
  final Duration longestDuration;
  final int currentStreakDays;
  final int longestStreakDays;
  final int totalRuns;
  final int averageTokensPerRun;
  final double conservativeEstimateRatio;
  final List<TokenUsageDailyBucket> dailyBuckets;
  final List<TokenUsageModelBucket> modelBuckets;

  static TokenUsageStats fromRecords(
    List<TokenUsageRecord> records, {
    DateTime? now,
  }) {
    final today = _dayOf(now ?? DateTime.now());
    if (records.isEmpty) {
      return TokenUsageStats(
        totalTokens: 0,
        peakRunTokens: 0,
        longestDuration: Duration.zero,
        currentStreakDays: 0,
        longestStreakDays: 0,
        totalRuns: 0,
        averageTokensPerRun: 0,
        conservativeEstimateRatio: 0,
        dailyBuckets: _emptyDailyBuckets(today),
        modelBuckets: const [],
      );
    }

    var totalTokens = 0;
    var peakRunTokens = 0;
    var longestDuration = Duration.zero;
    var conservativeCount = 0;
    final daily = <DateTime, _MutableDailyBucket>{};
    final models = <String, _MutableModelBucket>{};

    for (final record in records) {
      final tokens = record.totalTokens;
      totalTokens += tokens;
      if (tokens > peakRunTokens) {
        peakRunTokens = tokens;
      }
      if (record.duration > longestDuration) {
        longestDuration = record.duration;
      }
      if (record.isConservativeEstimate) {
        conservativeCount += 1;
      }
      final day = _dayOf(record.startedAt);
      daily.putIfAbsent(day, () => _MutableDailyBucket()).add(tokens);
      final modelName = record.modelName.trim().isEmpty
          ? record.providerId
          : record.modelName.trim();
      models.putIfAbsent(modelName, () => _MutableModelBucket()).add(tokens);
    }

    final activeDays = daily.keys.toSet();
    final dailyBuckets = _dailyBuckets(today, daily);
    final modelBuckets =
        models.entries
            .map(
              (entry) => TokenUsageModelBucket(
                name: entry.key,
                tokens: entry.value.tokens,
                runCount: entry.value.runCount,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final byTokens = b.tokens.compareTo(a.tokens);
            if (byTokens != 0) {
              return byTokens;
            }
            return a.name.compareTo(b.name);
          });

    return TokenUsageStats(
      totalTokens: totalTokens,
      peakRunTokens: peakRunTokens,
      longestDuration: longestDuration,
      currentStreakDays: _currentStreakDays(today, activeDays),
      longestStreakDays: _longestStreakDays(activeDays),
      totalRuns: records.length,
      averageTokensPerRun: (totalTokens / records.length).round(),
      conservativeEstimateRatio: conservativeCount / records.length,
      dailyBuckets: dailyBuckets,
      modelBuckets: modelBuckets,
    );
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static List<TokenUsageDailyBucket> _emptyDailyBuckets(DateTime today) {
    return _dailyBuckets(today, const {});
  }

  static List<TokenUsageDailyBucket> _dailyBuckets(
    DateTime today,
    Map<DateTime, _MutableDailyBucket> daily,
  ) {
    final start = today.subtract(const Duration(days: 364));
    return List.generate(365, (index) {
      final day = start.add(Duration(days: index));
      final bucket = daily[day];
      return TokenUsageDailyBucket(
        day: day,
        tokens: bucket?.tokens ?? 0,
        runCount: bucket?.runCount ?? 0,
      );
    }, growable: false);
  }

  static int _currentStreakDays(DateTime today, Set<DateTime> activeDays) {
    var cursor = today;
    var streak = 0;
    while (activeDays.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int _longestStreakDays(Set<DateTime> activeDays) {
    if (activeDays.isEmpty) {
      return 0;
    }
    final sorted = activeDays.toList(growable: false)..sort();
    var longest = 1;
    var current = 1;
    for (var index = 1; index < sorted.length; index += 1) {
      final previous = sorted[index - 1];
      final day = sorted[index];
      if (day.difference(previous).inDays == 1) {
        current += 1;
      } else {
        current = 1;
      }
      if (current > longest) {
        longest = current;
      }
    }
    return longest;
  }
}

class _MutableDailyBucket {
  int tokens = 0;
  int runCount = 0;

  void add(int value) {
    tokens += value;
    runCount += 1;
  }
}

class _MutableModelBucket {
  int tokens = 0;
  int runCount = 0;

  void add(int value) {
    tokens += value;
    runCount += 1;
  }
}
