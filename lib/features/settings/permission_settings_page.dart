import 'package:flutter/material.dart';

import '../../data/permissions/app_permission_service.dart';
import '../../domain/permissions/app_permission.dart';

class PermissionSettingsPage extends StatefulWidget {
  const PermissionSettingsPage({
    this.permissionService = const AppPermissionService(),
    super.key,
  });

  final AppPermissionService permissionService;

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage>
    with WidgetsBindingObserver {
  late Future<List<AppPermissionSnapshot>> _snapshotsFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapshotsFuture = widget.permissionService.getSnapshots();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _snapshotsFuture = widget.permissionService.getSnapshots();
    });
  }

  Future<void> _request(AppPermissionId id) async {
    await widget.permissionService.request(id);
    _reload();
  }

  Future<void> _openSettings() async {
    await widget.permissionService.openSettings();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限管理'),
        actions: [
          IconButton(
            tooltip: '刷新权限状态',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<AppPermissionSnapshot>>(
        future: _snapshotsFuture,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done ||
              data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              return _PermissionTile(
                snapshot: data[index],
                onRequest: () => _request(data[index].descriptor.id),
                onOpenSettings: _openSettings,
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: data.length,
          );
        },
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.snapshot,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final AppPermissionSnapshot snapshot;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final descriptor = snapshot.descriptor;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    descriptor.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: snapshot.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              descriptor.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(snapshot.detail, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final capability in descriptor.affectedCapabilities)
                  Chip(
                    label: Text(capability),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (snapshot.canRequestInApp)
                  FilledButton.tonalIcon(
                    onPressed: onRequest,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('申请'),
                  ),
                if (snapshot.canRequestInApp && snapshot.shouldOpenSettings)
                  const SizedBox(width: 8),
                if (snapshot.canOpenSettings && snapshot.shouldOpenSettings)
                  OutlinedButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('系统设置'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AppPermissionStatusKind status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      AppPermissionStatusKind.granted ||
      AppPermissionStatusKind.limited ||
      AppPermissionStatusKind.provisional => colorScheme.primaryContainer,
      AppPermissionStatusKind.denied => colorScheme.secondaryContainer,
      AppPermissionStatusKind.permanentlyDenied ||
      AppPermissionStatusKind.restricted ||
      AppPermissionStatusKind.serviceDisabled ||
      AppPermissionStatusKind.unavailable => colorScheme.errorContainer,
    };
    final textColor = switch (status) {
      AppPermissionStatusKind.granted ||
      AppPermissionStatusKind.limited ||
      AppPermissionStatusKind.provisional => colorScheme.onPrimaryContainer,
      AppPermissionStatusKind.denied => colorScheme.onSecondaryContainer,
      AppPermissionStatusKind.permanentlyDenied ||
      AppPermissionStatusKind.restricted ||
      AppPermissionStatusKind.serviceDisabled ||
      AppPermissionStatusKind.unavailable => colorScheme.onErrorContainer,
    };
    return Chip(
      label: Text(status.label),
      backgroundColor: color,
      labelStyle: TextStyle(color: textColor),
      visualDensity: VisualDensity.compact,
    );
  }
}
