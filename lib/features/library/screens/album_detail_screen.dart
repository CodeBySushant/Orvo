import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/artwork.dart';
import '../../player/providers/player_providers.dart';
import '../providers/library_providers.dart';
import '../widgets/song_tile.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.albumId});
  final int albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final album = ref.watch(albumByIdProvider(albumId));
    final songsAsync = ref.watch(albumSongsProvider(albumId));

    return Scaffold(
      appBar: AppBar(),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load album')),
        data: (songs) {
          final total = songs.fold<Duration>(
              Duration.zero, (sum, s) => sum + s.duration);
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Artwork(
                      id: albumId,
                      type: ArtworkType.ALBUM,
                      fallbackText: album?.title ?? 'Album',
                      size: 132,
                      radius: 20,
                      queryScale: 600,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(album?.title ?? 'Album',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          Text(album?.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 4),
                          Text(
                            '${songs.length} songs · ${Formatters.duration(total)}',
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => ref
                                .read(playerControllerProvider)
                                .playFrom(songs, 0),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => ref
                                .read(playerControllerProvider)
                                .shuffleAll(songs),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < songs.length; i++)
                SongTile(
                  song: songs[i],
                  contextSongs: songs,
                  index: i,
                  leadingNumber: songs[i].track != null
                      ? songs[i].track! % 1000 // strip disc prefix (1001 -> 1)
                      : i + 1,
                ),
            ],
          );
        },
      ),
    );
  }
}
