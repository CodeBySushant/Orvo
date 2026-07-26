import 'dart:typed_data';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork.dart';
import '../../favorites/favorites_provider.dart';
import '../../lyrics/lyrics_parser.dart';
import '../../lyrics/lyrics_provider.dart';
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
  // REDESIGN: horizontal swipe on the artwork now opens lyrics inline
  // (transparent, over the blurred background) instead of changing tracks.
  bool _showLyrics = false;

  late final AnimationController _heartController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _heartController.dispose();
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
    final songId = item?.extras?['songId'] as int?;

    final palette = songId == null
        ? NowPlayingPalette.fallback
        : ref.watch(paletteProvider(songId)).valueOrNull ??
            NowPlayingPalette.fallback;

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
                          // REDESIGN: swipe the artwork sideways to reveal
                          // lyrics inline (transparent over the blurred
                          // background); swipe again or tap ✕ to come back.
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _showLyrics
                                ? _InlineLyrics(
                                    key: const ValueKey('lyrics'),
                                    item: item,
                                    accent: palette.accent,
                                    onClose: () =>
                                        setState(() => _showLyrics = false),
                                  )
                                : _ArtworkView(
                                    key: const ValueKey('artwork'),
                                    item: item,
                                    heartController: _heartController,
                                    onDoubleTap: () =>
                                        _onArtworkDoubleTap(songId),
                                    onOpenLyrics: () =>
                                        setState(() => _showLyrics = true),
                                  ),
                          ),
                        ),
                        _TitleRow(item: item, songId: songId,
                            accent: palette.accent),
                        const SizedBox(height: 8),
                        SeekBar(
                            accent: palette.accent,
                            onSurface: Colors.white),
                        const SizedBox(height: 12),
                        _Controls(accent: palette.accent),
                        const SizedBox(height: 8),
                        _FeatureRow(accent: palette.accent),
                        // REDESIGN: extra breathing room lifts everything a
                        // touch above the Up Next handle / bottom edge.
                        const SizedBox(height: 26),
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

/// REDESIGN: single artwork card. Double-tap favorites (heart burst),
/// horizontal swipe opens the inline lyrics view. Track skipping stays on
/// the previous / next buttons.
class _ArtworkView extends StatelessWidget {
  const _ArtworkView({
    super.key,
    required this.item,
    required this.heartController,
    required this.onDoubleTap,
    required this.onOpenLyrics,
  });

  final MediaItem item;
  final AnimationController heartController;
  final VoidCallback onDoubleTap;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: GestureDetector(
            onDoubleTap: onDoubleTap,
            onHorizontalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0).abs() > 250) onOpenLyrics();
            },
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

/// REDESIGN: lyrics shown inline where the artwork was — fully transparent,
/// floating over the blurred background. Synced lyrics auto-scroll with the
/// active line in the accent color; tap a line to seek. Swipe sideways or
/// tap ✕ to return to the artwork.
class _InlineLyrics extends ConsumerStatefulWidget {
  const _InlineLyrics({
    super.key,
    required this.item,
    required this.accent,
    required this.onClose,
  });

  final MediaItem item;
  final Color accent;
  final VoidCallback onClose;

  @override
  ConsumerState<_InlineLyrics> createState() => _InlineLyricsState();
}

class _InlineLyricsState extends ConsumerState<_InlineLyrics> {
  static const _lineExtent = 46.0;
  final _controller = ScrollController();
  int _lastIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _indexFor(List<LyricLine> lines, Duration position) {
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _autoScroll(int index, double viewport) {
    if (!_controller.hasClients || index == _lastIndex) return;
    _lastIndex = index;
    final target = (index * _lineExtent) - viewport / 2 + _lineExtent / 2;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final request = LyricsRequest(
      songId: item.extras?['songId'] as int? ?? 0,
      path: item.extras?['path'] as String? ?? '',
      title: item.title,
      artist: item.artist,
      album: item.album,
      durationSec: item.duration?.inSeconds,
    );
    final lyricsAsync = ref.watch(lyricsProvider(request));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 250) widget.onClose();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 2, 14, 0),
            child: Row(
              children: [
                Text('LYRICS',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    )),
                const Spacer(),
                IconButton(
                  tooltip: 'Back to artwork',
                  onPressed: widget.onClose,
                  icon: Icon(Icons.close_rounded,
                      size: 22, color: Colors.white.withOpacity(.7)),
                ),
              ],
            ),
          ),
          Expanded(
            child: lyricsAsync.when(
              loading: () => Center(
                child: Icon(Icons.graphic_eq_rounded,
                        size: 34, color: Colors.white.withOpacity(.7))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fade(begin: .3, end: 1, duration: 600.ms),
              ),
              error: (e, _) => _inlineMessage('Could not read lyrics'),
              data: (result) {
                final lyrics = result.lyrics;
                if (lyrics.isEmpty) {
                  final onlineOn = ref.watch(onlineLyricsProvider);
                  return _inlineMessage(!onlineOn
                      ? 'No lyrics in this file.\nTurn on Online lyrics in Settings.'
                      : result.lookupFailed
                          ? "Couldn't reach the lyrics service.\nCheck your internet connection."
                          : 'No lyrics found for this track.');
                }
                if (lyrics.isSynced) return _synced(lyrics.synced);
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(30, 4, 30, 24),
                  child: Text(
                    lyrics.unsynced!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.9),
                      fontSize: 17,
                      height: 1.8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineMessage(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(.55),
                  fontSize: 13.5,
                  height: 1.5)),
        ),
      );

  Widget _synced(List<LyricLine> lines) {
    final position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final current = _indexFor(lines, position);

    return LayoutBuilder(builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _autoScroll(current, constraints.maxHeight));
      return ListView.builder(
        controller: _controller,
        physics: const BouncingScrollPhysics(),
        itemExtent: _lineExtent,
        padding: EdgeInsets.symmetric(
          vertical: constraints.maxHeight / 2 - _lineExtent / 2,
          horizontal: 30,
        ),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final active = i == current;
          final line = lines[i];
          return InkWell(
            onTap: () => ref.read(audioHandlerProvider).seek(line.time),
            borderRadius: BorderRadius.circular(10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  fontSize: active ? 19 : 15.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active
                      ? widget.accent
                      : Colors.white.withOpacity(.45),
                ),
                child: Text(
                  line.text.isEmpty ? '\u00b7 \u00b7 \u00b7' : line.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      );
    });
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
          const SizedBox(width: 4),
          // REDESIGN: equalizer lives beside the favorites heart.
          IconButton(
            tooltip: 'Equalizer',
            onPressed: () => context.push('/equalizer'),
            iconSize: 24,
            icon: Icon(Icons.equalizer_rounded,
                color: Colors.white.withOpacity(.75)),
          ),
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
            iconSize: 34,
            icon: const Icon(Icons.skip_previous_rounded,
                color: Colors.white),
          ),
          // REDESIGN: square play/pause with a true morphing icon animation
          // (triangle physically bends into the pause bars) + press squish.
          _PlayPauseButton(
            playing: playing,
            accent: accent,
            onTap: playing ? handler.pause : handler.play,
          ),
          IconButton(
            onPressed: handler.skipToNext,
            iconSize: 34,
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

/// Secondary actions under the transport controls: lyrics, the Up Next
/// queue handle (tap or swipe up), and audio options (accent-lit when the
/// sleep timer is running — the cue the removed moon icon used to carry).
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
          // REDESIGN: lyrics icon removed — swipe the artwork instead.
          const SizedBox(width: 48),
          // REDESIGN: "Up Next" handle — tap or swipe up to open the queue.
          _UpNextHandle(onOpen: () => QueueSheet.show(context)),
          IconButton(
            tooltip: 'Audio options',
            onPressed: () => AudioOptionsSheet.show(context),
            icon: Icon(
              Icons.tune_rounded,
              size: 22,
              color: timer.active ? accent : inactive,
            ),
          ),
        ],
      ),
    );
  }
}

/// REDESIGN: chevron + "UP NEXT" label that opens the queue sheet with all
/// upcoming songs. Responds to a tap AND an upward swipe, with a gentle
/// idle float on the chevron hinting that it pulls up.
class _UpNextHandle extends StatelessWidget {
  const _UpNextHandle({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withOpacity(.65);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -200) onOpen(); // swiped up
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_arrow_up_rounded, size: 22, color: color)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 2, end: -2, duration: 900.ms,
                    curve: Curves.easeInOut),
            Text(
              'UP NEXT',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
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

/// REDESIGN: the main transport button — a rounded SQUARE (not a circle)
/// with two layered animations:
///  1. AnimatedIcon(play_pause): Flutter's built-in morph — the play
///     triangle physically bends into the pause bars and back.
///  2. A quick scale "squish" on press for tactile feedback.
/// The corner radius also eases slightly (rounder while playing) so the
/// state change reads on the shape itself, not just the glyph.
///
/// Stays in sync with EXTERNAL play/pause too (notification, headset,
/// widget): the morph is driven by the playing flag from the handler, not
/// by the tap.
class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.accent,
    required this.onTap,
  });

  final bool playing;
  final Color accent;
  final Future<void> Function() onTap;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.playing ? 1 : 0, // 0 = play glyph, 1 = pause glyph
  );

  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      widget.playing ? _morph.forward() : _morph.reverse();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? .9 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            // Square with softly eased corners — a touch rounder while
            // playing so the whole button "breathes" with the state.
            borderRadius: BorderRadius.circular(widget.playing ? 22 : 17),
            color: widget.accent,
            boxShadow: [
              BoxShadow(
                color: widget.accent.withOpacity(.45),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Center(
            child: AnimatedIcon(
              icon: AnimatedIcons.play_pause,
              progress: _morph,
              size: 34,
              color: Colors.black.withOpacity(.85),
            ),
          ),
        ),
      ),
    );
  }
}
