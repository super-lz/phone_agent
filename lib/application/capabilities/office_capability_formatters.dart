import 'office_document_codec.dart';

List<List<String>> officeRows(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return value
      .whereType<List<Object?>>()
      .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
      .toList();
}

List<SlideContent> officeSlides(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  final slides = <SlideContent>[];
  for (final item in value) {
    if (item is! Map<String, Object?>) {
      continue;
    }
    final title = officeString(item['title']) ?? 'Untitled';
    final rawBullets = item['bullets'];
    final bullets = rawBullets is List<Object?>
        ? rawBullets
              .map((bullet) => bullet?.toString() ?? '')
              .where((bullet) => bullet.trim().isNotEmpty)
              .toList()
        : <String>[?officeString(item['body'])];
    slides.add(SlideContent(title: title, bullets: bullets));
  }
  return slides;
}

String officeFormat(
  Map<String, Object?> arguments, {
  required String fallback,
}) {
  final explicit = officeString(arguments['format']);
  final inferred = officeExtension(officeString(arguments['path']) ?? '');
  final value = explicit ?? inferred;
  return value.isEmpty ? fallback : value.toLowerCase();
}

String officeOutputPath(
  Map<String, Object?> arguments, {
  required String fallback,
}) {
  return officeString(arguments['path']) ??
      fallback.replaceAll(RegExp(r'\s+'), '-');
}

String officeExtension(String path) {
  final index = path.lastIndexOf('.');
  if (index < 0 || index == path.length - 1) {
    return '';
  }
  return path.substring(index + 1).toLowerCase();
}

String officePatchedPath(String path, String format) {
  final dot = path.lastIndexOf('.');
  final suffix = format == 'pdf' ? '.pdf' : '.docx';
  if (dot < 0) {
    return '$path.patched$suffix';
  }
  return '${path.substring(0, dot)}.patched$suffix';
}

int officePositiveInt(Object? value, {required int fallback}) {
  return value is int && value > 0 ? value : fallback;
}

String? officeString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String officeCsv(List<List<String>> rows) {
  return rows
      .map(
        (row) => row.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','),
      )
      .join('\n');
}

String officeHtml(String title, String body) {
  return '<!doctype html><html><head><meta charset="utf-8"><title>${officeEscape(title)}</title></head>'
      '<body><h1>${officeEscape(title)}</h1><pre>${officeEscape(body)}</pre></body></html>';
}

String officeSlidesMarkdown(List<SlideContent> slides) {
  return slides
      .map(
        (slide) =>
            '# ${slide.title}\n\n${slide.bullets.map((item) => '- $item').join('\n')}',
      )
      .join('\n\n---\n\n');
}

String officeSlidesHtml(String title, List<SlideContent> slides) {
  final sections = slides.map((slide) {
    final bullets = slide.bullets
        .map((item) => '<li>${officeEscape(item)}</li>')
        .join();
    return '<section><h2>${officeEscape(slide.title)}</h2><ul>$bullets</ul></section>';
  }).join();
  return '<!doctype html><html><head><meta charset="utf-8"><title>${officeEscape(title)}</title></head><body>$sections</body></html>';
}

String officeEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
