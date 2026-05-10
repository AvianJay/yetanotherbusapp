String formatRelativeTimestamp(DateTime value) {
  final elapsed = DateTime.now().difference(value.toLocal());
  final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  if (seconds < 60) {
    return '$seconds 秒前';
  }

  final minutes = elapsed.inMinutes;
  if (minutes < 60) {
    return '$minutes 分鐘前';
  }

  final hours = elapsed.inHours;
  if (hours < 24) {
    return '$hours 小時前';
  }

  final days = elapsed.inDays;
  return '$days 天前';
}