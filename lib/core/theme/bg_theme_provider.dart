import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart' show sharedPreferencesProvider;

// ---------------------------------------------------------------------------
// FEATURE (backgrounds): wallpaper-style app backgrounds (reference: the
// DDMusic mountain wallpaper look). A background renders full-screen behind
// every route; the scaffold goes transparent and a gradient scrim keeps text
// readable. Background themes always use the DARK look — light text over a
// darkened wallpaper — like the reference app.
// ---------------------------------------------------------------------------

class BgTheme {
  const BgTheme(this.id, this.asset);
  final String id;
  final String asset;
}

/// All bundled wallpapers (assets/themes/theme1–14.webp).
final List<BgTheme> kBgThemes = List.unmodifiable([
  for (var n = 1; n <= 14; n++)
    BgTheme('theme$n', 'assets/themes/theme$n.webp'),
]);

const _kBgThemeKey = 'orvo.bgTheme';

/// null = no background (plain theme surfaces).
class BgThemeNotifier extends Notifier<BgTheme?> {
  @override
  BgTheme? build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_kBgThemeKey);
    if (stored == null || stored.isEmpty) return null;
    for (final bg in kBgThemes) {
      if (bg.id == stored) return bg;
    }
    return null;
  }

  void set(BgTheme? bg) {
    state = bg;
    ref
        .read(sharedPreferencesProvider)
        .setString(_kBgThemeKey, bg?.id ?? '');
  }
}

final bgThemeProvider =
    NotifierProvider<BgThemeNotifier, BgTheme?>(BgThemeNotifier.new);

/// Surface overrides applied on top of the dark / AMOLED ThemeData while a
/// background is active: the scaffold goes transparent so the wallpaper
/// shows through, and the bottom navigation bar becomes translucent glass.
/// Sheets, dialogs, cards and snackbars keep their solid surfaces for
/// readability.
ThemeData applyBgSurfaces(ThemeData t) => t.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      navigationBarTheme: t.navigationBarTheme.copyWith(
        backgroundColor: const Color(0xC20D0B16),
      ),
    );

/// Paints the selected wallpaper (plus a readability scrim) behind [child].
/// Sits inside MaterialApp.builder, so it covers every route.
class OrvoBackdrop extends ConsumerWidget {
  const OrvoBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = ref.watch(bgThemeProvider);
    if (bg == null) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          bg.asset,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
        // Scrim — heavier at the top (status bar / titles) and bottom
        // (mini player / nav bar), lighter in the middle so the wallpaper
        // still reads through, matching the reference look.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xB3000000), // 70%
                Color(0x73000000), // 45%
                Color(0xB3000000), // 70%
              ],
              stops: [0, .45, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
