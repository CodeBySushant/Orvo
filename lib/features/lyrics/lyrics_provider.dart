import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import '../system/system_channel.dart';
import 'lyrics_parser.dart';

const _kLyricsFolderKey = 'orvo.lyricsFolder';

/// FIX (#10): the user's chosen SAF lyrics folder (tree URI with a persisted
/// read grant), or null when not configured. Lets `.lrc` sidecar files work
/// under scoped storage on Android 11+.
class LyricsFolderNotifier extends Notifier<String?> {
  @override
  String? build() =>
      ref.read(sharedPreferencesProvider).getString(_kLyricsFolderKey);

  /// Opens the system folder picker; persists the grant on success.
  /// Returns true if a folder was chosen.
  Future<bool> pick() async {
    final uri = await SystemChannel.pickLyricsFolder();
    if (uri == null) return false;
    state = uri;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_kLyricsFolderKey, uri);
    return true;
  }

  Future<void> clear() async {
    state = null;
    await ref.read(sharedPreferencesProvider).remove(_kLyricsFolderKey);
  }
}

final lyricsFolderProvider =
    NotifierProvider<LyricsFolderNotifier, String?>(LyricsFolderNotifier.new);

/// Lyrics for a given audio file path. Keyed by path so results are shared
/// between the sheet and any future full-screen lyrics view.
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics, String>(
  (ref, path) => LyricsLoader.load(
    path,
    safTreeUri: ref.watch(lyricsFolderProvider),
  ),
);
