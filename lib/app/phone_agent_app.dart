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
      seedColor: const Color(0xFF007AFF),
      brightness: Brightness.light,
      surface: Colors.white,
      surfaceContainerHighest: const Color(0xFFF3F4F6),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Phone Agent',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        useMaterial3: true,
        fontFamily: '.SF Pro Text', // Native iOS feel on Darwin
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
          iconTheme: IconThemeData(color: Color(0xFF4B5563)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade200),
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE5E7EB),
          thickness: 1,
          space: 1,
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
