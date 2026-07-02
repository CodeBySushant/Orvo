import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';
import '../player/providers/player_providers.dart';

/// Counts a "play" when a track has been the current item for 15 seconds —
/// skipping through songs doesn't pollute Most Played.
class PlayTracker {
  PlayTracker(this._ref);

  final Ref _ref;
  StreamSubscription<MediaItem?>? _sub;
  Timer? _timer;
  int? _lastRecordedFor;

  void start() {
    _sub = _ref.read(audioHandlerProvider).mediaItem.listen((item) {
      _timer?.cancel();
      final songId = item?.extras?['songId'] as int?;
      if (songId == null || songId == _lastRecordedFor) return;
      _timer = Timer(const Duration(seconds: 15), () => _record(songId));
    });
  }

  Future<void> _record(int songId) async {
    _lastRecordedFor = songId;
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
    _sub?.cancel();
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
