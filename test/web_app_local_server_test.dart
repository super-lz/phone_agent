import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/artifacts/artifact.dart';
import 'package:phone_agent/domain/files/app_file_store.dart';
import 'package:phone_agent/features/web_app_runtime/web_app_local_server.dart';

void main() {
  test('serves web app project files from localhost until closed', () async {
    final fileStore = InMemoryAppFileStore();
    await fileStore.writeText(
      workspaceId: 'work',
      path: 'apps/demo/index.html',
      content:
          '<!doctype html><html><head><link rel="stylesheet" href="./style.css"></head><body>Hello</body></html>',
      overwrite: true,
    );
    await fileStore.writeText(
      workspaceId: 'work',
      path: 'apps/demo/style.css',
      content: 'body { color: rgb(1, 2, 3); }',
      overwrite: true,
    );

    final server = WebAppLocalServer(
      webApp: AgentArtifact(
        id: 'artifact-demo',
        workspaceId: 'work',
        type: ArtifactType.webApp,
        title: 'Demo',
        summary: 'Demo app',
        createdAt: DateTime.utc(2026, 5, 18),
        metadata: const {'entry': 'apps/demo/index.html'},
      ),
      resourceReader:
          ({
            required AgentArtifact webApp,
            required String path,
            required int maxChars,
          }) {
            return fileStore.readText(
              workspaceId: webApp.workspaceId,
              path: path,
              maxChars: maxChars,
            );
          },
      htmlHeadInjection: '<script>window.__phoneAgentBridge = true;</script>',
      fallbackHtml: '<main>Fallback</main>',
    );

    final url = await server.start();
    addTearDown(server.close);

    final html = await _get(url);
    expect(html.statusCode, HttpStatus.ok);
    expect(html.body, contains('window.__phoneAgentBridge = true'));
    expect(html.body, contains('Hello'));

    final css = await _get(url.resolve('style.css'));
    expect(css.statusCode, HttpStatus.ok);
    expect(css.contentType, startsWith('text/css'));
    expect(css.body, contains('rgb(1, 2, 3)'));

    await server.close();
    await expectLater(_get(url), throwsA(isA<SocketException>()));
  });
}

Future<_HttpTextResponse> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    return _HttpTextResponse(
      statusCode: response.statusCode,
      contentType: response.headers.contentType.toString(),
      body: body,
    );
  } finally {
    client.close(force: true);
  }
}

class _HttpTextResponse {
  const _HttpTextResponse({
    required this.statusCode,
    required this.contentType,
    required this.body,
  });

  final int statusCode;
  final String contentType;
  final String body;
}
