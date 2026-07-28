import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/l10n.dart';
import '../../core/utils/formatters.dart';
import '../library/providers/genre_providers.dart';
import '../library/providers/library_providers.dart';
import '../player/providers/sleep_timer.dart';

// ---------------------------------------------------------------------------
// REDESIGN v3.1 — mockup sidebar.
//
// Slide-in drawer on the midnight base: oversized app title, a faint
// music-note watermark bleeding off the top-right, then generously spaced
// icon + label rows. Only features Orvo actually has are listed:
//
//   Themes · Equalizer · Sleep Timer · Rescan Library ·
//   Excluded Folders · Settings
//
// (The mockup's Upgrade to Pro / Drive Mode / ad rows are intentionally
// not replicated.)
// ---------------------------------------------------------------------------

class HomeDrawer extends ConsumerWidget {
  const HomeDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);
    final timer = ref.watch(sleepTimerProvider);
    final onSurface = theme.colorScheme.onSurface;

    return Drawer(
      width: MediaQuery.of(context).size.width * .8,
      // FIX (backgrounds): scaffoldBackgroundColor goes transparent while a
      // wallpaper background is active, which made the open drawer
      // see-through (text merging with the screen behind). surface is the
      // exact same color in normal modes and always stays solid.
      backgroundColor: theme.colorScheme.surface,
      child: Stack(
        children: [
          // Watermark — giant faint note + thin circle outlines (mockup).
          Positioned(
            top: -26,
            right: -44,
            child: Icon(Icons.music_note_rounded,
                size: 230, color: onSurface.withOpacity(.045)),
          ),
          Positioned(
            top: 60,
            right: -20,
            child: _WatermarkRing(diameter: 210, color: onSurface),
          ),
          Positioned(
            top: 150,
            left: -60,
            child: _WatermarkRing(diameter: 150, color: onSurface),
          ),

          SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // Header — big bold app title.
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 42, 26, 44),
                  child: Text(
                    'Orvo',
                    style: theme.textTheme.headlineMedium!.copyWith(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                ),

                _DrawerItem(
                  icon: Icons.checkroom_outlined,
                  label: t.themes,
                  onTap: () {
                    Navigator.pop(context);
                    // FEATURE (#27): full skin themes hub (modes + skins).
                    context.push('/themes');
                  },
                ),
                _DrawerItem(
                  // Vertical-slider glyph, like the mockup's EQ icon.
                  iconWidget: RotatedBox(
                    quarterTurns: 1,
                    child: Icon(Icons.tune_rounded,
                        size: 25, color: onSurface.withOpacity(.92)),
                  ),
                  label: t.equalizer,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/equalizer');
                  },
                ),
                _DrawerItem(
                  icon: Icons.access_alarm_rounded,
                  label: t.sleepTimer,
                  trailing: timer.active
                      ? Text(
                          timer.endOfTrack
                              ? 'After this track'
                              : Formatters.duration(timer.remaining!),
                          style: theme.textTheme.labelMedium!
                              .copyWith(color: theme.colorScheme.primary),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _showSleepTimerSheet(context);
                  },
                ),
                _DrawerItem(
                  icon: Icons.refresh_rounded,
                  label: t.rescanLibrary,
                  onTap: () {
                    Navigator.pop(context);
                    ref.invalidate(rawSongsProvider);
                    ref.invalidate(albumsProvider);
                    ref.invalidate(artistsProvider);
                    ref.invalidate(genresProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rescanning your music…')),
                    );
                  },
                ),
                _DrawerItem(
                  icon: Icons.folder_off_outlined,
                  label: t.excludedFolders,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/excluded-folders');
                  },
                ),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: t.settings,
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/settings');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Sleep timer ----------------

  void _showSleepTimerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final t = ref.watch(l10nProvider);
          final timer = ref.watch(sleepTimerProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(t.sleepTimer,
                          style: theme.textTheme.titleMedium),
                      const Spacer(),
                      if (timer.active)
                        Text(
                          timer.endOfTrack
                              ? 'After this track'
                              : Formatters.duration(timer.remaining!),
                          style: theme.textTheme.labelMedium!
                              .copyWith(color: theme.colorScheme.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in const [15, 30, 45, 60])
                        ActionChip(
                          label: Text('${minutes}m'),
                          onPressed: () => ref
                              .read(sleepTimerProvider.notifier)
                              .start(Duration(minutes: minutes)),
                        ),
                      ActionChip(
                        label: const Text('End of track'),
                        onPressed: () => ref
                            .read(sleepTimerProvider.notifier)
                            .stopAfterTrack(),
                      ),
                      if (timer.active)
                        ActionChip(
                          avatar: Icon(Icons.close_rounded,
                              size: 16, color: theme.colorScheme.primary),
                          label: const Text('Cancel'),
                          onPressed: () =>
                              ref.read(sleepTimerProvider.notifier).cancel(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// Thin faint circle outline used as background decoration.
class _WatermarkRing extends StatelessWidget {
  const _WatermarkRing({required this.diameter, required this.color});
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(.035), width: 1.4),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onTap,
    this.trailing,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: iconWidget ??
                  Icon(icon, size: 25, color: onSurface.withOpacity(.92)),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium!.copyWith(
                  fontSize: 18.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .2,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
