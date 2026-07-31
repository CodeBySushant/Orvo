import 'package:flutter/services.dart';

/// Result of a set-ringtone attempt.
enum RingtoneResult { ok, needsPermission, failed }

/// Platform channel for OS-level song actions: share, set as ringtone,
/// delete-from-device (scoped-storage delete request on Android 11+), and
/// the SAF lyrics-folder integration.
abstract final class SystemChannel {
  static const _channel = MethodChannel('orvo/system');

  /// Opens the system share sheet for the audio file.
  static Future<void> shareSong(String uri, String title) async {
    try {
      await _channel.invokeMethod('share', {'uri': uri, 'title': title});
    } catch (_) {}
  }

  /// Sets the song as the default ringtone. Requires the special
  /// WRITE_SETTINGS permission — when missing, returns needsPermission and
  /// the caller should offer [openWriteSettings].
  static Future<RingtoneResult> setRingtone(String uri) async {
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('setRingtone', {'uri': uri});
      if (result == null) return RingtoneResult.failed;
      if (result['needsPermission'] == true) {
        return RingtoneResult.needsPermission;
      }
      return result['ok'] == true ? RingtoneResult.ok : RingtoneResult.failed;
    } catch (_) {
      return RingtoneResult.failed;
    }
  }

  /// Opens the system screen where the user can grant WRITE_SETTINGS.
  static Future<void> openWriteSettings() async {
    try {
      await _channel.invokeMethod('openWriteSettings');
    } catch (_) {}
  }

  /// Deletes the file via MediaStore. On Android 11+ this shows the system
  /// confirmation dialog (scoped storage); returns true once it's gone.
  static Future<bool> deleteSong(String uri) async {
    try {
      final ok = await _channel.invokeMethod<bool>('delete', {'uri': uri});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// FEATURE (duplicate finder): deletes several files at once. On Android
  /// 11+ this shows ONE system confirmation dialog covering all of them,
  /// instead of one dialog per file. Returns true once they're gone.
  static Future<bool> deleteSongs(List<String> uris) async {
    if (uris.isEmpty) return false;
    try {
      final ok =
          await _channel.invokeMethod<bool>('deleteMany', {'uris': uris});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- FEATURE (backup): SAF documents ------------------------------------

  /// Opens the system "Save as…" picker (Google Drive appears as a
  /// destination when installed) and writes [content] into the chosen file.
  /// Returns true on success, false when cancelled or the write failed.
  static Future<bool> createDocument(String fileName, String content) async {
    try {
      final ok = await _channel.invokeMethod<bool>('createDocument', {
        'fileName': fileName,
        'content': content,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system file picker and returns the picked file's text
  /// content, or null when cancelled / unreadable.
  static Future<String?> openDocument() async {
    try {
      return await _channel.invokeMethod<String>('openDocument');
    } catch (_) {
      return null;
    }
  }

  // --- FIX (#10): SAF lyrics folder --------------------------------------

  /// Opens the system folder picker. Returns the granted tree URI, or null
  /// if the user cancelled.
  static Future<String?> pickLyricsFolder() async {
    try {
      return await _channel.invokeMethod<String>('pickLyricsFolder');
    } catch (_) {
      return null;
    }
  }

  /// Reads "<baseName>.lrc" from the previously granted lyrics folder
  /// (searched up to 3 levels deep). Returns the file contents or null.
  static Future<String?> readLyrics(String treeUri, String baseName) async {
    try {
      return await _channel.invokeMethod<String>('readLyrics', {
        'treeUri': treeUri,
        'baseName': baseName,
      });
    } catch (_) {
      return null;
    }
  }
}
