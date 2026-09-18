import 'dart:io';
import 'dart:typed_data';

/// Loads a TrueType/OpenType font, including the first face in a .ttc.
class SfntFont {
  const SfntFont();

  static const systemCandidates = <String>[
    '/system/fonts/DroidSansFallback.ttf',
    '/system/fonts/NotoSansSC-Regular.ttf',
    '/system/fonts/NotoSansSC-Regular.otf',
    '/system/fonts/NotoSansCJKsc-Regular.otf',
    '/system/fonts/NotoSansHans-Regular.otf',
    '/system/fonts/NotoSansCJK-Regular.otf',
    '/system/fonts/NotoSansCJK-Regular.ttc',
    '/system/fonts/NotoSerifCJK-Regular.ttc',
    '/System/Library/Fonts/Supplemental/Songti.ttc',
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/STHeiti Medium.ttc',
    '/System/Library/Fonts/PingFang.ttc',
  ];

  Future<Uint8List?> loadSystemCjkFace() async {
    for (final path in systemCandidates) {
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        final count = _faceCount(bytes);
        for (var index = 0; index < count; index += 1) {
          final face = extractFace(bytes, fontIndex: index);
          if (isTrueType(face)) {
            return face;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  int _faceCount(Uint8List bytes) {
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'ttcf') {
      return ByteData.sublistView(bytes).getUint32(8);
    }
    return 1;
  }

  bool isTrueType(Uint8List face) {
    if (face.length < 4) {
      return false;
    }
    final scaler = ByteData.sublistView(face).getUint32(0);
    return scaler == 0x00010000 || scaler == 0x74727565;
  }

  Uint8List extractFace(Uint8List bytes, {int fontIndex = 0}) {
    if (bytes.length < 12) {
      throw const FormatException('font too small');
    }
    final tag = String.fromCharCodes(bytes.sublist(0, 4));
    if (tag != 'ttcf') {
      return bytes;
    }
    final data = ByteData.sublistView(bytes);
    final numFonts = data.getUint32(8);
    if (fontIndex < 0 || fontIndex >= numFonts) {
      throw FormatException(
        'fontIndex $fontIndex out of range 0..${numFonts - 1}',
      );
    }
    final fontOffset = data.getUint32(12 + fontIndex * 4);
    final numTables = data.getUint16(fontOffset + 4);
    final header = bytes.sublist(fontOffset, fontOffset + 12);
    final records = <_TableRecord>[];
    for (var i = 0; i < numTables; i++) {
      final rec = fontOffset + 12 + i * 16;
      records.add(
        _TableRecord(
          tag: data.getUint32(rec),
          checksum: data.getUint32(rec + 4),
          offset: data.getUint32(rec + 8),
          length: data.getUint32(rec + 12),
        ),
      );
    }

    var cursor = 12 + numTables * 16;
    final rewritten = <_TableRecord>[];
    final tableBlobs = <Uint8List>[];
    for (final record in records) {
      final aligned = (cursor + 3) & ~3;
      final pad = aligned - cursor;
      if (pad > 0) {
        tableBlobs.add(Uint8List(pad));
        cursor = aligned;
      }
      tableBlobs.add(
        bytes.sublist(record.offset, record.offset + record.length),
      );
      rewritten.add(
        _TableRecord(
          tag: record.tag,
          checksum: record.checksum,
          offset: cursor,
          length: record.length,
        ),
      );
      cursor += record.length;
    }

    final out = BytesBuilder(copy: false);
    out.add(header);
    final directory = ByteData(numTables * 16);
    for (var i = 0; i < rewritten.length; i++) {
      final record = rewritten[i];
      final base = i * 16;
      directory.setUint32(base, record.tag);
      directory.setUint32(base + 4, record.checksum);
      directory.setUint32(base + 8, record.offset);
      directory.setUint32(base + 12, record.length);
    }
    out.add(directory.buffer.asUint8List());
    for (final blob in tableBlobs) {
      out.add(blob);
    }
    return Uint8List.fromList(out.takeBytes());
  }
}

class _TableRecord {
  const _TableRecord({
    required this.tag,
    required this.checksum,
    required this.offset,
    required this.length,
  });

  final int tag;
  final int checksum;
  final int offset;
  final int length;
}
