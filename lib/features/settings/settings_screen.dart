import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/widgets/artwork.dart';
import '../library/providers/library_providers.dart';
import '../lyrics/lyrics_provider.dart';
import '../player/providers/audio_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);
    final current = ref.watch(themeProvider);
    final songCount =
        ref.watch(songsProvider).valueOrNull?.length;

    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionLabel(t.appearance),
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
          // FEATURE (#12): Material You — wallpaper-derived accent colors.
          Consumer(builder: (context, ref, _) {
            final dynamicOn = ref.watch(dynamicColorProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.palette_outlined),
              title: Text(ref.watch(l10nProvider).materialYou),
              subtitle: Text(ref.watch(l10nProvider).materialYouSub,
                  style: theme.textTheme.labelMedium),
              value: dynamicOn,
              onChanged: (v) =>
                  ref.read(dynamicColorProvider.notifier).set(v),
            );
          }),
          // FEATURE (#24): language picker — switching applies instantly.
          Consumer(builder: (context, ref, _) {
            final t2 = ref.watch(l10nProvider);
            final lang = ref.watch(languageProvider);
            return ListTile(
              leading: const Icon(Icons.language_rounded),
              title: Text(t2.language),
              subtitle:
                  Text(lang.nativeName, style: theme.textTheme.labelMedium),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: Text(t2.language),
                  children: [
                    for (final option in AppLanguage.values)
                      RadioListTile<AppLanguage>(
                        value: option,
                        groupValue: lang,
                        title: Text(option.nativeName),
                        onChanged: (v) {
                          if (v != null) {
                            ref.read(languageProvider.notifier).set(v);
                          }
                          Navigator.pop(dialogContext);
                        },
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          _SectionLabel(t.audio),
          ListTile(
            leading: const Icon(Icons.equalizer_rounded),
            title: Text(t.equalizer),
            subtitle: Text(t.equalizerSub,
                style: theme.textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/equalizer'),
          ),
          Consumer(builder: (context, ref, _) {
            final smooth = ref.watch(smoothTransitionsProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.waves_rounded),
              title: Text(ref.watch(l10nProvider).smoothTransitions),
              subtitle: Text(ref.watch(l10nProvider).smoothTransitionsSub,
                  style: theme.textTheme.labelMedium),
              value: smooth,
              onChanged: (v) =>
                  ref.read(smoothTransitionsProvider.notifier).set(v),
            );
          }),
          // FEATURE (#18): opt-in auto-resume when Bluetooth audio connects.
          Consumer(builder: (context, ref, _) {
            final btResume = ref.watch(btAutoResumeProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.bluetooth_audio_rounded),
              title: Text(ref.watch(l10nProvider).resumeOnBluetooth),
              subtitle: Text(ref.watch(l10nProvider).resumeOnBluetoothSub,
                  style: theme.textTheme.labelMedium),
              value: btResume,
              onChanged: (v) =>
                  ref.read(btAutoResumeProvider.notifier).set(v),
            );
          }),
          // FEATURE (crossfade v1): auto-crossfade between tracks.
          Consumer(builder: (context, ref, _) {
            final seconds = ref.watch(crossfadeProvider);
            return ListTile(
              leading: const Icon(Icons.compare_arrows_rounded),
              title: Text(ref.watch(l10nProvider).crossfade),
              subtitle: Text(
                seconds == 0
                    ? 'Off — tracks change instantly'
                    : 'Tracks blend over $seconds seconds',
                style: theme.textTheme.labelMedium,
              ),
              trailing: Text(
                  seconds == 0 ? ref.watch(l10nProvider).off : '${seconds}s',
                  style: theme.textTheme.labelLarge),
              onTap: () async {
                final picked = await showDialog<int>(
                  context: context,
                  builder: (dialogContext) => SimpleDialog(
                    title: Text(ref.watch(l10nProvider).crossfade),
                    children: [
                      for (final option in CrossfadeNotifier.options)
                        RadioListTile<int>(
                          value: option,
                          groupValue: seconds,
                          title: Text(
                              option == 0 ? 'Off' : '$option seconds'),
                          onChanged: (v) =>
                              Navigator.pop(dialogContext, v),
                        ),
                    ],
                  ),
                );
                if (picked != null) {
                  ref.read(crossfadeProvider.notifier).set(picked);
                }
              },
            );
          }),
          const SizedBox(height: 24),
          _SectionLabel(t.library),
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: Text(t.rescanLibrary),
            subtitle: Text(
              songCount != null ? t.nSongsIndexed(songCount) : t.scanning,
              style: theme.textTheme.labelMedium,
            ),
            onTap: () {
              ArtworkCache.instance.clear();
              ref.invalidate(rawSongsProvider);
              ref.invalidate(albumsProvider);
              ref.invalidate(artistsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.rescanning)),
              );
            },
          ),
          // FEATURE (#25): folder exclusions manager.
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: Text(t.excludedFolders),
            subtitle: Text(t.excludedFoldersSub,
                style: theme.textTheme.labelMedium),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/excluded-folders'),
          ),
          // FIX (#10): scoped storage blocks reading .lrc files owned by
          // other apps on Android 11+; a picked folder with a persisted SAF
          // grant makes sidecar lyrics work again.
          Consumer(builder: (context, ref, _) {
            final folder = ref.watch(lyricsFolderProvider);
            return ListTile(
              leading: const Icon(Icons.lyrics_rounded),
              title: Text(ref.watch(l10nProvider).lyricsFolder),
              subtitle: Text(
                folder == null
                    ? 'Pick the folder holding your .lrc files'
                    : 'Connected — tap to change, long-press to remove',
                style: theme.textTheme.labelMedium,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final picked =
                    await ref.read(lyricsFolderProvider.notifier).pick();
                if (picked && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Lyrics folder connected — .lrc files will now load')),
                  );
                }
              },
              onLongPress: folder == null
                  ? null
                  : () {
                      ref.read(lyricsFolderProvider.notifier).clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Lyrics folder removed')),
                      );
                    },
            );
          }),
          // FEATURE (#21): opt-in online lyrics (LRCLIB). Off by default so
          // the no-network privacy promise holds unless the user opts in.
          Consumer(builder: (context, ref, _) {
            final online = ref.watch(onlineLyricsProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.travel_explore_rounded),
              title: Text(ref.watch(l10nProvider).onlineLyrics),
              subtitle: Text(
                ref.watch(l10nProvider).onlineLyricsSub,
                style: theme.textTheme.labelMedium,
              ),
              value: online,
              onChanged: (v) =>
                  ref.read(onlineLyricsProvider.notifier).set(v),
            );
          }),
          const SizedBox(height: 24),
          _SectionLabel(t.about),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Orvo'),
            subtitle: Text('Version 0.1.0 · Phase 1 core'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: Text(t.privacy),
            subtitle: const Text(
                'Fully offline by default. Your music and listening data never '
                'leave this device. If Online lyrics is on, only song titles, '
                'artists and durations are sent to LRCLIB.'),
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
    final t = ProviderScope.containerOf(context).read(l10nProvider);
    final (label, swatch) = switch (option) {
      OrvoTheme.system => (t.themeAuto, theme.colorScheme.surfaceContainerHigh),
      OrvoTheme.light => (t.themeLight, const Color(0xFFFAF7F5)),
      OrvoTheme.dark => (t.themeDark, const Color(0xFF1F181B)),
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
