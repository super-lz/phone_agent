enum AppPermissionId { location, notifications, camera, microphone, contacts }

enum AppPermissionStatusKind {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  limited,
  provisional,
  serviceDisabled,
  unavailable,
}

class AppPermissionDescriptor {
  const AppPermissionDescriptor({
    required this.id,
    required this.title,
    required this.description,
    required this.affectedCapabilities,
    this.canRequestInApp = true,
    this.checksSystemService = false,
  });

  final AppPermissionId id;
  final String title;
  final String description;
  final List<String> affectedCapabilities;
  final bool canRequestInApp;
  final bool checksSystemService;
}

class AppPermissionSnapshot {
  const AppPermissionSnapshot({
    required this.descriptor,
    required this.status,
    required this.detail,
    this.canOpenSettings = true,
  });

  final AppPermissionDescriptor descriptor;
  final AppPermissionStatusKind status;
  final String detail;
  final bool canOpenSettings;

  bool get granted {
    return status == AppPermissionStatusKind.granted ||
        status == AppPermissionStatusKind.limited ||
        status == AppPermissionStatusKind.provisional;
  }

  bool get canRequestInApp {
    return descriptor.canRequestInApp &&
        (status == AppPermissionStatusKind.denied ||
            status == AppPermissionStatusKind.unavailable);
  }

  bool get shouldOpenSettings {
    return status == AppPermissionStatusKind.permanentlyDenied ||
        status == AppPermissionStatusKind.restricted ||
        status == AppPermissionStatusKind.serviceDisabled;
  }
}

class AppPermissionRegistry {
  const AppPermissionRegistry._();

  static const descriptors = [
    AppPermissionDescriptor(
      id: AppPermissionId.location,
      title: '位置',
      description: '用于用户明确要求基于当前位置处理任务时获取当前定位。',
      affectedCapabilities: ['location.get_current'],
      checksSystemService: true,
    ),
    AppPermissionDescriptor(
      id: AppPermissionId.notifications,
      title: '通知',
      description: '用于用户明确要求稍后提醒时发送本地系统通知。',
      affectedCapabilities: ['notification.schedule'],
    ),
    AppPermissionDescriptor(
      id: AppPermissionId.camera,
      title: '相机',
      description: '用于用户明确要求拍照、拍视频或本地 Web App 请求相机输入时采集画面。',
      affectedCapabilities: [
        'camera.capture_photo',
        'camera.capture_video',
        'barcode.scan_camera',
      ],
    ),
    AppPermissionDescriptor(
      id: AppPermissionId.microphone,
      title: '麦克风',
      description: '用于用户明确要求录音、拍摄带声音的视频或本地 Web App 请求音频输入时采集声音。',
      affectedCapabilities: [
        'camera.capture_video',
        'audio.record_start',
        'audio.record_stop',
        'audio.record_cancel',
      ],
    ),
    AppPermissionDescriptor(
      id: AppPermissionId.contacts,
      title: '联系人',
      description: '用于用户明确要求从系统通讯录选择联系人时读取被选中的联系人姓名、电话和邮箱。',
      affectedCapabilities: ['contacts.pick'],
    ),
  ];

  static AppPermissionDescriptor byId(AppPermissionId id) {
    return descriptors.firstWhere((descriptor) => descriptor.id == id);
  }
}

extension AppPermissionStatusKindLabel on AppPermissionStatusKind {
  String get label {
    switch (this) {
      case AppPermissionStatusKind.granted:
        return '已允许';
      case AppPermissionStatusKind.denied:
        return '未允许';
      case AppPermissionStatusKind.permanentlyDenied:
        return '已永久拒绝';
      case AppPermissionStatusKind.restricted:
        return '受系统限制';
      case AppPermissionStatusKind.limited:
        return '部分允许';
      case AppPermissionStatusKind.provisional:
        return '临时允许';
      case AppPermissionStatusKind.serviceDisabled:
        return '系统服务关闭';
      case AppPermissionStatusKind.unavailable:
        return '状态不可用';
    }
  }
}
