import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';

/// FEATURE (#20): tapping the media notification opens the Now Playing
/// screen instead of just landing on whatever screen was last open.
///
/// audio_service already reopens the Activity on tap (via
/// AudioServiceActivity); this listens to its notificationClicked stream and
/// finishes the job by pushing /player. The stream is a BehaviorSubject, so
/// a cold start FROM the notification also replays the tap once the app
/// shell mounts — the player slides up right after launch.
///
/// Uses the raw stream (not a StreamProvider) deliberately: repeated taps
/// re-emit `true`, and Riverpod's value-equality would swallow those.
final notificationTapProvider = Provider<void>((ref) {
  final router = ref.watch(routerProvider);

  final sub = AudioService.notificationClicked.listen((clicked) {
    if (!clicked) return;
    // Already on the player (or mid-transition to it): don't stack copies.
    final current = router.routerDelegate.currentConfiguration.uri.path;
    if (current == '/player') return;
    router.push('/player');
  });

  ref.onDispose(sub.cancel);
});
