/// Small formatting helpers used across the app.
abstract final class Formatters {
  /// 03:45 or 1:03:45 for hour-plus tracks.
  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
    return '$m:$s';
  }

  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Up late';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Good night';
  }

  /// "1,204 songs · 82 hrs"
  static String libraryStats(int songCount, Duration total) {
    final hours = total.inHours;
    final songs = _thousands(songCount);
    return hours > 0 ? '$songs songs · $hours hrs' : '$songs songs';
  }

  static String _thousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final remaining = s.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }

  /// Initials for artwork placeholders: "Midnight City" -> "MC".
  static String initials(String text) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? '♪' : letters;
  }
}
