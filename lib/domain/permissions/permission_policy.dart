import '../capabilities/capability.dart';

enum PermissionMode { defaultMode, autoReview, fullAccess }

enum PermissionDecision { allow, ask, deny }

class PermissionPolicy {
  const PermissionPolicy(this.mode);

  final PermissionMode mode;

  PermissionDecision decide(CapabilityDefinition capability) {
    switch (mode) {
      case PermissionMode.defaultMode:
        return capability.risk == CapabilityRisk.high
            ? PermissionDecision.ask
            : PermissionDecision.allow;
      case PermissionMode.autoReview:
        return capability.risk == CapabilityRisk.high
            ? PermissionDecision.ask
            : PermissionDecision.allow;
      case PermissionMode.fullAccess:
        return PermissionDecision.allow;
    }
  }
}

extension PermissionModeLabel on PermissionMode {
  String get label {
    switch (this) {
      case PermissionMode.defaultMode:
        return '默认权限';
      case PermissionMode.autoReview:
        return '自动审查';
      case PermissionMode.fullAccess:
        return '完全访问权限';
    }
  }
}
