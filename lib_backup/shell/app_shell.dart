import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/player/widgets/mini_player.dart';
import '../features/player/providers/audio_settings.dart';
import '../features/stats/play_stats.dart';
import '../features/widget/widget_updater.dart';

/// Bottom-navigation shell with the mini player docked above the nav bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index {
    if (location.startsWith('/library') ||
        location.startsWith('/album') ||
        location.startsWith('/artist') ||
        location.startsWith('/playlist') ||
        location.startsWith('/folder')) {
      return 1;
    }
    if (location.startsWith('/settings')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the play tracker alive for the whole app session.
    ref.watch(playTrackerProvider);
    // Push the persisted smooth-transitions setting into the audio handler.
    ref.watch(smoothTransitionsProvider);
    // Keep the home-screen widget in sync with playback.
    ref.watch(widgetUpdaterProvider);

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
              1 => context.go('/library'),
              _ => context.go('/settings'),
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
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
