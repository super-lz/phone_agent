import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../domain/artifacts/artifact.dart';

typedef WebAppCapabilityCaller =
    Future<Map<String, Object?>> Function({
      required AgentArtifact webApp,
      required String capabilityId,
      required Map<String, Object?> input,
    });

class WebAppRuntimePage extends StatefulWidget {
  const WebAppRuntimePage({
    required this.webApp,
    required this.callCapability,
    super.key,
  });

  final AgentArtifact webApp;
  final WebAppCapabilityCaller callCapability;

  @override
  State<WebAppRuntimePage> createState() => _WebAppRuntimePageState();
}

class _WebAppRuntimePageState extends State<WebAppRuntimePage> {
  late final WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PhoneAgentBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..loadHtmlString(_htmlWithBridge(widget.webApp));
  }

  Future<void> _handleBridgeMessage(JavaScriptMessage message) async {
    final payload = _decodeMessage(message.message);
    if (payload == null) {
      return;
    }
    final requestId = payload['requestId'];
    final capabilityId = payload['capabilityId'];
    if (requestId is! String || capabilityId is! String) {
      return;
    }
    final input = _decodeInput(payload['input']);
    final response = await _callCapability(capabilityId, input);
    await _webViewController.runJavaScript(
      'window.PhoneAgent.__resolve(${jsonEncode(requestId)}, '
      '${jsonEncode(response)});',
    );
  }

  Map<String, Object?>? _decodeMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  Map<String, Object?> _decodeInput(Object? rawInput) {
    if (rawInput is! Map<Object?, Object?>) {
      return <String, Object?>{};
    }
    return rawInput.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Map<String, Object?>> _callCapability(
    String capabilityId,
    Map<String, Object?> input,
  ) async {
    try {
      return await widget.callCapability(
        webApp: widget.webApp,
        capabilityId: capabilityId,
        input: input,
      );
    } on Object catch (error) {
      return {'ok': false, 'error': error.toString()};
    }
  }

  String _htmlWithBridge(AgentArtifact webApp) {
    final html = _htmlFor(webApp);
    return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <script>
    (function() {
      const manifest = ${jsonEncode(_manifestFor(webApp))};
      const pending = new Map();
      window.PhoneAgent = {
        getManifest: function() {
          return manifest;
        },
        callCapability: function(capabilityId, input) {
          const requestId = Date.now().toString(36) + Math.random().toString(36).slice(2);
          const payload = { requestId, capabilityId, input: input || {} };
          PhoneAgentBridge.postMessage(JSON.stringify(payload));
          return new Promise(function(resolve) {
            pending.set(requestId, resolve);
          });
        },
        subscribeEvent: function(_eventName, _handler) {
          return { unsubscribe: function() {} };
        },
        __resolve: function(requestId, response) {
          const resolve = pending.get(requestId);
          if (!resolve) return;
          pending.delete(requestId);
          resolve(response);
        }
      };
    })();
  </script>
</head>
<body>
$html
</body>
</html>
''';
  }

  Map<String, Object?> _manifestFor(AgentArtifact webApp) {
    return {
      'id': webApp.id,
      'title': webApp.title,
      'entry': webApp.metadata['entry'] ?? 'index.html',
      'permissions': webApp.metadata['permissions'] ?? <String>[],
    };
  }

  String _htmlFor(AgentArtifact webApp) {
    final html = webApp.metadata['html'];
    if (html is String && html.trim().isNotEmpty) {
      return html;
    }
    return '''
<main style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px;">
  <h1>${_escapeHtml(webApp.title)}</h1>
  <p>${_escapeHtml(webApp.summary)}</p>
  <pre id="out">Web App 已加载。</pre>
</main>
''';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.webApp.title)),
      body: WebViewWidget(controller: _webViewController),
    );
  }
}
