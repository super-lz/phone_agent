import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/files/app_file_store.dart';
import 'package:phone_agent/features/workbench/widgets/workspace_file_manager_page.dart';

void main() {
  testWidgets('browses workspace files by directory levels', (tester) async {
    final opened = <String>[];
    final files = [
      AppFileEntry(
        path: 'reports/today.md',
        uri: Uri.file('/tmp/reports/today.md'),
        bytes: 2048,
        modifiedAt: DateTime(2026, 6, 11, 10, 30),
      ),
      AppFileEntry(
        path: 'media/audio/recording.m4a',
        uri: Uri.file('/tmp/media/audio/recording.m4a'),
        bytes: 4096,
        modifiedAt: DateTime(2026, 6, 11, 10, 31),
      ),
      AppFileEntry(
        path: 'root.txt',
        uri: Uri.file('/tmp/root.txt'),
        bytes: 12,
        modifiedAt: DateTime(2026, 6, 11, 10, 32),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceFileManagerPage(
          files: files,
          onOpenFile: (entry) {
            opened.add(entry.path);
          },
          onRefreshFiles: () async => files,
        ),
      ),
    );

    expect(find.text('工作区文件'), findsOneWidget);
    expect(find.text('media'), findsOneWidget);
    expect(find.text('reports'), findsOneWidget);
    expect(find.text('root.txt'), findsOneWidget);

    await tester.tap(find.text('media'));
    await tester.pumpAndSettle();

    expect(find.text('audio'), findsOneWidget);
    expect(find.text('root.txt'), findsNothing);
    expect(find.text('media'), findsWidgets);

    await tester.tap(find.text('audio'));
    await tester.pumpAndSettle();

    expect(find.text('recording.m4a'), findsOneWidget);
    await tester.tap(find.text('recording.m4a'));
    await tester.pump();
    expect(opened, ['media/audio/recording.m4a']);

    await tester.tap(find.byTooltip('返回上级'));
    await tester.pumpAndSettle();

    expect(find.text('audio'), findsOneWidget);
    expect(find.text('recording.m4a'), findsNothing);
  });
}
