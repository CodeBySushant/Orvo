import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playlist_providers.dart';

/// Bottom sheet to add a song to an existing playlist or a new one.
class AddToPlaylistSheet extends ConsumerWidget {
  const AddToPlaylistSheet({super.key, required this.songId});

  final int songId;

  static Future<void> show(BuildContext context, int songId) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => AddToPlaylistSheet(songId: songId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlists = ref.watch(playlistsProvider).valueOrNull ?? const [];
    final actions = ref.read(playlistActionsProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Text('Add to playlist', style: theme.textTheme.titleLarge),
          ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
            title: Text('New playlist',
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600)),
            onTap: () async {
              final name = await promptPlaylistName(context);
              if (name == null || name.isEmpty) return;
              final id = await actions.create(name);
              await actions.addSongs(id, [songId]);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added to "$name"')),
                );
              }
            },
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final playlist in playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(playlist.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${playlist.songCount} songs',
                        style: theme.textTheme.labelMedium),
                    onTap: () async {
                      await actions.addSongs(playlist.id, [songId]);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Added to "${playlist.name}"')),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Shared name dialog for create/rename.
Future<String?> promptPlaylistName(BuildContext context,
    {String? initial}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(initial == null ? 'New playlist' : 'Rename playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(initial == null ? 'Create' : 'Rename'),
        ),
      ],
    ),
  );
  return (result == null || result.isEmpty) ? null : result;
}
