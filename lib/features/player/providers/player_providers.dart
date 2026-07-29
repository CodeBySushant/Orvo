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

/// FIX (#6): user-visible playback error messages (corrupt / missing files).
/// The app shell listens to this and shows a SnackBar.
final playbackErrorProvider = StreamProvider<String>(
  (ref) => ref.watch(audioHandlerProvider).errors,
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
    final items = songs.map(toMediaItem).toList(growable: false);
    // FIX (#17): tapping a song keeps the user's shuffle preference.
    // FIX (UI desync): the shuffled case now goes through loadShuffled —
    // a SINGLE queue rebuild — instead of loadQueue + setShuffleMode (two
    // full source swaps racing each other, with the second always landing
    // on index 0 where currentIndexStream stays silent and the UI kept
    // showing the previous song).
    if (_handler.shuffleEnabled) {
      await _handler.loadShuffled(items, currentIndex: index);
    } else {
      await _handler.loadQueue(items, startIndex: index);
    }
  }

  Future<void> shuffleAll(List<Song> songs) async {
    if (songs.isEmpty) return;
    final items = songs.map(toMediaItem).toList(growable: false);
    // FIX (UI desync): one rebuild with a random starting track, instead
    // of loadQueue(shuffled) + setShuffleMode (which reshuffled AND
    // rebuilt a second time). The shuffle toggle still lights up because
    // loadShuffled sets the handler's shuffle flag before broadcasting.
    await _handler.loadShuffled(
      items,
      currentIndex: Random().nextInt(items.length),
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
