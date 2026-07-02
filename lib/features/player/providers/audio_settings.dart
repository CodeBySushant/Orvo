import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import 'player_providers.dart';

const _kSmoothKey = 'orvo.smoothTransitions';

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

/// Current playback speed, mirrored from the engine for UI display.
final playbackSpeedProvider = Provider<double>(
  (ref) => ref.watch(playbackStateProvider).valueOrNull?.speed ?? 1.0,
);
