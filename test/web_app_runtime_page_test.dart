import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/artifacts/artifact.dart';
import 'package:phone_agent/domain/files/app_file_store.dart';
import 'package:phone_agent/features/web_app_runtime/web_app_bridge_script.dart';
import 'package:phone_agent/features/web_app_runtime/web_app_capability_bridge.dart';
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

  testWidgets('web app runtime pops with the normal route lifecycle', (
    tester,
  ) async {
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
    await tester.pumpAndSettle();

    expect(find.text('权限确认'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  test(
    'bridge script exposes helpers for first-version phone capabilities',
    () {
      final script = buildWebAppBridgeHeadHtml(_webApp());

      for (final capabilityId in WebAppRuntimeDefaults.permissions) {
        expect(script, contains(capabilityId), reason: capabilityId);
      }
      expect(script, contains('createNote: function'));
      expect(script, contains('queryNotes: function'));
      expect(script, contains('readAppFile: function'));
      expect(script, contains('writeAppFile: function'));
      expect(script, contains('readClipboard: function'));
      expect(script, contains('writeClipboard: function'));
      expect(script, contains('openPermissionSettings: function'));
      expect(script, contains('setSystemUiMode: function'));
      expect(script, contains('getSystemUiStatus: function'));
      expect(script, contains('setScreenOrientation: function'));
      expect(script, contains('getScreenOrientationStatus: function'));
      expect(script, contains('createCalendarEvent: function'));
      expect(script, contains('webSearch: function'));
      expect(script, contains('webFetch: function'));
      expect(script, contains('queryMemory: function'));
      expect(script, contains('switchWorkspace: function'));
    },
  );

  test(
    'bridge script applies baseline web app viewport and interaction styles',
    () {
      final script = buildWebAppBridgeHeadHtml(_webApp());

      expect(script, contains('phone-agent-runtime-edge-reset'));
      expect(script, contains('margin: 0'));
      expect(script, contains('min-height: 100%'));
      expect(script, contains('overflow-x: hidden'));
      expect(script, contains('-webkit-tap-highlight-color: transparent'));
      expect(script, contains('scrollbar-width: thin'));
      expect(script, contains('::-webkit-scrollbar-thumb'));
      expect(script, contains('overscroll-behavior: none'));
      expect(script, contains(':focus-visible'));
    },
  );
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
