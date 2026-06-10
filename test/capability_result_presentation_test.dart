import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/capability_result_presentation.dart';

void main() {
  test(
    'amap location keeps provider and coordinate metadata for the model',
    () {
      final output = {
        'ok': true,
        'latitude': 31.2304,
        'longitude': 121.4737,
        'accuracy': 42.0,
        'timestamp': '2026-05-19T14:38:46.000',
        'address': '上海市黄浦区人民大道',
        'provider': 'amap_location',
        'coordinateSystem': 'gcj02',
        'isCurrent': true,
        'locationSource': 'amap_current',
        'providerHint': 'amap_location_android',
        'mapsUrl': 'https://uri.amap.com/marker?position=121.4737,31.2304',
      };

      final presentation = presentCapabilityResult(
        capabilityId: 'location.get_current',
        output: output,
      );
      final observation = modelObservationForCapability(
        capabilityId: 'location.get_current',
        output: output,
      );

      expect(presentation.ok, isTrue);
      expect(presentation.summary, startsWith('当前位置：上海市黄浦区人民大道'));
      expect(observation['provider'], 'amap_location');
      expect(observation['coordinateSystem'], 'gcj02');
      expect(observation['isCurrent'], isTrue);
      expect(observation['locationSource'], 'amap_current');
      expect(observation['providerHint'], 'amap_location_android');
      expect(observation['mapsUrl'], contains('uri.amap.com'));
    },
  );

  test('native action results produce useful summaries and observations', () {
    final notification = _presentAndObserve(
      capabilityId: 'notification.schedule',
      output: const {
        'ok': true,
        'notificationId': 42,
        'title': '喝水',
        'body': '休息一下',
        'scheduledAt': '2026-06-10T16:30:00',
      },
    );
    expect(notification.presentation.summary, contains('喝水'));
    expect(notification.observation['notificationId'], 42);
    expect(notification.observation['body'], '休息一下');

    final sensor = _presentAndObserve(
      capabilityId: 'sensor.accelerometer.read',
      output: const {
        'ok': true,
        'sensor': 'accelerometer',
        'x': 1.23456,
        'y': -2.0,
        'z': 9.8,
      },
    );
    expect(sensor.presentation.summary, contains('加速度计 当前读数'));
    expect(sensor.observation['sensor'], 'accelerometer');
    expect(sensor.observation['z'], 9.8);

    final url = _presentAndObserve(
      capabilityId: 'url.open_external',
      output: const {
        'ok': true,
        'opened': true,
        'url': 'https://example.com',
        'scheme': 'https',
      },
    );
    expect(url.presentation.summary, contains('https://example.com'));
    expect(url.observation['scheme'], 'https');

    final calendar = _presentAndObserve(
      capabilityId: 'calendar.event.create',
      output: const {
        'ok': true,
        'title': '项目会',
        'startsAt': '2026-06-10T18:00:00',
        'endsAt': '2026-06-10T19:00:00',
        'allDay': false,
        'requiresUserConfirmation': true,
        'completionInferred': false,
      },
    );
    expect(calendar.presentation.summary, contains('系统日历添加流程'));
    expect(calendar.observation['requiresUserConfirmation'], isTrue);
  });

  test('native side-effect results avoid generic completed summary', () {
    final share = _presentAndObserve(
      capabilityId: 'share.text',
      output: const {'ok': true, 'status': 'success', 'length': 12},
    );
    expect(share.presentation.summary, contains('success'));
    expect(share.observation['length'], 12);

    final haptic = _presentAndObserve(
      capabilityId: 'system.haptic_feedback',
      output: const {'ok': true, 'type': 'selection'},
    );
    expect(haptic.presentation.summary, contains('选择'));
    expect(haptic.observation['type'], 'selection');

    final sound = _presentAndObserve(
      capabilityId: 'system.sound_alert',
      output: const {'ok': true, 'type': 'click'},
    );
    expect(sound.presentation.summary, contains('点击音'));
    expect(sound.observation['type'], 'click');

    final systemUi = _presentAndObserve(
      capabilityId: 'system.ui.set',
      output: const {
        'ok': true,
        'mode': 'immersive_sticky',
        'overlays': <String>[],
        'isFullscreen': true,
      },
    );
    expect(systemUi.presentation.summary, contains('粘性沉浸'));
    expect(systemUi.observation['isFullscreen'], isTrue);

    final systemUiStatus = _presentAndObserve(
      capabilityId: 'system.ui.status',
      output: const {
        'ok': true,
        'mode': 'normal',
        'overlays': ['top', 'bottom'],
        'isFullscreen': false,
      },
    );
    expect(systemUiStatus.presentation.summary, contains('状态栏和导航栏'));
    expect(systemUiStatus.observation['mode'], 'normal');

    final orientation = _presentAndObserve(
      capabilityId: 'screen.orientation.set',
      output: const {
        'ok': true,
        'mode': 'landscape',
        'locked': true,
        'preferredOrientations': ['landscape_left', 'landscape_right'],
      },
    );
    expect(orientation.presentation.summary, contains('横屏'));
    expect(orientation.observation['locked'], isTrue);

    final orientationStatus = _presentAndObserve(
      capabilityId: 'screen.orientation.status',
      output: const {
        'ok': true,
        'mode': 'unlocked',
        'locked': false,
        'preferredOrientations': <String>[],
      },
    );
    expect(orientationStatus.presentation.summary, contains('自动旋转'));
    expect(orientationStatus.observation['mode'], 'unlocked');
  });
}

({CapabilityResultPresentation presentation, Map<String, Object?> observation})
_presentAndObserve({
  required String capabilityId,
  required Map<String, Object?> output,
}) {
  return (
    presentation: presentCapabilityResult(
      capabilityId: capabilityId,
      output: output,
    ),
    observation: modelObservationForCapability(
      capabilityId: capabilityId,
      output: output,
    ),
  );
}
