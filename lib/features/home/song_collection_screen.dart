import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../favorites/favorites_provider.dart';
import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/song_tile.dart';
import '../stats/play_stats.dart';

/// "See All" target for the Home shelves: full lists of Recently Played,
/// Recently Added, or (BUG FIX #23) Favorite songs.
class SongCollectionScreen extends ConsumerWidget {
  const SongCollectionScreen({super.key, required this.kind});

  /// 'recent' = recently played, 'added' = recently added,
  /// 'favorites' = hearted songs.
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, songs, emptyText) = switch (kind) {
      'recent' => (
          'Recently Played',
          ref.watch(recentlyPlayedProvider).valueOrNull ?? const <Song>[],
          'Nothing played yet — songs appear here\nafter 15 seconds of listening.',
        ),
      // REDESIGN v3: "Most Played" shelf target.
      'most' => (
          'Most Played',
          ref.watch(mostPlayedProvider).valueOrNull ?? const <Song>[],
          'Nothing here yet — play counts build\nafter 15 seconds of listening.',
        ),
      'favorites' => (
          'Favorites',
          ref.watch(favoriteSongsProvider),
          'No favorites yet — tap the heart or\ndouble-tap the artwork on any song.',
        ),
      _ => (
          'Recently Added',
          (ref.watch(songsProvider).valueOrNull ?? const <Song>[])
              .take(100)
              .toList(growable: false),
          'No songs found',
        ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: songs.isEmpty
          ? Center(
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                song: songs[i],
                contextSongs: songs,
                index: i,
              ),
            ),
    );
  }
}
