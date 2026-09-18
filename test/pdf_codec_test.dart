import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/capabilities/office/pdf/pdf_codec.dart';

void main() {
  test('pdf generate embeds chinese and paginates', () async {
    const codec = PdfCodec();
    final body = List.generate(
      80,
      (index) => '第 ${index + 1} 段内容，用于验证分页。',
    ).join('\n');
    final bytes = await codec.encode(title: '摘要标题', body: body);
    expect(bytes.length, greaterThan(1000));

    final text = await codec.extract(bytes);
    expect(text, contains('摘要标题'));
    expect(text, contains('第 1 段内容'));
    expect(text, contains('第 80 段内容'));

    final pageCount = RegExp(
      r'/Type\s*/Page[^s]',
    ).allMatches(String.fromCharCodes(bytes)).length;
    expect(pageCount, greaterThan(1));
  });
}
