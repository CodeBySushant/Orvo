import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One timestamped lyric line.
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({this.synced = const [], this.unsynced});
  final List<LyricLine> synced;
  final String? unsynced;

  bool get isSynced => synced.isNotEmpty;
  bool get isEmpty =>
      synced.isEmpty && (unsynced == null || unsynced!.trim().isEmpty);

  static const none = Lyrics();
}

/// Loads lyrics for a track, in priority order:
///  1. `.lrc` sidecar file next to the audio (may be blocked by scoped
///     storage on Android 13+ — wrapped in try/catch)
///  2. Embedded ID3v2 USLT frame in the audio file itself; if its text
///     contains LRC timestamps it is treated as synced.
abstract final class LyricsLoader {
  static Future<Lyrics> load(String audioPath) async {
    // 1. Sidecar .lrc
    try {
      final lrcPath = audioPath.replaceAll(RegExp(r'\.[^.\\/]+$'), '.lrc');
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        final parsed = parseLrc(await lrcFile.readAsString());
        if (!parsed.isEmpty) return parsed;
      }
    } catch (_) {/* scoped storage denial — fall through */}

    // 2. Embedded USLT
    try {
      final text = await _readUsltFrame(File(audioPath));
      if (text != null && text.trim().isNotEmpty) {
        final parsed = parseLrc(text);
        if (parsed.isSynced) return parsed;
        return Lyrics(unsynced: text.trim());
      }
    } catch (_) {}

    return Lyrics.none;
  }

  // ---------------------------------------------------------------------
  // LRC parsing
  // ---------------------------------------------------------------------

  static final _timeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

  static Lyrics parseLrc(String raw) {
    final lines = <LyricLine>[];
    for (final line in const LineSplitter().convert(raw)) {
      final tags = _timeTag.allMatches(line).toList();
      if (tags.isEmpty) continue;
      final text = line.substring(tags.last.end).trim();
      for (final tag in tags) {
        final min = int.parse(tag.group(1)!);
        final sec = int.parse(tag.group(2)!);
        final fracRaw = tag.group(3) ?? '0';
        // ".5" = 500ms, ".50" = 500ms, ".500" = 500ms
        final ms = (int.parse(fracRaw) *
                (fracRaw.length == 1 ? 100 : fracRaw.length == 2 ? 10 : 1))
            .clamp(0, 999);
        lines.add(LyricLine(
          Duration(minutes: min, seconds: sec, milliseconds: ms),
          text,
        ));
      }
    }
    if (lines.isEmpty) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? Lyrics.none : Lyrics(unsynced: trimmed);
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return Lyrics(synced: lines);
  }

  // ---------------------------------------------------------------------
  // Minimal ID3v2 USLT extraction (v2.3 / v2.4)
  // ---------------------------------------------------------------------

  static Future<String?> _readUsltFrame(File file) async {
    final raf = await file.open();
    try {
      final header = await raf.read(10);
      if (header.length < 10 ||
          header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
        return null; // no ID3v2 tag
      }
      final version = header[3]; // 3 = v2.3, 4 = v2.4
      if (version < 3 || version > 4) return null;
      final tagSize = _synchsafe(header, 6);
      // Cap the read: lyrics tags are small; 2 MB covers embedded art too.
      final toRead = tagSize.clamp(0, 2 * 1024 * 1024);
      final body = await raf.read(toRead);

      var offset = 0;
      while (offset + 10 <= body.length) {
        final id = String.fromCharCodes(body.sublist(offset, offset + 4));
        if (id.codeUnitAt(0) == 0) break; // padding reached
        final frameSize = version == 4
            ? _synchsafe(body, offset + 4)
            : _uint32(body, offset + 4);
        if (frameSize <= 0 || offset + 10 + frameSize > body.length) break;
        if (id == 'USLT') {
          return _decodeUslt(
              body.sublist(offset + 10, offset + 10 + frameSize));
        }
        offset += 10 + frameSize;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  static String? _decodeUslt(Uint8List frame) {
    if (frame.length < 5) return null;
    final encoding = frame[0];
    var pos = 4; // skip encoding byte + 3-byte language code

    // Skip the content descriptor (null-terminated; 2-byte for UTF-16).
    if (encoding == 1 || encoding == 2) {
      while (pos + 1 < frame.length &&
          !(frame[pos] == 0 && frame[pos + 1] == 0)) {
        pos += 2;
      }
      pos += 2;
    } else {
      while (pos < frame.length && frame[pos] != 0) {
        pos++;
      }
      pos += 1;
    }
    if (pos >= frame.length) return null;
    final textBytes = frame.sublist(pos);

    switch (encoding) {
      case 0: // ISO-8859-1
        return latin1.decode(textBytes, allowInvalid: true);
      case 3: // UTF-8
        return utf8.decode(textBytes, allowMalformed: true);
      case 1: // UTF-16 with BOM
      case 2: // UTF-16BE without BOM
        return _decodeUtf16(textBytes, defaultBigEndian: encoding == 2);
    }
    return null;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool defaultBigEndian}) {
    var start = 0;
    var bigEndian = defaultBigEndian;
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        bigEndian = false;
        start = 2;
      } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        bigEndian = true;
        start = 2;
      }
    }
    final codeUnits = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      codeUnits.add(bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : (bytes[i + 1] << 8) | bytes[i]);
    }
    return String.fromCharCodes(codeUnits);
  }

  static int _synchsafe(List<int> b, int i) =>
      ((b[i] & 0x7F) << 21) |
      ((b[i + 1] & 0x7F) << 14) |
      ((b[i + 2] & 0x7F) << 7) |
      (b[i + 3] & 0x7F);

  static int _uint32(List<int> b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
}
