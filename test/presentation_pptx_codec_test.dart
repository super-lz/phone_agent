import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/office/presentation/presentation_model.dart';
import 'package:phone_agent/application/capabilities/office/presentation/presentation_pptx.dart';

void main() {
  test('pptx export has geometry theme and extractable text', () {
    const codec = PresentationPptxCodec();
    final bytes = codec.encode(const [
      SlideContent(title: '第一页', bullets: ['市场机会', '产品能力']),
    ]);
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((file) => file.name).toSet();

    expect(names, contains('ppt/theme/theme1.xml'));
    expect(names, contains('ppt/slideMasters/slideMaster1.xml'));
    expect(names, contains('ppt/slideLayouts/slideLayout1.xml'));
    expect(names, contains('ppt/slides/slide1.xml'));
    expect(names, contains('ppt/slides/_rels/slide1.xml.rels'));

    final slideXml = utf8.decode(
      archive.findFile('ppt/slides/slide1.xml')!.content,
    );
    expect(slideXml, contains('<a:ext cx="11093280"'));
    expect(slideXml.contains('<p:sp>'), isTrue);
    expect(RegExp(r'<p:sp>').allMatches(slideXml).length, 2);
    expect(slideXml, contains('wrap="square"'));
    expect(slideXml, contains('+mn-ea'));
    expect(slideXml, contains('<a:buChar char="•"/>'));

    final extracted = codec.extract(bytes);
    expect(extracted, contains('第一页'));
    expect(extracted, contains('市场机会'));
  });
}
