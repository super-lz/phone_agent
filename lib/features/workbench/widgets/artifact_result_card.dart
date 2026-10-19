import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';

/// Generic artifacts have no preview callback. Do not imply an open action.
class ArtifactResultCard extends StatelessWidget {
  const ArtifactResultCard({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: colors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
