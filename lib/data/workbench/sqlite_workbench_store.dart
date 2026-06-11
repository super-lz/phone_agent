import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/conversation/message_block.dart';
import '../../domain/memory/memory.dart';
import '../../domain/usage/token_usage.dart';
import '../../domain/workbench/pending_agent_run.dart';
import '../../domain/workbench/workbench_store.dart';
import '../../domain/workspace/workspace.dart';

class SqliteWorkbenchStore implements WorkbenchStore {
  SqliteWorkbenchStore() : _dbPath = null;

  SqliteWorkbenchStore.forPath(String dbPath) : _dbPath = dbPath;

  final String? _dbPath;
  Database? _database;
  static const _resetMarkerKey = 'local_data_reset_at';
  static const _pendingAgentRunKey = 'pending_agent_run';
  static const _contextBudgetSnapshotPrefix = 'context_budget_snapshot:';

  @override
  Future<void> initialize({
    required List<AgentWorkspace> seedWorkspaces,
    required List<AgentMemory> seedMemories,
    required List<AgentArtifact> seedArtifacts,
    required List<AgentMessage> seedMessages,
    required String defaultWorkspaceId,
  }) async {
    final db = await _open();
    await _seedWorkspaces(db, seedWorkspaces);
    await _seedMemories(db, seedMemories);
    await _seedArtifacts(db, seedArtifacts);
    await _seedMessages(db, defaultWorkspaceId, seedMessages);
    final currentWorkspaceId = await loadCurrentWorkspaceId();
    if (currentWorkspaceId == null || currentWorkspaceId.isEmpty) {
      await saveCurrentWorkspaceId(defaultWorkspaceId);
    }
  }

  @override
  Future<List<AgentWorkspace>> loadWorkspaces() async {
    final rows = await (await _open()).query(
      'workspaces',
      orderBy: 'created_at ASC',
    );
    return rows.map(_workspaceFromRow).toList(growable: false);
  }

  @override
  Future<String?> loadCurrentWorkspaceId() async {
    final rows = await (await _open()).query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['current_workspace_id'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  @override
  Future<void> saveCurrentWorkspaceId(String workspaceId) async {
    await (await _open()).insert('app_state', {
      'key': 'current_workspace_id',
      'value': workspaceId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<PendingAgentRun?> loadPendingAgentRun() async {
    final rows = await (await _open()).query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_pendingAgentRunKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    try {
      return PendingAgentRun.fromJson(
        _decodeMap(rows.first['value']! as String),
      );
    } on Object catch (error) {
      AppLogger.warning('workbench.pending_run.decode_failed', {
        'error': error.toString(),
      });
      await (await _open()).delete(
        'app_state',
        where: 'key = ?',
        whereArgs: [_pendingAgentRunKey],
      );
      return null;
    }
  }

  @override
  Future<void> savePendingAgentRun(PendingAgentRun run) async {
    await (await _open()).insert('app_state', {
      'key': _pendingAgentRunKey,
      'value': jsonEncode(run.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearPendingAgentRun(String runId) async {
    final pending = await loadPendingAgentRun();
    if (pending?.id != runId) {
      return;
    }
    await (await _open()).delete(
      'app_state',
      where: 'key = ?',
      whereArgs: [_pendingAgentRunKey],
    );
  }

  @override
  Future<void> upsertWorkspace(AgentWorkspace workspace) async {
    await (await _open()).insert(
      'workspaces',
      _workspaceToRow(workspace),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<AgentMemory>> loadMemories() async {
    final rows = await (await _open()).query(
      'memories',
      orderBy: 'created_at DESC',
    );
    return rows.map(_memoryFromRow).toList(growable: false);
  }

  @override
  Future<void> upsertMemory(AgentMemory memory) async {
    await (await _open()).insert(
      'memories',
      _memoryToRow(memory),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteMemory(String memoryId) async {
    await (await _open()).delete(
      'memories',
      where: 'id = ?',
      whereArgs: [memoryId],
    );
  }

  @override
  Future<List<AgentArtifact>> loadArtifacts() async {
    final rows = await (await _open()).query(
      'artifacts',
      orderBy: 'created_at DESC',
    );
    return rows.map(_artifactFromRow).toList(growable: false);
  }

  @override
  Future<void> upsertArtifact(AgentArtifact artifact) async {
    await (await _open()).insert(
      'artifacts',
      _artifactToRow(artifact),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<AgentMessage>> loadMessages(String workspaceId) async {
    final rows = await (await _open()).query(
      'messages',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      orderBy: 'created_at ASC',
    );
    return rows.map(_messageFromRow).toList(growable: false);
  }

  @override
  Future<void> upsertMessage({
    required String workspaceId,
    required AgentMessage message,
  }) async {
    await (await _open()).insert(
      'messages',
      _messageToRow(workspaceId, message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> recordInvocation(CapabilityInvocation invocation) async {
    await (await _open()).insert(
      'capability_invocations',
      _invocationToRow(invocation),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<CapabilityInvocation>> loadInvocations() async {
    final rows = await (await _open()).query(
      'capability_invocations',
      orderBy: 'created_at ASC',
    );
    return rows.map(_invocationFromRow).toList(growable: false);
  }

  @override
  Future<void> upsertTokenUsageRecord(TokenUsageRecord record) async {
    await (await _open()).insert(
      'token_usage_records',
      _tokenUsageRecordToRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<TokenUsageRecord>> loadTokenUsageRecords() async {
    final rows = await (await _open()).query(
      'token_usage_records',
      orderBy: 'started_at ASC',
    );
    return rows.map(_tokenUsageRecordFromRow).toList(growable: false);
  }

  @override
  Future<void> saveContextBudgetSnapshot({
    required String workspaceId,
    required Map<String, Object?> snapshot,
  }) async {
    await (await _open()).insert('app_state', {
      'key': '$_contextBudgetSnapshotPrefix$workspaceId',
      'value': jsonEncode(snapshot),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Map<String, Object?>?> loadContextBudgetSnapshot(
    String workspaceId,
  ) async {
    final rows = await (await _open()).query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['$_contextBudgetSnapshotPrefix$workspaceId'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    try {
      return _decodeMap(rows.first['value']! as String);
    } on Object catch (error) {
      AppLogger.warning('workbench.context_budget.decode_failed', {
        'workspaceId': workspaceId,
        'error': error.toString(),
      });
      await (await _open()).delete(
        'app_state',
        where: 'key = ?',
        whereArgs: ['$_contextBudgetSnapshotPrefix$workspaceId'],
      );
      return null;
    }
  }

  @override
  Future<List<McpConnection>> loadMcpConnections() async {
    final rows = await (await _open()).query(
      'mcp_connections',
      orderBy: 'created_at ASC',
    );
    return rows.map(_mcpConnectionFromRow).toList(growable: false);
  }

  @override
  Future<void> upsertMcpConnection(McpConnection connection) async {
    await (await _open()).insert(
      'mcp_connections',
      _mcpConnectionToRow(connection),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteMcpConnection(String url) async {
    await (await _open()).delete(
      'mcp_connections',
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  @override
  Future<List<AgentSkill>> loadSkills() async {
    final rows = await (await _open()).query(
      'skills',
      orderBy: 'created_at ASC',
    );
    return rows.map(_skillFromRow).toList(growable: false);
  }

  @override
  Future<void> upsertSkill(AgentSkill skill) async {
    await (await _open()).insert(
      'skills',
      _skillToRow(skill),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteSkill(String skillId) async {
    await (await _open()).delete(
      'skills',
      where: 'id = ?',
      whereArgs: [skillId],
    );
  }

  @override
  Future<void> resetLocalData({
    required AgentWorkspace defaultWorkspace,
    required List<AgentMessage> defaultMessages,
  }) async {
    final db = await _open();
    await db.transaction((transaction) async {
      await transaction.delete('token_usage_records');
      await transaction.delete('capability_invocations');
      await transaction.delete('messages');
      await transaction.delete('artifacts');
      await transaction.delete('memories');
      await transaction.delete('workspaces');
      await transaction.delete('app_state');
      await transaction.insert('workspaces', _workspaceToRow(defaultWorkspace));
      await transaction.insert('app_state', {
        'key': 'current_workspace_id',
        'value': defaultWorkspace.id,
      });
      await transaction.insert('app_state', {
        'key': _resetMarkerKey,
        'value': DateTime.now().toIso8601String(),
      });
      for (final message in defaultMessages) {
        await transaction.insert(
          'messages',
          _messageToRow(defaultWorkspace.id, message),
        );
      }
    });
  }

  @override
  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) {
      await _ensureSchema(existing);
      return existing;
    }
    final dbPath = _dbPath ?? await _defaultDbPath();
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (database, version) async => _ensureSchema(database),
      onOpen: _ensureSchema,
    );
    _database = db;
    await _ensureSchema(db);
    return db;
  }

  Future<String> _defaultDbPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'phone_agent.sqlite');
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS artifacts (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        uri TEXT,
        metadata_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        role TEXT NOT NULL,
        blocks_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS capability_invocations (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        capability_id TEXT NOT NULL,
        input_json TEXT NOT NULL,
        status TEXT NOT NULL,
        permission_decision TEXT,
        output_json TEXT,
        error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS token_usage_records (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        run_id TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        model_name TEXT NOT NULL,
        input_tokens INTEGER NOT NULL,
        reserved_output_tokens INTEGER NOT NULL,
        max_context_tokens INTEGER NOT NULL,
        is_conservative_estimate INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mcp_connections (
        url TEXT PRIMARY KEY,
        transport TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS skills (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        script TEXT NOT NULL,
        manifest_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_workspace '
      'ON messages(workspace_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_artifacts_workspace '
      'ON artifacts(workspace_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invocations_workspace '
      'ON capability_invocations(workspace_id, created_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_token_usage_run '
      'ON token_usage_records(run_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_token_usage_workspace '
      'ON token_usage_records(workspace_id, started_at)',
    );
  }

  Future<void> _seedWorkspaces(
    Database db,
    List<AgentWorkspace> seedWorkspaces,
  ) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM workspaces'),
    );
    if (count != 0) {
      return;
    }
    await db.transaction((transaction) async {
      for (final workspace in seedWorkspaces) {
        await transaction.insert('workspaces', _workspaceToRow(workspace));
      }
    });
  }

  Future<void> _seedMemories(
    Database db,
    List<AgentMemory> seedMemories,
  ) async {
    if (await _hasResetMarker(db)) {
      return;
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM memories'),
    );
    if (count != 0) {
      return;
    }
    await db.transaction((transaction) async {
      for (final memory in seedMemories) {
        await transaction.insert('memories', _memoryToRow(memory));
      }
    });
  }

  Future<void> _seedArtifacts(
    Database db,
    List<AgentArtifact> seedArtifacts,
  ) async {
    if (await _hasResetMarker(db)) {
      return;
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM artifacts'),
    );
    if (count != 0) {
      return;
    }
    await db.transaction((transaction) async {
      for (final artifact in seedArtifacts) {
        await transaction.insert('artifacts', _artifactToRow(artifact));
      }
    });
  }

  Future<void> _seedMessages(
    Database db,
    String workspaceId,
    List<AgentMessage> seedMessages,
  ) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM messages WHERE workspace_id = ?',
        [workspaceId],
      ),
    );
    if (count != 0) {
      return;
    }
    await db.transaction((transaction) async {
      for (final message in seedMessages) {
        await transaction.insert(
          'messages',
          _messageToRow(workspaceId, message),
        );
      }
    });
  }

  Future<bool> _hasResetMarker(Database db) async {
    final rows = await db.query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_resetMarkerKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Map<String, Object?> _workspaceToRow(AgentWorkspace workspace) => {
    'id': workspace.id,
    'name': workspace.name,
    'description': workspace.description,
    'created_at': workspace.createdAt.toIso8601String(),
  };

  AgentWorkspace _workspaceFromRow(Map<String, Object?> row) => AgentWorkspace(
    id: row['id']! as String,
    name: row['name']! as String,
    description: row['description']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
  );

  Map<String, Object?> _memoryToRow(AgentMemory memory) => {
    'id': memory.id,
    'content': memory.content,
    'created_at': memory.createdAt.toIso8601String(),
  };

  AgentMemory _memoryFromRow(Map<String, Object?> row) => AgentMemory(
    id: row['id']! as String,
    content: row['content']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
  );

  Map<String, Object?> _artifactToRow(AgentArtifact artifact) => {
    'id': artifact.id,
    'workspace_id': artifact.workspaceId,
    'type': artifact.type.name,
    'title': artifact.title,
    'summary': artifact.summary,
    'uri': artifact.uri?.toString(),
    'metadata_json': jsonEncode(artifact.metadata),
    'created_at': artifact.createdAt.toIso8601String(),
  };

  AgentArtifact _artifactFromRow(Map<String, Object?> row) => AgentArtifact(
    id: row['id']! as String,
    workspaceId: row['workspace_id']! as String,
    type: ArtifactType.values.byName(row['type']! as String),
    title: row['title']! as String,
    summary: row['summary']! as String,
    uri: (row['uri'] as String?) == null
        ? null
        : Uri.parse(row['uri']! as String),
    metadata: _decodeMap(row['metadata_json']! as String),
    createdAt: DateTime.parse(row['created_at']! as String),
  );

  Map<String, Object?> _messageToRow(
    String workspaceId,
    AgentMessage message,
  ) => {
    'id': message.id,
    'workspace_id': workspaceId,
    'role': message.role.name,
    'blocks_json': jsonEncode(
      message.blocks
          .map((block) => {'type': block.type.name, 'data': block.data})
          .toList(growable: false),
    ),
    'created_at': message.createdAt.toIso8601String(),
  };

  AgentMessage _messageFromRow(Map<String, Object?> row) => AgentMessage(
    id: row['id']! as String,
    role: MessageRole.values.byName(row['role']! as String),
    createdAt: DateTime.parse(row['created_at']! as String),
    blocks: _decodeList(row['blocks_json']! as String)
        .map((item) {
          final map = _objectMap(item);
          return MessageBlock(
            type: MessageBlockType.values.byName(map['type']! as String),
            data: _objectMap(map['data']),
          );
        })
        .toList(growable: false),
  );

  Map<String, Object?> _invocationToRow(CapabilityInvocation invocation) => {
    'id': invocation.id,
    'workspace_id': invocation.workspaceId,
    'capability_id': invocation.capabilityId,
    'input_json': jsonEncode(invocation.input),
    'status': invocation.status.name,
    'permission_decision': invocation.permissionDecision,
    'output_json': invocation.output == null
        ? null
        : jsonEncode(invocation.output),
    'error': invocation.error,
    'created_at': invocation.createdAt.toIso8601String(),
  };

  CapabilityInvocation _invocationFromRow(Map<String, Object?> row) =>
      CapabilityInvocation(
        id: row['id']! as String,
        workspaceId: row['workspace_id']! as String,
        capabilityId: row['capability_id']! as String,
        input: _decodeMap(row['input_json']! as String),
        status: CapabilityInvocationStatus.values.byName(
          row['status']! as String,
        ),
        permissionDecision: row['permission_decision'] as String?,
        output: row['output_json'] == null
            ? null
            : _decodeMap(row['output_json']! as String),
        error: row['error'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
      );

  Map<String, Object?> _tokenUsageRecordToRow(TokenUsageRecord record) => {
    'id': record.id,
    'workspace_id': record.workspaceId,
    'run_id': record.runId,
    'provider_id': record.providerId,
    'model_name': record.modelName,
    'input_tokens': record.inputTokens,
    'reserved_output_tokens': record.reservedOutputTokens,
    'max_context_tokens': record.maxContextTokens,
    'is_conservative_estimate': record.isConservativeEstimate ? 1 : 0,
    'started_at': record.startedAt.toIso8601String(),
    'ended_at': record.endedAt.toIso8601String(),
  };

  TokenUsageRecord _tokenUsageRecordFromRow(Map<String, Object?> row) =>
      TokenUsageRecord(
        id: row['id']! as String,
        workspaceId: row['workspace_id']! as String,
        runId: row['run_id']! as String,
        providerId: row['provider_id']! as String,
        modelName: row['model_name']! as String,
        inputTokens: row['input_tokens']! as int,
        reservedOutputTokens: row['reserved_output_tokens']! as int,
        maxContextTokens: row['max_context_tokens']! as int,
        isConservativeEstimate: (row['is_conservative_estimate']! as int) == 1,
        startedAt: DateTime.parse(row['started_at']! as String),
        endedAt: DateTime.parse(row['ended_at']! as String),
      );

  Map<String, Object?> _mcpConnectionToRow(McpConnection connection) => {
    'url': connection.url,
    'transport': connection.transport,
    'created_at': connection.createdAt.toIso8601String(),
  };

  McpConnection _mcpConnectionFromRow(Map<String, Object?> row) =>
      McpConnection(
        url: row['url']! as String,
        transport: row['transport']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
      );

  Map<String, Object?> _skillToRow(AgentSkill skill) => {
    'id': skill.id,
    'name': skill.name,
    'description': skill.description,
    'script': skill.script,
    'manifest_path': skill.manifestPath,
    'created_at': skill.createdAt.toIso8601String(),
  };

  AgentSkill _skillFromRow(Map<String, Object?> row) => AgentSkill(
    id: row['id']! as String,
    name: row['name']! as String,
    description: row['description']! as String,
    script: row['script']! as String,
    manifestPath: row['manifest_path'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String),
  );

  Map<String, Object?> _decodeMap(String value) =>
      _objectMap(jsonDecode(value));

  List<Object?> _decodeList(String value) =>
      (jsonDecode(value) as List<Object?>).toList(growable: false);

  Map<String, Object?> _objectMap(Object? value) {
    final map = value as Map<Object?, Object?>;
    return map.map((key, value) => MapEntry(key.toString(), value));
  }
}
