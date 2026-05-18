import 'package:flutter/material.dart';

class LoadEarlierMessagesButton extends StatelessWidget {
  const LoadEarlierMessagesButton({
    required this.hiddenCount,
    required this.onPressed,
    super.key,
  });

  final int hiddenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
          label: Text('加载更早消息 · $hiddenCount'),
        ),
      ),
    );
  }
}
