import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/phone_agent_colors.dart';
import '../../../domain/files/app_file_store.dart';

class WorkspaceFileManagerPage extends StatefulWidget {
  const WorkspaceFileManagerPage({
    required this.files,
    required this.onOpenFile,
    required this.onRefreshFiles,
    super.key,
  });

  final List<AppFileEntry> files;
  final ValueChanged<AppFileEntry> onOpenFile;
  final Future<List<AppFileEntry>> Function() onRefreshFiles;

  @override
  State<WorkspaceFileManagerPage> createState() =>
      _WorkspaceFileManagerPageState();
}

class _WorkspaceFileManagerPageState extends State<WorkspaceFileManagerPage> {
  final List<String> _segments = [];
  late List<AppFileEntry> _files = List.of(widget.files);
  bool _isRefreshing = false;

  String get _currentPath => _segments.join('/');

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final items = _itemsForCurrentPath();
    return Scaffold(
      backgroundColor: colors.panelBackground,
      appBar: AppBar(
        title: const Text('工作区文件'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: _isRefreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _isRefreshing ? null : _refreshFiles,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _FileManagerToolbar(
            segments: _segments,
            canGoUp: _segments.isNotEmpty,
            onGoUp: _goUp,
            onOpenSegment: _openSegment,
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: items.isEmpty
                ? _EmptyFolder(path: _currentPath)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _FileManagerRow(
                        item: item,
                        onTap: () => _openItem(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<_FileManagerItem> _itemsForCurrentPath() {
    final prefix = _currentPath.isEmpty ? '' : '$_currentPath/';
    final directories = <String, _FileManagerItem>{};
    final files = <_FileManagerItem>[];

    for (final file in _files) {
      if (!file.path.startsWith(prefix)) {
        continue;
      }
      final remaining = file.path.substring(prefix.length);
      if (remaining.isEmpty) {
        continue;
      }
      final separatorIndex = remaining.indexOf('/');
      if (separatorIndex >= 0) {
        final name = remaining.substring(0, separatorIndex);
        final directoryPath = prefix.isEmpty ? name : '$prefix$name';
        directories.putIfAbsent(
          name,
          () => _FileManagerItem.directory(
            name: name,
            path: directoryPath,
            childCount: _childCount(directoryPath),
          ),
        );
        continue;
      }
      files.add(_FileManagerItem.file(entry: file));
    }

    final items = [...directories.values, ...files];
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  int _childCount(String directoryPath) {
    final prefix = '$directoryPath/';
    final children = <String>{};
    for (final file in _files) {
      if (!file.path.startsWith(prefix)) {
        continue;
      }
      final remaining = file.path.substring(prefix.length);
      if (remaining.isEmpty) {
        continue;
      }
      children.add(remaining.split('/').first);
    }
    return children.length;
  }

  void _openItem(_FileManagerItem item) {
    if (item.isDirectory) {
      setState(() {
        _segments
          ..clear()
          ..addAll(item.path.split('/'));
      });
      return;
    }
    final entry = item.entry;
    if (entry != null) {
      widget.onOpenFile(entry);
    }
  }

  void _goUp() {
    if (_segments.isEmpty) {
      return;
    }
    setState(() {
      _segments.removeLast();
    });
  }

  void _openSegment(int segmentCount) {
    setState(() {
      _segments.removeRange(segmentCount, _segments.length);
    });
  }

  Future<void> _refreshFiles() async {
    setState(() {
      _isRefreshing = true;
    });
    try {
      final files = await widget.onRefreshFiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _files = List.of(files);
        _trimCurrentPathIfMissing();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _trimCurrentPathIfMissing() {
    while (_segments.isNotEmpty) {
      final prefix = '${_segments.join('/')}/';
      if (_files.any((file) => file.path.startsWith(prefix))) {
        return;
      }
      _segments.removeLast();
    }
  }
}

class _FileManagerToolbar extends StatelessWidget {
  const _FileManagerToolbar({
    required this.segments,
    required this.canGoUp,
    required this.onGoUp,
    required this.onOpenSegment,
  });

  final List<String> segments;
  final bool canGoUp;
  final VoidCallback onGoUp;
  final ValueChanged<int> onOpenSegment;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Material(
      color: colors.cardBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '返回上级',
              icon: const Icon(Icons.arrow_upward_rounded),
              onPressed: canGoUp ? onGoUp : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _BreadcrumbButton(
                      label: '文件',
                      isCurrent: segments.isEmpty,
                      onTap: () => onOpenSegment(0),
                    ),
                    for (var i = 0; i < segments.length; i++) ...[
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                      _BreadcrumbButton(
                        label: segments[i],
                        isCurrent: i == segments.length - 1,
                        onTap: () => onOpenSegment(i + 1),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreadcrumbButton extends StatelessWidget {
  const _BreadcrumbButton({
    required this.label,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return TextButton(
      onPressed: isCurrent ? null : onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
          color: isCurrent ? colors.textPrimary : colors.primaryAction,
        ),
      ),
    );
  }
}

class _FileManagerRow extends StatelessWidget {
  const _FileManagerRow({required this.item, required this.onTap});

  final _FileManagerItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                item.isDirectory
                    ? Icons.folder_rounded
                    : _iconForFile(item.name),
                color: item.isDirectory
                    ? colors.primaryAction
                    : colors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                item.isDirectory
                    ? Icons.chevron_right_rounded
                    : Icons.open_in_new_rounded,
                size: 20,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForFile(String name) {
    final extension = p.extension(name).toLowerCase();
    if ({
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.heic',
    }.contains(extension)) {
      return Icons.image_outlined;
    }
    if ({'.mp3', '.m4a', '.wav', '.aac'}.contains(extension)) {
      return Icons.graphic_eq_rounded;
    }
    if ({'.mp4', '.mov', '.m4v'}.contains(extension)) {
      return Icons.movie_outlined;
    }
    if ({'.pdf'}.contains(extension)) {
      return Icons.picture_as_pdf_outlined;
    }
    if ({'.html', '.htm', '.js', '.css', '.json'}.contains(extension)) {
      return Icons.code_rounded;
    }
    return Icons.description_outlined;
  }
}

class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 40,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              path.isEmpty ? '当前工作区暂无文件' : '此文件夹为空',
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileManagerItem {
  const _FileManagerItem._({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.subtitle,
    this.entry,
  });

  factory _FileManagerItem.directory({
    required String name,
    required String path,
    required int childCount,
  }) {
    return _FileManagerItem._(
      name: name,
      path: path,
      isDirectory: true,
      subtitle: '$childCount 项',
    );
  }

  factory _FileManagerItem.file({required AppFileEntry entry}) {
    return _FileManagerItem._(
      name: p.basename(entry.path),
      path: entry.path,
      isDirectory: false,
      subtitle:
          '${_formatBytes(entry.bytes)} · ${_formatModified(entry.modifiedAt)}',
      entry: entry,
    );
  }

  final String name;
  final String path;
  final bool isDirectory;
  final String subtitle;
  final AppFileEntry? entry;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(1)} KB';
  }
  return '${(kib / 1024).toStringAsFixed(1)} MB';
}

String _formatModified(DateTime modifiedAt) {
  final local = modifiedAt.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}
