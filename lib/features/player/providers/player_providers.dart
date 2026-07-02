import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;
import 'package:palette_generator/palette_generator.dart';

import '../../../core/widgets/artwork.dart';
import '../../library/domain/entities.dart';
import '../audio/audio_handler.dart';

/// Overridden in main() once AudioService.init completes.
final audioHandlerProvider =
    Provider<OrvoAudioHandler>((ref) => throw UnimplementedError());

final currentMediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);

final isPlayingProvider = Provider<bool>(
  (ref) => ref.watch(playbackStateProvider).valueOrNull?.playing ?? false,
);

final queueIndexProvider = Provider<int?>(
  (ref) => ref.watch(playbackStateProvider).valueOrNull?.queueIndex,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => AudioService.position,
);

/// Song id of the item currently loaded, for "now playing" row highlights.
final currentSongIdProvider = Provider<int?>((ref) {
  final item = ref.watch(currentMediaItemProvider).valueOrNull;
  return item?.extras?['songId'] as int?;
});

// ---------------------------------------------------------------------------
// Palette — dynamic colors extracted from the current artwork
// ---------------------------------------------------------------------------

class NowPlayingPalette {
  const NowPlayingPalette({required this.background, required this.accent});
  final Color background;
  final Color accent;

  static const fallback = NowPlayingPalette(
    background: Color(0xFF23151A),
    accent: Color(0xFFFF4D63),
  );
}

final paletteProvider =
    FutureProvider.family<NowPlayingPalette, int>((ref, songId) async {
  final bytes =
      await ArtworkCache.instance.load(songId, ArtworkType.AUDIO, size: 200);
  if (bytes == null || bytes.isEmpty) return NowPlayingPalette.fallback;
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      MemoryImage(bytes),
      maximumColorCount: 16,
    );
    final base = palette.darkVibrantColor?.color ??
        palette.darkMutedColor?.color ??
        palette.dominantColor?.color ??
        NowPlayingPalette.fallback.background;
    final accent = palette.vibrantColor?.color ??
        palette.lightVibrantColor?.color ??
        NowPlayingPalette.fallback.accent;
    return NowPlayingPalette(
      background: Color.lerp(base, Colors.black, .35)!,
      accent: Color.lerp(accent, Colors.white, .15)!,
    );
  } catch (_) {
    return NowPlayingPalette.fallback;
  }
});

// ---------------------------------------------------------------------------
// Controller — the only way screens start playback
// ---------------------------------------------------------------------------

final playerControllerProvider = Provider<PlayerController>(
  (ref) => PlayerController(ref.watch(audioHandlerProvider)),
);

class PlayerController {
  PlayerController(this._handler);
  final OrvoAudioHandler _handler;

  Future<void> playFrom(List<Song> songs, int index) async {
    await _handler.setShuffleMode(AudioServiceShuffleMode.none);
    await _handler.loadQueue(
      songs.map(toMediaItem).toList(growable: false),
      startIndex: index,
    );
  }

  Future<void> shuffleAll(List<Song> songs) async {
    if (songs.isEmpty) return;
    final shuffled = List<Song>.from(songs)..shuffle(Random());
    await _handler.setShuffleMode(AudioServiceShuffleMode.none);
    await _handler.loadQueue(
      shuffled.map(toMediaItem).toList(growable: false),
    );
  }

  Future<void> playNext(Song song) =>
      _handler.insertNext([toMediaItem(song)]);

  Future<void> addToQueue(Song song) =>
      _handler.appendToQueue([toMediaItem(song)]);

  static MediaItem toMediaItem(Song s) => MediaItem(
        id: s.uri,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.duration,
        artUri: s.albumId > 0
            ? Uri.parse('content://media/external/audio/albumart/${s.albumId}')
            : null,
        extras: {
          'songId': s.id,
          'albumId': s.albumId,
          'artistId': s.artistId,
          'path': s.path,
        },
      );
}
