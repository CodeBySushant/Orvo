import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_providers.dart';

/// Bottom sheet showing the play queue: drag to reorder, swipe to remove,
/// tap to jump. Playback continues seamlessly through edits.
///
/// REDESIGN: frosted-glass overlay instead of a solid white/card sheet —
/// transparent blurred background so the Now Playing screen glows through,
/// white typography, and a shorter height (62%) so it sits lower and feels
/// lighter.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      barrierColor: Colors.black.withOpacity(.3),
      builder: (context) => const FractionallySizedBox(
        heightFactor: .62,
        child: QueueSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queue = ref.watch(queueProvider).valueOrNull ?? const <MediaItem>[];
    final currentIndex = ref.watch(queueIndexProvider);
    final handler = ref.read(audioHandlerProvider);
    final accent = theme.colorScheme.primary;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          color: Colors.black.withOpacity(.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag pill
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 2),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Up next',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.3,
                        )),
                    Text('${queue.length} tracks',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.55),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
              Expanded(
                child: queue.isEmpty
                    ? Center(
                        child: Text('Queue is empty',
                            style: TextStyle(
                                color: Colors.white.withOpacity(.55),
                                fontSize: 13)),
                      )
                    : ReorderableListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 20),
                        proxyDecorator: (child, index, animation) =>
                            Material(
                          color: Colors.white.withOpacity(.08),
                          borderRadius: BorderRadius.circular(14),
                          child: child,
                        ),
                        itemCount: queue.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex -= 1;
                          if (oldIndex == newIndex) return;
                          handler.moveQueueItem(oldIndex, newIndex);
                        },
                        itemBuilder: (context, i) {
                          final item = queue[i];
                          final isCurrent = i == currentIndex;
                          return Dismissible(
                            key: ValueKey('queue-${item.id}-$i'),
                            direction: isCurrent
                                ? DismissDirection.none
                                : DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              color: accent.withOpacity(.2),
                              child: Icon(Icons.delete_outline_rounded,
                                  color: accent),
                            ),
                            onDismissed: (_) =>
                                handler.removeQueueItemAt(i),
                            child: ListTile(
                              onTap: () => handler.skipToQueueItem(i),
                              dense: true,
                              visualDensity:
                                  const VisualDensity(vertical: -1),
                              leading: SizedBox(
                                width: 30,
                                child: Center(
                                  child: isCurrent
                                      ? Icon(Icons.graphic_eq_rounded,
                                          size: 18, color: accent)
                                      : Text('${i + 1}',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withOpacity(.45),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          )),
                                ),
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      isCurrent ? accent : Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.5),
                                  fontSize: 12,
                                ),
                              ),
                              trailing: ReorderableDragStartListener(
                                index: i,
                                child: Icon(Icons.drag_handle_rounded,
                                    color: Colors.white.withOpacity(.35)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
