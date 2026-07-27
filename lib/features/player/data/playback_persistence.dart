import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_database.dart';
import '../audio/audio_handler.dart';
import '../providers/player_providers.dart';

/// FIX (#5): persists the playback session (queue, current track, position,
/// shuffle state + remembered original order, repeat mode) into the app's
/// sqflite database, and restores it — paused, at the exact position — on
/// the next launch.
///
/// Save triggers:
///  - queue changes and track changes (debounced 800ms)
///  - pause (captures the final position)
///  - every 10 seconds while playing
class PlaybackPersistence {
  PlaybackPersistence(this._handler);

  final OrvoAudioHandler _handler;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _positionTimer;
  Timer? _saveDebounce;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _restore();

    _subs.add(_handler.queue.listen((_) => _scheduleSave()));
    _subs.add(_handler.mediaItem.listen((_) => _scheduleSave()));
    _subs.add(_handler.playbackState
        .map((s) => s.playing)
        .distinct()
        .listen((playing) {
      _positionTimer?.cancel();
      if (playing) {
        _positionTimer = Timer.periodic(
            const Duration(seconds: 10), (_) => _save());
      } else {
        _save(); // capture position on pause / stop
      }
    }));
  }

  void dispose() {
    _positionTimer?.cancel();
    _saveDebounce?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _save);
  }

  // --- Save ---------------------------------------------------------------

  Future<void> _save() async {
    try {
      final queue = _handler.queue.value;
      if (queue.isEmpty) return;

      final payload = jsonEncode({
        'index': _handler.currentIndex ?? 0,
        'positionMs': _handler.position.inMilliseconds,
        'shuffle': _handler.shuffleEnabled,
        'repeat': _repeatToString(
            _handler.playbackState.value.repeatMode),
        'queue': [for (final m in queue) _itemToMap(m)],
        'unshuffled': _handler.shuffleEnabled
            ? [for (final m in _handler.unshuffledQueue ?? queue) m.id]
            : null,
      });

      final db = await AppDatabase.instance.database;
      await db.insert(
        'player_state',
        {
          'id': 1,
          'payload': payload,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[Orvo] persistence save ERROR: $e');
    }
  }

  // --- Restore ------------------------------------------------------------

  Future<void> _restore() async {
    try {
      // Never clobber a session that's already running (e.g. the playback
      // service survived while the UI process restarted).
      if (_handler.queue.value.isNotEmpty) return;

      final db = await AppDatabase.instance.database;
      final rows =
          await db.query('player_state', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return;

      final data =
          jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
      final rawQueue = (data['queue'] as List?) ?? const [];
      if (rawQueue.isEmpty) return;

      final items = [
        for (final raw in rawQueue)
          _itemFromMap((raw as Map).cast<String, dynamic>()),
      ];

      // Rebuild the remembered original order from stored uris (duplicates
      // resolved by consuming matches one at a time).
      List<MediaItem>? unshuffled;
      final shuffle = data['shuffle'] == true;
      final unshuffledIds = (data['unshuffled'] as List?)?.cast<String>();
      if (shuffle && unshuffledIds != null) {
        final pool = List<MediaItem>.from(items);
        unshuffled = [];
        for (final id in unshuffledIds) {
          final i = pool.indexWhere((m) => m.id == id);
          if (i != -1) unshuffled.add(pool.removeAt(i));
        }
        unshuffled.addAll(pool); // anything left over keeps its place
      }

      await _handler.restoreState(
        items: items,
        index: (data['index'] as num?)?.toInt() ?? 0,
        position: Duration(
            milliseconds: (data['positionMs'] as num?)?.toInt() ?? 0),
        shuffleEnabled: shuffle,
        unshuffled: unshuffled,
        repeatMode: _repeatFromString(data['repeat'] as String?),
      );
      debugPrint('[Orvo] restored session: ${items.length} tracks');
    } catch (e) {
      debugPrint('[Orvo] persistence restore ERROR: $e');
    }
  }

  // --- Serialization ------------------------------------------------------

  Map<String, dynamic> _itemToMap(MediaItem m) => {
        'uri': m.id,
        'title': m.title,
        'artist': m.artist,
        'album': m.album,
        'durMs': m.duration?.inMilliseconds,
        'songId': m.extras?['songId'],
        'albumId': m.extras?['albumId'],
        'artistId': m.extras?['artistId'],
        'path': m.extras?['path'],
      };

  MediaItem _itemFromMap(Map<String, dynamic> map) {
    final albumId = (map['albumId'] as num?)?.toInt() ?? -1;
    // FIX (lock screen): sessions persisted BEFORE the metadata sanitizer
    // still contain raw "<unknown>" strings — clean them on the way out so
    // an old saved queue can't reintroduce ugly names into the notification.
    String clean(String? v, String fallback) {
      final t = v?.trim();
      if (t == null || t.isEmpty || t.toLowerCase() == '<unknown>') {
        return fallback;
      }
      return t;
    }

    return MediaItem(
      id: map['uri'] as String,
      title: clean(map['title'] as String?, 'Unknown'),
      artist: clean(map['artist'] as String?, 'Unknown Artist'),
      album: clean(map['album'] as String?, 'Unknown Album'),
      duration: map['durMs'] == null
          ? null
          : Duration(milliseconds: (map['durMs'] as num).toInt()),
      artUri: albumId > 0
          ? Uri.parse('content://media/external/audio/albumart/$albumId')
          : null,
      extras: {
        'songId': (map['songId'] as num?)?.toInt(),
        'albumId': albumId,
        'artistId': (map['artistId'] as num?)?.toInt() ?? -1,
        'path': map['path'],
      },
    );
  }

  String _repeatToString(AudioServiceRepeatMode mode) => switch (mode) {
        AudioServiceRepeatMode.one => 'one',
        AudioServiceRepeatMode.all => 'all',
        AudioServiceRepeatMode.group => 'all',
        AudioServiceRepeatMode.none => 'none',
      };

  AudioServiceRepeatMode _repeatFromString(String? value) => switch (value) {
        'one' => AudioServiceRepeatMode.one,
        'all' => AudioServiceRepeatMode.all,
        _ => AudioServiceRepeatMode.none,
      };
}

/// Kept alive for the whole app session by app_shell. Restores the previous
/// session once on creation, then keeps saving as playback evolves.
final playbackPersistenceProvider = Provider<PlaybackPersistence>((ref) {
  final persistence = PlaybackPersistence(ref.watch(audioHandlerProvider))
    ..start();
  ref.onDispose(persistence.dispose);
  return persistence;
});
