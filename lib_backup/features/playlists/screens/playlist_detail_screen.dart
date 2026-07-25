import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../library/widgets/song_tile.dart';
import '../data/playlist_repository.dart';
import '../../player/providers/player_providers.dart';
import '../providers/playlist_providers.dart';
import '../widgets/add_to_playlist_sheet.dart' show promptPlaylistName;

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final songsAsync = ref.watch(playlistSongsProvider(playlistId));
    final playlists = ref.watch(playlistsProvider).valueOrNull ?? const [];
    Playlist? playlist;
    for (final p in playlists) {
      if (p.id == playlistId) {
        playlist = p;
        break;
      }
    }
    final actions = ref.read(playlistActionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'rename':
                  final name = await promptPlaylistName(context,
                      initial: playlist?.name);
                  if (name != null) await actions.rename(playlistId, name);
                case 'delete':
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete playlist?'),
                      content: Text(
                          '"${playlist?.name ?? ''}" will be removed. Your songs stay on the device.'),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await actions.delete(playlistId);
                    if (context.mounted) context.go('/library');
                  }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            const Center(child: Text('Could not load playlist')),
        data: (songs) {
          if (songs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'This playlist is empty.\nLong-press any song → Add to playlist.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            );
          }
          final total = songs.fold<Duration>(
              Duration.zero, (sum, s) => sum + s.duration);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Text(
                      '${songs.length} songs · ${Formatters.duration(total)}',
                      style: theme.textTheme.labelMedium,
                    ),
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
                child: ReorderableListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: songs.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    if (oldIndex == newIndex) return;
                    actions.reorder(playlistId, oldIndex, newIndex);
                  },
                  itemBuilder: (context, i) => Dismissible(
                    key: ValueKey('pl-$playlistId-${songs[i].id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: theme.colorScheme.primary.withOpacity(.15),
                      child: Icon(Icons.delete_outline_rounded,
                          color: theme.colorScheme.primary),
                    ),
                    onDismissed: (_) =>
                        actions.removeSong(playlistId, songs[i].id),
                    child: SongTile(
                      song: songs[i],
                      contextSongs: songs,
                      index: i,
                    ),
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
