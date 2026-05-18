import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';

class SqliteAgentNoteStore implements AgentNoteStore {
  SqliteAgentNoteStore({List<AgentNote> seedNotes = const []})
    : _seedNotes = List.of(seedNotes),
      _dbPath = null;

  SqliteAgentNoteStore.forPath(
    String dbPath, {
    List<AgentNote> seedNotes = const [],
  }) : _seedNotes = List.of(seedNotes),
       _dbPath = dbPath;

  final List<AgentNote> _seedNotes;
  final String? _dbPath;
  Database? _database;
  static const _resetMarkerKey = 'local_data_reset_at';

  @override
  Future<List<AgentNote>> loadAll() async {
    final db = await _open();
    final rows = await db.query('notes', orderBy: 'created_at DESC');
    return rows.map(_rowToNote).toList(growable: false);
  }

  @override
  Future<void> upsert(AgentNote note) async {
    final db = await _open();
    await db.insert(
      'notes',
      _noteToRow(note),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<AgentNote>> query({
    required String workspaceId,
    required String keyword,
  }) async {
    final db = await _open();
    final normalizedKeyword = keyword.trim();
    final rows = normalizedKeyword.isEmpty
        ? await db.query(
            'notes',
            where: 'workspace_id = ?',
            whereArgs: [workspaceId],
            orderBy: 'created_at DESC',
          )
        : await db.query(
            'notes',
            where: 'workspace_id = ? AND (title LIKE ? OR content LIKE ?)',
            whereArgs: [
              workspaceId,
              '%$normalizedKeyword%',
              '%$normalizedKeyword%',
            ],
            orderBy: 'created_at DESC',
          );
    return rows.map(_rowToNote).toList(growable: false);
  }

  @override
  Future<void> resetLocalData() async {
    final db = await _open();
    await db.transaction((transaction) async {
      await transaction.delete('notes');
      await transaction.delete('note_store_state');
      await transaction.insert('note_store_state', {
        'key': _resetMarkerKey,
        'value': DateTime.now().toIso8601String(),
      });
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
      return existing;
    }

    final dbPath = _dbPath ?? await _defaultDbPath();
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (database, version) async {
        await _ensureSchema(database);
      },
      onOpen: (database) async {
        await _ensureSchema(database);
      },
    );
    _database = db;
    await _seedIfEmpty(db);
    return db;
  }

  Future<String> _defaultDbPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'phone_agent.sqlite');
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_workspace '
      'ON notes(workspace_id, created_at)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_store_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedIfEmpty(Database db) async {
    if (_seedNotes.isEmpty) {
      return;
    }
    if (await _hasResetMarker(db)) {
      return;
    }
    final countRows = await db.rawQuery('SELECT COUNT(*) AS count FROM notes');
    final rawCount = countRows.first['count'];
    if (rawCount is int && rawCount > 0) {
      return;
    }
    await db.transaction((transaction) async {
      for (final note in _seedNotes) {
        await transaction.insert(
          'notes',
          _noteToRow(note),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<bool> _hasResetMarker(Database db) async {
    final rows = await db.query(
      'note_store_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_resetMarkerKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Map<String, Object?> _noteToRow(AgentNote note) {
    return {
      'id': note.id,
      'workspace_id': note.workspaceId,
      'title': note.title,
      'content': note.content,
      'created_at': note.createdAt.toIso8601String(),
    };
  }

  AgentNote _rowToNote(Map<String, Object?> row) {
    return AgentNote(
      id: row['id']! as String,
      workspaceId: row['workspace_id']! as String,
      title: row['title']! as String,
      content: row['content']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }
}
