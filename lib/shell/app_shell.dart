import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/equalizer/equalizer_provider.dart';
import '../features/player/widgets/mini_player.dart';
import '../features/player/data/playback_persistence.dart';
import '../features/player/providers/audio_settings.dart';
import '../features/player/providers/player_providers.dart';
import '../features/stats/play_stats.dart';
import '../features/widget/widget_updater.dart';

/// Bottom-navigation shell with the mini player docked above the nav bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  // REDESIGN: 4-tab navigation — Search promoted to the bottom bar
  // (mockup: Home · Search · Library · Settings).
  int get _index {
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/library') ||
        location.startsWith('/album') ||
        location.startsWith('/artist') ||
        location.startsWith('/playlist') ||
        location.startsWith('/folder') ||
        location.startsWith('/genre')) {
      return 2;
    }
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the play tracker alive for the whole app session.
    ref.watch(playTrackerProvider);
    // Push the persisted smooth-transitions setting into the audio handler.
    ref.watch(smoothTransitionsProvider);
    // FEATURE (crossfade v1): push the persisted crossfade length into the
    // audio handler so it applies from app start.
    ref.watch(crossfadeProvider);
    // Keep the home-screen widget in sync with playback.
    ref.watch(widgetUpdaterProvider);
    // FIX (#2): apply persisted EQ settings as soon as playback starts,
    // instead of waiting for the user to open the equalizer screen.
    ref.watch(equalizerAutoAttachProvider);
    // FIX (#16): purge stats / playlist rows / favorites for songs deleted
    // from the device, after each successful scan.
    ref.watch(libraryCleanupProvider);
    // FIX (#5): restore the last playback session (paused, exact position)
    // and keep persisting it as it evolves.
    ref.watch(playbackPersistenceProvider);
    // FIX (#6): surface playback errors (corrupt / missing files) that were
    // previously swallowed silently.
    ref.listen(playbackErrorProvider, (previous, next) {
      final message = next.valueOrNull;
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return Scaffold(
      body: child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => switch (i) {
              0 => context.go('/home'),
              1 => context.go('/search'),
              2 => context.go('/library'),
              _ => context.go('/settings'),
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                selectedIcon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
