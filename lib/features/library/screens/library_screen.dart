import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/alphabet_rail.dart';
import '../../player/providers/player_providers.dart';
import '../../playlists/screens/playlists_tab.dart';
import 'folders_tab.dart';
import '../domain/entities.dart';
import '../providers/library_providers.dart';
import '../widgets/album_card.dart';
import '../widgets/song_tile.dart';

/// FEATURE (#9): the sort button now adapts to the active tab — Songs,
/// Albums, and Artists each get their own sort options (previously only
/// Songs was sortable).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    // Rebuild the AppBar actions when the active tab changes.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget? _sortButton() {
    switch (_tabController.index) {
      case 0:
        return PopupMenuButton<SongSort>(
          icon: const Icon(Icons.sort_rounded),
          tooltip: 'Sort songs',
          onSelected: (sort) =>
              ref.read(songSortProvider.notifier).state = sort,
          itemBuilder: (context) => [
            for (final sort in SongSort.values)
              CheckedPopupMenuItem(
                value: sort,
                checked: ref.read(songSortProvider) == sort,
                child: Text(sort.label),
              ),
          ],
        );
      case 1:
        return PopupMenuButton<AlbumSort>(
          icon: const Icon(Icons.sort_rounded),
          tooltip: 'Sort albums',
          onSelected: (sort) =>
              ref.read(albumSortProvider.notifier).state = sort,
          itemBuilder: (context) => [
            for (final sort in AlbumSort.values)
              CheckedPopupMenuItem(
                value: sort,
                checked: ref.read(albumSortProvider) == sort,
                child: Text(sort.label),
              ),
          ],
        );
      case 2:
        return PopupMenuButton<ArtistSort>(
          icon: const Icon(Icons.sort_rounded),
          tooltip: 'Sort artists',
          onSelected: (sort) =>
              ref.read(artistSortProvider.notifier).state = sort,
          itemBuilder: (context) => [
            for (final sort in ArtistSort.values)
              CheckedPopupMenuItem(
                value: sort,
                checked: ref.read(artistSortProvider) == sort,
                child: Text(sort.label),
              ),
          ],
        );
      default:
        return null; // Playlists / Folders have their own natural order.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortButton = _sortButton();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search',
            onPressed: () => context.push('/search'),
          ),
          if (sortButton != null) sortButton,
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          labelStyle: Theme.of(context).textTheme.labelLarge,
          tabs: const [
            Tab(text: 'Songs'),
            Tab(text: 'Albums'),
            Tab(text: 'Artists'),
            Tab(text: 'Playlists'),
            Tab(text: 'Folders'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: const [
          _SongsTab(),
          _AlbumsTab(),
          _ArtistsTab(),
          PlaylistsTab(),
          FoldersTab(),
        ],
      ),
    );
  }
}

class _SongsTab extends ConsumerStatefulWidget {
  const _SongsTab();

  @override
  ConsumerState<_SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends ConsumerState<_SongsTab> {
  static const _rowExtent = 64.0;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpToLetter(String letter, List<Song> songs) {
    int index = 0;
    if (letter != '#') {
      index = songs.indexWhere((s) {
        final first = s.title.isEmpty ? '' : s.title[0].toUpperCase();
        return first.compareTo(letter) >= 0;
      });
      if (index == -1) index = songs.length - 1;
    }
    final offset = (index * _rowExtent).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(sortedSongsProvider);
    final sort = ref.watch(songSortProvider);
    final showRail = sort == SongSort.title;

    return songsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not load songs')),
      data: (songs) {
        if (songs.isEmpty) {
          return const Center(child: Text('No songs found'));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Text('${songs.length} songs',
                      style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  TextButton.icon(
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
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: songs.length,
                    itemExtent: _rowExtent,
                    padding:
                        EdgeInsets.only(right: showRail ? 24 : 0),
                    itemBuilder: (context, i) => SongTile(
                      song: songs[i],
                      contextSongs: songs,
                      index: i,
                    ),
                  ),
                  if (showRail)
                    Positioned(
                      right: 0,
                      top: 8,
                      bottom: 8,
                      child: AlphabetRail(
                        onLetter: (letter) =>
                            _jumpToLetter(letter, songs),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FEATURE (#9): respects the album sort selection.
    final albumsAsync = ref.watch(sortedAlbumsProvider);
    return albumsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not load albums')),
      data: (albums) {
        if (albums.isEmpty) {
          return const Center(child: Text('No albums found'));
        }
        return LayoutBuilder(builder: (context, constraints) {
          final columns = (constraints.maxWidth / 190).floor().clamp(2, 6);
          // BUG FIX: childAspectRatio sized cells as a pure width ratio, so
          // the taller Plus Jakarta Sans metrics overflowed the text block
          // by a few pixels ("BOTTOM OVERFLOWED"). Compute the exact height
          // instead: square artwork (= cell width) + a text block measured
          // through the system text scaler, so it also survives users'
          // accessibility font-size settings.
          const gridPadding = 32.0; // 16 left + 16 right
          const crossSpacing = 14.0;
          final cellWidth = (constraints.maxWidth -
                  gridPadding -
                  crossSpacing * (columns - 1)) /
              columns;
          final textBlock =
              MediaQuery.textScalerOf(context).scale(46) + 12;
          return GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 18,
              crossAxisSpacing: crossSpacing,
              mainAxisExtent: cellWidth + textBlock,
            ),
            itemCount: albums.length,
            itemBuilder: (context, i) => AlbumCard(album: albums[i]),
          );
        });
      },
    );
  }
}

class _ArtistsTab extends ConsumerWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FEATURE (#9): respects the artist sort selection.
    final artistsAsync = ref.watch(sortedArtistsProvider);
    final theme = Theme.of(context);
    return artistsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not load artists')),
      data: (artists) {
        if (artists.isEmpty) {
          return const Center(child: Text('No artists found'));
        }
        return Scrollbar(
          interactive: true,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            itemBuilder: (context, i) {
              final artist = artists[i];
              return ListTile(
                onTap: () => context.go('/artist/${artist.id}'),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      theme.colorScheme.primary.withOpacity(.14),
                  child: Text(
                    artist.name.isEmpty
                        ? '?'
                        : artist.name[0].toUpperCase(),
                    style: theme.textTheme.titleMedium!
                        .copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                title: Text(artist.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${artist.trackCount} songs · ${artist.albumCount} albums',
                  style: theme.textTheme.labelMedium,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              );
            },
          ),
        );
      },
    );
  }
}
