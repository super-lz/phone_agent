import 'presentation_model.dart';

/// Canonical editable source for presentations.
///
/// ```
/// # Slide title
///
/// - bullet
///
/// ---
///
/// # Next slide
/// ```
class PresentationMarkdown {
  const PresentationMarkdown();

  String serialize(List<SlideContent> slides) {
    return slides
        .map(
          (slide) =>
              '# ${slide.title}\n\n${slide.bullets.map((item) => '- $item').join('\n')}',
        )
        .join('\n\n---\n\n');
  }

  List<SlideContent> parse(String markdown) {
    final chunks = markdown
        .split(RegExp(r'\n---\n'))
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty);
    final slides = <SlideContent>[];
    for (final chunk in chunks) {
      final lines = chunk
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        continue;
      }
      var title = 'Untitled';
      final bullets = <String>[];
      for (final line in lines) {
        if (line.startsWith('# ')) {
          title = line.replaceFirst(RegExp(r'^#+\s*'), '');
        } else if (line.startsWith('- ') || line.startsWith('* ')) {
          bullets.add(line.substring(2).trim());
        } else if (title == 'Untitled') {
          title = line;
        } else {
          bullets.add(line);
        }
      }
      slides.add(SlideContent(title: title, bullets: bullets));
    }
    return slides;
  }

  String previewHtml(String title, List<SlideContent> slides) {
    final sections = slides.map((slide) {
      final bullets = slide.bullets
          .map((item) => '<li>${_escape(item)}</li>')
          .join();
      return '<section><h2>${_escape(slide.title)}</h2><ul>$bullets</ul></section>';
    }).join();
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<title>${_escape(title)}</title></head><body>$sections</body></html>';
  }

  List<SlideContent> slidesFrom(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return parse(value);
    }
    if (value is! List<Object?>) {
      return const [];
    }
    final slides = <SlideContent>[];
    for (final item in value) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final title = (item['title'] as String?)?.trim();
      final rawBullets = item['bullets'];
      final bullets = rawBullets is List<Object?>
          ? rawBullets
                .map((bullet) => bullet?.toString() ?? '')
                .where((bullet) => bullet.trim().isNotEmpty)
                .toList()
          : <String>[
              if ((item['body'] as String?)?.trim().isNotEmpty == true)
                (item['body'] as String).trim(),
            ];
      slides.add(
        SlideContent(
          title: (title == null || title.isEmpty) ? 'Untitled' : title,
          bullets: bullets,
        ),
      );
    }
    return slides;
  }

  String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
