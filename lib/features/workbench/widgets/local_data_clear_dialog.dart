import 'package:flutter/material.dart';

Future<bool?> showLocalDataClearDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清理本地数据'),
      content: const Text(
        '将清空工作区、会话、长期记忆、Note、Artifact、Web App、工作区文件和工具审计记录。'
        '\n\n模型名称和 API Key 会保留。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('清理'),
        ),
      ],
    ),
  );
}
