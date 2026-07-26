import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/song_tile.dart';
import '../stats/play_stats.dart';

/// "See All" target for the Home shelves: full lists of Recently Played or
/// Recently Added songs.
class SongCollectionScreen extends ConsumerWidget {
  const SongCollectionScreen({super.key, required this.kind});

  /// 'recent' = recently played, 'added' = recently added.
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRecent = kind == 'recent';
    final title = isRecent ? 'Recently Played' : 'Recently Added';
    final songs = isRecent
        ? (ref.watch(recentlyPlayedProvider).valueOrNull ?? const <Song>[])
        : (ref.watch(songsProvider).valueOrNull ?? const <Song>[])
            .take(100)
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: songs.isEmpty
          ? Center(
              child: Text(
                isRecent
                    ? 'Nothing played yet — songs appear here\nafter 15 seconds of listening.'
                    : 'No songs found',
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
