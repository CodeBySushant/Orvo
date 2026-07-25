import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/pressable.dart';
import '../favorites/favorites_provider.dart';
import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/album_card.dart';
import '../player/providers/player_providers.dart';
import '../stats/play_stats.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final songsAsync = ref.watch(songsProvider);
    final albums = ref.watch(albumsProvider).valueOrNull ?? const <Album>[];
    final favorites = ref.watch(favoriteSongsProvider);
    final recentlyPlayed =
        ref.watch(recentlyPlayedProvider).valueOrNull ?? const <Song>[];
    final mostPlayed =
        ref.watch(mostPlayedProvider).valueOrNull ?? const <Song>[];

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
            final recentlyAdded = songs.take(12).toList(growable: false);
            final totalDuration = songs.fold<Duration>(
                Duration.zero, (sum, s) => sum + s.duration);

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(songsProvider);
                ref.invalidate(albumsProvider);
                ref.invalidate(artistsProvider);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(Formatters.greeting(DateTime.now()),
                                style: theme.textTheme.labelMedium),
                            IconButton(
                              onPressed: () => context.push('/search'),
                              icon: const Icon(Icons.search_rounded),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Your sound,\nyour space.',
                            style: theme.textTheme.displayLarge),
                        const SizedBox(height: 6),
                        Text(
                          Formatters.libraryStats(
                              songs.length, totalDuration),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms).moveY(
                      begin: 14, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _QuickAction(
                            icon: Icons.shuffle_rounded,
                            label: 'Shuffle all',
                            filled: true,
                            onTap: () => ref
                                .read(playerControllerProvider)
                                .shuffleAll(songs),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickAction(
                            icon: Icons.history_rounded,
                            label: 'Latest first',
                            onTap: () => ref
                                .read(playerControllerProvider)
                                .playFrom(songs, 0),
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: 80.ms).fadeIn(duration: 400.ms).moveY(
                      begin: 14, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 28),
                  _Section(
                    title: 'Recently added',
                    child: SizedBox(
                      height: 208,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: recentlyAdded.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, i) => _RecentCard(
                          song: recentlyAdded[i],
                          onTap: () => ref
                              .read(playerControllerProvider)
                              .playFrom(recentlyAdded, i),
                        ),
                      ),
                    ),
                  ),
                  if (recentlyPlayed.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _Section(
                      title: 'Recently played',
                      child: SizedBox(
                        height: 208,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: recentlyPlayed.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, i) => _RecentCard(
                            song: recentlyPlayed[i],
                            onTap: () => ref
                                .read(playerControllerProvider)
                                .playFrom(recentlyPlayed, i),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (mostPlayed.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _Section(
                      title: 'On repeat',
                      child: SizedBox(
                        height: 168,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: mostPlayed.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, i) => _FavoriteCard(
                            song: mostPlayed[i],
                            onTap: () => ref
                                .read(playerControllerProvider)
                                .playFrom(mostPlayed, i),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (favorites.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _Section(
                      title: 'Favorites',
                      child: SizedBox(
                        height: 168,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: favorites.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, i) => _FavoriteCard(
                            song: favorites[i],
                            onTap: () => ref
                                .read(playerControllerProvider)
                                .playFrom(favorites, i),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (albums.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _Section(
                      title: 'Albums',
                      trailing: TextButton(
                        onPressed: () => context.go('/library'),
                        child: const Text('See all'),
                      ),
                      child: SizedBox(
                        height: 196,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: albums.length.clamp(0, 12),
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, i) =>
                              AlbumCard(album: albums[i], width: 140),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        filled ? Colors.white : theme.colorScheme.onSurface;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 8),
            Text(label,
                style: theme.textTheme.labelLarge!.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.song, required this.onTap});
  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(
              id: song.id,
              type: ArtworkType.AUDIO,
              fallbackText: song.title,
              size: 150,
              radius: 18,
            ),
            const SizedBox(height: 8),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.song, required this.onTap});
  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(
              id: song.id,
              type: ArtworkType.AUDIO,
              fallbackText: song.title,
              size: 118,
              radius: 16,
            ),
            const SizedBox(height: 8),
            Text(song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _ScanningState extends StatelessWidget {
  const _ScanningState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq_rounded,
                  size: 44, color: theme.colorScheme.primary)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                  begin: const Offset(.9, .9),
                  end: const Offset(1.05, 1.05),
                  duration: 700.ms,
                  curve: Curves.easeInOut),
          const SizedBox(height: 16),
          Text('Building your library…',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('This only takes a moment.',
              style: theme.textTheme.bodySmall),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off_rounded,
                size: 44,
                color: theme.colorScheme.onSurface.withOpacity(.4)),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            OutlinedButton(
                onPressed: onRefresh, child: const Text('Rescan')),
          ],
        ),
      ),
    );
  }
}
