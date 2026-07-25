import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show ArtworkType;

import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/pressable.dart';
import '../providers/player_providers.dart';

/// Always-visible dock above the navigation bar. Tap to expand, swipe up to
/// expand, controls inline.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              child: Pressable(
                onTap: () => context.push('/player'),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(bottom: Radius.circular(18)),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 2.5,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
