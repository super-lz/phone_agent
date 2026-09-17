import 'dart:convert';
import 'dart:typed_data';

import 'document/document_codec.dart';
import 'pdf/pdf_codec.dart';
import 'presentation/presentation_pptx.dart';
import 'spreadsheet/spreadsheet_codec.dart';

/// UI/preview dispatcher only. Agent tools must call the format-specific handler.
Future<String> extractOfficeText(String path, Uint8List bytes) async {
  final lower = path.toLowerCase();
  try {
    if (lower.endsWith('.docx')) {
      return DocumentCodec().extract(bytes);
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.csv')) {
      return SpreadsheetCodec().extract(path, bytes);
    }
    if (lower.endsWith('.pptx')) {
      return PresentationPptxCodec().extract(bytes);
    }
    if (lower.endsWith('.pdf')) {
      return PdfCodec().extract(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  } catch (error) {
    return 'Extraction failed for $path: $error';
  }
}
