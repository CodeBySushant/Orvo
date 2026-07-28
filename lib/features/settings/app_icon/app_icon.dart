import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/theme_provider.dart' show sharedPreferencesProvider;

// ---------------------------------------------------------------------------
// FEATURE (app icon): Snapchat-style selectable launcher icon.
//
// The four choices map 1:1 to the .LauncherIcon1–4 activity-aliases on the
// Android side; the orvo/appicon channel enables exactly one of them.
// The selection is also persisted in prefs so the picker can highlight the
// current icon instantly (the channel's "current" call confirms it).
// ---------------------------------------------------------------------------

class AppIconOption {
  const AppIconOption(this.index, this.label, this.asset);
  final int index;
  final String label;
  final String asset;
}

const List<AppIconOption> kAppIconOptions = [
  AppIconOption(1, 'Classic', 'assets/icons/icon1.png'),
  AppIconOption(2, 'Neon', 'assets/icons/icon2.png'),
  AppIconOption(3, 'Pulse', 'assets/icons/icon3.png'),
  AppIconOption(4, 'Glow', 'assets/icons/icon4.png'),
];

const _channel = MethodChannel('orvo/appicon');
const _kAppIconKey = 'orvo.appIcon';

class AppIconNotifier extends Notifier<int> {
  @override
  int build() {
    final stored = ref.read(sharedPreferencesProvider).getInt(_kAppIconKey);
    // Reconcile with the platform truth in the background (e.g. after a
    // reinstall the component state resets to alias 1).
    _sync();
    return (stored ?? 1).clamp(1, kAppIconOptions.length);
  }

  Future<void> _sync() async {
    if (!Platform.isAndroid) return;
    try {
      final current = await _channel.invokeMethod<int>('current');
      if (current != null && current != state) {
        state = current;
        ref.read(sharedPreferencesProvider).setInt(_kAppIconKey, current);
      }
    } catch (_) {}
  }

  /// Applies the icon. Returns true on success.
  Future<bool> set(int index) async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod('set', {'index': index});
      state = index;
      await ref.read(sharedPreferencesProvider).setInt(_kAppIconKey, index);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final appIconProvider =
    NotifierProvider<AppIconNotifier, int>(AppIconNotifier.new);

// ---------------------------------------------------------------------------
// Picker screen — 2-column grid of icon previews, selected one ringed in the
// theme accent with a check badge.
// ---------------------------------------------------------------------------

class AppIconScreen extends ConsumerWidget {
  const AppIconScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(l10nProvider);
    final selected = ref.watch(appIconProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.appIcon)),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            t.appIconNote,
            style: theme.textTheme.bodyMedium!.copyWith(
              height: 1.45,
              color: theme.colorScheme.onSurface.withOpacity(.65),
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: .92,
            children: [
              for (final option in kAppIconOptions)
                _IconCard(
                  option: option,
                  selected: option.index == selected,
                  onTap: () async {
                    if (option.index == selected) return;
                    final ok =
                        await ref.read(appIconProvider.notifier).set(option.index);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(SnackBar(
                        content:
                            Text(ok ? t.appIconApplied : t.appIconFailed),
                      ));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconCard extends StatelessWidget {
  const _IconCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppIconOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            width: selected ? 2.4 : 1,
            color: selected
                ? accent
                : theme.colorScheme.onSurface.withOpacity(.12),
          ),
          color: selected
              ? accent.withOpacity(.06)
              : theme.colorScheme.surfaceContainerLow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  // ~22% radius mirrors how most launchers mask icons.
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    option.asset,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                if (selected)
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: theme.colorScheme.surface, width: 2),
                      ),
                      child: Icon(Icons.check_rounded,
                          size: 15, color: theme.colorScheme.onPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              option.label,
              style: theme.textTheme.labelLarge!.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? accent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
