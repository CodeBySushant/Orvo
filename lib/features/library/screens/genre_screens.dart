import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../player/providers/player_providers.dart';
import '../providers/genre_providers.dart';
import '../widgets/song_tile.dart';

const genreIcons = [
  Icons.graphic_eq_rounded,
  Icons.headphones_rounded,
  Icons.radio_rounded,
  Icons.album_rounded,
  Icons.piano_rounded,
  Icons.queue_music_rounded,
  Icons.mic_external_on_rounded,
  Icons.speaker_rounded,
];

IconData genreIconFor(String name) =>
    genreIcons[name.hashCode.abs() % genreIcons.length];

/// FEATURE (#10): all genres, as the colored tiles from the Home mockup.
class GenresScreen extends ConsumerWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(genresProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Genres')),
      body: genresAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load genres')),
        data: (genres) {
          if (genres.isEmpty) {
            return const Center(
                child: Text('No genre tags found in your music'));
          }
          return GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // BUG FIX: 1.9 left no headroom for Plus Jakarta Sans' taller
              // lines — the name + count block overflowed the tile.
              childAspectRatio: 1.62,
            ),
            itemCount: genres.length,
            itemBuilder: (context, i) {
              final genre = genres[i];
              final color = AppColors.tileColorFor(genre.name);
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.push(
                    '/genre/${genre.id}?name=${Uri.encodeComponent(genre.name)}'),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withOpacity(.85),
                        color.withOpacity(.45)
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(genreIconFor(genre.name),
                          color: Colors.white, size: 26),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(genre.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  height: 1.25)),
                          Text('${genre.songCount} songs',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(.85),
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// FEATURE (#10): songs of one genre with play / shuffle actions.
class GenreDetailScreen extends ConsumerWidget {
  const GenreDetailScreen({
    super.key,
    required this.genreId,
    required this.genreName,
  });

  final int genreId;
  final String genreName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final songsAsync = ref.watch(genreSongsProvider(genreId));
    return Scaffold(
      appBar: AppBar(title: Text(genreName)),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load songs')),
        data: (songs) {
          if (songs.isEmpty) {
            return const Center(child: Text('No songs in this genre'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Text('${songs.length} songs',
                        style: theme.textTheme.labelMedium),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(playerControllerProvider)
                          .playFrom(songs, 0),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Play'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(playerControllerProvider)
                          .shuffleAll(songs),
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: songs.length,
                  itemBuilder: (context, i) => SongTile(
                    song: songs[i],
                    contextSongs: songs,
                    index: i,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
