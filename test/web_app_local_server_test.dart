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
          '<!doctype html><html><head><script src="./app.js"></script><link rel="stylesheet" href="./style.css"></head><body>Hello</body></html>',
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
    expect(
      html.body.indexOf('window.__phoneAgentBridge = true'),
      lessThan(html.body.indexOf('<script src="./app.js"></script>')),
    );

    final css = await _get(url.resolve('style.css'));
    expect(css.statusCode, HttpStatus.ok);
    expect(css.contentType, startsWith('text/css'));
    expect(css.body, contains('rgb(1, 2, 3)'));

    final mediaDir = await Directory.systemTemp.createTemp(
      'phone-agent-webapp-media-',
    );
    addTearDown(() async {
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }
    });
    final audioFile = File('${mediaDir.path}/voice.m4a');
    await audioFile.writeAsBytes([0, 1, 2, 3, 4]);
    final imageFile = File('${mediaDir.path}/photo.jpg');
    await imageFile.writeAsBytes([5, 6, 7]);

    final bridgeResult = server.attachLocalFileUrls({
      'ok': true,
      'capabilityId': 'audio.record_stop',
      'output': {
        'ok': true,
        'mediaType': 'audio',
        'path': audioFile.path,
        'uri': audioFile.uri.toString(),
        'mimeType': 'audio/mp4',
        'items': [
          {
            'ok': true,
            'mediaType': 'image',
            'path': imageFile.path,
            'uri': imageFile.uri.toString(),
            'mimeType': 'image/jpeg',
          },
        ],
      },
    });
    final output = bridgeResult['output']! as Map<String, Object?>;
    final mediaUrl = Uri.parse(output['mediaUrl']! as String);
    expect(mediaUrl.host, InternetAddress.loopbackIPv4.address);

    final audio = await _getBytes(mediaUrl);
    expect(audio.statusCode, HttpStatus.ok);
    expect(audio.contentType, startsWith('audio/mp4'));
    expect(audio.bytes, [0, 1, 2, 3, 4]);

    final audioRange = await _getBytes(mediaUrl, range: 'bytes=1-3');
    expect(audioRange.statusCode, HttpStatus.partialContent);
    expect(audioRange.bytes, [1, 2, 3]);

    final items = output['items']! as List<Object?>;
    final firstItem = items.single! as Map<String, Object?>;
    final image = await _getBytes(Uri.parse(firstItem['mediaUrl']! as String));
    expect(image.statusCode, HttpStatus.ok);
    expect(image.contentType, startsWith('image/jpeg'));
    expect(image.bytes, [5, 6, 7]);

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

Future<_HttpBytesResponse> _getBytes(Uri uri, {String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );
    return _HttpBytesResponse(
      statusCode: response.statusCode,
      contentType: response.headers.contentType.toString(),
      bytes: bytes,
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

class _HttpBytesResponse {
  const _HttpBytesResponse({
    required this.statusCode,
    required this.contentType,
    required this.bytes,
  });

  final int statusCode;
  final String contentType;
  final List<int> bytes;
}
