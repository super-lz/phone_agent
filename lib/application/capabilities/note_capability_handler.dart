import '../../core/logging/app_logger.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import 'capability_execution_result.dart';

class NoteCapabilityHandler {
  const NoteCapabilityHandler();

  Future<CapabilityExecutionResult> create({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required List<AgentNote> notes,
    required AgentNoteStore? noteStore,
  }) async {
    final rawContent = arguments['content'];
    if (rawContent is! String || rawContent.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'db.note.create',
        output: {'ok': false, 'error': 'content is required'},
      );
    }

    final rawTitle = arguments['title'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : _deriveTitle(rawContent);
    final note = AgentNote(
      id: 'note-${DateTime.now().microsecondsSinceEpoch}',
      workspaceId: workspaceId,
      title: title,
      content: rawContent.trim(),
      createdAt: DateTime.now(),
    );
    notes.add(note);
    try {
      await noteStore?.upsert(note);
    } on Object catch (error) {
      notes.removeWhere((candidate) => candidate.id == note.id);
      AppLogger.warning('db.note.create.persist_failed', {
        'noteId': note.id,
        'error': error.toString(),
      });
      return CapabilityExecutionResult(
        capabilityId: 'db.note.create',
        output: {
          'ok': false,
          'error': 'note persistence failed',
          'detail': error.toString(),
        },
      );
    }

    return CapabilityExecutionResult(
      capabilityId: 'db.note.create',
      output: {
        'ok': true,
        'noteId': note.id,
        'workspaceId': note.workspaceId,
        'title': note.title,
        'content': note.content,
      },
    );
  }

  Future<CapabilityExecutionResult> query({
    required String workspaceId,
    required Map<String, Object?> arguments,
    required List<AgentNote> notes,
    required AgentNoteStore? noteStore,
  }) async {
    final query = arguments['query'];
    final keyword = query is String ? query.trim() : '';
    final matchedNotes = await _queryNotes(
      workspaceId: workspaceId,
      keyword: keyword,
      notes: notes,
      noteStore: noteStore,
    );
    final matched = matchedNotes
        .map((note) {
          return {
            'id': note.id,
            'workspaceId': note.workspaceId,
            'title': note.title,
            'content': note.content,
          };
        })
        .toList(growable: false);

    return CapabilityExecutionResult(
      capabilityId: 'db.note.query',
      output: {'ok': true, 'items': matched},
    );
  }

  Future<List<AgentNote>> _queryNotes({
    required String workspaceId,
    required String keyword,
    required List<AgentNote> notes,
    required AgentNoteStore? noteStore,
  }) async {
    if (noteStore != null) {
      try {
        return await noteStore.query(
          workspaceId: workspaceId,
          keyword: keyword,
        );
      } on Object catch (error) {
        AppLogger.warning('db.note.query.persist_failed', {
          'workspaceId': workspaceId,
          'error': error.toString(),
        });
      }
    }

    return notes
        .where((note) {
          if (note.workspaceId != workspaceId) {
            return false;
          }
          if (keyword.isEmpty) {
            return true;
          }
          return note.title.contains(keyword) || note.content.contains(keyword);
        })
        .toList(growable: false);
  }

  String _deriveTitle(String content) {
    final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 24) {
      return normalized;
    }
    return '${normalized.substring(0, 24)}...';
  }
}
