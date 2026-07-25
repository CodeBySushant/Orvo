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
class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _ticker;
  StreamSubscription<MediaItem?>? _trackSub;
  StreamSubscription<PlaybackState>? _stateSub;

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
    // Track changed -> stop. skip(1) ignores the current value replay.
    _trackSub = handler.mediaItem.skip(1).listen((_) => _finish());
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
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(
        SleepTimerNotifier.new);
