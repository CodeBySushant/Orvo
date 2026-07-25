import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../library/domain/entities.dart';
import '../../library/widgets/song_tile.dart';
import '../data/playlist_repository.dart';
import '../../player/providers/player_providers.dart';
import '../providers/playlist_providers.dart';
import '../widgets/add_to_playlist_sheet.dart' show promptPlaylistName;

/// FEATURE (#8): the playlist can now be filtered in place with the search
/// icon in the app bar. While a filter is active the list is a plain,
/// read-only view (no reorder / swipe-remove — those only make sense on the
/// full list).
///
/// Also fixes a latent issue from the duplicate-songs change (#15): list row
/// keys were based on song id alone, which produced duplicate keys — and a
/// crash — the moment the same song appeared twice. Keys now include an
/// occurrence counter.
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  String _filter = '';

  int get playlistId => widget.playlistId;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onFilterChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _filter = value.trim().toLowerCase());
    });
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _filter = '';
      }
    });
  }

  /// Unique, duplicate-safe keys: same song twice gets occurrence-numbered
  /// keys instead of colliding.
  List<Key> _rowKeys(List<Song> songs) {
    final seen = <int, int>{};
    return [
      for (final s in songs)
        ValueKey('pl-$playlistId-${s.id}-${seen[s.id] = (seen[s.id] ?? 0) + 1}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
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
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onFilterChanged,
                decoration: const InputDecoration(
                  hintText: 'Search in playlist',
                  border: InputBorder.none,
                ),
              )
            : Text(playlist?.name ?? 'Playlist'),
        actions: [
          IconButton(
            icon: Icon(
                _searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? 'Close search' : 'Search in playlist',
            onPressed: _toggleSearch,
          ),
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

          // FEATURE (#8): filtered read-only view while searching.
          if (_filter.isNotEmpty) {
            final hits = [
              for (final s in songs)
                if (s.title.toLowerCase().contains(_filter) ||
                    s.artist.toLowerCase().contains(_filter) ||
                    s.album.toLowerCase().contains(_filter))
                  s,
            ];
            if (hits.isEmpty) {
              return Center(
                child: Text('No matches in this playlist',
                    style: theme.textTheme.bodySmall),
              );
            }
            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: hits.length,
              itemBuilder: (context, i) => SongTile(
                song: hits[i],
                contextSongs: hits,
                index: i,
              ),
            );
          }

          final total = songs.fold<Duration>(
              Duration.zero, (sum, s) => sum + s.duration);
          final keys = _rowKeys(songs);
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
                    key: keys[i],
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
