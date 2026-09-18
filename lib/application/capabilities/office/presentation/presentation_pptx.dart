import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'presentation_model.dart';

/// PPTX export/import only. The editable source is Markdown, not this file.
///
/// The package is a complete minimal OOXML deck: theme, master, layout, and
/// slides with explicit text-box geometry. A shape without `a:xfrm` extent
/// renders as a zero-width column, which is why earlier exports stacked
/// characters on a vertical line.
class PresentationPptxCodec {
  const PresentationPptxCodec();

  static const _slideWidth = 12192000;
  static const _slideHeight = 6858000;

  Uint8List encode(List<SlideContent> slides) {
    final safeSlides = slides.isEmpty
        ? const [SlideContent(title: 'Untitled', bullets: [])]
        : slides;

    final files = <String, String>{
      '[Content_Types].xml': _contentTypes(safeSlides.length),
      '_rels/.rels': _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument|ppt/presentation.xml',
      }),
      'ppt/presentation.xml': _presentationXml(safeSlides.length),
      'ppt/_rels/presentation.xml.rels': _presentationRels(safeSlides.length),
      'ppt/theme/theme1.xml': _themeXml,
      'ppt/slideMasters/slideMaster1.xml': _slideMasterXml,
      'ppt/slideMasters/_rels/slideMaster1.xml.rels': _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme|../theme/theme1.xml',
        'rId2':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout|../slideLayouts/slideLayout1.xml',
      }),
      'ppt/slideLayouts/slideLayout1.xml': _slideLayoutXml,
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels': _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster|../slideMasters/slideMaster1.xml',
      }),
    };

    for (var index = 0; index < safeSlides.length; index += 1) {
      final slideNumber = index + 1;
      files['ppt/slides/slide$slideNumber.xml'] = _slideXml(safeSlides[index]);
      files['ppt/slides/_rels/slide$slideNumber.xml.rels'] = _rels({
        'rId1':
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout|../slideLayouts/slideLayout1.xml',
      });
    }

    return _zip(files);
  }

  String extract(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final parts = <String>[];
    for (final file in archive.files) {
      if (!file.isFile || !file.name.startsWith('ppt/slides/slide')) {
        continue;
      }
      if (file.name.contains('_rels')) {
        continue;
      }
      parts.add(_xmlText(utf8.decode(file.content, allowMalformed: true)));
    }
    return parts.where((part) => part.trim().isNotEmpty).join('\n\n');
  }

  Uint8List _zip(Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = _utf8Xml(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Uint8List _utf8Xml(String xml) {
    return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(xml)]);
  }

  String _presentationXml(int slideCount) {
    final slideIds = [
      for (var index = 0; index < slideCount; index += 1)
        '<p:sldId id="${256 + index}" r:id="rId${index + 2}"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>$slideIds</p:sldIdLst>'
        '<p:sldSz cx="$_slideWidth" cy="$_slideHeight" type="screen16x9"/>'
        '<p:notesSz cx="6858000" cy="9144000"/>'
        '</p:presentation>';
  }

  String _presentationRels(int slideCount) {
    final relationships = <String, String>{
      'rId1':
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster|slideMasters/slideMaster1.xml',
    };
    for (var index = 0; index < slideCount; index += 1) {
      relationships['rId${index + 2}'] =
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide|slides/slide${index + 1}.xml';
    }
    return _rels(relationships);
  }

  String _contentTypes(int slideCount) {
    final overrides = <String, String>{
      '/ppt/presentation.xml':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml',
      '/ppt/slideMasters/slideMaster1.xml':
          'application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml',
      '/ppt/slideLayouts/slideLayout1.xml':
          'application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml',
      '/ppt/theme/theme1.xml':
          'application/vnd.openxmlformats-officedocument.theme+xml',
    };
    for (var index = 1; index <= slideCount; index += 1) {
      overrides['/ppt/slides/slide$index.xml'] =
          'application/vnd.openxmlformats-officedocument.presentationml.slide+xml';
    }
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

  String _slideXml(SlideContent slide) {
    final titleBox = _textBox(
      id: 2,
      name: 'Title',
      x: 548640,
      y: 274320,
      cx: 11093280,
      cy: 1143000,
      paragraphs: [_titleParagraph(slide.title)],
    );
    final bodyParagraphs = slide.bullets.isEmpty
        ? [_bulletParagraph('')]
        : slide.bullets.map(_bulletParagraph).toList();
    final bodyBox = _textBox(
      id: 3,
      name: 'Content',
      x: 548640,
      y: 1600200,
      cx: 11093280,
      cy: 4525963,
      paragraphs: bodyParagraphs,
    );
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree>'
        '$_spTreeGroup'
        '$titleBox$bodyBox'
        '</p:spTree></p:cSld></p:sld>';
  }

  String _textBox({
    required int id,
    required String name,
    required int x,
    required int y,
    required int cx,
    required int cy,
    required List<String> paragraphs,
  }) {
    return '<p:sp>'
        '<p:nvSpPr><p:cNvPr id="$id" name="$name"/>'
        '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
        '<p:txBody>'
        '<a:bodyPr wrap="square" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0" anchor="t"/>'
        '<a:lstStyle/>'
        '${paragraphs.join()}'
        '</p:txBody></p:sp>';
  }

  String _titleParagraph(String text) {
    return '<a:p><a:pPr algn="l"/>'
        '<a:r><a:rPr lang="zh-CN" altLang="en-US" sz="3200" b="1" dirty="0">'
        '$_fontRefs</a:rPr>'
        '<a:t xml:space="preserve">${_xml(text)}</a:t></a:r></a:p>';
  }

  String _bulletParagraph(String text) {
    return '<a:p><a:pPr marL="342900" indent="-342900">'
        '<a:buFont typeface="Arial"/><a:buChar char="•"/></a:pPr>'
        '<a:r><a:rPr lang="zh-CN" altLang="en-US" sz="1800" dirty="0">'
        '$_fontRefs</a:rPr>'
        '<a:t xml:space="preserve">${_xml(text)}</a:t></a:r></a:p>';
  }

  static const _fontRefs =
      '<a:solidFill><a:srgbClr val="1F2937"/></a:solidFill>'
      '<a:latin typeface="+mn-lt"/>'
      '<a:ea typeface="+mn-ea"/>'
      '<a:cs typeface="+mn-cs"/>';

  static const _spTreeGroup =
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$_slideWidth" cy="$_slideHeight"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="$_slideWidth" cy="$_slideHeight"/></a:xfrm></p:grpSpPr>';

  String _rels(Map<String, String> relationships) {
    final rels = relationships.entries.map((entry) {
      final parts = entry.value.split('|');
      return '<Relationship Id="${entry.key}" Type="${parts[0]}" Target="${parts[1]}"/>';
    }).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>';
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

const _themeXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">'
    '<a:themeElements><a:clrScheme name="Office">'
    '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
    '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="1F2937"/></a:dk2>'
    '<a:lt2><a:srgbClr val="F8FAFC"/></a:lt2>'
    '<a:accent1><a:srgbClr val="2563EB"/></a:accent1>'
    '<a:accent2><a:srgbClr val="0F766E"/></a:accent2>'
    '<a:accent3><a:srgbClr val="C2410C"/></a:accent3>'
    '<a:accent4><a:srgbClr val="7C3AED"/></a:accent4>'
    '<a:accent5><a:srgbClr val="0369A1"/></a:accent5>'
    '<a:accent6><a:srgbClr val="BE123C"/></a:accent6>'
    '<a:hlink><a:srgbClr val="2563EB"/></a:hlink>'
    '<a:folHlink><a:srgbClr val="1D4ED8"/></a:folHlink>'
    '</a:clrScheme>'
    '<a:fontScheme name="Office">'
    '<a:majorFont><a:latin typeface="Calibri"/><a:ea typeface="Noto Sans CJK SC"/><a:cs typeface="Calibri"/>'
    '<a:font script="Hans" typeface="Noto Sans CJK SC"/>'
    '<a:font script="Hant" typeface="Noto Sans CJK TC"/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface="Noto Sans CJK SC"/><a:cs typeface="Calibri"/>'
    '<a:font script="Hans" typeface="Noto Sans CJK SC"/>'
    '<a:font script="Hant" typeface="Noto Sans CJK TC"/></a:minorFont>'
    '</a:fontScheme>'
    '<a:fmtScheme name="Office">'
    '<a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
    '<a:lnStyleLst>'
    '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
    '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
    '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
    '</a:lnStyleLst>'
    '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
    '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>'
    '</a:fmtScheme></a:themeElements></a:theme>';

const _slideMasterXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
    '<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>'
    '<p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="12192000" cy="6858000"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="12192000" cy="6858000"/></a:xfrm></p:grpSpPr>'
    '</p:spTree></p:cSld>'
    '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" '
    'accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
    '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId2"/></p:sldLayoutIdLst>'
    '</p:sldMaster>';

const _slideLayoutXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">'
    '<p:cSld name="Blank"><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="12192000" cy="6858000"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="12192000" cy="6858000"/></a:xfrm></p:grpSpPr>'
    '</p:spTree></p:cSld>'
    '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
    '</p:sldLayout>';
