import 'package:flutter/material.dart';

import 'app/phone_agent_app.dart';
import 'core/logging/app_logger.dart';
import 'data/background/agent_run_background_service.dart';
import 'data/bootstrap/phone_agent_seed.dart';
import 'data/files/local_app_file_store.dart';
import 'data/models/model_settings_store.dart';
import 'data/notes/sqlite_agent_note_store.dart';
import 'data/workbench/sqlite_workbench_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.initialize();
  runApp(
    PhoneAgentApp(
      fileStore: LocalAppFileStore(),
      backgroundService: PlatformAgentRunBackgroundService(),
      modelSettingsStore: SecureModelSettingsStore(),
      noteStore: SqliteAgentNoteStore(seedNotes: PhoneAgentSeed.notes()),
      workbenchStore: SqliteWorkbenchStore(),
    ),
  );
}
