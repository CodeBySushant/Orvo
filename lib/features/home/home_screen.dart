import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import '../../core/widgets/artwork.dart';
import '../../core/widgets/pressable.dart';
import '../favorites/favorites_provider.dart';
import '../library/domain/entities.dart';
import '../library/providers/genre_providers.dart';
import '../library/providers/library_providers.dart';
import '../library/screens/genre_screens.dart' show genreIconFor;
import '../player/providers/player_providers.dart';
import '../playlists/data/playlist_repository.dart';
import '../playlists/providers/playlist_providers.dart';
import '../stats/play_stats.dart';

// ---------------------------------------------------------------------------
// Profile name (for the greeting header) — editable, persisted.
// ---------------------------------------------------------------------------

const _kUserNameKey = 'orvo.userName';

class UserNameNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.read(sharedPreferencesProvider).getString(_kUserNameKey) ?? '';

  void set(String name) {
    state = name.trim();
    ref.read(sharedPreferencesProvider).setString(_kUserNameKey, state);
  }
}

final userNameProvider =
    NotifierProvider<UserNameNotifier, String>(UserNameNotifier.new);

// ---------------------------------------------------------------------------
// Home — mockup layout: greeting header, Recently Played, Favorite
// Playlists, Recently Added, Browse by Genre.
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: songsAsync.when(
          loading: () => const _ScanningState(),
          error: (e, _) => _EmptyState(
            title: 'Something went wrong',
            body: 'The library scan failed. Pull to try again.',
            onRefresh: () => ref.invalidate(songsProvider),
          ),
          data: (songs) {
            if (songs.isEmpty) {
              return _EmptyState(
                title: 'No music yet',
                body:
                    'Add audio files to this device and Orvo will pick them up.',
                onRefresh: () => ref.invalidate(songsProvider),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(songsProvider);
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
    final songs = ref.watch(songsProvider).valueOrNull ?? const <Song>[];
    final recentlyPlayed =
        ref.watch(recentlyPlayedProvider).valueOrNull ?? const <Song>[];
    final playlists =
        ref.watch(playlistsProvider).valueOrNull ?? const <Playlist>[];
    final genres = ref.watch(genresProvider).valueOrNull ?? const <GenreInfo>[];

    // Recently Played always has content: fall back to newest songs until
    // real listening stats exist.
    final playedShelf =
        (recentlyPlayed.isNotEmpty ? recentlyPlayed : songs)
            .take(10)
            .toList(growable: false);
    final recentlyAdded = songs.take(10).toList(growable: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _Header(),
        _SectionTitle(
          'Recently Played',
          onSeeAll: () => context.push('/collection/recent'),
        ),
        _RecentlyPlayedRow(songs: playedShelf),
        const SizedBox(height: 20),
        _SectionTitle(
          'Favorite Playlists',
          onSeeAll: () => context.go('/library'),
        ),
        _PlaylistsRow(playlists: playlists),
        const SizedBox(height: 20),
        _SectionTitle(
          'Recently Added',
          onSeeAll: () => context.push('/collection/added'),
        ),
        _RecentlyAddedRow(songs: recentlyAdded),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle(
            'Browse by Genre',
            onSeeAll: () => context.push('/genres'),
          ),
          _GenreRow(genres: genres.take(8).toList(growable: false)),
        ],
      ].animate(interval: 40.ms).fadeIn(duration: 260.ms),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — avatar, time-based greeting + name, bell, gear
// ---------------------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header();

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: ref.read(userNameProvider));
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'How should Orvo greet you?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null) ref.read(userNameProvider.notifier).set(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(userNameProvider);
    final displayName = name.isEmpty ? 'Music Lover' : name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 18),
      child: Row(
        children: [
          // BUG FIX (#5 report): avatar circle removed — the greeting text
          // itself remains the tap target for editing the name.
          Expanded(
            child: GestureDetector(
              onTap: () => _editName(context, ref),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_greeting(), style: theme.textTheme.bodyMedium),
                  Text('$displayName 👋',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium!
                          .copyWith(fontSize: 22)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("You're all caught up")),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section title with "See All"
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.onSeeAll});
  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: theme.textTheme.titleLarge!.copyWith(fontSize: 21)),
          ),
          TextButton(
            onPressed: onSeeAll,
            child: const Text('See All'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recently Played — large art cards with play overlay
// ---------------------------------------------------------------------------

class _RecentlyPlayedRow extends ConsumerWidget {
  const _RecentlyPlayedRow({required this.songs});
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 224,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: songs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final song = songs[i];
          return Pressable(
            onTap: () =>
                ref.read(playerControllerProvider).playFrom(songs, i),
            child: Container(
              width: 150,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Artwork(
                        id: song.id,
                        type: ArtworkType.AUDIO,
                        fallbackText: song.title,
                        size: 150,
                        radius: 0,
                        queryScale: 300,
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.black, size: 24),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium),
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
// Favorite Playlists — gradient cards with note icon
// ---------------------------------------------------------------------------

class _PlaylistsRow extends ConsumerWidget {
  const _PlaylistsRow({required this.playlists});
  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (playlists.isEmpty) {
      // BUG FIX (#23): even with no playlists, Liked Songs stays reachable.
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SizedBox(height: 176, child: Row(children: [_LikedSongsCard()])),
          ),
          Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Pressable(
          onTap: () => context.go('/library'),
          child: Container(
            height: 96,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [AppColors.violetDeep, AppColors.violet],
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    color: Colors.white, size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Create your first playlist',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
          ),
        ],
      );
    }

    return SizedBox(
      height: 176,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        // BUG FIX (#23): hearted songs were invisible on Home — the "Liked
        // Songs" card now leads this shelf.
        itemCount: playlists.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          if (i == 0) return const _LikedSongsCard();
          final playlist = playlists[i - 1];
          final color = AppColors.tileColorFor(playlist.name);
          final color2 = AppColors
              .tileColors[(AppColors.tileColors.indexOf(color) + 3) %
                  AppColors.tileColors.length];
          return Pressable(
            onTap: () => context.go('/playlist/${playlist.id}'),
            child: Container(
              width: 150,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color2.withOpacity(.75)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.music_note_rounded,
                      color: Colors.white, size: 30),
                  const Spacer(),
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${playlist.songCount} Songs',
                      style: TextStyle(
                          color: Colors.white.withOpacity(.85),
                          fontSize: 12.5)),
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
// Recently Added — square artwork row
// ---------------------------------------------------------------------------

class _RecentlyAddedRow extends ConsumerWidget {
  const _RecentlyAddedRow({required this.songs});
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: songs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => Pressable(
          onTap: () =>
              ref.read(playerControllerProvider).playFrom(songs, i),
          child: Artwork(
            id: songs[i].id,
            type: ArtworkType.AUDIO,
            fallbackText: songs[i].title,
            size: 112,
            radius: 16,
            queryScale: 224,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Browse by Genre — colored square chips
// ---------------------------------------------------------------------------

class _GenreRow extends StatelessWidget {
  const _GenreRow({required this.genres});
  final List<GenreInfo> genres;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final genre = genres[i];
          final color = AppColors.tileColorFor(genre.name);
          return Pressable(
            onTap: () => context.push(
                '/genre/${genre.id}?name=${Uri.encodeComponent(genre.name)}'),
            child: Container(
              width: 100,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(.9), color.withOpacity(.55)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(.8), width: 1.6),
                    ),
                    child: Icon(genreIconFor(genre.name),
                        color: Colors.white, size: 18),
                  ),
                  const Spacer(),
                  Text(genre.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5)),
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

// ---------------------------------------------------------------------------
// BUG FIX (#23): "Liked Songs" card — hearted songs, finally visible on Home
// ---------------------------------------------------------------------------

class _LikedSongsCard extends ConsumerWidget {
  const _LikedSongsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(favoritesProvider).length;
    return Pressable(
      onTap: () => context.push('/collection/favorites'),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.violetBright, AppColors.violetDeep],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
            const Spacer(),
            const Text('Liked Songs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('$count Songs',
                style: TextStyle(
                    color: Colors.white.withOpacity(.85), fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
