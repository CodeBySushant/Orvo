import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_providers.dart';

/// Bottom sheet showing the play queue: drag to reorder, swipe to remove,
/// tap to jump. Playback continues seamlessly through edits.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: .82,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Up next', style: theme.textTheme.titleLarge),
              Text('${queue.length} tracks',
                  style: theme.textTheme.labelMedium),
            ],
          ),
        ),
        Expanded(
          child: queue.isEmpty
              ? Center(
                  child: Text('Queue is empty',
                      style: theme.textTheme.bodySmall),
                )
              : ReorderableListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 20),
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
                        color: theme.colorScheme.primary.withOpacity(.15),
                        child: Icon(Icons.delete_outline_rounded,
                            color: theme.colorScheme.primary),
                      ),
                      onDismissed: (_) => handler.removeQueueItemAt(i),
                      child: ListTile(
                        onTap: () => handler.skipToQueueItem(i),
                        leading: SizedBox(
                          width: 30,
                          child: Center(
                            child: isCurrent
                                ? Icon(Icons.graphic_eq_rounded,
                                    size: 18,
                                    color: theme.colorScheme.primary)
                                : Text('${i + 1}',
                                    style: theme.textTheme.labelMedium),
                          ),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall!.copyWith(
                            color: isCurrent
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          item.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: Icon(Icons.drag_handle_rounded,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(.4)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
