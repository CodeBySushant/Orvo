import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../library/domain/entities.dart';
import '../library/providers/library_providers.dart';
import '../player/providers/player_providers.dart';

/// FEATURE (#15): launcher app shortcuts — long-press the Orvo icon to get
/// "Resume" and "Shuffle all". Registered once at startup and kept alive by
/// the app shell. Both actions also work from a cold start: the callback
/// fires after launch, and each action waits for the pieces it needs
/// (library scan / session restore) instead of assuming they're ready.
final appShortcutsProvider = Provider<void>((ref) {
  const quickActions = QuickActions();

  quickActions.initialize((type) async {
    switch (type) {
      case 'shuffle_all':
        final songs = await _songsWhenReady(ref);
        if (songs.isNotEmpty) {
          await ref.read(playerControllerProvider).shuffleAll(songs);
        }
      case 'resume':
        final handler = ref.read(audioHandlerProvider);
        // FIX (#5) restores the last session shortly after launch — give it
        // a moment before falling back to playing the whole library.
        for (var i = 0; i < 10 && handler.queue.value.isEmpty; i++) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        if (handler.queue.value.isNotEmpty) {
          await handler.play();
        } else {
          final songs = await _songsWhenReady(ref);
          if (songs.isNotEmpty) {
            await ref.read(playerControllerProvider).playFrom(songs, 0);
          }
        }
    }
  });

  quickActions.setShortcutItems(const [
    // Listed bottom-up in the launcher popup — Resume ends up on top.
    ShortcutItem(
      type: 'shuffle_all',
      localizedTitle: 'Shuffle all',
      icon: 'ic_shortcut_shuffle',
    ),
    ShortcutItem(
      type: 'resume',
      localizedTitle: 'Resume',
      icon: 'ic_shortcut_resume',
    ),
  ]);
});

/// On a cold start the library provider resolves to an empty list until the
/// permission gate flips [permissionGrantedProvider] — poll briefly so a
/// shortcut launch still lands on real data.
Future<List<Song>> _songsWhenReady(Ref ref) async {
  for (var i = 0; i < 16; i++) {
    final songs = await ref.read(songsProvider.future);
    if (songs.isNotEmpty) return songs;
    await Future.delayed(const Duration(milliseconds: 300));
  }
  return ref.read(songsProvider.future);
}
