import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/l10n.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/bg_theme_provider.dart';
import 'core/theme/skin_provider.dart';
import 'core/theme/theme_provider.dart';
import 'features/onboarding/permission_gate.dart';

class OrvoApp extends ConsumerWidget {
  const OrvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSetting = ref.watch(themeProvider);
    // FEATURE (#24): app language — switching updates instantly.
    final language = ref.watch(languageProvider);
    // FEATURE (#12): Material You — wallpaper-derived accent colors.
    final useDynamic = ref.watch(dynamicColorProvider);
    // FEATURE (#27): skin accent (overridden by Material You when enabled).
    final skin = ref.watch(skinProvider);
    // FEATURE (backgrounds): wallpaper behind the whole app.
    final bg = ref.watch(bgThemeProvider);
    final router = ref.watch(routerProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Null on Android < 12 (or when the toggle is off) — Orvo violet.
        final lightScheme = useDynamic ? lightDynamic : null;
        final darkScheme = useDynamic ? darkDynamic : null;

        final bright = skin.accentBright;
        var (ThemeData darkTheme, ThemeMode mode) = switch (themeSetting) {
          OrvoTheme.system => (AppTheme.dark(darkScheme, bright), ThemeMode.system),
          OrvoTheme.light => (AppTheme.dark(darkScheme, bright), ThemeMode.light),
          OrvoTheme.dark => (AppTheme.dark(darkScheme, bright), ThemeMode.dark),
          OrvoTheme.amoled => (AppTheme.amoled(darkScheme, bright), ThemeMode.dark),
        };
        var lightTheme = AppTheme.light(lightScheme, skin.accent);

        // FEATURE (backgrounds): while a wallpaper is active, the whole app
        // uses the dark look (light text over the darkened image, like the
        // reference) with transparent scaffolds so the wallpaper shows
        // through on every route.
        if (bg != null) {
          darkTheme = applyBgSurfaces(darkTheme);
          lightTheme = darkTheme;
          mode = ThemeMode.dark;
        }

        return MaterialApp.router(
          title: 'Orvo',
          debugShowCheckedModeBanner: false,
          locale: language.locale,
          supportedLocales: [
            for (final l in AppLanguage.values) l.locale,
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          routerConfig: router,
          builder: (context, child) => OrvoBackdrop(
            child: PermissionGate(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
