/// Pembantu pemformatan paparan (BM).
library;

const _bmMonths = [
  'Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun',
  'Jul', 'Ogo', 'Sep', 'Okt', 'Nov', 'Dis',
];

String formatBytes(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${_trim(kb)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${_trim(mb)} MB';
  final gb = mb / 1024;
  return '${_trim(gb)} GB';
}

String _trim(double v) {
  final s = v.toStringAsFixed(v < 10 ? 2 : 1);
  if (s.endsWith('.00')) return s.substring(0, s.length - 3);
  if (s.endsWith('0')) return s.substring(0, s.length - 1);
  return s;
}

String formatSpeed(double megaBytesPerSecond) {
  if (megaBytesPerSecond <= 0) return '0 MB/s';
  if (megaBytesPerSecond < 1) {
    return '${(megaBytesPerSecond * 1024).toStringAsFixed(0)} KB/s';
  }
  return '${megaBytesPerSecond.toStringAsFixed(1)} MB/s';
}

String formatMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  final s = ms / 1000;
  return '${s.toStringAsFixed(s < 10 ? 2 : 1)}s';
}

String formatCountdown(int ms) {
  if (ms <= 0) return '0s';
  final s = (ms / 1000).ceil();
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  return '${m}m ${s % 60}s';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Jam 24 jam: 09:41:05
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// 09:41
String formatClockShort(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// 12 Sep 2026
String formatDate(DateTime d) => '${d.day} ${_bmMonths[d.month - 1]} ${d.year}';

/// 12 Sep 2026, 09:41
String formatDateTime(DateTime d) => '${formatDate(d)}, ${formatClockShort(d)}';

/// 'Hari Ini' / 'Semalam' / tarikh penuh
String formatRelativeDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Hari Ini';
  if (diff == 1) return 'Semalam';
  return formatDate(d);
}

String formatPercent(double value) {
  final pct = (value.clamp(0.0, 1.0) * 100).toStringAsFixed(value < 0.1 ? 1 : 0);
  return '$pct%';
}
