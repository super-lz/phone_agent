import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../domain/conversation/message_block.dart';

class PendingAttachmentStrip extends StatelessWidget {
  const PendingAttachmentStrip({
    required this.attachments,
    required this.onRemove,
    super.key,
  });

  final List<MessageBlock> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            return _PendingAttachmentCard(
              key: ValueKey('pending-attachment-$index'),
              block: attachments[index],
              onRemove: () => onRemove(index),
            );
          },
        ),
      ),
    );
  }
}

class _PendingAttachmentCard extends StatelessWidget {
  const _PendingAttachmentCard({
    required this.block,
    required this.onRemove,
    super.key,
  });

  final MessageBlock block;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final name = block.data['name'] as String? ?? '未命名附件';
    final bytes = block.data['bytes'];

    return Container(
      width: 176,
      decoration: BoxDecoration(
        color: colors.cardBackground.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _AttachmentThumbnail(block: block),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          letterSpacing: 0,
                        ),
                      ),
                      if (bytes is int) ...[
                        const SizedBox(height: 3),
                        Text(
                          _formatBytes(bytes),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: '移除附件',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              style: IconButton.styleFrom(
                fixedSize: const Size(28, 28),
                minimumSize: const Size(28, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: colors.cardBackground.withValues(alpha: 0.88),
                foregroundColor: colors.textSecondary,
              ),
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({required this.block});

  final MessageBlock block;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final isImage = block.type == MessageBlockType.image;
    final icon = isImage
        ? Icons.image_outlined
        : Icons.insert_drive_file_outlined;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.inputBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colors.border.withValues(alpha: 0.72)),
      ),
      clipBehavior: Clip.antiAlias,
      child: isImage ? _imagePreview(context, icon) : Icon(icon, size: 22),
    );
  }

  Widget _imagePreview(BuildContext context, IconData fallbackIcon) {
    final uriText = block.data['uri'] as String? ?? '';
    final filePath = _filePath(uriText);
    if (filePath == null) {
      return Icon(fallbackIcon, size: 22);
    }
    return Image.file(
      File(filePath),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          Icon(fallbackIcon, size: 22),
    );
  }

  String? _filePath(String uriText) {
    if (uriText.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(uriText);
    if (uri != null && uri.isScheme('file')) {
      return uri.toFilePath();
    }
    return uriText.startsWith('/') ? uriText : null;
  }
}
