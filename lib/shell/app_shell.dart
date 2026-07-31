import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n/l10n.dart';
import '../features/equalizer/equalizer_provider.dart';
import '../features/home/home_drawer.dart';
import '../features/library/providers/exclusions_bootstrap.dart';
import '../features/metadata/online_artwork.dart';
import '../features/player/widgets/mini_player.dart';
import '../features/player/data/playback_persistence.dart';
import '../features/player/providers/audio_settings.dart';
import '../features/player/providers/notification_tap.dart';
import '../features/player/providers/player_providers.dart';
import '../features/shortcuts/app_shortcuts.dart';
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
    // FEATURE (#18): push the persisted Bluetooth auto-resume setting into
    // the audio handler so it applies from app start.
    ref.watch(btAutoResumeProvider);
    // FEATURE (#15): register the launcher app shortcuts and their handler.
    ref.watch(appShortcutsProvider);
    // FEATURE (#20): media-notification tap opens the Now Playing screen.
    ref.watch(notificationTapProvider);
    // FIX (#2): apply persisted EQ settings as soon as playback starts,
    // instead of waiting for the user to open the equalizer screen.
    ref.watch(equalizerAutoAttachProvider);
    // FEATURE (online artwork): install the missing-cover fallback and keep
    // its song catalog in sync with the library scan.
    ref.watch(onlineArtworkBinderProvider);
    // FEATURE (#25): apply first-run smart folder exclusions after the
    // first raw scan (WhatsApp audio, recordings, notifications…).
    ref.watch(exclusionDefaultsProvider);
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

    final t = ref.watch(l10nProvider);

    return Scaffold(
      // FIX (drawer height): the drawer used to live on HomeScreen's inner
      // Scaffold, which only spans the shell's BODY — the mini player and
      // navigation bar sit outside it in bottomNavigationBar, so the drawer
      // physically could not paint over that region and stopped short of
      // the bottom edge, leaving a broken-looking gap. Hosting it on the
      // shell's Scaffold makes it one continuous panel over the full
      // screen height (over the mini player and nav bar too). Same Drawer
      // widget, same styling — nothing visual changed.
      drawer: const HomeDrawer(),
      // Edge-swipe open stays a HOME-only gesture, exactly as before —
      // on Library it would fight the tab swipe, so it's off elsewhere
      // (the drawer there is unreachable anyway; only Home has the menu
      // button).
      drawerEnableOpenDragGesture: _index == 0,
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
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: t.home,
              ),
              NavigationDestination(
                icon: const Icon(Icons.search_rounded),
                selectedIcon: const Icon(Icons.search_rounded),
                label: t.search,
              ),
              NavigationDestination(
                icon: const Icon(Icons.library_music_outlined),
                selectedIcon: const Icon(Icons.library_music_rounded),
                label: t.library,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings_rounded),
                label: t.settings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
