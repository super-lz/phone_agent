import '../../data/capabilities/web_capability_adapter.dart';
import 'capability_execution_result.dart';

class WebCapabilityHandler {
  WebCapabilityHandler({WebCapabilityAdapter? webAdapter})
    : _webAdapter = webAdapter ?? WebCapabilityAdapter();

  final WebCapabilityAdapter _webAdapter;

  Future<CapabilityExecutionResult> search({
    required Map<String, Object?> arguments,
    required String? apiKey,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'web.search',
      output: await _webAdapter.search(arguments, apiKey: apiKey),
    );
  }

  Future<CapabilityExecutionResult> fetch({
    required Map<String, Object?> arguments,
    required String? apiKey,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'web.fetch',
      output: await _webAdapter.fetch(arguments, apiKey: apiKey),
    );
  }
}
