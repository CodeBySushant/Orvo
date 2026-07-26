import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// FIX (#18): Permission.audio / Permission.photos only exist on Android 13+
/// (READ_MEDIA_AUDIO / READ_MEDIA_IMAGES). On Android 12 and below,
/// permission_handler 11.x has NO manifest mapping for them and instantly
/// returns denied ("No permissions found in manifest for: []33") — the
/// system dialog never appears. The correct permission there is
/// Permission.storage (READ_EXTERNAL_STORAGE, declared in the manifest with
/// maxSdkVersion=32).
class MediaPermissions {
  MediaPermissions._();

  static int? _sdkInt;

  static Future<int> sdkInt() async {
    if (_sdkInt != null) return _sdkInt!;
    if (!Platform.isAndroid) return _sdkInt = 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return _sdkInt = info.version.sdkInt;
  }

  /// The permission REQUIRED to read the music library on this device.
  static Future<Permission> required() async =>
      (await sdkInt()) >= 33 ? Permission.audio : Permission.storage;

  /// Optional extra permission that improves album art. Android 13+ only —
  /// below that, storage already covers everything, so there's nothing
  /// extra to ask for.
  static Future<Permission?> optionalImages() async =>
      (await sdkInt()) >= 33 ? Permission.photos : null;

  static Future<bool> isGranted() async => (await required()).isGranted;
}
