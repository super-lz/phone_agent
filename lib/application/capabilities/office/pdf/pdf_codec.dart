import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// PDF codec. Other Office formats must not import this file.
class PdfCodec {
  const PdfCodec();

  Future<Uint8List> encode({
    required String title,
    required String body,
  }) async {
    final source = '$title\n$body';
    if (_hasNonLatin(source)) {
      return _encodeCid(title: title, body: body);
    }
    try {
      return await _encodeLatin(title: title, body: body);
    } catch (_) {
      return _encodeCid(title: title, body: body);
    }
  }

  String extract(Uint8List bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
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

  Future<Uint8List> _encodeLatin({
    required String title,
    required String body,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(title, style: const pw.TextStyle(fontSize: 18)),
            ),
            ...body.split('\n').map((line) => pw.Paragraph(text: line)),
          ];
        },
      ),
    );
    return document.save();
  }

  Uint8List _encodeCid({required String title, required String body}) {
    final wrappedLines = _wrapPdfText([
      title,
      ...body.split('\n'),
    ], maxWidth: 45);
    final lines = wrappedLines.take(38).toList(growable: false);
    final stream = StringBuffer('BT /F1 18 Tf 72 760 Td ');
    for (var index = 0; index < lines.length; index += 1) {
      if (index == 1) {
        stream.write('/F1 12 Tf 0 -28 Td ');
      } else if (index > 1) {
        stream.write('0 -18 Td ');
      }
      stream.write('<${_pdfHexText(lines[index])}> Tj ');
    }
    stream.write('ET');
    final content = stream.toString();
    final objects = <String>[
      '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj',
      '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj',
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
          '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj',
      '4 0 obj << /Type /Font /Subtype /Type0 /BaseFont /STSong-Light '
          '/Encoding /UniGB-UCS2-H /DescendantFonts [<< /Type /Font '
          '/Subtype /CIDFontType0 /BaseFont /STSong-Light /CIDSystemInfo '
          '<< /Registry (Adobe) /Ordering (GB1) /Supplement 2 >> >>] >> endobj',
      '5 0 obj << /Length ${ascii.encode(content).length} >> stream\n$content\nendstream endobj',
    ];
    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (final object in objects) {
      offsets.add(ascii.encode(buffer.toString()).length);
      buffer.write('$object\n');
    }
    final xrefOffset = ascii.encode(buffer.toString()).length;
    buffer
      ..write('xref\n0 ${objects.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer
      ..write('trailer << /Size ${objects.length + 1} /Root 1 0 R >>\n')
      ..write('startxref\n$xrefOffset\n%%EOF');
    return Uint8List.fromList(ascii.encode(buffer.toString()));
  }

  bool _hasNonLatin(String value) {
    return value.runes.any((rune) => rune > 127);
  }

  List<String> _wrapPdfText(List<String> rawLines, {required int maxWidth}) {
    final result = <String>[];
    for (final line in rawLines) {
      if (line.isEmpty) {
        result.add('');
        continue;
      }
      var currentLine = line;
      while (currentLine.isNotEmpty) {
        if (currentLine.length <= maxWidth) {
          result.add(currentLine);
          break;
        }
        result.add(currentLine.substring(0, maxWidth));
        currentLine = currentLine.substring(maxWidth);
      }
    }
    return result;
  }

  String _pdfHexText(String value) {
    final bytes = <int>[0xfe, 0xff];
    for (final codeUnit in value.codeUnits) {
      bytes
        ..add(codeUnit >> 8)
        ..add(codeUnit & 0xff);
    }
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
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
