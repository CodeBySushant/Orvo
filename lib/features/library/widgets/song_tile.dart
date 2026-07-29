import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/playing_indicator.dart';
import '../../favorites/favorites_provider.dart';
import '../../player/providers/player_providers.dart';
import '../../playlists/widgets/add_to_playlist_sheet.dart';
import '../../system/system_channel.dart';
import '../providers/library_providers.dart';
import '../domain/entities.dart';
import 'song_info_sheet.dart';

/// Standard song row. Pass the list it belongs to so tapping plays in context.
class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.contextSongs,
    required this.index,
    this.leadingNumber,
  });

  final Song song;
  final List<Song> contextSongs;
  final int index;
  final int? leadingNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCurrent = ref.watch(currentSongIdProvider) == song.id;
    // REDESIGN v3.6: equalizer bars animate only while actually playing.
    final isPlaying = isCurrent && ref.watch(isPlayingProvider);
    final isFavorite = ref.watch(favoritesProvider).contains(song.id);
    final accent = theme.colorScheme.primary;

    return ListTile(
      onTap: () =>
          ref.read(playerControllerProvider).playFrom(contextSongs, index),
      onLongPress: () => SongTile.showActions(context, ref, song),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: leadingNumber != null
          ? SizedBox(
              width: 42,
              child: Center(
                child: isCurrent
                    ? PlayingIndicator(
                        color: accent, size: 20, animating: isPlaying)
                    : Text('$leadingNumber',
                        style: theme.textTheme.labelMedium),
              ),
            )
          : Stack(
              alignment: Alignment.center,
              children: [
                Artwork(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  fallbackText: song.title,
                  size: 48,
                  radius: 10,
                  queryScale: 200,
                  // FIX: while this row is the current song, the equalizer
                  // bars are drawn on top — hide the placeholder's music
                  // note so two icons don't stack on art-less tracks.
                  showPlaceholderIcon: !isCurrent,
                ),
                if (isCurrent)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: PlayingIndicator(
                          color: accent, size: 22, animating: isPlaying),
                    ),
                  ),
              ],
            ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall!.copyWith(
          color: isCurrent ? accent : null,
        ),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFavorite)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.favorite_rounded, size: 15, color: accent),
            ),
          Text(Formatters.duration(song.duration),
              style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  /// Full song actions sheet — also opened from the Home tiles' ⋮ menu.
  static void showActions(BuildContext context, WidgetRef ref, Song song) {
    final theme = Theme.of(context);
    final isFavorite = ref.read(favoritesProvider).contains(song.id);
    final controller = ref.read(playerControllerProvider);

    showModalBottomSheet<void>(
      context: context,
      // BUG FIX: on smaller screens the action list is taller than the
      // sheet's default height budget ("BOTTOM OVERFLOWED BY 194 PIXELS").
      // Cap the sheet below full screen and let the content scroll.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * .86,
          ),
          child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                        Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Play next'),
              onTap: () {
                controller.playNext(song);
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Playing next')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_rounded),
              title: const Text('Add to queue'),
              onTap: () {
                controller.addToQueue(song);
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Added to queue')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add to playlist'),
              onTap: () {
                Navigator.pop(sheetContext);
                AddToPlaylistSheet.show(context, song.id);
              },
            ),
            ListTile(
              leading: Icon(isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              title: Text(isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites'),
              onTap: () {
                ref.read(favoritesProvider.notifier).toggle(song.id);
                Navigator.pop(sheetContext);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Song info'),
              onTap: () {
                Navigator.pop(sheetContext);
                SongInfoSheet.show(context, song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(sheetContext);
                SystemChannel.shareSong(song.uri, song.title);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Set as ringtone'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final result = await SystemChannel.setRingtone(song.uri);
                if (!context.mounted) return;
                switch (result) {
                  case RingtoneResult.ok:
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('"${song.title}" set as ringtone')),
                    );
                  case RingtoneResult.needsPermission:
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                            'Orvo needs the "Modify system settings" permission'),
                        action: SnackBarAction(
                          label: 'Open',
                          onPressed: SystemChannel.openWriteSettings,
                        ),
                      ),
                    );
                  case RingtoneResult.failed:
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Could not set ringtone')),
                    );
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: theme.colorScheme.primary),
              title: Text('Delete from device',
                  style:
                      TextStyle(color: theme.colorScheme.primary)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Delete this song?'),
                    content: Text(
                        '"${song.title}" will be permanently removed from this device.'),
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
                if (confirmed != true) return;
                final ok = await SystemChannel.deleteSong(song.uri);
                if (!context.mounted) return;
                if (ok) {
                  ref.invalidate(rawSongsProvider);
                  ref.invalidate(albumsProvider);
                  ref.invalidate(artistsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Song deleted')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Delete was cancelled or failed')),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
            ),
          ),
        ),
      ),
    );
  }
}
