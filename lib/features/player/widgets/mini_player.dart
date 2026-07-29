import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/pressable.dart';
import '../providers/player_providers.dart';

/// Always-visible dock above the navigation bar. Tap to expand, swipe up to
/// expand, controls inline.
///
/// FEATURE (mini player gestures): horizontal swipes change tracks —
/// swipe LEFT → next song, swipe RIGHT → previous song — calling the exact
/// same handler methods the Next / Previous buttons use. The card follows
/// the finger while dragging (a pure Transform.translate: paint-only, no
/// relayout, stays at 60fps), a track change fires only past a distance OR
/// fling-velocity threshold so accidental nudges do nothing, a light
/// haptic tick confirms the trigger, and the card springs back smoothly on
/// release. Tap-to-expand and swipe-up-to-expand are unchanged, and
/// vertical page scrolling is unaffected — the horizontal recognizer only
/// wins horizontal gestures in the gesture arena.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  /// Horizontal displacement needed to trigger a track change.
  static const double _actionThreshold = 64;

  /// A fling faster than this (logical px/s) triggers even from a short drag.
  static const double _flingVelocity = 700;

  /// The card never slides further than this while dragging.
  static const double _maxShift = 104;

  late final AnimationController _settle;
  Animation<double>? _settleAnim;
  double _dragX = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        final anim = _settleAnim;
        if (anim != null) setState(() => _dragX = anim.value);
      });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    // Grab the card even if it's mid spring-back.
    _settle.stop();
    _settleAnim = null;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragX = (_dragX + details.delta.dx)
          .clamp(-_maxShift, _maxShift)
          .toDouble();
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final byDistance = _dragX.abs() > _actionThreshold;
    final byFling = velocity.abs() > _flingVelocity;

    if (byDistance || byFling) {
      // Distance decides the direction when the threshold was crossed;
      // otherwise the fling direction does. Left = next, right = previous.
      final goNext = byDistance ? _dragX < 0 : velocity < 0;
      HapticFeedback.lightImpact();
      final handler = ref.read(audioHandlerProvider);
      if (goNext) {
        handler.skipToNext();
      } else {
        handler.skipToPrevious();
      }
    }
    _springBack();
  }

  void _springBack() {
    if (_dragX == 0) return;
    _settleAnim = Tween<double>(begin: _dragX, end: 0).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
    );
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentMediaItemProvider).valueOrNull;
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: item == null
          ? const SizedBox(width: double.infinity)
          : GestureDetector(
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -300) {
                  context.push('/player');
                }
              },
              // FEATURE (mini player gestures): swipe left/right to skip.
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: Transform.translate(
                offset: Offset(_dragX, 0),
                child: Pressable(
                  onTap: () => context.push('/player'),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    // FIX: decoration radius doesn't clip children — the
                    // progress strip ran straight through the rounded corners
                    // and visibly stuck out below the card. Clip to the shape.
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withOpacity(.06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
                          child: Row(
                            children: [
                              Artwork(
                                id: item.extras?['songId'] as int? ?? -1,
                                type: ArtworkType.AUDIO,
                                fallbackText: item.title,
                                size: 42,
                                radius: 10,
                                queryScale: 200,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall),
                                    const SizedBox(height: 2),
                                    Text(item.artist ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium),
                                  ],
                                ),
                              ),
                              const _PlayPauseButton(),
                              IconButton(
                                onPressed: () => ref
                                    .read(audioHandlerProvider)
                                    .skipToNext(),
                                icon: const Icon(Icons.skip_next_rounded),
                                iconSize: 26,
                              ),
                            ],
                          ),
                        ),
                        const _MiniProgress(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _PlayPauseButton extends ConsumerWidget {
  const _PlayPauseButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider);
    final handler = ref.read(audioHandlerProvider);
    return IconButton(
      onPressed: playing ? handler.pause : handler.play,
      iconSize: 28,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(playing),
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(currentMediaItemProvider).valueOrNull?.duration ??
            Duration.zero;
    final value = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    // The parent card clips to its rounded shape now, so the strip can be a
    // plain straight bar — the corners are handled by the card itself.
    return LinearProgressIndicator(
      value: value,
      minHeight: 2.5,
      backgroundColor: Colors.transparent,
    );
  }
}
