import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/logging/app_logger.dart';

/// A secure sandbox for executing Skill scripts using a hidden WebView.
/// This allows us to run JS code and bridge it back to our Capability Runtime.
class SkillSandbox {
  SkillSandbox._();

  static final SkillSandbox instance = SkillSandbox._();

  HeadlessInAppWebView? _headlessWebView;
  final Completer<void> _readyCompleter = Completer<void>();
  bool _isReady = false;

  /// Map of pending call requests from the sandbox.
  final Map<String, Completer<Map<String, Object?>>> _pendingCalls = {};

  /// Callback to handle capability calls from the sandbox.
  Future<Map<String, Object?>> Function(String capabilityId, Map<String, Object?> input)? onCallCapability;

  Future<void> ensureInitialized() async {
    if (_isReady) return;
    if (_headlessWebView != null) return _readyCompleter.future;

    AppLogger.info('skill.sandbox.initializing', {});

    _headlessWebView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        isInspectable: true,
      ),
      initialData: InAppWebViewInitialData(
        data: '''
          <!DOCTYPE html>
          <html>
          <head>
            <script>
              window.PhoneAgent = {
                callCapability: async (capabilityId, input) => {
                  const requestId = Math.random().toString(36).substring(2);
                  return new Promise((resolve) => {
                    window.flutter_inappwebview.callHandler('callCapability', {
                      requestId,
                      capabilityId,
                      input
                    }).then(resolve);
                  });
                }
              };
              console.log('Skill Sandbox Ready');
            </script>
          </head>
          <body></body>
          </html>
        ''',
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'callCapability',
          callback: (args) async {
            final data = args[0] as Map<String, dynamic>;
            final capabilityId = data['capabilityId'] as String;
            final input = Map<String, Object?>.from(data['input'] as Map);
            
            AppLogger.info('skill.sandbox.call_request', {'id': capabilityId});
            
            if (onCallCapability != null) {
              return await onCallCapability!(capabilityId, input);
            }
            return {'ok': false, 'error': 'onCallCapability handler not set'};
          },
        );
      },
      onConsoleMessage: (controller, message) {
        AppLogger.info('skill.sandbox.console', {
          'level': message.messageLevel.toString(),
          'message': message.message,
        });
      },
      onLoadStop: (controller, url) {
        _isReady = true;
        if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        AppLogger.info('skill.sandbox.ready', {});
      },
    );

    await _headlessWebView!.run();
    return _readyCompleter.future;
  }

  Future<Map<String, Object?>> execute(String script, {Map<String, Object?>? context}) async {
    await ensureInitialized();
    final controller = _headlessWebView?.webViewController;
    if (controller == null) {
      return {'ok': false, 'error': 'Sandbox controller unavailable'};
    }

    final contextJson = jsonEncode(context ?? {});
    final wrappedScript = '''
      (async () => {
        try {
          const context = $contextJson;
          const result = await (async () => {
            $script
          })();
          return { ok: true, result: result };
        } catch (e) {
          return { 
            ok: false, 
            error: e.message || e.toString(),
            stack: e.stack,
            type: e.name
          };
        }
      })()
    ''';

    try {
      final result = await controller.evaluateJavascript(source: wrappedScript);
      if (result is Map) {
        return Map<String, Object?>.from(result);
      }
      return {'ok': true, 'result': result};
    } catch (e) {
      AppLogger.error('skill.sandbox.execute_error', e);
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<void> dispose() async {
    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _isReady = false;
  }
}
