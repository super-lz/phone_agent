import 'package:bz_map/bz_map.dart';
import 'package:flutter/material.dart';

import '../../data/amap/amap_runtime_config.dart';

class AmapLocationPage extends StatelessWidget {
  const AmapLocationPage({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.title,
    this.subtitle,
    super.key,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    const config = AmapRuntimeConfig();
    return Scaffold(
      appBar: AppBar(title: Text(title ?? '地图查看')),
      body: !config.supportsCurrentPlatform
          ? _MapUnavailable(message: '当前平台暂不支持高德地图：${config.platformName}。')
          : !config.hasCurrentPlatformKey
          ? const _MapUnavailable(
              message:
                  '缺少高德地图 Key。请通过 --dart-define-from-file=config/amap_keys.local.json 启动应用。',
            )
          : _MapBody(
              config: config,
              latitude: latitude,
              longitude: longitude,
              accuracy: accuracy,
              title: title,
              subtitle: subtitle,
            ),
    );
  }
}

class _MapBody extends StatelessWidget {
  const _MapBody({
    required this.config,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.title,
    this.subtitle,
  });

  final AmapRuntimeConfig config;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    final markerTitle = title ?? '目标位置';
    final markerSnippet =
        subtitle ??
        '纬度 ${latitude.toStringAsFixed(6)}，经度 ${longitude.toStringAsFixed(6)}'
            '${accuracy == null ? '' : '，精度约 ${accuracy!.toStringAsFixed(0)} 米'}';
    return Stack(
      children: [
        AMapWidget(
          apiKey: AMapApiKey(
            androidKey: config.androidKey,
            iosKey: config.iosKey,
          ),
          privacyStatement: const AMapPrivacyStatement(
            hasContains: true,
            hasShow: true,
            hasAgree: true,
          ),
          initialCameraPosition: CameraPosition(target: point, zoom: 16),
          scaleEnabled: true,
          compassEnabled: true,
          trafficEnabled: false,
          markers: {
            Marker(
              position: point,
              infoWindow: InfoWindow(
                title: markerTitle,
                snippet: markerSnippet,
              ),
            ),
          },
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.paddingOf(context).bottom,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    markerTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    markerSnippet,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
