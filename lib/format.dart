/// Display helpers for sizes and dates.
class Fmt {
  /// Binary units (1 GB = 1024³ bytes) — the same way MEGA reports quota, so a
  /// free account shows "20 GB".
  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
    var v = bytes / 1024;
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    final digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
    var s = v.toStringAsFixed(digits);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return '$s ${units[u]}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `2026-11-15 14:03` in local time.
  static String dateTime(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)} '
        '${_two(l.hour)}:${_two(l.minute)}';
  }

  /// `just now`, `5 min ago`, `3 h ago`, `12 d ago`, `4 mo ago`, `1 y ago`.
  static String ago(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d);
    if (diff.isNegative || diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 30) return '${diff.inDays} d ago';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30} mo ago';
    return '${diff.inDays ~/ 365} y ago';
  }
}
