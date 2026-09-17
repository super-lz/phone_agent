import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';

/// Excel/xlsx codec. Other Office formats must not import this file.
class SpreadsheetCodec {
  const SpreadsheetCodec();

  Uint8List encodeXlsx(List<List<String>> rows) {
    final excel = Excel.createExcel();
    const sheetName = 'Sheet1';
    final sheet = excel[sheetName];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
      final row = rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex += 1) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(
            columnIndex: columnIndex,
            rowIndex: rowIndex,
          ),
          _cellValue(row[columnIndex]),
        );
      }
    }
    final saved = excel.save();
    if (saved == null) {
      throw StateError('xlsx encode failed');
    }
    return Uint8List.fromList(saved);
  }

  String encodeCsv(List<List<String>> rows) {
    return rows
        .map(
          (row) =>
              row.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','),
        )
        .join('\n');
  }

  String extract(String path, Uint8List bytes) {
    if (path.toLowerCase().endsWith('.csv')) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    final excel = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();
    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName];
      if (sheet == null) {
        continue;
      }
      if (excel.tables.length > 1) {
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.writeln('# $sheetName');
      }
      for (final row in sheet.rows) {
        buffer.writeln(row.map(_cellText).join('\t'));
      }
    }
    return buffer.toString().trim();
  }

  CellValue _cellValue(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return TextCellValue('');
    }
    final asInt = int.tryParse(text);
    if (asInt != null) {
      return IntCellValue(asInt);
    }
    final asDouble = double.tryParse(text);
    if (asDouble != null) {
      return DoubleCellValue(asDouble);
    }
    return TextCellValue(raw);
  }

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) {
      return '';
    }
    return switch (value) {
      TextCellValue(:final value) => value.toString(),
      IntCellValue(:final value) => '$value',
      DoubleCellValue(:final value) => '$value',
      BoolCellValue(:final value) => '$value',
      FormulaCellValue(:final formula) => formula,
      DateCellValue() => value.toString(),
      TimeCellValue() => value.toString(),
      DateTimeCellValue() => value.toString(),
    };
  }
}
