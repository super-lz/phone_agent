import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/permissions/app_permission.dart';

void main() {
  test('system permission registry lists all affected native capabilities', () {
    final camera = AppPermissionRegistry.byId(AppPermissionId.camera);
    final microphone = AppPermissionRegistry.byId(AppPermissionId.microphone);

    expect(camera.affectedCapabilities, contains('camera.capture_photo'));
    expect(camera.affectedCapabilities, contains('camera.capture_video'));
    expect(camera.affectedCapabilities, contains('barcode.scan_camera'));
    expect(microphone.affectedCapabilities, contains('camera.capture_video'));
    expect(microphone.affectedCapabilities, contains('audio.record_start'));
    expect(microphone.affectedCapabilities, contains('audio.record_stop'));
    expect(microphone.affectedCapabilities, contains('audio.record_cancel'));
  });
}
