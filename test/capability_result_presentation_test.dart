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
}
