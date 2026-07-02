import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/widgets/artwork.dart';
import '../library/providers/library_providers.dart';
import '../player/providers/audio_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(themeProvider);
    final songCount =
        ref.watch(songsProvider).valueOrNull?.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionLabel('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final option in OrvoTheme.values) ...[
                  Expanded(
                    child: _ThemeCard(
                      option: option,
                      selected: option == current,
                      onTap: () =>
                          ref.read(themeProvider.notifier).set(option),
                    ),
                  ),
                  if (option != OrvoTheme.values.last)
                    const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Audio'),
          ListTile(
            leading: const Icon(Icons.equalizer_rounded),
            title: const Text('Equalizer'),
            subtitle: Text('5-band EQ, presets, bass boost',
                style: theme.textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/equalizer'),
          ),
          Consumer(builder: (context, ref, _) {
            final smooth = ref.watch(smoothTransitionsProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.waves_rounded),
              title: const Text('Smooth transitions'),
              subtitle: Text('Gentle fade on play, pause and skip',
                  style: theme.textTheme.labelMedium),
              value: smooth,
              onChanged: (v) =>
                  ref.read(smoothTransitionsProvider.notifier).set(v),
            );
          }),
          const SizedBox(height: 24),
          _SectionLabel('Library'),
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Rescan library'),
            subtitle: Text(
              songCount != null ? '$songCount songs indexed' : 'Scanning…',
              style: theme.textTheme.labelMedium,
            ),
            onTap: () {
              ArtworkCache.instance.clear();
              ref.invalidate(songsProvider);
              ref.invalidate(albumsProvider);
              ref.invalidate(artistsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rescanning your library')),
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionLabel('About'),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Orvo'),
            subtitle: Text('Version 0.1.0 · Phase 1 core'),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline_rounded),
            title: Text('Privacy'),
            subtitle: Text(
                'Fully offline. Your music and listening data never leave this device.'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final OrvoTheme option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, swatch) = switch (option) {
      OrvoTheme.system => ('Auto', theme.colorScheme.surfaceContainerHigh),
      OrvoTheme.light => ('Light', const Color(0xFFFAF7F5)),
      OrvoTheme.dark => ('Dark', const Color(0xFF1F181B)),
      OrvoTheme.amoled => ('AMOLED', Colors.black),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            width: selected ? 2 : 1,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(.12),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(
                    color: theme.colorScheme.onSurface.withOpacity(.2)),
              ),
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
