import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../core/widgets/artwork.dart';
import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/song_tile.dart';

/// In-memory search across the whole library — instant even on huge
/// libraries since everything is already loaded.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songs = ref.watch(songsProvider).valueOrNull ?? const <Song>[];
    final albums = ref.watch(albumsProvider).valueOrNull ?? const <Album>[];
    final artists =
        ref.watch(artistsProvider).valueOrNull ?? const <Artist>[];

    final q = _query;
    final songHits = q.isEmpty
        ? const <Song>[]
        : songs
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q))
            .take(30)
            .toList(growable: false);
    final albumHits = q.isEmpty
        ? const <Album>[]
        : albums
            .where((a) =>
                a.title.toLowerCase().contains(q) ||
                a.artist.toLowerCase().contains(q))
            .take(10)
            .toList(growable: false);
    final artistHits = q.isEmpty
        ? const <Artist>[]
        : artists
            .where((a) => a.name.toLowerCase().contains(q))
            .take(10)
            .toList(growable: false);

    final empty =
        q.isNotEmpty && songHits.isEmpty && albumHits.isEmpty && artistHits.isEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search songs, albums, artists',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: q.isEmpty
          ? Center(
              child: Text('Type to search your library',
                  style: theme.textTheme.bodySmall),
            )
          : empty
              ? Center(
                  child: Text('No results for "$q"',
                      style: theme.textTheme.bodySmall),
                )
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (songHits.isNotEmpty) ...[
                      _Header('Songs'),
                      for (var i = 0; i < songHits.length; i++)
                        SongTile(
                          song: songHits[i],
                          contextSongs: songHits,
                          index: i,
                        ),
                    ],
                    if (albumHits.isNotEmpty) ...[
                      _Header('Albums'),
                      for (final album in albumHits)
                        ListTile(
                          onTap: () => context.go('/album/${album.id}'),
                          leading: Artwork(
                            id: album.id,
                            type: ArtworkType.ALBUM,
                            fallbackText: album.title,
                            size: 48,
                            radius: 10,
                            queryScale: 200,
                          ),
                          title: Text(album.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(album.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium),
                        ),
                    ],
                    if (artistHits.isNotEmpty) ...[
                      _Header('Artists'),
                      for (final artist in artistHits)
                        ListTile(
                          onTap: () => context.go('/artist/${artist.id}'),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                theme.colorScheme.primary.withOpacity(.14),
                            child: Text(
                              artist.name.isEmpty
                                  ? '?'
                                  : artist.name[0].toUpperCase(),
                              style: theme.textTheme.titleMedium!.copyWith(
                                  color: theme.colorScheme.primary),
                            ),
                          ),
                          title: Text(artist.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${artist.trackCount} songs',
                              style: theme.textTheme.labelMedium),
                        ),
                    ],
                  ],
                ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
