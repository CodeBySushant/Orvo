import 'package:flutter/services.dart';

/// Result of a set-ringtone attempt.
enum RingtoneResult { ok, needsPermission, failed }

/// Platform channel for OS-level song actions: share, set as ringtone,
/// and delete-from-device (scoped-storage delete request on Android 11+).
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
}
