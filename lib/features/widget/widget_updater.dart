import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/providers/player_providers.dart';

/// Pushes the current track + play state into the home-screen widget via a
/// method channel. Runs for the app session; while music plays the process
/// stays alive (foreground service), so the widget stays fresh.
final widgetUpdaterProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;

  const channel = MethodChannel('orvo/widget');
  final handler = ref.watch(audioHandlerProvider);
  final subs = <StreamSubscription<dynamic>>[];

  Future<void> push() async {
    final MediaItem? item = handler.mediaItem.valueOrNull;
    final playing = handler.playbackState.valueOrNull?.playing ?? false;
    try {
      await channel.invokeMethod('update', {
        'title': item?.title ?? 'Orvo',
        'artist': item?.artist ?? 'Nothing playing',
        'playing': playing,
        'albumId': item?.extras?['albumId'] as int? ?? -1,
      });
    } catch (_) {/* widget not placed / channel unavailable */}
  }

  subs.add(handler.mediaItem.listen((_) => push()));
  subs.add(handler.playbackState
      .map((s) => s.playing)
      .distinct()
      .listen((_) => push()));

  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
});
