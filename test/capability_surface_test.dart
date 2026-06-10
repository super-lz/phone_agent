import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/bootstrap/phone_agent_seed.dart';
import 'package:phone_agent/domain/capabilities/capability.dart';
import 'package:phone_agent/features/web_app_runtime/web_app_capability_bridge.dart';

void main() {
  test('first-version Web App permissions exist in seed capabilities', () {
    final seedCapabilities = PhoneAgentSeed.capabilities()
        .map((capability) => capability.id)
        .toSet();

    expect(seedCapabilities, containsAll(WebAppRuntimeDefaults.permissions));
    expect(seedCapabilities, contains('project.test_web_app'));
  });

  test('native seed capabilities have expected adapters and permissions', () {
    final byId = {
      for (final capability in PhoneAgentSeed.capabilities())
        capability.id: capability,
    };

    for (final capabilityId in const [
      'device.info',
      'time.get_current',
      'battery.status',
      'network.status',
      'clipboard.read',
      'clipboard.write',
      'camera.capture_photo',
      'camera.capture_video',
      'media.pick_image',
      'media.pick_video',
      'file.pick_system_file',
      'audio.record_start',
      'audio.record_stop',
      'audio.record_cancel',
      'contacts.pick',
      'barcode.scan_camera',
      'barcode.scan_image',
      'share.text',
      'system.haptic_feedback',
      'system.sound_alert',
      'system.volume.set',
      'system.volume.status',
      'system.ui.set',
      'system.ui.status',
      'permission.open_settings',
      'url.open_external',
      'screen.keep_awake',
      'screen.keep_awake_status',
      'screen.orientation.set',
      'screen.orientation.status',
      'screen.metrics',
      'sensor.accelerometer.read',
      'sensor.gyroscope.read',
      'sensor.magnetometer.read',
      'location.get_current',
      'notification.schedule',
      'notification.pending',
      'notification.cancel',
      'notification.cancel_all',
      'calendar.event.create',
    ]) {
      expect(byId[capabilityId]?.adapter, CapabilityAdapter.native);
    }

    expect(
      byId['location.get_current']?.requiredPermissions,
      contains('location'),
    );
    expect(
      byId['notification.schedule']?.requiredPermissions,
      contains('notifications'),
    );
    expect(
      byId['camera.capture_photo']?.requiredPermissions,
      contains('camera'),
    );
    expect(
      byId['camera.capture_video']?.requiredPermissions,
      containsAll(['camera', 'microphone']),
    );
    expect(
      byId['audio.record_start']?.requiredPermissions,
      contains('microphone'),
    );
    expect(byId['contacts.pick']?.requiredPermissions, contains('contacts'));
    expect(
      byId['barcode.scan_camera']?.requiredPermissions,
      contains('camera'),
    );
  });

  test('first-version native tool names are exposed to the model', () {
    final toolNames = CapabilityRuntime().toolDefinitions
        .map((tool) => tool['function'])
        .whereType<Map<String, Object?>>()
        .map((function) => function['name'])
        .whereType<String>()
        .toSet();

    expect(
      toolNames,
      containsAll(const [
        'device_info',
        'time_get_current',
        'battery_status',
        'network_status',
        'clipboard_read',
        'clipboard_write',
        'camera_capture_photo',
        'camera_capture_video',
        'flashlight_set',
        'flashlight_status',
        'media_pick_image',
        'media_pick_images',
        'media_pick_video',
        'file_pick_system_file',
        'audio_record_start',
        'audio_record_stop',
        'audio_record_cancel',
        'contacts_pick',
        'barcode_scan_camera',
        'barcode_scan_image',
        'share_text',
        'system_haptic_feedback',
        'system_sound_alert',
        'system_volume_set',
        'system_volume_status',
        'system_ui_set',
        'system_ui_status',
        'permission_open_settings',
        'url_open_external',
        'screen_keep_awake',
        'screen_keep_awake_status',
        'screen_brightness_set',
        'screen_brightness_status',
        'screen_metrics',
        'screen_orientation_set',
        'screen_orientation_status',
        'sensor_accelerometer_read',
        'sensor_gyroscope_read',
        'sensor_magnetometer_read',
        'location_get_current',
        'notification_schedule',
        'notification_pending',
        'notification_cancel',
        'notification_cancel_all',
        'calendar_event_create',
        'project_test_web_app',
      ]),
    );
  });
}
