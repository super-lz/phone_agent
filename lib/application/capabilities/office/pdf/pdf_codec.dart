import 'dart:typed_data';

import 'package:docx_creator/docx_creator.dart' as docx;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'sfnt_font.dart';

/// PDF codec. Other Office formats must not import this file.
class PdfCodec {
  const PdfCodec({this.fontBytes, this.fontLoader = const SfntFont()});

  final Uint8List? fontBytes;
  final SfntFont fontLoader;

  Future<Uint8List> encode({
    required String title,
    required String body,
  }) async {
    final face = fontBytes ?? await fontLoader.loadSystemCjkFace();
    if (face == null) {
      throw StateError('no CJK font available for PDF generation');
    }
    final isolated = Uint8List.fromList(face);
    final font = pw.Font.ttf(ByteData.sublistView(isolated));
    final theme = pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
      boldItalic: font,
    );
    final document = pw.Document(theme: theme);
    final titleStyle = pw.TextStyle(font: font, fontSize: 18);
    final bodyStyle = pw.TextStyle(font: font, fontSize: 12);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        build: (context) {
          return [
            pw.Text(title, style: titleStyle),
            pw.SizedBox(height: 16),
            ...body
                .split('\n')
                .map(
                  (line) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(line.isEmpty ? ' ' : line, style: bodyStyle),
                  ),
                ),
          ];
        },
      ),
    );
    return document.save();
  }

  Future<String> extract(Uint8List bytes) async {
    try {
      final parsed = await docx.PdfReader.loadFromBytes(bytes);
      final text = parsed.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    } catch (_) {}
    return _extractOperators(bytes);
  }

  String _extractOperators(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    final literalMatches = RegExp(r'\(([^()]*)\)\s*Tj').allMatches(text).map((
      match,
    ) {
      return match.group(1)?.replaceAll(r'\(', '(').replaceAll(r'\)', ')') ??
          '';
    });
    final hexMatches = RegExp(r'<([0-9A-Fa-f]+)>\s*Tj').allMatches(text).map((
      match,
    ) {
      return _decodePdfHexText(match.group(1) ?? '');
    });
    return literalMatches
        .followedBy(hexMatches)
        .where((value) => value.trim().isNotEmpty)
        .join('\n');
  }

  String _decodePdfHexText(String hex) {
    final bytes = <int>[];
    for (var index = 0; index + 1 < hex.length; index += 2) {
      final byte = int.tryParse(hex.substring(index, index + 2), radix: 16);
      if (byte != null) {
        bytes.add(byte);
      }
    }
    final offset = bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff
        ? 2
        : 0;
    final units = <int>[];
    for (var index = offset; index + 1 < bytes.length; index += 2) {
      units.add((bytes[index] << 8) + bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }
}
