import 'package:flutter/material.dart';

import 'app/phone_agent_app.dart';
import 'core/logging/app_logger.dart';
import 'data/bootstrap/phone_agent_seed.dart';
import 'data/notes/sqlite_agent_note_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.initialize();
  runApp(
    PhoneAgentApp(
      noteStore: SqliteAgentNoteStore(seedNotes: PhoneAgentSeed.notes()),
    ),
  );
}
