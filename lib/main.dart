import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'app/phone_agent_app.dart';
import 'core/logging/app_logger.dart';
import 'data/bootstrap/phone_agent_seed.dart';
import 'data/files/local_app_file_store.dart';
import 'data/models/model_settings_store.dart';
import 'data/notes/sqlite_agent_note_store.dart';
import 'data/workbench/sqlite_workbench_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.initialize();
  try {
    await FlutterGemma.initialize();
  } catch (e) {
    AppLogger.error('main.gemma_init_failed', {'error': e.toString()});
  }
  runApp(
    PhoneAgentApp(
      fileStore: LocalAppFileStore(),
      modelSettingsStore: SecureModelSettingsStore(),
      noteStore: SqliteAgentNoteStore(seedNotes: PhoneAgentSeed.notes()),
      workbenchStore: SqliteWorkbenchStore(),
    ),
  );
}
