import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../core/i18n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/pressable.dart';
import '../library/domain/entities.dart';
import '../library/providers/genre_providers.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/song_tile.dart' show SongTile;
import '../player/providers/player_providers.dart';
import '../playlists/data/playlist_repository.dart';
import '../playlists/providers/playlist_providers.dart';
import '../playlists/widgets/add_to_playlist_sheet.dart'
    show promptPlaylistName;
import '../stats/play_stats.dart';
import 'home_drawer.dart';

// ---------------------------------------------------------------------------
// REDESIGN v3 — mockup home.
//
// Structure (top → bottom), exactly as the reference:
//   1. Top bar        — menu (⋯ lines + red dot) ....... search
//   2. Hero cards     — [ Favorites ] [ Shuffle ]
//   3. Recently Played  ›   (vertical song tiles, ⋮ actions)
//   4. My Playlist          (horizontal: “+” card, then playlists)
//   5. Last Added       ›   (vertical song tiles)
//   6. Most Played      ›   (vertical song tiles)
//   7. Recommend Artists ›  (initial-avatar rows)
//   8. Recommend Albums  ›  (large horizontal art cards)
//
// The greeting header is gone; the crown/premium action and the mockup's
// bottom navbar are intentionally not replicated.
// ---------------------------------------------------------------------------

// Mockup palette accents (local to Home — global theme is untouched).
const _kMagenta = Color(0xFFFF2D78); // bright pink (icons / “+”)
const _kMagentaCardA = Color(0xFF8E1553); // Favorites card gradient
const _kMagentaCardB = Color(0xFF5C0F3B);
const _kVioletIcon = Color(0xFF8B5CF6); // shuffle glyph
const _kVioletCardA = Color(0xFF3B2F86); // Shuffle card gradient
const _kVioletCardB = Color(0xFF251C56);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      drawer: const HomeDrawer(),
      body: SafeArea(
        bottom: false,
        child: songsAsync.when(
          loading: () => const _ScanningState(),
          error: (e, _) => _EmptyState(
            title: 'Something went wrong',
            body: 'The library scan failed. Pull to try again.',
            onRefresh: () => ref.invalidate(rawSongsProvider),
          ),
          data: (songs) {
            if (songs.isEmpty) {
              return _EmptyState(
                title: 'No music yet',
                body:
                    'Add audio files to this device and Orvo will pick them up.',
                onRefresh: () => ref.invalidate(rawSongsProvider),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(rawSongsProvider);
                ref.invalidate(albumsProvider);
                ref.invalidate(artistsProvider);
                ref.invalidate(genresProvider);
              },
              child: const _HomeBody(),
            );
          },
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(l10nProvider);
    final songs = ref.watch(songsProvider).valueOrNull ?? const <Song>[];
    final recentlyPlayed =
        ref.watch(recentlyPlayedProvider).valueOrNull ?? const <Song>[];
    final mostPlayed =
        ref.watch(mostPlayedProvider).valueOrNull ?? const <Song>[];
    final playlists =
        ref.watch(playlistsProvider).valueOrNull ?? const <Playlist>[];
    final artists =
        ref.watch(artistsProvider).valueOrNull ?? const <Artist>[];
    final albums = ref.watch(albumsProvider).valueOrNull ?? const <Album>[];

    // Shelves always have content: fall back to the newest songs until real
    // listening stats exist (same behaviour as the previous design).
    final playedShelf = (recentlyPlayed.isNotEmpty ? recentlyPlayed : songs)
        .take(3)
        .toList(growable: false);
    final lastAdded = songs.take(3).toList(growable: false);
    final mostShelf = (mostPlayed.isNotEmpty ? mostPlayed : songs)
        .take(3)
        .toList(growable: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _TopBar(),
        const SizedBox(height: 10),
        const _HeroCards(),
        const SizedBox(height: 8),

        // 3 — Recently Played
        _SectionHeader(
          t.recentlyPlayed,
          onSeeAll: () => context.push('/collection/recent'),
        ),
        for (var i = 0; i < playedShelf.length; i++)
          _HomeSongTile(song: playedShelf[i], contextSongs: playedShelf, index: i),
        const SizedBox(height: 14),

        // 4 — My Playlist
        _SectionHeader(t.myPlaylist),
        _MyPlaylistRow(playlists: playlists),
        const SizedBox(height: 18),

        // 5 — Last Added
        _SectionHeader(
          t.lastAdded,
          onSeeAll: () => context.push('/collection/added'),
        ),
        for (var i = 0; i < lastAdded.length; i++)
          _HomeSongTile(song: lastAdded[i], contextSongs: lastAdded, index: i),
        const SizedBox(height: 14),

        // 6 — Most Played
        _SectionHeader(
          t.mostPlayed,
          onSeeAll: () => context.push('/collection/most'),
        ),
        for (var i = 0; i < mostShelf.length; i++)
          _HomeSongTile(song: mostShelf[i], contextSongs: mostShelf, index: i),

        // 7 — Recommend Artists
        if (artists.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionHeader(
            t.recommendArtists,
            onSeeAll: () => context.go('/library'),
          ),
          for (final artist in artists.take(4)) _ArtistTile(artist: artist),
        ],

        // 8 — Recommend Albums
        if (albums.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionHeader(
            t.recommendAlbums,
            onSeeAll: () => context.go('/library'),
          ),
          _AlbumsRow(albums: albums.take(8).toList(growable: false)),
        ],
      ].animate(interval: 40.ms).fadeIn(duration: 260.ms),
    );
  }
}

// ---------------------------------------------------------------------------
// 1 — Top bar: menu glyph (three lines + red dot) and search
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
      child: Row(
        children: [
          // Opens the mockup-style sidebar (HomeDrawer).
          Builder(
            builder: (context) => Pressable(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: _MenuGlyph(color: onSurface),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded, size: 27),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
    );
  }
}

/// The mockup's staggered three-line menu icon with a red status dot.
class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget line(double width) => Container(
          width: width,
          height: 2.6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line(22),
                const SizedBox(height: 4.5),
                line(13),
                const SizedBox(height: 4.5),
                line(18),
              ],
            ),
          ),
          const Positioned(
            top: 6,
            right: 4,
            child: CircleAvatar(radius: 3.5, backgroundColor: _kMagenta),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2 — Hero cards: Favorites + Shuffle
// ---------------------------------------------------------------------------

class _HeroCards extends ConsumerWidget {
  const _HeroCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(l10nProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _HeroCard(
              label: t.favorites,
              icon: Icons.favorite_rounded,
              iconColor: _kMagenta,
              gradient: const [_kMagentaCardA, _kMagentaCardB],
              watermark: Icons.favorite_rounded,
              onTap: () => context.push('/collection/favorites'),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _HeroCard(
              label: t.shuffle,
              icon: Icons.shuffle_rounded,
              iconColor: _kVioletIcon,
              gradient: const [_kVioletCardA, _kVioletCardB],
              watermark: Icons.arrow_outward_rounded,
              onTap: () {
                final songs =
                    ref.read(songsProvider).valueOrNull ?? const <Song>[];
                if (songs.isEmpty) return;
                ref.read(playerControllerProvider).shuffleAll(songs);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.gradient,
    required this.watermark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final List<Color> gradient;
  final IconData watermark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 100,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
        ),
        child: Stack(
          children: [
            // Oversized faint glyph bleeding off the corner (mockup detail).
            Positioned(
              right: -18,
              bottom: -22,
              child: Icon(watermark,
                  size: 96, color: Colors.white.withOpacity(.10)),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor, size: 30),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header — title + chevron (mockup uses “›”, not “See All”)
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge!
                  .copyWith(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (onSeeAll != null)
            IconButton(
              tooltip: 'See all',
              onPressed: onSeeAll,
              icon: const Icon(Icons.chevron_right_rounded, size: 28),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vertical song tile — artwork · title · “artist - album” · ⋮
// ---------------------------------------------------------------------------

class _HomeSongTile extends ConsumerWidget {
  const _HomeSongTile({
    required this.song,
    required this.contextSongs,
    required this.index,
  });

  final Song song;
  final List<Song> contextSongs;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCurrent = ref.watch(currentSongIdProvider) == song.id;
    final accent = theme.colorScheme.primary;

    return Pressable(
      onTap: () =>
          ref.read(playerControllerProvider).playFrom(contextSongs, index),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 7, 8, 7),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Artwork(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  fallbackText: song.title,
                  size: 58,
                  radius: 15,
                  queryScale: 200,
                ),
                if (isCurrent)
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child:
                        Icon(Icons.graphic_eq_rounded, color: accent, size: 24),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall!.copyWith(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? accent : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${song.artist} - ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded, size: 22),
              onPressed: () => SongTile.showActions(context, ref, song),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4 — My Playlist: leading “+” card, then existing playlists
// ---------------------------------------------------------------------------

class _MyPlaylistRow extends ConsumerWidget {
  const _MyPlaylistRow({required this.playlists});
  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: playlists.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          if (i == 0) {
            // “+” create card — magenta block, exactly like the mockup.
            return Pressable(
              onTap: () async {
                final name = await promptPlaylistName(context);
                if (name == null) return;
                final id =
                    await ref.read(playlistActionsProvider).create(name);
                if (context.mounted) context.go('/playlist/$id');
              },
              child: Container(
                width: 116,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kMagentaCardA, _kMagentaCardB],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.add_rounded, color: _kMagenta, size: 44),
                ),
              ),
            );
          }
          final playlist = playlists[i - 1];
          final color = AppColors.tileColorFor(playlist.name);
          return Pressable(
            onTap: () => context.go('/playlist/${playlist.id}'),
            child: Container(
              width: 116,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(.9), color.withOpacity(.55)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.music_note_rounded,
                      color: Colors.white, size: 24),
                  const Spacer(),
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    ref.watch(l10nProvider).nSongsExact(playlist.songCount),
                    style: TextStyle(
                        color: Colors.white.withOpacity(.85), fontSize: 11.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7 — Recommend Artists: colored-initial avatar rows
// ---------------------------------------------------------------------------

class _ArtistTile extends ConsumerWidget {
  const _ArtistTile({required this.artist});
  final Artist artist;

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Play all'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final songs =
                    await ref.read(artistSongsProvider(artist.id).future);
                if (songs.isEmpty) return;
                ref.read(playerControllerProvider).playFrom(songs, 0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle_rounded),
              title: const Text('Shuffle'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final songs =
                    await ref.read(artistSongsProvider(artist.id).future);
                if (songs.isEmpty) return;
                ref.read(playerControllerProvider).shuffleAll(songs);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: const Text('Go to artist'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/artist/${artist.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);
    final color = AppColors.tileColorFor(artist.name);
    final initial =
        artist.name.isEmpty ? '?' : artist.name.characters.first.toUpperCase();

    return Pressable(
      onTap: () => context.push('/artist/${artist.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 7, 8, 7),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHigh.withOpacity(.7),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall!.copyWith(
                        fontSize: 16.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(t.nSongsExact(artist.trackCount),
                      style: theme.textTheme.labelMedium),
                ],
              ),
            ),
            IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded, size: 22),
              onPressed: () => _showActions(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8 — Recommend Albums: large horizontal art cards
// ---------------------------------------------------------------------------

class _AlbumsRow extends StatelessWidget {
  const _AlbumsRow({required this.albums});
  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final album = albums[i];
          return Pressable(
            onTap: () => context.push('/album/${album.id}'),
            child: Artwork(
              id: album.id,
              type: ArtworkType.ALBUM,
              fallbackText: album.title,
              size: 172,
              radius: 26,
              queryScale: 344,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading / empty states (with pull-to-refresh rescan)
// ---------------------------------------------------------------------------

class _ScanningState extends StatelessWidget {
  const _ScanningState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text('Scanning your music…', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.body,
    required this.onRefresh,
  });

  final String title;
  final String body;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * .28),
          Icon(Icons.library_music_outlined,
              size: 52,
              color: theme.colorScheme.onSurface.withOpacity(.3)),
          const SizedBox(height: 16),
          Center(child: Text(title, style: theme.textTheme.titleLarge)),
          const SizedBox(height: 8),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ),
          ),
          const SizedBox(height: 18),
          Center(
              child: OutlinedButton(
                  onPressed: onRefresh, child: const Text('Rescan'))),
        ],
      ),
    );
  }
}
