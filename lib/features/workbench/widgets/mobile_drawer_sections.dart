import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../data/models/model_api_key_store.dart';
import '../../../data/models/model_settings_store.dart';
import '../../../data/permissions/app_permission_service.dart';
import '../../../domain/workbench/workbench_store.dart';
import '../../settings/model_settings_page.dart';
import '../../settings/permission_settings_page.dart';
import '../audit_log_page.dart';
import 'drawer_action_tile.dart';

class MobileDrawerHeader extends StatelessWidget {
  const MobileDrawerHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.phoneAgentColors;
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
        decoration: BoxDecoration(color: colors.panelBackground),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primaryAction,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'Phone Agent',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileDrawerFooter extends StatelessWidget {
  const MobileDrawerFooter({
    required this.workbenchStore,
    required this.permissionService,
    required this.apiKeyStore,
    required this.modelSettingsStore,
    required this.onClearLocalData,
    super.key,
  });

  final WorkbenchStore? workbenchStore;
  final AppPermissionService permissionService;
  final ModelApiKeyStore apiKeyStore;
  final ModelSettingsStore modelSettingsStore;
  final VoidCallback onClearLocalData;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            DrawerActionTile(
              icon: Icons.history_outlined,
              label: '操作审计日志',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        AuditLogPage(workbenchStore: workbenchStore!),
                  ),
                );
              },
            ),
            DrawerActionTile(
              icon: Icons.privacy_tip_outlined,
              label: '权限管理',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => PermissionSettingsPage(
                      permissionService: permissionService,
                    ),
                  ),
                );
              },
            ),
            DrawerActionTile(
              icon: Icons.settings_outlined,
              label: '模型设置',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => ModelSettingsPage(
                      apiKeyStore: apiKeyStore,
                      modelSettingsStore: modelSettingsStore,
                    ),
                  ),
                );
              },
            ),
            DrawerActionTile(
              icon: Icons.cleaning_services_outlined,
              label: '清理本地数据',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                onClearLocalData();
              },
            ),
          ],
        ),
      ),
    );
  }
}
