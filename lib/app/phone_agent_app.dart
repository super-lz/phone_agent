import 'package:flutter/material.dart';

import '../application/capabilities/capability_runtime.dart';
import '../data/models/model_api_key_store.dart';
import '../data/models/model_settings_store.dart';
import '../data/models/openai_compatible_chat_client.dart';
import '../domain/files/app_file_store.dart';
import '../domain/notes/note_store.dart';
import '../domain/workbench/workbench_store.dart';
import '../features/workbench/phone_agent_home.dart';
import 'phone_agent_colors.dart';

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
    final colors = PhoneAgentColors.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.primaryAction,
      brightness: Brightness.light,
      surface: colors.cardBackground,
      primary: colors.primaryAction,
      surfaceContainerHighest: colors.panelBackground,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Phone Agent',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colors.pageBackground,
        useMaterial3: true,
        fontFamily: '.SF Pro Text',
        extensions: <ThemeExtension<dynamic>>[colors],
        textTheme: TextTheme(
          titleLarge: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          titleMedium: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          bodyLarge: TextStyle(color: colors.textPrimary, height: 1.5),
          bodyMedium: TextStyle(color: colors.textSecondary, height: 1.5),
          labelSmall: TextStyle(color: colors.textTertiary, letterSpacing: 0),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: colors.panelBackground,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 64,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          iconTheme: IconThemeData(color: colors.textSecondary),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: colors.cardBackground,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colors.border),
            borderRadius: const BorderRadius.all(Radius.circular(20)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.inputBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          hintStyle: TextStyle(color: colors.inputHint, fontSize: 16),
        ),
        dividerTheme: DividerThemeData(
          color: colors.border,
          thickness: 1,
          space: 1,
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: colors.panelBackground,
          modalBackgroundColor: colors.panelBackground,
          surfaceTintColor: Colors.transparent,
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
