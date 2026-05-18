import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'message_block_cards.dart';

class MarkdownBlockView extends StatelessWidget {
  const MarkdownBlockView({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final segments = _splitFencedCode(text);
    if (segments.length == 1 && !segments.first.isCode) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _MarkdownText(content: segments.first.content),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          if (segment.isCode)
            CodeBlockCard(
              language: segment.language,
              code: segment.content,
              initiallyExpanded: false,
              showCollapsedPreview: false,
            )
          else if (segment.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MarkdownText(content: segment.content),
            ),
      ],
    );
  }

  List<_MarkdownSegment> _splitFencedCode(String value) {
    final segments = <_MarkdownSegment>[];
    final textBuffer = StringBuffer();
    final codeBuffer = StringBuffer();
    var inCode = false;
    var language = '';

    for (final line in value.split('\n')) {
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft.startsWith('```')) {
        if (inCode) {
          segments.add(
            _MarkdownSegment.code(language, _withoutTrailingLine(codeBuffer)),
          );
          codeBuffer.clear();
          language = '';
          inCode = false;
        } else {
          final text = _withoutTrailingLine(textBuffer);
          if (text.trim().isNotEmpty) {
            segments.add(_MarkdownSegment.text(text));
          }
          textBuffer.clear();
          language = trimmedLeft.substring(3).trim();
          inCode = true;
        }
        continue;
      }

      if (inCode) {
        codeBuffer.writeln(line);
      } else {
        textBuffer.writeln(line);
      }
    }

    if (inCode) {
      segments.add(
        _MarkdownSegment.code(language, _withoutTrailingLine(codeBuffer)),
      );
    } else {
      final text = _withoutTrailingLine(textBuffer);
      if (text.trim().isNotEmpty || segments.isEmpty) {
        segments.add(_MarkdownSegment.text(text));
      }
    }
    return segments;
  }

  String _withoutTrailingLine(StringBuffer buffer) {
    final value = buffer.toString();
    return value.endsWith('\n') ? value.substring(0, value.length - 1) : value;
  }
}

class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: MarkdownTextRepair.repair(content),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
        listBullet: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFFF6F8F5),
          border: const Border(left: BorderSide(color: Color(0xFF9BB49E))),
          borderRadius: BorderRadius.circular(4),
        ),
        blockSpacing: 10,
      ),
    );
  }
}

class MarkdownTextRepair {
  const MarkdownTextRepair._();

  static String repair(String value) {
    var repaired = value.replaceAll('\r\n', '\n');
    repaired = _closeOddDelimiter(repaired, '`');
    repaired = _closeOddDelimiter(repaired, '**');
    return repaired;
  }

  static String _closeOddDelimiter(String value, String delimiter) {
    if (_delimiterCount(value, delimiter).isEven) {
      return value;
    }
    return '$value$delimiter';
  }

  static int _delimiterCount(String value, String delimiter) {
    var count = 0;
    var index = 0;
    var inInlineCode = false;
    while (index < value.length) {
      if (delimiter != '`' && value.startsWith('`', index)) {
        inInlineCode = !inInlineCode;
        index += 1;
        continue;
      }
      if (!inInlineCode && value.startsWith(delimiter, index)) {
        final escaped = index > 0 && value.codeUnitAt(index - 1) == 92;
        if (!escaped) {
          count += 1;
        }
        index += delimiter.length;
      } else {
        index += 1;
      }
    }
    return count;
  }
}

class _MarkdownSegment {
  const _MarkdownSegment.text(this.content) : isCode = false, language = '';

  const _MarkdownSegment.code(this.language, this.content) : isCode = true;

  final bool isCode;
  final String language;
  final String content;
}
