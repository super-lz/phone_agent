import 'package:flutter/material.dart';

import '../domain/notes/note_store.dart';
import '../features/workbench/phone_agent_home.dart';

class PhoneAgentApp extends StatelessWidget {
  const PhoneAgentApp({this.noteStore, super.key});

  final AgentNoteStore? noteStore;

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
      home: PhoneAgentHome(noteStore: noteStore),
    );
  }
}
