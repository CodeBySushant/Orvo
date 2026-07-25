import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../core/widgets/artwork.dart';
import '../player/providers/player_providers.dart';

/// Pushes the current track + play state into the home-screen widget via a
/// method channel. Runs for the app session; while music plays the process
/// stays alive (foreground service), so the widget stays fresh.
///
/// FIX (#13): album art is now sent as raw bytes and rendered with
/// setImageViewBitmap on the native side. The old approach handed the
/// launcher a content://media/.../albumart URI, which most launchers have
/// no permission to read — so art showed blank on many devices.
final widgetUpdaterProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;

  const channel = MethodChannel('orvo/widget');
  final handler = ref.watch(audioHandlerProvider);
  final subs = <StreamSubscription<dynamic>>[];

  // Avoid re-loading the same artwork on every play/pause flip.
  int? lastArtSongId;
  Uint8List? lastArtBytes;

  Future<void> push() async {
    final MediaItem? item = handler.mediaItem.valueOrNull;
    final playing = handler.playbackState.valueOrNull?.playing ?? false;

    Uint8List? art;
    final songId = item?.extras?['songId'] as int?;
    if (songId != null) {
      if (songId == lastArtSongId) {
        art = lastArtBytes;
      } else {
        try {
          art = await ArtworkCache.instance
              .load(songId, ArtworkType.AUDIO, size: 256);
        } catch (_) {
          art = null;
        }
        lastArtSongId = songId;
        lastArtBytes = art;
      }
    }

    try {
      await channel.invokeMethod('update', {
        'title': item?.title ?? 'Orvo',
        'artist': item?.artist ?? 'Nothing playing',
        'playing': playing,
        'art': art,
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
