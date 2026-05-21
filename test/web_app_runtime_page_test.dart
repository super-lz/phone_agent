import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/artifacts/artifact.dart';
import 'package:phone_agent/domain/files/app_file_store.dart';
import 'package:phone_agent/features/web_app_runtime/web_app_runtime_page.dart';

void main() {
  test('web app runtime route does not animate the platform view route', () {
    final route = WebAppRuntimeRoute(
      webApp: _webApp(),
      callCapability:
          ({
            required AgentArtifact webApp,
            required String capabilityId,
            required Map<String, Object?> input,
          }) async => const {'ok': true},
      readResource:
          ({
            required AgentArtifact webApp,
            required String path,
            required int maxChars,
          }) async => AppFileReadResult(
            path: path,
            content: '<main>Demo</main>',
            length: '<main>Demo</main>'.length,
            truncated: false,
          ),
    );

    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });

  testWidgets('web app runtime fades out before popping', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    WebAppRuntimeRoute(
                      webApp: _webApp(),
                      callCapability:
                          ({
                            required AgentArtifact webApp,
                            required String capabilityId,
                            required Map<String, Object?> input,
                          }) async => const {'ok': true},
                      readResource:
                          ({
                            required AgentArtifact webApp,
                            required String path,
                            required int maxChars,
                          }) async => AppFileReadResult(
                            path: path,
                            content: '<main>Demo</main>',
                            length: '<main>Demo</main>'.length,
                            truncated: false,
                          ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('权限确认'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pump();

    expect(find.text('权限确认'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('权限确认'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}

AgentArtifact _webApp() {
  return AgentArtifact(
    id: 'artifact-web-app',
    workspaceId: 'workspace-default',
    type: ArtifactType.webApp,
    title: '测试 Web App',
    summary: '用于验证 WebView 预览页。',
    createdAt: DateTime.utc(2026, 5, 19),
    metadata: const {
      'html': '<!doctype html><html><body><main>Demo</main></body></html>',
    },
  );
}
