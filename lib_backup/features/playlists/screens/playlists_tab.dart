import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/playlist_providers.dart';
import '../widgets/add_to_playlist_sheet.dart' show promptPlaylistName;

/// "Playlists" tab inside the Library screen.
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await promptPlaylistName(context);
          if (name == null) return;
          await ref.read(playlistActionsProvider).create(name);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            const Center(child: Text('Could not load playlists')),
        data: (playlists) {
          if (playlists.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.queue_music_rounded,
                      size: 44,
                      color: theme.colorScheme.onSurface.withOpacity(.4)),
                  const SizedBox(height: 14),
                  Text('No playlists yet',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Create one, or long-press any song.',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: playlists.length,
            itemBuilder: (context, i) {
              final playlist = playlists[i];
              return ListTile(
                onTap: () => context.go('/playlist/${playlist.id}'),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.queue_music_rounded,
                      color: theme.colorScheme.primary),
                ),
                title: Text(playlist.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${playlist.songCount} songs',
                    style: theme.textTheme.labelMedium),
                trailing: const Icon(Icons.chevron_right_rounded),
              );
            },
          );
        },
      ),
    );
  }
}
