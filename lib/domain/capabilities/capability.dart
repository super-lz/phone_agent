enum CapabilityRisk { low, medium, high }

enum CapabilityAdapter {
  native,
  search,
  file,
  database,
  memory,
  workspace,
  artifact,
  mcp,
  skill,
  webview,
}

class CapabilityDefinition {
  const CapabilityDefinition({
    required this.id,
    required this.description,
    required this.inputSchema,
    required this.outputSchema,
    required this.risk,
    required this.requiredPermissions,
    required this.adapter,
  });

  final String id;
  final String description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final CapabilityRisk risk;
  final List<String> requiredPermissions;
  final CapabilityAdapter adapter;
}

class CapabilityInvocation {
  const CapabilityInvocation({
    required this.id,
    required this.capabilityId,
    required this.input,
    required this.status,
    this.output,
    this.error,
  });

  final String id;
  final String capabilityId;
  final Map<String, Object?> input;
  final CapabilityInvocationStatus status;
  final Map<String, Object?>? output;
  final String? error;
}

enum CapabilityInvocationStatus { pending, approved, completed, denied, failed }
