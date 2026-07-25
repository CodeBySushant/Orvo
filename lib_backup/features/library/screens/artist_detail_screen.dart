import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/providers/player_providers.dart';
import '../providers/library_providers.dart';
import '../widgets/song_tile.dart';

class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.artistId});
  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final artist = ref.watch(artistByIdProvider(artistId));
    final songsAsync = ref.watch(artistSongsProvider(artistId));

    return Scaffold(
      appBar: AppBar(title: Text(artist?.name ?? 'Artist')),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load artist')),
        data: (songs) => ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Row(
                children: [
                  Text('${songs.length} songs',
                      style: theme.textTheme.labelMedium),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: songs.isEmpty
                        ? null
                        : () => ref
                            .read(playerControllerProvider)
                            .shuffleAll(songs),
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < songs.length; i++)
              SongTile(song: songs[i], contextSongs: songs, index: i),
          ],
        ),
      ),
    );
  }
}
