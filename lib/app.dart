import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/onboarding/permission_gate.dart';

class OrvoApp extends ConsumerWidget {
  const OrvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSetting = ref.watch(themeProvider);
    // FEATURE (#12): Material You — wallpaper-derived accent colors.
    final useDynamic = ref.watch(dynamicColorProvider);
    final router = ref.watch(routerProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Null on Android < 12 (or when the toggle is off) — Orvo violet.
        final lightScheme = useDynamic ? lightDynamic : null;
        final darkScheme = useDynamic ? darkDynamic : null;

        final (ThemeData darkTheme, ThemeMode mode) = switch (themeSetting) {
          OrvoTheme.system => (AppTheme.dark(darkScheme), ThemeMode.system),
          OrvoTheme.light => (AppTheme.dark(darkScheme), ThemeMode.light),
          OrvoTheme.dark => (AppTheme.dark(darkScheme), ThemeMode.dark),
          OrvoTheme.amoled => (AppTheme.amoled(darkScheme), ThemeMode.dark),
        };

        return MaterialApp.router(
          title: 'Orvo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(lightScheme),
          darkTheme: darkTheme,
          themeMode: mode,
          routerConfig: router,
          builder: (context, child) =>
              PermissionGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
