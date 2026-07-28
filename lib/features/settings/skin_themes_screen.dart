import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bg_theme_provider.dart';
import '../../core/theme/skin_provider.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/widgets/pressable.dart';

// ---------------------------------------------------------------------------
// FEATURE (#27): Skin Themes screen (reference: DDMusic "Skin themes").
//
// Layout, top → bottom:
//   1. Appearance mode chips — System / Light / Dark / AMOLED
//   2. Phone-frame LIVE preview — a miniature Orvo home rendered with the
//      exact ThemeData the current mode + selected skin produce
//   3. Swatch grid — 10 skins; the active one gets a ring + check badge
//
// Picking a skin applies instantly (and switches Material You off if it was
// on, so the choice is always visible).
// ---------------------------------------------------------------------------

class SkinThemesScreen extends ConsumerWidget {
  const SkinThemesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(l10nProvider);
    final mode = ref.watch(themeProvider);
    final skin = ref.watch(skinProvider);

    // Resolve the preview's ThemeData exactly as the app would build it,
    // minus Material You (the point here is to see the skin).
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final previewTheme = switch (mode) {
      OrvoTheme.light => AppTheme.light(null, skin.accent),
      OrvoTheme.dark => AppTheme.dark(null, skin.accentBright),
      OrvoTheme.amoled => AppTheme.amoled(null, skin.accentBright),
      OrvoTheme.system => platformDark
          ? AppTheme.dark(null, skin.accentBright)
          : AppTheme.light(null, skin.accent),
    };

    return Scaffold(
      appBar: AppBar(title: Text(t.themes)),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // 1 — appearance mode
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Wrap(
              spacing: 8,
              children: [
                for (final option in OrvoTheme.values)
                  ChoiceChip(
                    label: Text(switch (option) {
                      OrvoTheme.system => t.themeAuto,
                      OrvoTheme.light => t.themeLight,
                      OrvoTheme.dark => t.themeDark,
                      OrvoTheme.amoled => 'AMOLED',
                    }),
                    selected: mode == option,
                    onSelected: (_) =>
                        ref.read(themeProvider.notifier).set(option),
                  ),
              ],
            ),
          ),

          // 2 — phone-frame live preview
          Center(child: _PhonePreview(theme: previewTheme)),
          const SizedBox(height: 26),

          // 3 — swatch grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 18,
              crossAxisSpacing: 16,
              children: [
                for (final option in OrvoSkin.values)
                  _SkinSwatch(
                    skin: option,
                    selected: option == skin,
                    onTap: () {
                      ref.read(skinProvider.notifier).set(option);
                      // Material You would override the skin — turn it off
                      // so the pick is visible, and say so once.
                      if (ref.read(dynamicColorProvider)) {
                        ref.read(dynamicColorProvider.notifier).set(false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Material You turned off to apply the skin')),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),

          // 4 — FEATURE (backgrounds): wallpaper grid, below the skins.
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              t.backgrounds,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: Text(t.backgroundsNote,
                style: Theme.of(context).textTheme.labelMedium),
          ),
          Consumer(builder: (context, ref, _) {
            final selectedBg = ref.watch(bgThemeProvider);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: .52,
                children: [
                  _BgCard(
                    bg: null,
                    label: t.noBackground,
                    selected: selectedBg == null,
                    onTap: () =>
                        ref.read(bgThemeProvider.notifier).set(null),
                  ),
                  for (final bg in kBgThemes)
                    _BgCard(
                      bg: bg,
                      selected: selectedBg?.id == bg.id,
                      onTap: () =>
                          ref.read(bgThemeProvider.notifier).set(bg),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FEATURE (backgrounds): wallpaper thumbnail card. `bg == null` renders the
// "None" card (plain surface + slash icon).
// ---------------------------------------------------------------------------

class _BgCard extends StatelessWidget {
  const _BgCard({
    required this.bg,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final BgTheme? bg;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            width: selected ? 2.6 : 1,
            color: selected
                ? accent
                : theme.colorScheme.onSurface.withOpacity(.12),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bg != null)
                Image.asset(
                  bg!.asset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                )
              else
                Container(
                  color: theme.colorScheme.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_rounded,
                          size: 26,
                          color:
                              theme.colorScheme.onSurface.withOpacity(.5)),
                      if (label != null) ...[
                        const SizedBox(height: 6),
                        Text(label!,
                            style: theme.textTheme.labelMedium),
                      ],
                    ],
                  ),
                ),
              if (selected)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.colorScheme.surface, width: 2),
                    ),
                    child: Icon(Icons.check_rounded,
                        size: 14, color: theme.colorScheme.onPrimary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone-frame preview — a miniature home screen, real widgets, real theme.
// ---------------------------------------------------------------------------

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bezel = Theme.of(context).colorScheme.onSurface.withOpacity(.14);
    return Container(
      width: 246,
      height: 430,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: bezel, width: 5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      // AnimatedTheme so switching skins/modes cross-fades the preview.
      child: IgnorePointer(
        child: AnimatedTheme(
          data: theme,
          duration: const Duration(milliseconds: 260),
          child: const _MiniHome(),
        ),
      ),
    );
  }
}

class _MiniHome extends StatelessWidget {
  const _MiniHome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget bar(double w, {double h = 7, Color? color}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color ?? scheme.onSurface.withOpacity(.28),
            borderRadius: BorderRadius.circular(4),
          ),
        );

    Widget songRow() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    scheme.primary.withOpacity(.85),
                    scheme.primary.withOpacity(.45),
                  ]),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.music_note_rounded,
                    size: 13, color: scheme.onPrimary),
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(74),
                  const SizedBox(height: 4),
                  bar(46, h: 5),
                ],
              ),
              const Spacer(),
              Icon(Icons.more_vert_rounded,
                  size: 12, color: scheme.onSurface.withOpacity(.4)),
            ],
          ),
        );

    return ColoredBox(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                bar(16, h: 10),
                const Spacer(),
                Icon(Icons.search_rounded,
                    size: 14, color: scheme.onSurface.withOpacity(.7)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // hero cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.favorite_rounded,
                        size: 15, color: scheme.onPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.shuffle_rounded,
                        size: 15, color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: bar(88, h: 9),
          ),
          const SizedBox(height: 6),
          songRow(),
          songRow(),
          songRow(),
          const Spacer(),
          // mini player
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.music_note_rounded,
                      size: 12, color: scheme.onPrimary),
                ),
                const SizedBox(width: 8),
                bar(58),
                const Spacer(),
                Icon(Icons.pause_rounded, size: 15, color: scheme.primary),
                const SizedBox(width: 7),
                Icon(Icons.skip_next_rounded,
                    size: 15, color: scheme.onSurface.withOpacity(.75)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swatch — rounded gradient square; selected = ring + check badge (mockup).
// ---------------------------------------------------------------------------

class _SkinSwatch extends StatelessWidget {
  const _SkinSwatch({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final OrvoSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.onSurface;
    return Pressable(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected ? ring : Colors.transparent,
                width: 2.4,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [skin.accentBright, skin.accent],
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              bottom: -7,
              child: Container(
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  color: ring,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface, width: 2),
                ),
                child: Icon(Icons.check_rounded,
                    size: 13, color: Theme.of(context).colorScheme.surface),
              ),
            ),
        ],
      ),
    );
  }
}
