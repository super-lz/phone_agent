String formatTokenCount(int value) {
  if (value >= 100000000) {
    return '${_trimDecimal(value / 100000000)}亿';
  }
  if (value >= 10000) {
    return '${_trimDecimal(value / 10000)}万';
  }
  return value.toString();
}

String formatTokenDuration(Duration value) {
  if (value.inSeconds <= 0) {
    return '0 分';
  }
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours > 0) {
    return '$hours 小时 $minutes 分';
  }
  final seconds = value.inSeconds.remainder(60);
  if (minutes > 0) {
    return '$minutes 分 $seconds 秒';
  }
  return '$seconds 秒';
}

String _trimDecimal(double value) {
  final text = value.toStringAsFixed(1);
  if (text.endsWith('.0')) {
    return text.substring(0, text.length - 2);
  }
  return text;
}
