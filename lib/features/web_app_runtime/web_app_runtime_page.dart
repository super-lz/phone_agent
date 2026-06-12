import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../domain/artifacts/artifact.dart';
import '../../domain/artifacts/web_app_runtime_log.dart';
import 'web_app_bridge_script.dart';
import 'web_app_fallback_html.dart';
import 'web_app_local_server.dart';
import 'web_app_permission_widgets.dart';

typedef WebAppCapabilityCaller =
    Future<Map<String, Object?>> Function({
      required AgentArtifact webApp,
      required String capabilityId,
      required Map<String, Object?> input,
    });

typedef WebAppRuntimeLogWriter =
    Future<void> Function({
      required AgentArtifact webApp,
      required WebAppRuntimeLogEntry entry,
    });

class WebAppRuntimePage extends StatefulWidget {
  const WebAppRuntimePage({
    required this.webApp,
    required this.callCapability,
    required this.readResource,
    this.runtimeLogWriter,
    super.key,
  });

  final AgentArtifact webApp;
  final WebAppCapabilityCaller callCapability;
  final WebAppResourceReader readResource;
  final WebAppRuntimeLogWriter? runtimeLogWriter;

  @override
  State<WebAppRuntimePage> createState() => _WebAppRuntimePageState();
}

class WebAppRuntimeRoute extends PageRouteBuilder<void> {
  WebAppRuntimeRoute({
    required AgentArtifact webApp,
    required WebAppCapabilityCaller callCapability,
    required WebAppResourceReader readResource,
    WebAppRuntimeLogWriter? runtimeLogWriter,
  }) : super(
         transitionDuration: Duration.zero,
         reverseTransitionDuration: Duration.zero,
         pageBuilder: (context, animation, secondaryAnimation) {
           return WebAppRuntimePage(
             webApp: webApp,
             callCapability: callCapability,
             readResource: readResource,
             runtimeLogWriter: runtimeLogWriter,
           );
         },
       );
}

class _WebAppRuntimePageState extends State<WebAppRuntimePage> {
  static const double _webViewViewportBleed = 1;

  WebAppPermissionDecision _permissionDecision =
      WebAppPermissionDecision.pending;
  WebAppLocalServer? _localServer;
  Uri? _localServerUrl;
  String? _localServerError;
  bool _showConsole = false;
  final List<WebAppRuntimeLogEntry> _localLogs = [];

  @override
  void initState() {
    super.initState();
    unawaited(_startLocalServer());
  }

  @override
  void dispose() {
    final server = _localServer;
    _localServer = null;
    if (server != null) {
      unawaited(server.close());
    }
    super.dispose();
  }

  Future<void> _startLocalServer() async {
    final server = WebAppLocalServer(
      webApp: widget.webApp,
      resourceReader: widget.readResource,
      htmlHeadInjection: buildWebAppBridgeHeadHtml(widget.webApp),
      fallbackHtml: buildWebAppFallbackHtml(widget.webApp),
      apiRouteCaller:
          ({
            required String capabilityId,
            required Map<String, Object?> input,
          }) {
            return _callCapability(capabilityId, input);
          },
    );
    try {
      final url = await server.start();
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() {
        _localServer = server;
        _localServerUrl = url;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localServerError = error.toString();
      });
    }
  }

  InAppWebViewSettings _initialSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsBackForwardNavigationGestures: true,
      isInspectable: kDebugMode,
      databaseEnabled: true,
      domStorageEnabled: true,
      geolocationEnabled: true,
      allowContentAccess: true,
      allowFileAccess: true,
      allowFileAccessFromFileURLs: true,
      allowUniversalAccessFromFileURLs: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      supportZoom: false,
      builtInZoomControls: false,
      displayZoomControls: false,
      textZoom: 100,
      transparentBackground: false,
      verticalScrollBarEnabled: false,
      horizontalScrollBarEnabled: false,
      overScrollMode: OverScrollMode.NEVER,
      scrollBarStyle: ScrollBarStyle.SCROLLBARS_INSIDE_OVERLAY,
      scrollbarFadingEnabled: true,
      disableDefaultErrorPage: true,
      // Keep the Android WebView in Flutter's texture composition path so
      // route teardown behaves like a regular Flutter layer.
      useHybridComposition: false,
      useShouldOverrideUrlLoading: true,
      useOnDownloadStart: true,
      iframeAllow:
          'camera; microphone; geolocation; clipboard-read; clipboard-write; autoplay; fullscreen',
      iframeAllowFullscreen: true,
    );
  }

  void _configureBridge(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'PhoneAgentBridge',
      callback: (arguments) async {
        return _handleBridgeCall(arguments);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'PhoneAgentRuntimeLog',
      callback: (arguments) async {
        final payload = arguments.isEmpty ? null : arguments.first;
        await _recordRuntimeLog(
          WebAppRuntimeLogEntry.fromBridgePayload(payload),
        );
        return const {'ok': true};
      },
    );
  }

  Future<Map<String, Object?>> _handleBridgeCall(
    List<dynamic> arguments,
  ) async {
    final payload = _decodeBridgePayload(arguments);
    if (payload == null) {
      return const {'ok': false, 'error': 'invalid bridge payload'};
    }
    final capabilityId = payload['capabilityId'];
    if (capabilityId is! String) {
      return const {'ok': false, 'error': 'missing capabilityId'};
    }
    final input = _decodeInput(payload['input']);
    return _callCapability(capabilityId, input);
  }

  Map<String, Object?>? _decodeBridgePayload(List<dynamic> arguments) {
    if (arguments.isEmpty) {
      return null;
    }
    final first = arguments.first;
    if (first is Map<Object?, Object?>) {
      return first.map((key, value) => MapEntry(key.toString(), value));
    }
    if (first is! String) {
      return null;
    }
    try {
      final decoded = jsonDecode(first);
      if (decoded is! Map<Object?, Object?>) {
        return null;
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
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
    if (_permissionDecision != WebAppPermissionDecision.granted) {
      return {
        'ok': false,
        'error': 'web app permissions denied',
        'capabilityId': capabilityId,
      };
    }
    try {
      final result = await widget.callCapability(
        webApp: widget.webApp,
        capabilityId: capabilityId,
        input: input,
      );
      return _localServer?.attachLocalFileUrls(result) ?? result;
    } on Object catch (error) {
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<void> _recordRuntimeLog(WebAppRuntimeLogEntry entry) async {
    if (mounted) {
      setState(() {
        _localLogs.add(entry);
        if (_localLogs.length > 200) {
          _localLogs.removeAt(0);
        }
      });
    }
    final writer = widget.runtimeLogWriter;
    if (writer == null) {
      return;
    }
    try {
      await writer(webApp: widget.webApp, entry: entry);
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('[PhoneAgent WebApp] runtime log failed: $error');
      }
    }
  }

  void _openWithPermissionDecision(WebAppPermissionDecision decision) {
    setState(() {
      _permissionDecision = decision;
    });
  }

  Future<PermissionResponse> _handlePermissionRequest(
    PermissionRequest request,
  ) async {
    final action = _permissionDecision == WebAppPermissionDecision.granted
        ? PermissionResponseAction.GRANT
        : PermissionResponseAction.DENY;
    return PermissionResponse(resources: request.resources, action: action);
  }

  Future<GeolocationPermissionShowPromptResponse> _handleGeolocationPrompt(
    String origin,
  ) async {
    return GeolocationPermissionShowPromptResponse(
      origin: origin,
      allow: _permissionDecision == WebAppPermissionDecision.granted,
      retain: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.webApp.title)),
      body: _permissionDecision == WebAppPermissionDecision.pending
          ? WebAppPermissionGate(
              webApp: widget.webApp,
              onApprove: () {
                _openWithPermissionDecision(WebAppPermissionDecision.granted);
              },
              onDeny: () {
                _openWithPermissionDecision(WebAppPermissionDecision.denied);
              },
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                _webViewBody(),
                if (_permissionDecision == WebAppPermissionDecision.denied)
                  const WebAppPermissionDeniedBanner(),
                if (_showConsole) _buildConsoleOverlay(),
              ],
            ),
      floatingActionButton:
          _permissionDecision == WebAppPermissionDecision.granted
          ? FloatingActionButton(
              mini: true,
              onPressed: () {
                setState(() {
                  _showConsole = !_showConsole;
                });
              },
              child: Icon(
                _showConsole ? Icons.bug_report : Icons.bug_report_outlined,
              ),
            )
          : null,
    );
  }

  Widget _buildConsoleOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.4,
      child: Material(
        elevation: 16,
        color: const Color(0xFF1E1E1E),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black,
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    '开发者控制台',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_sweep,
                      color: Colors.white70,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _localLogs.clear();
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _showConsole = false;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _localLogs.length,
                itemBuilder: (context, index) {
                  final entry = _localLogs[_localLogs.length - 1 - index];
                  return _ConsoleLogRow(entry: entry);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _webViewBody() {
    final error = _localServerError;
    if (error != null) {
      return _RuntimeStatusView(title: '本地 Web App 服务启动失败', message: error);
    }

    final url = _localServerUrl;
    if (url == null) {
      return const _RuntimeStatusView(
        title: '正在启动本地 Web App 服务',
        message: '页面资源会从 127.0.0.1 临时服务加载，关闭预览页后自动停止。',
        showProgress: true,
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (!width.isFinite || !height.isFinite) {
            return SizedBox.expand(child: _buildInAppWebView(url));
          }
          // Android platform views can round fractional physical pixels down,
          // leaving a 1px host-background seam on the trailing edges.
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: width + _webViewViewportBleed,
              maxWidth: width + _webViewViewportBleed,
              minHeight: height + _webViewViewportBleed,
              maxHeight: height + _webViewViewportBleed,
              child: SizedBox(
                width: width + _webViewViewportBleed,
                height: height + _webViewViewportBleed,
                child: _buildInAppWebView(url),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInAppWebView(Uri url) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url.toString())),
      initialSettings: _initialSettings(),
      onWebViewCreated: (controller) {
        _configureBridge(controller);
      },
      onPermissionRequest: (_, request) {
        return _handlePermissionRequest(request);
      },
      onGeolocationPermissionsShowPrompt: (_, origin) {
        return _handleGeolocationPrompt(origin);
      },
      onLoadStop: (_, url) {
        unawaited(
          _recordRuntimeLog(
            WebAppRuntimeLogEntry(
              timestamp: DateTime.now(),
              level: 'info',
              source: 'webview.load',
              message: 'Web App loaded',
              url: url?.toString(),
            ),
          ),
        );
      },
      shouldOverrideUrlLoading: (_, navigationAction) async {
        return NavigationActionPolicy.ALLOW;
      },
      onConsoleMessage: (_, message) {
        _recordRuntimeLog(
          WebAppRuntimeLogEntry(
            timestamp: DateTime.now(),
            level: message.messageLevel.toLogString(),
            source: 'webview.console',
            message: message.message,
          ),
        );
      },
    );
  }
}

extension on ConsoleMessageLevel {
  String toLogString() {
    switch (this) {
      case ConsoleMessageLevel.TIP:
      case ConsoleMessageLevel.LOG:
        return 'info';
      case ConsoleMessageLevel.WARNING:
        return 'warning';
      case ConsoleMessageLevel.ERROR:
        return 'error';
      default:
        return 'info';
    }
  }
}

class _ConsoleLogRow extends StatelessWidget {
  const _ConsoleLogRow({required this.entry});

  final WebAppRuntimeLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      'error' => Colors.redAccent,
      'warning' => Colors.orangeAccent,
      _ => Colors.white,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeStatusView extends StatelessWidget {
  const _RuntimeStatusView({
    required this.title,
    required this.message,
    this.showProgress = false,
  });

  final String title;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum WebAppPermissionDecision { pending, granted, denied }
