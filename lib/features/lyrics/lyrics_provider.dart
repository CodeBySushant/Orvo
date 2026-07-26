import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import '../system/system_channel.dart';
import 'lyrics_online.dart';
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

// FEATURE (#21): opt-in online lyrics (LRCLIB). Off by default so Orvo's
// no-network privacy promise holds unless the user chooses otherwise.
const _kOnlineLyricsKey = 'orvo.onlineLyrics';

class OnlineLyricsNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_kOnlineLyricsKey) ?? false;

  void set(bool value) {
    state = value;
    ref.read(sharedPreferencesProvider).setBool(_kOnlineLyricsKey, value);
  }
}

final onlineLyricsProvider =
    NotifierProvider<OnlineLyricsNotifier, bool>(OnlineLyricsNotifier.new);

/// Everything a lyrics lookup needs. Equality is (songId, path) so the
/// family caches one result per track.
class LyricsRequest {
  const LyricsRequest({
    required this.songId,
    required this.path,
    required this.title,
    this.artist,
    this.album,
    this.durationSec,
  });

  final int songId;
  final String path;
  final String title;
  final String? artist;
  final String? album;
  final int? durationSec;

  @override
  bool operator ==(Object other) =>
      other is LyricsRequest && other.songId == songId && other.path == path;

  @override
  int get hashCode => Object.hash(songId, path);
}

/// FEATURE (#21): result wrapper so the sheet can tell "no lyrics exist"
/// apart from "the online lookup couldn't run" (offline / timeout).
class LyricsResult {
  const LyricsResult(this.lyrics, {this.lookupFailed = false});
  final Lyrics lyrics;
  final bool lookupFailed;
}

/// Lyrics for a track, in priority order: local sources (sidecar .lrc, SAF
/// lyrics folder, embedded USLT) → then, if the toggle is on, the sqflite
/// cache → LRCLIB. Watching [onlineLyricsProvider] means flipping the
/// toggle re-runs open lookups immediately.
final lyricsProvider =
    FutureProvider.autoDispose.family<LyricsResult, LyricsRequest>(
        (ref, req) async {
  final local = await LyricsLoader.load(
    req.path,
    safTreeUri: ref.watch(lyricsFolderProvider),
  );
  if (!local.isEmpty) return LyricsResult(local);

  if (!ref.watch(onlineLyricsProvider)) return const LyricsResult(Lyrics.none);

  final online = await OnlineLyrics.load(
    songId: req.songId,
    title: req.title,
    artist: req.artist,
    album: req.album,
    durationSec: req.durationSec,
  );
  if (online == null) {
    return const LyricsResult(Lyrics.none, lookupFailed: true);
  }
  return LyricsResult(online);
});
