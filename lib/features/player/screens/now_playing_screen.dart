import 'dart:typed_data';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork.dart';
import '../../favorites/favorites_provider.dart';
import '../../lyrics/lyrics_sheet.dart';
import '../providers/player_providers.dart';
import '../providers/sleep_timer.dart';
import '../widgets/audio_options_sheet.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/seek_bar.dart';

/// Full-screen player. Always dark-styled for immersion: blurred artwork +
/// palette gradient background, swipeable artwork synced to the queue,
/// double-tap to favorite, drag down to dismiss.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  PageController? _pageController;
  bool _syncingPage = false;

  late final AnimationController _heartController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _heartController.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _onArtworkDoubleTap(int? songId) {
    if (songId == null) return;
    final favorites = ref.read(favoritesProvider.notifier);
    if (!favorites.isFavorite(songId)) {
      favorites.toggle(songId);
    }
    _heartController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentMediaItemProvider).valueOrNull;
    final queue = ref.watch(queueProvider).valueOrNull ?? const <MediaItem>[];
    final queueIndex = ref.watch(queueIndexProvider) ?? 0;
    final songId = item?.extras?['songId'] as int?;

    final palette = songId == null
        ? NowPlayingPalette.fallback
        : ref.watch(paletteProvider(songId)).valueOrNull ??
            NowPlayingPalette.fallback;

    _pageController ??= PageController(initialPage: queueIndex);

    // Keep the artwork pager in sync when the track changes elsewhere
    // (notification buttons, song end, queue taps).
    ref.listen<int?>(queueIndexProvider, (prev, next) {
      final controller = _pageController;
      if (next == null || controller == null || !controller.hasClients) return;
      if (controller.page?.round() == next) return;
      _syncingPage = true;
      controller
          .animateToPage(
            next,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _syncingPage = false);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 500) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _BlurredBackground(songId: songId, palette: palette),
            SafeArea(
              child: item == null
                  ? const _NothingPlaying()
                  : Column(
                      children: [
                        _TopBar(
                          onCollapse: () => Navigator.of(context).pop(),
                          onQueue: () => QueueSheet.show(context),
                        ),
                        Expanded(
                          child: _ArtworkPager(
                            controller: _pageController!,
                            queue: queue,
                            heartController: _heartController,
                            onDoubleTap: () => _onArtworkDoubleTap(songId),
                            onPageChanged: (page) {
                              if (_syncingPage) return;
                              if (page != ref.read(queueIndexProvider)) {
                                ref
                                    .read(audioHandlerProvider)
                                    .skipToQueueItem(page);
                              }
                            },
                          ),
                        ),
                        _TitleRow(item: item, songId: songId,
                            accent: palette.accent),
                        const SizedBox(height: 10),
                        SeekBar(
                            accent: palette.accent,
                            onSurface: Colors.white),
                        const SizedBox(height: 14),
                        _Controls(accent: palette.accent),
                        const SizedBox(height: 10),
                        _FeatureRow(accent: palette.accent),
                        const SizedBox(height: 16),
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

class _BlurredBackground extends ConsumerWidget {
  const _BlurredBackground({required this.songId, required this.palette});
  final int? songId;
  final NowPlayingPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      color: palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (songId != null)
            FutureBuilder<Uint8List?>(
              future: ArtworkCache.instance
                  .load(songId!, ArtworkType.AUDIO, size: 200),
              builder: (context, snap) {
                final bytes = snap.data;
                if (bytes == null || bytes.isEmpty) {
                  return const SizedBox.shrink();
                }
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: ImageFiltered(
                    key: ValueKey(songId),
                    imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                    child: Opacity(
                      opacity: .55,
                      child: Image.memory(bytes,
                          fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                  ),
                );
              },
            ),
          // Legibility scrim, deepest at the controls.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(.25),
                  Colors.black.withOpacity(.45),
                  Colors.black.withOpacity(.72),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onCollapse, required this.onQueue});
  final VoidCallback onCollapse;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onCollapse,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 30),
          ),
          Text('NOW PLAYING',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
                color: Colors.white.withOpacity(.7),
              )),
          IconButton(
            onPressed: onQueue,
            icon: const Icon(Icons.queue_music_rounded,
                color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }
}

class _ArtworkPager extends StatelessWidget {
  const _ArtworkPager({
    required this.controller,
    required this.queue,
    required this.heartController,
    required this.onDoubleTap,
    required this.onPageChanged,
  });

  final PageController controller;
  final List<MediaItem> queue;
  final AnimationController heartController;
  final VoidCallback onDoubleTap;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        PageView.builder(
          controller: controller,
          onPageChanged: onPageChanged,
          physics: const BouncingScrollPhysics(),
          itemCount: queue.length,
          itemBuilder: (context, i) {
            final item = queue[i];
            return Center(
              child: GestureDetector(
                onDoubleTap: onDoubleTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.5),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Artwork(
                        id: item.extras?['songId'] as int? ?? -1,
                        type: ArtworkType.AUDIO,
                        fallbackText: item.title,
                        radius: 26,
                        queryScale: 800,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // Heart burst on double-tap.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: heartController,
            builder: (context, _) {
              final t = heartController.value;
              if (t == 0 || heartController.isCompleted) {
                return const SizedBox.shrink();
              }
              final scale = Curves.elasticOut.transform(t) * 1.1;
              final opacity =
                  t < .7 ? 1.0 : (1 - (t - .7) / .3).clamp(0.0, 1.0);
              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: const Icon(Icons.favorite_rounded,
                      size: 96, color: AppColors.garnetBright),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TitleRow extends ConsumerWidget {
  const _TitleRow({
    required this.item,
    required this.songId,
    required this.accent,
  });

  final MediaItem item;
  final int? songId;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite =
        songId != null && ref.watch(favoritesProvider).contains(songId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((item.artist ?? '').isNotEmpty) item.artist,
                    if ((item.album ?? '').isNotEmpty) item.album,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.65),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: songId == null
                ? null
                : () =>
                    ref.read(favoritesProvider.notifier).toggle(songId!),
            iconSize: 28,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey(isFavorite),
                color: isFavorite ? accent : Colors.white.withOpacity(.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final state = ref.watch(playbackStateProvider).valueOrNull;
    final playing = state?.playing ?? false;
    final repeatMode = state?.repeatMode ?? AudioServiceRepeatMode.none;
    final shuffleOn =
        (state?.shuffleMode ?? AudioServiceShuffleMode.none) !=
            AudioServiceShuffleMode.none;

    final inactive = Colors.white.withOpacity(.55);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => handler.setShuffleMode(shuffleOn
                ? AudioServiceShuffleMode.none
                : AudioServiceShuffleMode.all),
            iconSize: 22,
            icon: Icon(Icons.shuffle_rounded,
                color: shuffleOn ? accent : inactive),
          ),
          IconButton(
            onPressed: handler.skipToPrevious,
            iconSize: 40,
            icon: const Icon(Icons.skip_previous_rounded,
                color: Colors.white),
          ),
          GestureDetector(
            onTap: playing ? handler.pause : handler.play,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(.45),
                    blurRadius: 26,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: 40,
                  color: Colors.black.withOpacity(.85),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: handler.skipToNext,
            iconSize: 40,
            icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: () => handler.setRepeatMode(switch (repeatMode) {
              AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
              AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
              _ => AudioServiceRepeatMode.none,
            }),
            iconSize: 22,
            icon: Icon(
              repeatMode == AudioServiceRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: repeatMode == AudioServiceRepeatMode.none
                  ? inactive
                  : accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary actions under the transport controls: lyrics, speed,
/// sleep timer (accent-lit when active), and audio options.
class _FeatureRow extends ConsumerWidget {
  const _FeatureRow({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final inactive = Colors.white.withOpacity(.6);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Lyrics',
            onPressed: () => LyricsSheet.show(context),
            icon: Icon(Icons.lyrics_outlined, size: 22, color: inactive),
          ),
          IconButton(
            tooltip: 'Sleep timer',
            onPressed: () => AudioOptionsSheet.show(context),
            icon: Icon(
              Icons.bedtime_outlined,
              size: 22,
              color: timer.active ? accent : inactive,
            ),
          ),
          IconButton(
            tooltip: 'Audio options',
            onPressed: () => AudioOptionsSheet.show(context),
            icon: Icon(Icons.tune_rounded, size: 22, color: inactive),
          ),
        ],
      ),
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note_rounded,
              size: 48, color: Colors.white.withOpacity(.4)),
          const SizedBox(height: 12),
          Text('Nothing playing',
              style: TextStyle(
                  color: Colors.white.withOpacity(.7),
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Pick a song from your library',
              style: TextStyle(
                  color: Colors.white.withOpacity(.45), fontSize: 13)),
        ],
      ),
    );
  }
}
