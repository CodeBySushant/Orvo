import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/providers/player_providers.dart';
import '../providers/folder_providers.dart';
import '../widgets/song_tile.dart';

class FolderDetailScreen extends ConsumerWidget {
  const FolderDetailScreen({super.key, required this.folderPath});

  final String folderPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final songsAsync = ref.watch(folderSongsProvider(folderPath));
    final segments = folderPath
        .split(RegExp(r'[/\\]'))
        .where((s) => s.isNotEmpty)
        .toList();
    final name = segments.isEmpty ? 'Folder' : segments.last;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load folder')),
        data: (songs) => ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${songs.length} songs · $folderPath',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
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
