import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../../domain/files/app_file_store.dart';

class FilePreviewPage extends StatelessWidget {
  const FilePreviewPage({
    required this.entry,
    required this.content,
    super.key,
  });

  final AppFileEntry entry;
  final String content;

  @override
  Widget build(BuildContext context) {
    final extension = p.extension(entry.path).toLowerCase();
    final fileName = p.basename(entry.path);

    Widget body;
    if (extension == '.md' || extension == '.markdown') {
      body = Markdown(
        data: content,
        selectable: true,
      );
    } else if (_isImage(extension)) {
      body = Center(
        child: SingleChildScrollView(
          child: Image.file(File(entry.uri.toFilePath())),
        ),
      );
    } else if (extension == '.html' || extension == '.htm') {
      body = InAppWebView(
        initialData: InAppWebViewInitialData(data: content),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          supportZoom: true,
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          IconButton(
            tooltip: '分享',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _shareFile(context),
          ),
          IconButton(
            tooltip: '另存为',
            icon: const Icon(Icons.save_alt),
            onPressed: () => _saveFile(context),
          ),
          IconButton(
            tooltip: '用外部应用打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openExternal(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  bool _isImage(String ext) {
    return const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic'}
        .contains(ext);
  }

  Future<void> _openExternal(BuildContext context) async {
    final filePath = entry.uri.toFilePath();
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件: ${result.message}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开外部应用失败: $e')),
        );
      }
    }
  }

  Future<void> _shareFile(BuildContext context) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: p.basename(entry.path),
            mimeType: _mimeTypeForFile(entry.path),
          ),
        ],
        subject: entry.path,
        fileNameOverrides: [p.basename(entry.path)],
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  Future<void> _saveFile(BuildContext context) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: p.basename(entry.path),
        bytes: bytes,
        type: FileType.any,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存到: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  String _mimeTypeForFile(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'text/plain';
  }
}
