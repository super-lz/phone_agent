import 'package:flutter/material.dart';

import '../../../domain/conversation/message_block.dart';
import '../../../domain/workspace/workspace.dart';
import 'message_view.dart';

class ChatPanel extends StatelessWidget {
  const ChatPanel({
    required this.workspace,
    required this.messages,
    required this.composerController,
    required this.onSendPrompt,
    super.key,
  });

  final AgentWorkspace workspace;
  final List<AgentMessage> messages;
  final TextEditingController composerController;
  final VoidCallback onSendPrompt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _WorkspaceHeader(workspace: workspace),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              return MessageView(message: messages[index]);
            },
          ),
        ),
        const Divider(height: 1),
        _PromptComposer(
          controller: composerController,
          onSendPrompt: onSendPrompt,
        ),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.workspace});

  final AgentWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.workspaces_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workspace.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  workspace.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptComposer extends StatelessWidget {
  const _PromptComposer({required this.controller, required this.onSendPrompt});

  final TextEditingController controller;
  final VoidCallback onSendPrompt;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            IconButton(
              tooltip: '添加文件',
              icon: const Icon(Icons.attach_file),
              onPressed: () {},
            ),
            IconButton(
              tooltip: '添加图片',
              icon: const Icon(Icons.image_outlined),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: '输入任务，例如：搜索 Flutter WebView Bridge，或：记住我喜欢结构化输出',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onSendPrompt(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('发送'),
              onPressed: onSendPrompt,
            ),
          ],
        ),
      ),
    );
  }
}
