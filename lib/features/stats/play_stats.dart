import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../favorites/favorites_provider.dart';
import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';
import '../player/providers/player_providers.dart';

/// Counts a "play" when a track has been LISTENED TO for 15 seconds.
///
/// FIX (#8): the old implementation armed a 15-second wall-clock timer as
/// soon as a track became current — so playing 2 seconds, pausing, and
/// waiting still counted as a play. It also never counted replays on
/// repeat-one, because the media item stream doesn't re-emit when a track
/// loops. Now:
///  - a Stopwatch accumulates only actual playing time (paused time doesn't
///    count), and the play is recorded once 15 listened seconds accumulate;
///  - a position snap back to the start of the same track (repeat-one loop
///    or a manual restart) begins a fresh "spin" that can count again.
class PlayTracker {
  PlayTracker(this._ref);

  final Ref _ref;

  StreamSubscription<MediaItem?>? _itemSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _timer;

  final Stopwatch _listened = Stopwatch();
  int? _songId;
  bool _recorded = false;
  bool _playing = false;
  Duration _lastPosition = Duration.zero;

  static const _threshold = Duration(seconds: 15);

  void start() {
    final handler = _ref.read(audioHandlerProvider);

    _itemSub = handler.mediaItem.listen((item) {
      _beginSpin(item?.extras?['songId'] as int?);
    });

    _playingSub = handler.playbackState
        .map((s) => s.playing)
        .distinct()
        .listen((playing) {
      _playing = playing;
      if (playing) {
        _listened.start();
        _schedule();
      } else {
        _listened.stop();
        _timer?.cancel();
      }
    });

    _positionSub = AudioService.position.listen((pos) {
      // Same track snapped back to the start after real progress =
      // repeat-one loop or manual restart → new spin, can count again.
      if (pos < const Duration(seconds: 2) &&
          _lastPosition > const Duration(seconds: 10)) {
        _beginSpin(_songId, keepSong: true);
      }
      _lastPosition = pos;
    });
  }

  void _beginSpin(int? songId, {bool keepSong = false}) {
    _timer?.cancel();
    _listened
      ..stop()
      ..reset();
    if (!keepSong) {
      _songId = songId;
      _lastPosition = Duration.zero;
    }
    _recorded = false;
    if (_songId != null && _playing) {
      _listened.start();
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_songId == null || _recorded) return;
    final remaining = _threshold - _listened.elapsed;
    if (remaining <= Duration.zero) {
      _record();
    } else {
      _timer = Timer(remaining, _record);
    }
  }

  Future<void> _record() async {
    final songId = _songId;
    if (songId == null || _recorded) return;
    // Guard against the timer firing right after a pause.
    if (_listened.elapsed < _threshold) {
      if (_playing) _schedule();
      return;
    }
    _recorded = true;
    final db = await AppDatabase.instance.database;
    await db.rawInsert('''
      INSERT INTO play_stats(song_id, play_count, last_played_at)
      VALUES(?, 1, ?)
      ON CONFLICT(song_id) DO UPDATE SET
        play_count = play_count + 1,
        last_played_at = excluded.last_played_at
    ''', [songId, DateTime.now().millisecondsSinceEpoch]);
    _ref.invalidate(recentlyPlayedProvider);
    _ref.invalidate(mostPlayedProvider);
  }

  void dispose() {
    _timer?.cancel();
    _itemSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
  }
}

final playTrackerProvider = Provider<PlayTracker>((ref) {
  final tracker = PlayTracker(ref)..start();
  ref.onDispose(tracker.dispose);
  return tracker;
});

Future<List<Song>> _resolve(Ref ref, String orderBy, {String? where}) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(
    'play_stats',
    columns: ['song_id'],
    where: where,
    orderBy: orderBy,
    limit: 20,
  );
  final ids = rows.map((r) => r['song_id'] as int).toList(growable: false);
  if (ids.isEmpty) return const [];
  final songs = await ref.watch(songsProvider.future);
  final byId = {for (final s in songs) s.id: s};
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
}

final recentlyPlayedProvider = FutureProvider<List<Song>>(
  (ref) => _resolve(ref, 'last_played_at DESC'),
);

final mostPlayedProvider = FutureProvider<List<Song>>(
  (ref) => _resolve(ref, 'play_count DESC, last_played_at DESC',
      where: 'play_count >= 2'),
);

// ---------------------------------------------------------------------------
// FIX (#16): orphan cleanup
// ---------------------------------------------------------------------------

/// After every successful library scan, purges rows referencing songs that
/// no longer exist in the media store (deleted / moved files) from
/// play_stats, playlist_songs, and favorites. Previously these accumulated
/// forever. Kept alive for the whole app session by app_shell.
final libraryCleanupProvider = Provider<void>((ref) {
  // FEATURE (#25): listen to the RAW scan so folder exclusions never purge
  // favorites / playlist rows / stats — only truly deleted files do.
  ref.listen(rawSongsProvider, (previous, next) {
    final songs = next.valueOrNull;
    // Empty can mean "permission lost" or "scan failed" — never treat it
    // as "everything was deleted".
    if (songs == null || songs.isEmpty) return;
    _cleanupOrphans(ref, songs);
  });
});

Future<void> _cleanupOrphans(Ref ref, List<Song> songs) async {
  try {
    final valid = {for (final s in songs) s.id};
    final db = await AppDatabase.instance.database;

    var removedAny = false;
    for (final table in ['play_stats', 'playlist_songs']) {
      final rows =
          await db.query(table, columns: ['song_id'], distinct: true);
      final orphans = [
        for (final r in rows)
          if (!valid.contains(r['song_id'] as int)) r['song_id'] as int,
      ];
      if (orphans.isEmpty) continue;
      removedAny = true;
      final batch = db.batch();
      for (final id in orphans) {
        batch.delete(table, where: 'song_id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    }
    if (removedAny) {
      ref.invalidate(recentlyPlayedProvider);
      ref.invalidate(mostPlayedProvider);
    }

    // Favorites live in SharedPreferences, not the DB.
    ref.read(favoritesProvider.notifier).retainOnly(valid);
  } catch (_) {
    // Cleanup is best-effort; never let it break the app.
  }
}
