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
    required this.workspaceId,
    required this.capabilityId,
    required this.input,
    required this.status,
    required this.createdAt,
    this.permissionDecision,
    this.output,
    this.error,
  });

  final String id;
  final String workspaceId;
  final String capabilityId;
  final Map<String, Object?> input;
  final CapabilityInvocationStatus status;
  final DateTime createdAt;
  final String? permissionDecision;
  final Map<String, Object?>? output;
  final String? error;
}

enum CapabilityInvocationStatus { pending, approved, completed, denied, failed }

class McpConnection {
  const McpConnection({
    required this.url,
    required this.transport,
    required this.createdAt,
  });

  final String url;
  final String transport;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'url': url,
    'transport': transport,
    'createdAt': createdAt.toIso8601String(),
  };

  factory McpConnection.fromJson(Map<String, Object?> json) => McpConnection(
    url: json['url']! as String,
    transport: json['transport']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
  );
}

class AgentSkill {
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.script,
    required this.createdAt,
    this.manifestPath,
  });

  final String id;
  final String name;
  final String description;
  final String script;
  final DateTime createdAt;
  final String? manifestPath;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'script': script,
    'createdAt': createdAt.toIso8601String(),
    'manifestPath': manifestPath,
  };

  factory AgentSkill.fromJson(Map<String, Object?> json) => AgentSkill(
    id: json['id']! as String,
    name: json['name']! as String,
    description: json['description']! as String,
    script: json['script']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    manifestPath: json['manifestPath'] as String?,
  );
}
