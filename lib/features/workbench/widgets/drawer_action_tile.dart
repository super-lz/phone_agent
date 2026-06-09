import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';

class DrawerActionTile extends StatelessWidget {
  const DrawerActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return ListTile(
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(icon, color: color ?? colors.textSecondary, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: color ?? colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
