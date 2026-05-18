import 'package:flutter/material.dart';

class ApprovalBlock extends StatelessWidget {
  const ApprovalBlock({
    required this.data,
    required this.onApprove,
    required this.onDeny,
    super.key,
  });

  final Map<String, Object?> data;
  final ValueChanged<Map<String, Object?>>? onApprove;
  final ValueChanged<Map<String, Object?>>? onDeny;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final pending = status == 'pending';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: const Color(0xFFE6C76B)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '需要确认 · ${data['capabilityId']}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(data['detail'] as String? ?? '该能力需要用户确认后才能执行。'),
          const SizedBox(height: 8),
          SelectableText(
            data['input']?.toString() ?? '{}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (pending)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('允许执行'),
                  onPressed: onApprove == null ? null : () => onApprove!(data),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('拒绝'),
                  onPressed: onDeny == null ? null : () => onDeny!(data),
                ),
              ],
            )
          else
            Text(
              status == 'approved' ? '已允许执行' : '已拒绝',
              style: Theme.of(context).textTheme.labelMedium,
            ),
        ],
      ),
    );
  }
}
