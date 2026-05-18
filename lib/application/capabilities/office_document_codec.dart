import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class OfficeDocumentCodec {
  const OfficeDocumentCodec();

  Uint8List encodeDocx({required String title, required String body}) {
    final paragraphs = [
      title,
      ...body.split('\n'),
    ].where((line) => line.trim().isNotEmpty).map(_wordParagraph).join();
    return _zip({
      '[Content_Types].xml': _contentTypes({
        '/word/document.xml':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
      }),
      '_rels/.rels': _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument|word/document.xml',
      }),
      'word/document.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:body>$paragraphs<w:sectPr/></w:body></w:document>',
    });
  }

  Uint8List encodeXlsx(List<List<String>> rows) {
    final sheetData = rows.asMap().entries.map((rowEntry) {
      final rowIndex = rowEntry.key + 1;
      final cells = rowEntry.value.asMap().entries.map((cellEntry) {
        final ref = '${_columnName(cellEntry.key + 1)}$rowIndex';
        return '<c r="$ref" t="inlineStr"><is><t>${_xml(cellEntry.value)}</t></is></c>';
      }).join();
      return '<row r="$rowIndex">$cells</row>';
    }).join();
    return _zip({
      '[Content_Types].xml': _contentTypes({
        '/xl/workbook.xml':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
        '/xl/worksheets/sheet1.xml':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml',
      }),
      '_rels/.rels': _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument|xl/workbook.xml',
      }),
      'xl/workbook.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet|worksheets/sheet1.xml',
      }),
      'xl/worksheets/sheet1.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>$sheetData</sheetData></worksheet>',
    });
  }

  Uint8List encodePptx(List<SlideContent> slides) {
    final safeSlides = slides.isEmpty
        ? const [SlideContent(title: 'Untitled', bullets: [])]
        : slides;
    final contentTypes = <String, String>{
      '/ppt/presentation.xml':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml',
    };
    final presentationRels = <String, String>{};
    final files = <String, String>{
      '[Content_Types].xml': '',
      '_rels/.rels': _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument|ppt/presentation.xml',
      }),
    };
    final slideIds = <String>[];
    for (var index = 0; index < safeSlides.length; index += 1) {
      final slideNumber = index + 1;
      final relId = 'rId$slideNumber';
      final slidePath = '/ppt/slides/slide$slideNumber.xml';
      contentTypes[slidePath] =
          'application/vnd.openxmlformats-officedocument.presentationml.slide+xml';
      presentationRels[relId] =
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide|slides/slide$slideNumber.xml';
      slideIds.add('<p:sldId id="${256 + slideNumber}" r:id="$relId"/>');
      files['ppt/slides/slide$slideNumber.xml'] = _slideXml(safeSlides[index]);
    }
    files['ppt/presentation.xml'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<p:sldIdLst>${slideIds.join()}</p:sldIdLst>'
        '<p:sldSz cx="9144000" cy="5143500" type="screen4x3"/></p:presentation>';
    files['ppt/_rels/presentation.xml.rels'] = _rels(presentationRels);
    files['[Content_Types].xml'] = _contentTypes(contentTypes);
    return _zip(files);
  }

  Uint8List encodePdf({required String title, required String body}) {
    final lines = [
      title,
      ...body.split('\n'),
    ].where((line) => line.trim().isNotEmpty).take(42).toList(growable: false);
    final stream = StringBuffer('BT /F1 18 Tf 72 760 Td ');
    for (var index = 0; index < lines.length; index += 1) {
      if (index == 1) {
        stream.write('/F1 12 Tf ');
      }
      if (index > 0) {
        stream.write('0 -22 Td ');
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

  String extractText(String path, Uint8List bytes) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.docx')) {
      return _extractZipText(bytes, ['word/document.xml']);
    }
    if (lower.endsWith('.xlsx')) {
      return _extractZipText(bytes, ['xl/worksheets/sheet1.xml']);
    }
    if (lower.endsWith('.pptx')) {
      return _extractZipText(bytes, ['ppt/slides/']);
    }
    if (lower.endsWith('.pdf')) {
      return _extractPdfText(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Uint8List _zip(Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  String _extractZipText(Uint8List bytes, List<String> pathsOrPrefixes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final parts = <String>[];
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final shouldRead = pathsOrPrefixes.any(
        (path) => file.name == path || file.name.startsWith(path),
      );
      if (!shouldRead) {
        continue;
      }
      parts.add(_xmlText(utf8.decode(file.content, allowMalformed: true)));
    }
    return parts.where((part) => part.trim().isNotEmpty).join('\n\n');
  }

  String _extractPdfText(Uint8List bytes) {
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

  String _xmlText(String xml) {
    return xml
        .replaceAll(RegExp(r'<[^>]+>'), '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  String _slideXml(SlideContent slide) {
    final bullets = slide.bullets.map(_paragraph).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr/><p:grpSpPr/>'
        '<p:sp><p:txBody><a:bodyPr/><a:lstStyle/>'
        '${_paragraph(slide.title)}$bullets'
        '</p:txBody></p:sp></p:spTree></p:cSld></p:sld>';
  }

  String _wordParagraph(String text) {
    return '<w:p><w:r><w:t>${_xml(text)}</w:t></w:r></w:p>';
  }

  String _paragraph(String text) {
    return '<a:p><a:r><a:t>${_xml(text)}</a:t></a:r></a:p>';
  }

  String _rels(Map<String, String> relationships) {
    final rels = relationships.entries.map((entry) {
      final parts = entry.value.split('|');
      return '<Relationship Id="${entry.key}" Type="${parts[0]}" Target="${parts[1]}"/>';
    }).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>';
  }

  String _contentTypes(Map<String, String> overrides) {
    final overrideXml = overrides.entries
        .map(
          (entry) =>
              '<Override PartName="${entry.key}" ContentType="${entry.value}"/>',
        )
        .join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '$overrideXml</Types>';
  }

  String _columnName(int index) {
    var value = index;
    final chars = <String>[];
    while (value > 0) {
      value -= 1;
      chars.insert(0, String.fromCharCode(65 + value.remainder(26)));
      value = value ~/ 26;
    }
    return chars.join();
  }

  String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
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

class SlideContent {
  const SlideContent({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;
}
