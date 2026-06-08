import 'package:flutter/material.dart';

import '../../../domain/memory/memory.dart';

class MemoryEditorDialog extends StatefulWidget {
  const MemoryEditorDialog({this.memory, super.key});

  final AgentMemory? memory;

  @override
  State<MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<MemoryEditorDialog> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    final memory = widget.memory;
    _textController = TextEditingController(text: memory?.content ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.memory == null ? '新增记忆' : '编辑记忆'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '长期记忆会在所有 Workspace 中自动作为上下文使用。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            minLines: 3,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '记忆内容',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_textController.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
