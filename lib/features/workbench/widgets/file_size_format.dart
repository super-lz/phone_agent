String formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }

  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${_formatUnit(kib)} KB';
  }

  return '${_formatUnit(kib / 1024)} MB';
}

String _formatUnit(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(value < 10 ? 1 : 0);
}
