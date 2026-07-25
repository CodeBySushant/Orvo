import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_providers.dart';

class SleepTimerState {
  const SleepTimerState({this.remaining, this.endOfTrack = false});

  /// Time left for a countdown timer; null when not counting down.
  final Duration? remaining;

  /// True when set to stop after the current track finishes.
  final bool endOfTrack;

  bool get active => remaining != null || endOfTrack;
}

/// Pauses playback when the countdown hits zero or the current track ends.
///
/// FIX (#9): "stop after current track" used to pause on ANY track change —
/// including the user manually skipping to the next song, which is clearly
/// not "the track ended". Now a track change only triggers the stop when the
/// previous track actually played to (within 2s of) its end; a manual skip
/// keeps the timer armed for the newly current track instead.
class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _ticker;
  StreamSubscription<MediaItem?>? _trackSub;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  MediaItem? _armedTrack;
  Duration _lastPosition = Duration.zero;

  @override
  SleepTimerState build() {
    ref.onDispose(_cleanup);
    return const SleepTimerState();
  }

  void start(Duration duration) {
    _cleanup();
    state = SleepTimerState(remaining: duration);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = (state.remaining ?? Duration.zero) -
          const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _finish();
      } else {
        state = SleepTimerState(remaining: left);
      }
    });
  }

  void stopAfterTrack() {
    _cleanup();
    state = const SleepTimerState(endOfTrack: true);
    final handler = ref.read(audioHandlerProvider);

    _armedTrack = handler.mediaItem.valueOrNull;
    _lastPosition = Duration.zero;

    // Track how far into the armed track playback actually got.
    _positionSub = AudioService.position.listen((p) => _lastPosition = p);

    // Track changed: only a NATURAL end (played to within 2s of the track's
    // duration) stops playback. A manual skip re-arms for the new track.
    _trackSub = handler.mediaItem.skip(1).listen((item) {
      final dur = _armedTrack?.duration;
      final naturalEnd =
          dur != null && _lastPosition >= dur - const Duration(seconds: 2);
      if (naturalEnd) {
        _finish();
      } else {
        _armedTrack = item;
        _lastPosition = Duration.zero;
      }
    });

    // Queue ended (no next item emits) -> stop on completion.
    _stateSub = handler.playbackState.listen((s) {
      if (s.processingState == AudioProcessingState.completed) _finish();
    });
  }

  void cancel() {
    _cleanup();
    state = const SleepTimerState();
  }

  void _finish() {
    ref.read(audioHandlerProvider).pause();
    cancel();
  }

  void _cleanup() {
    _ticker?.cancel();
    _ticker = null;
    _trackSub?.cancel();
    _trackSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _armedTrack = null;
    _lastPosition = Duration.zero;
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(
        SleepTimerNotifier.new);
