import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import 'player_providers.dart';

const _kSmoothKey = 'orvo.smoothTransitions';
const _kCrossfadeKey = 'orvo.crossfadeSec';
const _kBtResumeKey = 'orvo.btAutoResume';

/// "Smooth transitions": short volume ramps on play / pause / skip.
/// Persisted, and pushed into the audio handler on read.
class SmoothTransitionsNotifier extends Notifier<bool> {
  @override
  bool build() {
    final value =
        ref.read(sharedPreferencesProvider).getBool(_kSmoothKey) ?? false;
    ref.read(audioHandlerProvider).fadeEnabled = value;
    return value;
  }

  void set(bool value) {
    state = value;
    ref.read(audioHandlerProvider).fadeEnabled = value;
    ref.read(sharedPreferencesProvider).setBool(_kSmoothKey, value);
  }
}

final smoothTransitionsProvider =
    NotifierProvider<SmoothTransitionsNotifier, bool>(
        SmoothTransitionsNotifier.new);

/// FEATURE (crossfade v1): auto-crossfade length in seconds (0 = off).
/// The ending track fades out over its final N seconds and the next track
/// fades in. Persisted, and pushed into the audio handler on read.
class CrossfadeNotifier extends Notifier<int> {
  static const options = [0, 2, 4, 6, 8, 12];

  @override
  int build() {
    final value =
        ref.read(sharedPreferencesProvider).getInt(_kCrossfadeKey) ?? 0;
    ref.read(audioHandlerProvider).crossfadeDuration =
        Duration(seconds: value);
    return value;
  }

  void set(int seconds) {
    state = seconds;
    ref.read(audioHandlerProvider).crossfadeDuration =
        Duration(seconds: seconds);
    ref.read(sharedPreferencesProvider).setInt(_kCrossfadeKey, seconds);
  }
}

final crossfadeProvider =
    NotifierProvider<CrossfadeNotifier, int>(CrossfadeNotifier.new);

/// FEATURE (#18): auto-resume playback when a Bluetooth audio device
/// (headphones / car) connects. Off by default — some users hate surprise
/// audio in the car. Persisted, and pushed into the audio handler on read.
class BtAutoResumeNotifier extends Notifier<bool> {
  @override
  bool build() {
    final value =
        ref.read(sharedPreferencesProvider).getBool(_kBtResumeKey) ?? false;
    ref.read(audioHandlerProvider).autoResumeOnDeviceConnect = value;
    return value;
  }

  void set(bool value) {
    state = value;
    ref.read(audioHandlerProvider).autoResumeOnDeviceConnect = value;
    ref.read(sharedPreferencesProvider).setBool(_kBtResumeKey, value);
  }
}

final btAutoResumeProvider = NotifierProvider<BtAutoResumeNotifier, bool>(
    BtAutoResumeNotifier.new);

/// Current playback speed, mirrored from the engine for UI display.
final playbackSpeedProvider = Provider<double>(
  (ref) => ref.watch(playbackStateProvider).valueOrNull?.speed ?? 1.0,
);
