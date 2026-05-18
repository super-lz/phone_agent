import 'package:flutter/material.dart';

class TodoBlock extends StatelessWidget {
  const TodoBlock({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Row(
              children: [
                const Icon(Icons.check, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
        ],
      ),
    );
  }
}
