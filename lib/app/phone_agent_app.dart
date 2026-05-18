import 'package:flutter/material.dart';

import '../application/capabilities/capability_runtime.dart';
import '../data/models/model_api_key_store.dart';
import '../data/models/model_settings_store.dart';
import '../data/models/openai_compatible_chat_client.dart';
import '../domain/files/app_file_store.dart';
import '../domain/notes/note_store.dart';
import '../domain/workbench/workbench_store.dart';
import '../features/workbench/phone_agent_home.dart';

class PhoneAgentApp extends StatelessWidget {
  const PhoneAgentApp({
    this.apiKeyStore,
    this.chatClient,
    this.capabilityRuntime,
    this.modelSettingsStore,
    this.noteStore,
    this.fileStore,
    this.workbenchStore,
    super.key,
  });

  final ModelApiKeyStore? apiKeyStore;
  final OpenAiCompatibleChatClient? chatClient;
  final CapabilityRuntime? capabilityRuntime;
  final ModelSettingsStore? modelSettingsStore;
  final AgentNoteStore? noteStore;
  final AppFileStore? fileStore;
  final WorkbenchStore? workbenchStore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1C7C54),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Phone Agent',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F8F5),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: PhoneAgentHome(
        apiKeyStore: apiKeyStore,
        chatClient: chatClient,
        capabilityRuntime: capabilityRuntime,
        modelSettingsStore: modelSettingsStore,
        noteStore: noteStore,
        fileStore: fileStore,
        workbenchStore: workbenchStore,
      ),
    );
  }
}
