import 'package:permission_handler/permission_handler.dart' as permission_api;

import '../../domain/permissions/app_permission.dart';

class AppPermissionService {
  const AppPermissionService();

  Future<List<AppPermissionSnapshot>> getSnapshots() async {
    final snapshots = <AppPermissionSnapshot>[];
    for (final descriptor in AppPermissionRegistry.descriptors) {
      snapshots.add(await getStatus(descriptor.id));
    }
    return snapshots;
  }

  Future<AppPermissionSnapshot> getStatus(AppPermissionId id) async {
    final descriptor = AppPermissionRegistry.byId(id);
    try {
      final permission = _permissionFor(id);
      final status = await permission.status;
      return await _snapshotFor(
        descriptor: descriptor,
        permission: permission,
        status: status,
      );
    } on Object catch (error) {
      return AppPermissionSnapshot(
        descriptor: descriptor,
        status: AppPermissionStatusKind.unavailable,
        detail: '读取权限状态失败：$error',
      );
    }
  }

  Future<AppPermissionSnapshot> request(AppPermissionId id) async {
    final descriptor = AppPermissionRegistry.byId(id);
    if (!descriptor.canRequestInApp) {
      return getStatus(id);
    }
    try {
      final permission = _permissionFor(id);
      final status = await permission.request();
      return await _snapshotFor(
        descriptor: descriptor,
        permission: permission,
        status: status,
      );
    } on Object catch (error) {
      return AppPermissionSnapshot(
        descriptor: descriptor,
        status: AppPermissionStatusKind.unavailable,
        detail: '申请权限失败：$error',
      );
    }
  }

  Future<AppPermissionSnapshot> ensureGranted(AppPermissionId id) async {
    final current = await getStatus(id);
    if (current.granted || current.shouldOpenSettings) {
      return current;
    }
    if (!current.canRequestInApp) {
      return current;
    }
    return request(id);
  }

  Future<bool> openSettings() {
    return permission_api.openAppSettings();
  }

  permission_api.Permission _permissionFor(AppPermissionId id) {
    switch (id) {
      case AppPermissionId.location:
        return permission_api.Permission.locationWhenInUse;
      case AppPermissionId.notifications:
        return permission_api.Permission.notification;
      case AppPermissionId.camera:
        return permission_api.Permission.camera;
      case AppPermissionId.microphone:
        return permission_api.Permission.microphone;
      case AppPermissionId.contacts:
        return permission_api.Permission.contacts;
    }
  }

  Future<AppPermissionSnapshot> _snapshotFor({
    required AppPermissionDescriptor descriptor,
    required permission_api.Permission permission,
    required permission_api.PermissionStatus status,
  }) async {
    if (descriptor.checksSystemService &&
        permission is permission_api.PermissionWithService) {
      final serviceStatus = await permission.serviceStatus;
      if (serviceStatus.isDisabled) {
        return AppPermissionSnapshot(
          descriptor: descriptor,
          status: AppPermissionStatusKind.serviceDisabled,
          detail: '系统服务已关闭，请到系统设置开启后再使用。',
        );
      }
    }
    final normalized = _normalizeStatus(status);
    return AppPermissionSnapshot(
      descriptor: descriptor,
      status: normalized,
      detail: _detailFor(normalized),
    );
  }

  AppPermissionStatusKind _normalizeStatus(
    permission_api.PermissionStatus status,
  ) {
    if (status.isGranted) {
      return AppPermissionStatusKind.granted;
    }
    if (status.isPermanentlyDenied) {
      return AppPermissionStatusKind.permanentlyDenied;
    }
    if (status.isRestricted) {
      return AppPermissionStatusKind.restricted;
    }
    if (status.isLimited) {
      return AppPermissionStatusKind.limited;
    }
    if (status.isProvisional) {
      return AppPermissionStatusKind.provisional;
    }
    return AppPermissionStatusKind.denied;
  }

  String _detailFor(AppPermissionStatusKind status) {
    switch (status) {
      case AppPermissionStatusKind.granted:
        return '当前已授权。';
      case AppPermissionStatusKind.denied:
        return '当前未授权，可以在 App 内发起系统授权申请。';
      case AppPermissionStatusKind.permanentlyDenied:
        return '权限已被永久拒绝，需要到系统设置中重新允许。';
      case AppPermissionStatusKind.restricted:
        return '权限受到系统策略限制，需要到系统设置检查。';
      case AppPermissionStatusKind.limited:
        return '系统只授予了部分访问能力。';
      case AppPermissionStatusKind.provisional:
        return '系统授予了临时或静默授权。';
      case AppPermissionStatusKind.serviceDisabled:
        return '系统服务已关闭。';
      case AppPermissionStatusKind.unavailable:
        return '当前平台无法读取权限状态。';
    }
  }
}
