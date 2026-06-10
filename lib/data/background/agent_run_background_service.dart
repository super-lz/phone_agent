import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AgentRunBackgroundTask {
  const AgentRunBackgroundTask({
    required this.runId,
    required this.title,
    required this.detail,
  });

  final String runId;
  final String title;
  final String detail;
}

abstract interface class AgentRunBackgroundService {
  Future<void> start(AgentRunBackgroundTask task);

  Future<void> stop({String? runId});
}

class PlatformAgentRunBackgroundService implements AgentRunBackgroundService {
  PlatformAgentRunBackgroundService({
    MethodChannel channel = const MethodChannel(
      'phone_agent/agent_run_background',
    ),
    TargetPlatform? platform,
  }) : _channel = channel,
       _platform = platform;

  final MethodChannel _channel;
  final TargetPlatform? _platform;

  TargetPlatform get _effectivePlatform => _platform ?? defaultTargetPlatform;

  @override
  Future<void> start(AgentRunBackgroundTask task) async {
    if (_effectivePlatform != TargetPlatform.android) {
      return;
    }
    await _channel.invokeMethod<void>('start', {
      'runId': task.runId,
      'title': task.title,
      'detail': task.detail,
    });
  }

  @override
  Future<void> stop({String? runId}) async {
    if (_effectivePlatform != TargetPlatform.android) {
      return;
    }
    await _channel.invokeMethod<void>('stop', {'runId': ?runId});
  }
}

class NoopAgentRunBackgroundService implements AgentRunBackgroundService {
  const NoopAgentRunBackgroundService();

  @override
  Future<void> start(AgentRunBackgroundTask task) async {}

  @override
  Future<void> stop({String? runId}) async {}
}
