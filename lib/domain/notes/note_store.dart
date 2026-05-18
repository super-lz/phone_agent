import 'note.dart';

abstract class AgentNoteStore {
  Future<List<AgentNote>> loadAll();

  Future<void> upsert(AgentNote note);

  Future<List<AgentNote>> query({
    required String workspaceId,
    required String keyword,
  });

  Future<void> resetLocalData();

  Future<void> close();
}

class InMemoryAgentNoteStore implements AgentNoteStore {
  InMemoryAgentNoteStore([List<AgentNote> seedNotes = const []])
    : _notes = List.of(seedNotes);

  final List<AgentNote> _notes;

  @override
  Future<List<AgentNote>> loadAll() async {
    return List.unmodifiable(_notes);
  }

  @override
  Future<void> upsert(AgentNote note) async {
    final index = _notes.indexWhere((candidate) => candidate.id == note.id);
    if (index < 0) {
      _notes.add(note);
      return;
    }
    _notes[index] = note;
  }

  @override
  Future<List<AgentNote>> query({
    required String workspaceId,
    required String keyword,
  }) async {
    final normalizedKeyword = keyword.trim();
    return _notes
        .where((note) {
          if (note.workspaceId != workspaceId) {
            return false;
          }
          if (normalizedKeyword.isEmpty) {
            return true;
          }
          return note.title.contains(normalizedKeyword) ||
              note.content.contains(normalizedKeyword);
        })
        .toList(growable: false);
  }

  @override
  Future<void> resetLocalData() async {
    _notes.clear();
  }

  @override
  Future<void> close() async {}
}
