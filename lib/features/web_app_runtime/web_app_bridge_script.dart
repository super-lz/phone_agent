import 'dart:convert';

import '../../domain/artifacts/artifact.dart';
import 'web_app_capability_bridge.dart';

String buildWebAppBridgeHeadHtml(AgentArtifact webApp) {
  const capabilities = WebAppRuntimeDefaults.permissions;
  return '''
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <script>
    (function() {
      const manifest = ${jsonEncode(_manifestFor(webApp))};
      const supportedCapabilities = ${jsonEncode(capabilities)};
      window.PhoneAgent = {
        version: '0.1.0',
        capabilities: supportedCapabilities.slice(),
        docs: {
          callCapability: "await window.PhoneAgent.callCapability('device.info', {})",
          getDeviceInfo: "await window.PhoneAgent.getDeviceInfo()",
          getRuntimeInfo: "window.PhoneAgent.getRuntimeInfo()",
          permissionDeclaration: "artifact_create.metadata.permissions must include each called capability id",
          localMediaOutput: "camera/audio/file outputs may include output.mediaUrl, output.fileUrl, or output.localUrl for same-origin preview/playback"
        },
        getManifest: function() {
          return manifest;
        },
        getAvailableCapabilities: function() {
          return supportedCapabilities.slice();
        },
        isCapabilityAllowed: function(capabilityId) {
          return Array.isArray(manifest.permissions) && manifest.permissions.indexOf(capabilityId) !== -1;
        },
        getRuntimeInfo: function() {
          return {
            manifest: manifest,
            capabilities: supportedCapabilities.slice(),
            viewport: {
              width: window.innerWidth,
              height: window.innerHeight,
              devicePixelRatio: window.devicePixelRatio || 1
            },
            userAgent: navigator.userAgent,
            language: navigator.language,
            platform: navigator.platform,
            url: location.href
          };
        },
        callCapability: async function(capabilityId, input) {
          if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) {
            return {
              ok: false,
              capabilityId: capabilityId,
              error: 'phone_agent_bridge_unavailable'
            };
          }
          return await window.flutter_inappwebview.callHandler('PhoneAgentBridge', {
            capabilityId: capabilityId,
            input: input || {}
          });
        },
        createNote: function(input) {
          return window.PhoneAgent.callCapability('db.note.create', input || {});
        },
        queryNotes: function(input) {
          return window.PhoneAgent.callCapability('db.note.query', input || {});
        },
        readAppFile: function(path, options) {
          return window.PhoneAgent.callCapability('file.read_app_file', Object.assign({
            path: path || ''
          }, options || {}));
        },
        writeAppFile: function(path, content, options) {
          return window.PhoneAgent.callCapability('file.write_app_file', Object.assign({
            path: path || '',
            content: content || ''
          }, options || {}));
        },
        searchAppFiles: function(input) {
          return window.PhoneAgent.callCapability('file.search_app_files', input || {});
        },
        createArtifact: function(input) {
          return window.PhoneAgent.callCapability('artifact.create', input || {});
        },
        queryArtifacts: function(input) {
          return window.PhoneAgent.callCapability('artifact.query', input || {});
        },
        getAppInfo: function() {
          return window.PhoneAgent.callCapability('app.info', {});
        },
        getDeviceInfo: function() {
          return window.PhoneAgent.callCapability('device.info', {});
        },
        getCurrentTime: function() {
          return window.PhoneAgent.callCapability('time.get_current', {});
        },
        getBatteryStatus: function() {
          return window.PhoneAgent.callCapability('battery.status', {});
        },
        getNetworkStatus: function() {
          return window.PhoneAgent.callCapability('network.status', {});
        },
        readClipboard: function() {
          return window.PhoneAgent.callCapability('clipboard.read', {});
        },
        writeClipboard: function(text) {
          return window.PhoneAgent.callCapability('clipboard.write', {
            text: text || ''
          });
        },
        getCurrentLocation: function() {
          return window.PhoneAgent.callCapability('location.get_current', {});
        },
        capturePhoto: function(options) {
          return window.PhoneAgent.callCapability('camera.capture_photo', options || {});
        },
        captureVideo: function(options) {
          return window.PhoneAgent.callCapability('camera.capture_video', options || {});
        },
        setFlashlight: function(enabled) {
          return window.PhoneAgent.callCapability('flashlight.set', {
            enabled: !!enabled
          });
        },
        getFlashlightStatus: function() {
          return window.PhoneAgent.callCapability('flashlight.status', {});
        },
        pickImage: function(options) {
          return window.PhoneAgent.callCapability('media.pick_image', options || {});
        },
        pickImages: function(options) {
          return window.PhoneAgent.callCapability('media.pick_images', options || {});
        },
        pickVideo: function() {
          return window.PhoneAgent.callCapability('media.pick_video', {});
        },
        pickSystemFile: function(options) {
          return window.PhoneAgent.callCapability('file.pick_system_file', options || {});
        },
        startAudioRecording: function() {
          return window.PhoneAgent.callCapability('audio.record_start', {});
        },
        stopAudioRecording: function() {
          return window.PhoneAgent.callCapability('audio.record_stop', {});
        },
        cancelAudioRecording: function() {
          return window.PhoneAgent.callCapability('audio.record_cancel', {});
        },
        shareText: function(text, subject) {
          return window.PhoneAgent.callCapability('share.text', {
            text: text || '',
            subject: subject
          });
        },
        hapticFeedback: function(type) {
          return window.PhoneAgent.callCapability('system.haptic_feedback', {
            type: type || 'light'
          });
        },
        playSystemSound: function(type) {
          return window.PhoneAgent.callCapability('system.sound_alert', {
            type: type || 'alert'
          });
        },
        setMediaVolume: function(level) {
          return window.PhoneAgent.callCapability('system.volume.set', {
            level: Number(level)
          });
        },
        getMediaVolume: function() {
          return window.PhoneAgent.callCapability('system.volume.status', {});
        },
        setSystemUiMode: function(mode) {
          return window.PhoneAgent.callCapability('system.ui.set', {
            mode: mode || 'normal'
          });
        },
        getSystemUiStatus: function() {
          return window.PhoneAgent.callCapability('system.ui.status', {});
        },
        openPermissionSettings: function() {
          return window.PhoneAgent.callCapability('permission.open_settings', {});
        },
        openExternalUrl: function(url) {
          return window.PhoneAgent.callCapability('url.open_external', {
            url: url || ''
          });
        },
        keepScreenAwake: function(enabled) {
          return window.PhoneAgent.callCapability('screen.keep_awake', {
            enabled: !!enabled
          });
        },
        getKeepScreenAwakeStatus: function() {
          return window.PhoneAgent.callCapability('screen.keep_awake_status', {});
        },
        setScreenBrightness: function(level) {
          return window.PhoneAgent.callCapability('screen.brightness.set', {
            level: Number(level)
          });
        },
        getScreenBrightness: function() {
          return window.PhoneAgent.callCapability('screen.brightness.status', {});
        },
        getScreenMetrics: function() {
          return window.PhoneAgent.callCapability('screen.metrics', {});
        },
        setScreenOrientation: function(mode) {
          return window.PhoneAgent.callCapability('screen.orientation.set', {
            mode: mode || 'unlocked'
          });
        },
        getScreenOrientationStatus: function() {
          return window.PhoneAgent.callCapability('screen.orientation.status', {});
        },
        getAccelerometer: function() {
          return window.PhoneAgent.callCapability('sensor.accelerometer.read', {});
        },
        getGyroscope: function() {
          return window.PhoneAgent.callCapability('sensor.gyroscope.read', {});
        },
        getMagnetometer: function() {
          return window.PhoneAgent.callCapability('sensor.magnetometer.read', {});
        },
        scheduleNotification: function(input) {
          return window.PhoneAgent.callCapability('notification.schedule', input || {});
        },
        getPendingNotifications: function() {
          return window.PhoneAgent.callCapability('notification.pending', {});
        },
        cancelNotification: function(notificationId) {
          return window.PhoneAgent.callCapability('notification.cancel', {
            notification_id: notificationId
          });
        },
        cancelAllNotifications: function() {
          return window.PhoneAgent.callCapability('notification.cancel_all', {});
        },
        pickContact: function() {
          return window.PhoneAgent.callCapability('contacts.pick', {});
        },
        scanBarcode: function(options) {
          return window.PhoneAgent.callCapability('barcode.scan_camera', options || {});
        },
        scanBarcodeImage: function(options) {
          return window.PhoneAgent.callCapability('barcode.scan_image', options || {});
        },
        createCalendarEvent: function(input) {
          return window.PhoneAgent.callCapability('calendar.event.create', input || {});
        },
        webSearch: function(queryOrInput) {
          const input = typeof queryOrInput === 'string'
            ? { query: queryOrInput }
            : (queryOrInput || {});
          return window.PhoneAgent.callCapability('web.search', input);
        },
        webFetch: function(urlOrInput) {
          const input = typeof urlOrInput === 'string'
            ? { url: urlOrInput }
            : (urlOrInput || {});
          return window.PhoneAgent.callCapability('web.fetch', input);
        },
        queryMemory: function(input) {
          return window.PhoneAgent.callCapability('memory.query', input || {});
        },
        switchWorkspace: function(input) {
          return window.PhoneAgent.callCapability('workspace.switch', input || {});
        },
        subscribeEvent: function(_eventName, _handler) {
          return { unsubscribe: function() {} };
        }
      };
    })();
  </script>
  <script>
    (function() {
      function formatArg(value) {
        if (value instanceof Error) return value.stack || value.message;
        if (typeof value === 'object' && value !== null) {
          try { return JSON.stringify(value); } catch (_) { return String(value); }
        }
        return String(value);
      }
      function viewport() {
        return {
          width: window.innerWidth,
          height: window.innerHeight,
          devicePixelRatio: window.devicePixelRatio || 1
        };
      }
      function sendRuntimeLog(payload) {
        if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) return;
        try {
          window.flutter_inappwebview.callHandler('PhoneAgentRuntimeLog', Object.assign({
            url: location.href,
            userAgent: navigator.userAgent,
            viewport: viewport()
          }, payload));
        } catch (_) {}
      }
      ['log', 'info', 'warn', 'error'].forEach(function(level) {
        const original = console[level];
        console[level] = function() {
          const args = Array.prototype.slice.call(arguments);
          sendRuntimeLog({
            level: (level === 'warn' ? 'warning' : (level === 'log' ? 'info' : level)),
            source: 'console.' + level,
            message: args.map(formatArg).join(' ')
          });
          return original.apply(console, args);
        };
      });
      window.addEventListener('error', function(event) {
        sendRuntimeLog({
          level: 'error',
          source: 'window.error',
          message: event.message || 'Uncaught error',
          filename: event.filename,
          line: event.lineno,
          column: event.colno,
          stackTrace: event.error && event.error.stack
        });
      });
      window.addEventListener('unhandledrejection', function(event) {
        sendRuntimeLog({
          level: 'error',
          source: 'unhandledrejection',
          message: formatArg(event.reason),
          stackTrace: event.reason && event.reason.stack
        });
      });
    })();
  </script>
''';
}

Map<String, Object?> _manifestFor(AgentArtifact webApp) {
  return {
    'id': webApp.id,
    'title': webApp.title,
    'entry': webApp.metadata['entry'] ?? 'index.html',
    'permissions': webApp.metadata['permissions'] ?? <String>[],
    'databaseNamespace': webApp.metadata['databaseNamespace'],
    'fileNamespace': webApp.metadata['fileNamespace'],
  };
}
