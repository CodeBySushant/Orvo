import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show OnAudioQuery;

import '../../library/data/library_repository_impl.dart';
import '../../library/domain/entities.dart';
import '../../library/domain/library_repository.dart';

/// The single playback engine. Bridges just_audio to the system layer
/// (notification, lock screen, Bluetooth / headset buttons, Android Auto
/// surface in a later phase) via audio_service.
class OrvoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  OrvoAudioHandler() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource? _playlist;

  /// When true, play/pause/skip use short volume ramps ("smooth transitions").
  /// True overlapping crossfade needs a dual-player architecture — deferred.
  bool fadeEnabled = false;

  /// Needed by the equalizer platform channel (audiofx attaches per-session).
  int? get androidAudioSessionId => _player.androidAudioSessionId;

  Future<void> _fadeVolume(double from, double to, Duration duration) async {
    const steps = 8;
    final stepMs = duration.inMilliseconds ~/ steps;
    for (var i = 1; i <= steps; i++) {
      await _player.setVolume(from + (to - from) * i / steps);
      await Future.delayed(Duration(milliseconds: stepMs));
    }
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // System playback state (notification buttons, seek bar, etc).
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Keep the notification's current item in sync with the player index.
    _player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index != null && index >= 0 && index < q.length) {
        mediaItem.add(q[index]);
      }
    });

    // Pause when headphones are unplugged.
    session.becomingNoisyEventStream.listen((_) => pause());

    // Duck / pause on interruptions (calls, navigation prompts).
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (event.type == AudioInterruptionType.duck) {
          _player.setVolume(.3);
        } else {
          pause();
        }
      } else {
        _player.setVolume(1);
      }
    });
  }

  /// Replaces the queue and starts playback. Lazy preparation keeps huge
  /// queues (10k+ items) instant to load.
  Future<void> loadQueue(
    List<MediaItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (items.isEmpty) return;
    queue.add(items);
    _playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: [
        for (final item in items)
          AudioSource.uri(Uri.parse(item.id), tag: item),
      ],
    );
    try {
      await _player.setAudioSource(_playlist!, initialIndex: startIndex);
      if (autoPlay) await _player.play();
    } catch (_) {
      // Corrupt / missing file at the start index — surface idle state
      // rather than crashing.
    }
  }

  /// Inserts items right after the current track ("Play next").
  /// Falls back to starting a fresh queue if nothing is loaded.
  Future<void> insertNext(List<MediaItem> items) async {
    final playlist = _playlist;
    if (playlist == null || queue.value.isEmpty) {
      await loadQueue(items);
      return;
    }
    final index =
        ((_player.currentIndex ?? -1) + 1).clamp(0, queue.value.length);
    await playlist.insertAll(index, [
      for (final item in items) AudioSource.uri(Uri.parse(item.id), tag: item),
    ]);
    final q = List<MediaItem>.from(queue.value)..insertAll(index, items);
    queue.add(q);
  }

  /// Appends items to the end of the queue ("Add to queue").
  Future<void> appendToQueue(List<MediaItem> items) async {
    final playlist = _playlist;
    if (playlist == null || queue.value.isEmpty) {
      await loadQueue(items);
      return;
    }
    await playlist.addAll([
      for (final item in items) AudioSource.uri(Uri.parse(item.id), tag: item),
    ]);
    final q = List<MediaItem>.from(queue.value)..addAll(items);
    queue.add(q);
  }

  Future<void> moveQueueItem(int from, int to) async {
    final playlist = _playlist;
    if (playlist == null) return;
    await playlist.move(from, to);
    final q = List<MediaItem>.from(queue.value);
    final item = q.removeAt(from);
    q.insert(to, item);
    queue.add(q);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final playlist = _playlist;
    if (playlist == null || index < 0 || index >= queue.value.length) return;
    await playlist.removeAt(index);
    final q = List<MediaItem>.from(queue.value)..removeAt(index);
    queue.add(q);
  }

  // --- Transport -----------------------------------------------------------

  @override
  Future<void> play() async {
    if (fadeEnabled && !_player.playing) {
      await _player.setVolume(0);
      _player.play();
      await _fadeVolume(0, 1, const Duration(milliseconds: 260));
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    if (fadeEnabled && _player.playing) {
      await _fadeVolume(_player.volume, 0, const Duration(milliseconds: 200));
      await _player.pause();
      await _player.setVolume(1);
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (fadeEnabled && _player.playing) {
      await _fadeVolume(_player.volume, 0, const Duration(milliseconds: 160));
      await _player.seekToNext();
      await _player.setVolume(1);
    } else {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    // Standard behaviour: restart the track after 3s, otherwise go back.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (fadeEnabled && _player.playing) {
      await _fadeVolume(_player.volume, 0, const Duration(milliseconds: 160));
      await _player.seekToPrevious();
      await _player.setVolume(1);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
    _player.play();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await _player.setLoopMode(LoopMode.all);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  // --- Android Auto browsing ----------------------------------------------
  //
  // audio_service exposes this handler as a MediaBrowserService; Android
  // Auto (and Bluetooth browsers) call getChildren to build their UI.

  final LibraryRepository _autoLibrary = LibraryRepositoryImpl(OnAudioQuery());
  final Map<String, List<Song>> _autoLists = {};

  static const _idRecent = 'orvo-recent';
  static const _idSongs = 'orvo-songs';
  static const _idAlbums = 'orvo-albums';
  static const _idAlbumPrefix = 'orvo-album-';

  MediaItem _songToItem(Song s) => MediaItem(
        id: s.uri,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.duration,
        artUri: s.albumId > 0
            ? Uri.parse(
                'content://media/external/audio/albumart/${s.albumId}')
            : null,
        extras: {
          'songId': s.id,
          'albumId': s.albumId,
          'artistId': s.artistId,
          'path': s.path,
        },
      );

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    try {
      if (parentMediaId == AudioService.browsableRootId) {
        return const [
          MediaItem(
              id: _idRecent, title: 'Recently added', playable: false),
          MediaItem(id: _idSongs, title: 'Songs', playable: false),
          MediaItem(id: _idAlbums, title: 'Albums', playable: false),
        ];
      }
      if (parentMediaId == _idRecent) {
        final songs =
            (await _autoLibrary.songs()).take(50).toList(growable: false);
        _autoLists[parentMediaId] = songs;
        return songs.map(_songToItem).toList(growable: false);
      }
      if (parentMediaId == _idSongs) {
        final songs =
            (await _autoLibrary.songs()).take(300).toList(growable: false);
        _autoLists[parentMediaId] = songs;
        return songs.map(_songToItem).toList(growable: false);
      }
      if (parentMediaId == _idAlbums) {
        final albums = await _autoLibrary.albums();
        return [
          for (final album in albums.take(100))
            MediaItem(
              id: '$_idAlbumPrefix${album.id}',
              title: album.title,
              artist: album.artist,
              playable: false,
              artUri: Uri.parse(
                  'content://media/external/audio/albumart/${album.id}'),
            ),
        ];
      }
      if (parentMediaId.startsWith(_idAlbumPrefix)) {
        final albumId =
            int.tryParse(parentMediaId.substring(_idAlbumPrefix.length));
        if (albumId == null) return const [];
        final songs = await _autoLibrary.albumSongs(albumId);
        _autoLists[parentMediaId] = songs;
        return songs.map(_songToItem).toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    // Prefer the list the item was browsed from so next/previous stay
    // within that context.
    for (final list in _autoLists.values) {
      final index = list.indexWhere((s) => s.uri == mediaId);
      if (index != -1) {
        await loadQueue(list.map(_songToItem).toList(growable: false),
            startIndex: index);
        return;
      }
    }
    final songs = await _autoLibrary.songs();
    final index = songs.indexWhere((s) => s.uri == mediaId);
    if (index != -1) {
      await loadQueue(songs.map(_songToItem).toList(growable: false),
          startIndex: index);
    }
  }

  // --- State mapping -------------------------------------------------------

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
      repeatMode: const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.one: AudioServiceRepeatMode.one,
        LoopMode.all: AudioServiceRepeatMode.all,
      }[_player.loopMode]!,
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }
}
