import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'presentation_model.dart';

/// PPTX export/import only. The editable source is Markdown, not this file.
class PresentationPptxCodec {
  const PresentationPptxCodec();

  Uint8List encode(List<SlideContent> slides) {
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

  String extract(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final parts = <String>[];
    for (final file in archive.files) {
      if (!file.isFile || !file.name.startsWith('ppt/slides/slide')) {
        continue;
      }
      parts.add(_xmlText(utf8.decode(file.content, allowMalformed: true)));
    }
    return parts.where((part) => part.trim().isNotEmpty).join('\n\n');
  }

  Uint8List _zip(Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  String _slideXml(SlideContent slide) {
    final bullets = slide.bullets.map(_paragraph).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr/><p:grpSpPr/>'
        '<p:sp><p:txBody><a:bodyPr/><a:lstStyle/>'
        '${_paragraph(slide.title, fontSize: 3200)}$bullets'
        '</p:txBody></p:sp></p:spTree></p:cSld></p:sld>';
  }

  String _paragraph(String text, {int fontSize = 1800}) {
    return '<a:p><a:r><a:rPr sz="$fontSize"/><a:t>${_xml(text)}</a:t></a:r></a:p>';
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

  String _xmlText(String xml) {
    return xml
        .replaceAll(RegExp(r'<[^>]+>'), '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
