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
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('权限管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          const SizedBox(width: 8),
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
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: data.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PermissionTile(
                  snapshot: data[index],
                  onRequest: () => _request(data[index].descriptor.id),
                  onOpenSettings: _openSettings,
                ),
              );
            },
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
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _iconFor(descriptor.id),
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    descriptor.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusChip(status: snapshot.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              descriptor.description,
              style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
            ),
            const SizedBox(height: 8),
            Text(
              snapshot.detail,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 16),
            const Text(
              '影响的能力:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final capability in descriptor.affectedCapabilities)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      capability,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (snapshot.canRequestInApp)
                  FilledButton.icon(
                    onPressed: onRequest,
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: const Text('立即授权'),
                  ),
                if (snapshot.canRequestInApp && snapshot.shouldOpenSettings)
                  const SizedBox(width: 8),
                if (snapshot.canOpenSettings && snapshot.shouldOpenSettings)
                  OutlinedButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('系统设置'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(AppPermissionId id) {
    return switch (id) {
      AppPermissionId.location => Icons.location_on_outlined,
      AppPermissionId.notifications => Icons.notifications_outlined,
      AppPermissionId.camera => Icons.camera_alt_outlined,
      AppPermissionId.microphone => Icons.mic_none_outlined,
      AppPermissionId.contacts => Icons.contacts_outlined,
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AppPermissionStatusKind status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      AppPermissionStatusKind.granted ||
      AppPermissionStatusKind.limited ||
      AppPermissionStatusKind.provisional => (
        const Color(0xFFDCFCE7),
        const Color(0xFF166534),
      ),
      AppPermissionStatusKind.denied => (
        const Color(0xFFFEF3C7),
        const Color(0xFF92400E),
      ),
      AppPermissionStatusKind.permanentlyDenied ||
      AppPermissionStatusKind.restricted ||
      AppPermissionStatusKind.serviceDisabled ||
      AppPermissionStatusKind.unavailable => (
        const Color(0xFFFEE2E2),
        const Color(0xFF991B1B),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
