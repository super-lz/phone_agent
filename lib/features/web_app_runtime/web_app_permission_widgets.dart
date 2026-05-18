import 'package:flutter/material.dart';

import '../../domain/artifacts/artifact.dart';

class WebAppPermissionGate extends StatelessWidget {
  const WebAppPermissionGate({
    required this.webApp,
    required this.onApprove,
    required this.onDeny,
    super.key,
  });

  final AgentArtifact webApp;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final permissions = _permissions;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('权限确认', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '${webApp.title} 请求使用以下能力。拒绝后应用仍可打开，但 JSBridge 调用会返回权限错误。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final permission in permissions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension_outlined),
            title: Text(permission),
            subtitle: const Text('通过 Phone Agent Capability Runtime 受控执行'),
          ),
        if (permissions.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_open_outlined),
            title: Text('未声明受控能力'),
          ),
        const SizedBox(height: 20),
        FilledButton(onPressed: onApprove, child: const Text('允许并打开')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onDeny, child: const Text('拒绝并打开')),
      ],
    );
  }

  List<String> get _permissions {
    final permissions = webApp.metadata['permissions'];
    if (permissions is! List<Object?>) {
      return const [];
    }
    return permissions.whereType<String>().toList(growable: false);
  }
}

class WebAppPermissionDeniedBanner extends StatelessWidget {
  const WebAppPermissionDeniedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.block_outlined,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已拒绝此 Web App 的能力权限',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
