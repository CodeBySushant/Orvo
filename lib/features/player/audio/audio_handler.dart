import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show OnAudioQuery;

import '../../library/data/library_repository_impl.dart';
import '../../library/domain/entities.dart';
import '../../library/domain/library_repository.dart';

/// The single playback engine. Bridges just_audio to the system layer
/// (notification, lock screen, Bluetooth / headset buttons, Android Auto)
/// via audio_service.
///
/// FIX (#4): shuffle is now implemented at the QUEUE level instead of using
/// just_audio's internal shuffle mode. Enabling shuffle physically reorders
/// the queue (current track first, the rest shuffled after it) and remembers
/// the original order; disabling restores it. This means the visible queue is
/// ALWAYS the true play order — so the queue sheet's "Up next", drag-reorder,
/// swipe-remove and "Play next" are correct in every mode. Previously, queue
/// edits operated on unshuffled indices while playback followed a hidden
/// shuffled order, silently corrupting the mapping.
class OrvoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  OrvoAudioHandler() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource? _playlist;

  /// Queue-level shuffle state.
  bool _shuffleEnabled = false;

  /// Original order, remembered while shuffle is on so it can be restored.
  List<MediaItem>? _unshuffledQueue;

  /// When true, play/pause/skip use short volume ramps ("smooth transitions").
  /// True overlapping crossfade needs a dual-player architecture — deferred.
  bool fadeEnabled = false;

  /// FIX (#6): user-visible playback error messages ("couldn't play X —
  /// skipped"). The app shell listens and shows a SnackBar.
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errors => _errorController.stream;
  int _consecutiveErrors = 0;

  /// FIX (#7): whether playback should auto-resume when a transient
  /// interruption (phone call, alarm) ends.
  bool _resumeAfterInterruption = false;

  /// FEATURE (#18): opt-in — when true, paused playback auto-resumes when a
  /// Bluetooth audio device (headphones / car stereo) connects while a queue
  /// is loaded. Pushed in from the persisted setting on app start.
  bool autoResumeOnDeviceConnect = false;

  /// BUG FIX (#22b): consecutive watchdog ticks spent pinned at track end.
  int _stallTicks = 0;

  void _stallTick() {
    if (!_player.playing) {
      _stallTicks = 0;
      return;
    }
    final duration = _player.duration;
    if (duration == null || duration == Duration.zero) {
      _stallTicks = 0;
      return;
    }
    final nearEnd =
        duration - _player.position <= const Duration(milliseconds: 300);
    if (!nearEnd) {
      _stallTicks = 0;
      return;
    }
    if (++_stallTicks < 2) return; // still within a normal transition window
    _stallTicks = 0;

    // Stuck at the end while "playing": force the move ourselves.
    final i = _player.currentIndex;
    final hasNext = i != null && i + 1 < queue.value.length;
    _cancelCrossfade();
    _player.seek(Duration.zero, index: hasNext ? i + 1 : 0);
    _player.play();
  }

  /// Needed by the equalizer platform channel (audiofx attaches per-session).
  int? get androidAudioSessionId => _player.androidAudioSessionId;

  /// FIX (#2): emits whenever the platform allocates / changes the audio
  /// session, so the equalizer can auto-attach as soon as playback exists.
  Stream<int?> get androidAudioSessionIdStream =>
      _player.androidAudioSessionIdStream;

  // --- FIX (#5): read access for the persistence layer --------------------

  int? get currentIndex => _player.currentIndex;
  Duration get position => _player.position;
  bool get shuffleEnabled => _shuffleEnabled;
  List<MediaItem>? get unshuffledQueue =>
      _unshuffledQueue == null ? null : List.unmodifiable(_unshuffledQueue!);

  /// FIX (#17): generation token — bumping it cancels any in-flight fade so
  /// rapid play/pause/skip taps can't race the volume ramp.
  int _fadeToken = 0;

  // --- FEATURE (crossfade v1) --------------------------------------------
  //
  // Radio-style auto-crossfade on the single-player engine: the ending
  // track fades out over its final N seconds and the next fades in.
  // True dual-player overlap is deliberately NOT used: Android's audiofx
  // equalizer binds to one audio session, so a second player would play
  // un-EQ'd through every transition (and would break the lazy gapless
  // queue). This version keeps EQ, gapless, and persistence fully intact.

  Duration _crossfade = Duration.zero;
  Timer? _crossfadeTicker;
  bool _crossfadingOut = false;

  set crossfadeDuration(Duration value) {
    _crossfade = value;
    if (value == Duration.zero) {
      _crossfadeTicker?.cancel();
      _crossfadeTicker = null;
    } else {
      _crossfadeTicker ??= Timer.periodic(
          const Duration(milliseconds: 400), (_) => _crossfadeTick());
    }
  }

  void _crossfadeTick() {
    if (_crossfade == Duration.zero || _crossfadingOut) return;
    if (!_player.playing) return;
    if (_player.loopMode == LoopMode.one) return; // looping one track: no fade
    final duration = _player.duration;
    if (duration == null || duration <= _crossfade) return;
    final remaining = duration - _player.position;
    if (remaining <= Duration.zero || remaining > _crossfade) return;

    final i = _player.currentIndex;
    final hasNext = (i != null && i + 1 < queue.value.length) ||
        (_player.loopMode == LoopMode.all && queue.value.length > 1);
    if (!hasNext) return; // last track, no repeat: let it end naturally

    _crossfadingOut = true;
    final fadeSpan = remaining - const Duration(milliseconds: 150);
    if (fadeSpan > Duration.zero) {
      _fadeVolume(_player.volume, 0.05, fadeSpan); // deliberately not awaited
    }
  }

  /// Cancels any crossfade in progress and restores full volume. Called by
  /// every manual transport action so user intent always wins.
  Future<void> _cancelCrossfade({bool restoreVolume = true}) async {
    _crossfadingOut = false;
    _fadeToken++;
    if (restoreVolume) await _player.setVolume(1);
  }

  Future<void> _fadeVolume(double from, double to, Duration duration) async {
    final token = ++_fadeToken;
    // More steps for long crossfades, few for short button ramps.
    final steps = (duration.inMilliseconds / 100).clamp(8, 60).round();
    final stepMs = duration.inMilliseconds ~/ steps;
    for (var i = 1; i <= steps; i++) {
      if (token != _fadeToken) return; // superseded by a newer transport op
      await _player.setVolume(from + (to - from) * i / steps);
      await Future.delayed(Duration(milliseconds: stepMs));
    }
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // System playback state (notification buttons, seek bar, etc).
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // FIX (#6): a corrupt / missing file used to stop playback silently.
    // Now: tell the user and auto-skip to the next track. A run of 3
    // consecutive failures stops instead of looping through a dead queue.
    _player.playbackEventStream.listen((event) {
      if (_player.processingState == ProcessingState.ready) {
        _consecutiveErrors = 0;
      }
    }, onError: (Object e, StackTrace st) async {
      _consecutiveErrors++;
      final failedTitle = _currentItem?.title;
      _errorController.add(failedTitle == null
          ? "Couldn't play this track — skipping."
          : 'Couldn\'t play "$failedTitle" — skipping.');
      if (_consecutiveErrors >= 3) {
        _errorController.add('Several tracks failed to play — stopping.');
        await _player.stop();
        return;
      }
      final i = _player.currentIndex;
      if (i != null && i + 1 < queue.value.length) {
        try {
          await _player.seek(Duration.zero, index: i + 1);
          _player.play();
        } catch (_) {}
      } else {
        await _player.stop();
      }
    });

    // Keep the notification's current item in sync with the player index.
    _player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index != null && index >= 0 && index < q.length) {
        mediaItem.add(q[index]);
      }
      // FEATURE (crossfade v1): the previous track faded out — bring the
      // new one in gently instead of snapping to full volume.
      if (_crossfadingOut) {
        _crossfadingOut = false;
        if (_crossfade > Duration.zero) {
          _player.setVolume(0);
          final fadeInMs =
              (_crossfade.inMilliseconds * .6).round().clamp(400, 4000);
          _fadeVolume(0, 1, Duration(milliseconds: fadeInMs));
        } else {
          _player.setVolume(1);
        }
      }
    });

    // Pause when headphones are unplugged (never auto-resume from this).
    session.becomingNoisyEventStream.listen((_) {
      _resumeAfterInterruption = false;
      pause();
    });

    // BUG FIX (#22a): wrap-around at the end of the queue. With repeat OFF,
    // just_audio reports `completed` after the LAST track and simply stops.
    // Standard player behaviour is to loop back to the first track and keep
    // playing — so do exactly that. (With repeat all/one, just_audio already
    // wraps by itself and `completed` never fires here.)
    _player.processingStateStream.listen((state) async {
      if (state != ProcessingState.completed) return;
      if (_player.loopMode != LoopMode.off) return;
      if (queue.value.isEmpty) return;
      await _cancelCrossfade();
      await _player.seek(Duration.zero, index: 0);
      _player.play();
    });

    // BUG FIX (#22b): auto-advance watchdog. On some devices the lazily
    // prepared playlist can stall at a track boundary — the track finishes
    // but ExoPlayer never moves to the next one (player still "playing",
    // position pinned at the end). Detect that state (stuck within 300ms of
    // the end across two consecutive checks ≈ 3s) and force the advance.
    // Normal playback never trips this: a real transition passes through
    // the end zone in well under one check interval.
    Timer.periodic(const Duration(milliseconds: 1500), (_) => _stallTick());

    // FEATURE (#18): opt-in auto-resume when a Bluetooth audio device
    // connects (headphones, car). Guarded so it only fires when paused with
    // a real queue, and re-checked after a short delay so the system has
    // time to route audio to the new device — and so a user action in the
    // meantime always wins.
    session.devicesChangedEventStream.listen((event) async {
      if (!autoResumeOnDeviceConnect) return;
      final bluetoothAdded = event.devicesAdded.any((d) =>
          d.type == AudioDeviceType.bluetoothA2dp ||
          d.type == AudioDeviceType.bluetoothSco);
      if (!bluetoothAdded) return;
      if (_player.playing || queue.value.isEmpty) return;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!autoResumeOnDeviceConnect ||
          _player.playing ||
          queue.value.isEmpty) {
        return;
      }
      play();
    });

    // FIX (#7): duck / pause on interruptions (calls, navigation prompts),
    // and auto-resume when a transient interruption ends — standard music
    // player behaviour. Volume is only restored for duck-type events so it
    // no longer races an in-flight fade after a pause-type interruption.
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(.3);
          case AudioInterruptionType.pause:
            _resumeAfterInterruption = _player.playing;
            pause();
          case AudioInterruptionType.unknown:
            _resumeAfterInterruption = false;
            pause();
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(1);
          case AudioInterruptionType.pause:
            if (_resumeAfterInterruption) {
              _resumeAfterInterruption = false;
              play();
            }
          case AudioInterruptionType.unknown:
            _resumeAfterInterruption = false;
        }
      }
    });
  }

  /// Rebuilds the audio source from [items], seeking to the given index +
  /// position. Used by shuffle toggling and session restore.
  Future<void> _rebuild(
    List<MediaItem> items, {
    required int index,
    Duration position = Duration.zero,
    bool resume = false,
  }) async {
    await _cancelCrossfade();
    queue.add(items);
    _playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: [
        for (final item in items)
          AudioSource.uri(Uri.parse(item.id), tag: item),
      ],
    );
    try {
      await _player.setAudioSource(
        _playlist!,
        initialIndex: index.clamp(0, items.length - 1),
        initialPosition: position,
      );
      if (resume) await _player.play();
    } catch (_) {
      // FIX (#6): corrupt / missing file at the target index — tell the
      // user instead of failing silently.
      _errorController.add("Couldn't start playback — the file may be "
          'missing or corrupt.');
    }
  }

  /// Replaces the queue and starts playback. Lazy preparation keeps huge
  /// queues (10k+ items) instant to load.
  ///
  /// Starting a fresh queue defines a fresh order, so any remembered
  /// unshuffled order is discarded and shuffle resets to off.
  Future<void> loadQueue(
    List<MediaItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (items.isEmpty) return;
    _shuffleEnabled = false;
    _unshuffledQueue = null;
    await _rebuild(items, index: startIndex, resume: autoPlay);
  }

  /// FIX (#5): restores a previously persisted session — queue, position,
  /// shuffle state (with its remembered original order) and repeat mode —
  /// WITHOUT starting playback.
  Future<void> restoreState({
    required List<MediaItem> items,
    required int index,
    required Duration position,
    bool shuffleEnabled = false,
    List<MediaItem>? unshuffled,
    AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none,
  }) async {
    if (items.isEmpty) return;
    _shuffleEnabled = shuffleEnabled;
    _unshuffledQueue =
        (shuffleEnabled && unshuffled != null) ? List.of(unshuffled) : null;
    await setRepeatMode(repeatMode);
    await _rebuild(items, index: index, position: position, resume: false);
    _broadcastState();
  }

  MediaItem? get _currentItem {
    final q = queue.value;
    final i = _player.currentIndex;
    if (i == null || i < 0 || i >= q.length) return null;
    return q[i];
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

    // Keep the remembered original order consistent while shuffled: insert
    // right after the current item's position there too.
    final orig = _unshuffledQueue;
    if (_shuffleEnabled && orig != null) {
      final curId = _currentItem?.id;
      var at =
          curId == null ? orig.length : orig.indexWhere((m) => m.id == curId) + 1;
      if (at <= 0) at = orig.length;
      orig.insertAll(at, items);
    }
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

    _unshuffledQueue?.addAll(items);
  }

  Future<void> moveQueueItem(int from, int to) async {
    final playlist = _playlist;
    if (playlist == null) return;
    await playlist.move(from, to);
    final q = List<MediaItem>.from(queue.value);
    final item = q.removeAt(from);
    q.insert(to, item);
    queue.add(q);
    // Reordering the live (shuffled) order doesn't change the remembered
    // original order — turning shuffle off returns to the pre-shuffle order.
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final playlist = _playlist;
    if (playlist == null || index < 0 || index >= queue.value.length) return;
    final removed = queue.value[index];
    await playlist.removeAt(index);
    final q = List<MediaItem>.from(queue.value)..removeAt(index);
    queue.add(q);

    // Remove ONE matching occurrence from the remembered original order.
    final orig = _unshuffledQueue;
    if (_shuffleEnabled && orig != null) {
      final i = orig.indexWhere((m) => m.id == removed.id);
      if (i != -1) orig.removeAt(i);
    }
  }

  // --- Transport -----------------------------------------------------------

  @override
  Future<void> play() async {
    _crossfadingOut = false;
    if (fadeEnabled && !_player.playing) {
      await _player.setVolume(0);
      _player.play();
      await _fadeVolume(0, 1, const Duration(milliseconds: 260));
    } else {
      if (!_player.playing) {
        _fadeToken++;
        await _player.setVolume(1);
      }
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    _crossfadingOut = false;
    if (fadeEnabled && _player.playing) {
      await _fadeVolume(_player.volume, 0, const Duration(milliseconds: 200));
      await _player.pause();
      await _player.setVolume(1);
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _cancelCrossfade();
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    _crossfadingOut = false;
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
    _crossfadingOut = false;
    // Standard behaviour: restart the track after 3s, otherwise go back.
    if (_player.position > const Duration(seconds: 3)) {
      await _cancelCrossfade();
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
    _crossfadingOut = false;
    // FIX (#17): respect the smooth-transitions setting here too.
    if (fadeEnabled && _player.playing) {
      await _fadeVolume(_player.volume, 0, const Duration(milliseconds: 160));
      await _player.seek(Duration.zero, index: index);
      await _player.setVolume(1);
      await _player.play();
    } else {
      _fadeToken++; // cancel any in-flight fade
      await _player.setVolume(1);
      await _player.seek(Duration.zero, index: index);
      await _player.play();
    }
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

  /// FIX (#4): queue-level shuffle.
  ///
  /// Enable: remember the current order, then rebuild the queue as
  /// [current track, ...rest shuffled], preserving playback position.
  /// Disable: restore the remembered order (reconciled with any items added
  /// or removed while shuffled), keeping the current track playing.
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    if (enable == _shuffleEnabled) return;

    final q = queue.value;
    if (q.isEmpty) {
      _shuffleEnabled = enable;
      _broadcastState();
      return;
    }

    final wasPlaying = _player.playing;
    final pos = _player.position;
    final curIdx = (_player.currentIndex ?? 0).clamp(0, q.length - 1);
    final current = q[curIdx];

    if (enable) {
      _unshuffledQueue = List.of(q);
      final rest = List.of(q)..removeAt(curIdx);
      rest.shuffle(Random());
      _shuffleEnabled = true;
      await _rebuild([current, ...rest],
          index: 0, position: pos, resume: wasPlaying);
    } else {
      final original = _unshuffledQueue;
      _shuffleEnabled = false;
      _unshuffledQueue = null;
      if (original == null) {
        _broadcastState();
        return;
      }
      // Reconcile: keep items still present (matching duplicates by count)
      // in their original order, then append anything added while shuffled.
      final counts = <String, int>{};
      for (final m in q) {
        counts[m.id] = (counts[m.id] ?? 0) + 1;
      }
      final restored = <MediaItem>[];
      for (final m in original) {
        final c = counts[m.id] ?? 0;
        if (c > 0) {
          restored.add(m);
          counts[m.id] = c - 1;
        }
      }
      for (final m in q) {
        final c = counts[m.id] ?? 0;
        if (c > 0) {
          restored.add(m);
          counts[m.id] = c - 1;
        }
      }
      var newIndex = restored.indexWhere((m) => m.id == current.id);
      if (newIndex == -1) newIndex = 0;
      await _rebuild(restored,
          index: newIndex, position: pos, resume: wasPlaying);
    }
    _broadcastState();
  }

  /// Re-emits the playback state so UI toggles (shuffle icon) update even
  /// when no player event fires.
  void _broadcastState() {
    playbackState.add(_transformEvent(_player.playbackEvent));
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

  /// FIX (#14): browse-cache entries now expire (5 min TTL) so playing from
  /// Android Auto can't use a list that's stale after a rescan or delete.
  final Map<String, (int, List<Song>)> _autoLists = {};
  static const _autoCacheTtl = Duration(minutes: 5);

  void _cacheAutoList(String key, List<Song> songs) {
    _autoLists[key] = (DateTime.now().millisecondsSinceEpoch, songs);
  }

  List<Song>? _freshAutoList(String key) {
    final entry = _autoLists[key];
    if (entry == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - entry.$1;
    if (age > _autoCacheTtl.inMilliseconds) {
      _autoLists.remove(key);
      return null;
    }
    return entry.$2;
  }

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
        _cacheAutoList(parentMediaId, songs);
        return songs.map(_songToItem).toList(growable: false);
      }
      if (parentMediaId == _idSongs) {
        // FIX (#14): raised cap (was 300).
        final songs =
            (await _autoLibrary.songs()).take(500).toList(growable: false);
        _cacheAutoList(parentMediaId, songs);
        return songs.map(_songToItem).toList(growable: false);
      }
      if (parentMediaId == _idAlbums) {
        final albums = await _autoLibrary.albums();
        return [
          // FIX (#14): raised cap (was 100).
          for (final album in albums.take(200))
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
        _cacheAutoList(parentMediaId, songs);
        return songs.map(_songToItem).toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    // Prefer the list the item was browsed from so next/previous stay
    // within that context — but only if the cached list is still fresh
    // (FIX #14: stale entries are skipped and later evicted).
    for (final key in List<String>.from(_autoLists.keys)) {
      final list = _freshAutoList(key);
      if (list == null) continue;
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
      // FIX (#4): shuffle is queue-level now; report our own flag.
      shuffleMode: _shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }
}
