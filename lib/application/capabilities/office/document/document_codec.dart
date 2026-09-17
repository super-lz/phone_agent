import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';

/// Word/docx codec. Other Office formats must not import this file.
class DocumentCodec {
  const DocumentCodec();

  Future<Uint8List> encodeDocx({required String title, required String body}) {
    final builder = docx().h1(title);
    for (final line in body.split('\n')) {
      builder.p(line);
    }
    return DocxExporter().exportToBytes(builder.build());
  }

  Future<String> extract(Uint8List bytes) async {
    try {
      final document = await DocxReader.loadFromBytes(bytes);
      return MarkdownExporter().export(document).trim();
    } catch (_) {
      return _extractXmlFallback(bytes);
    }
  }

  String _extractXmlFallback(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('word/document.xml');
    if (file == null) {
      return '';
    }
    final xml = utf8.decode(file.content, allowMalformed: true);
    var text = xml.replaceAll(RegExp(r'<w:p[ >]'), '\n');
    text = text.replaceAll('<w:br/>', '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
}
