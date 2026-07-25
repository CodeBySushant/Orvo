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
    final router = ref.watch(routerProvider);

    final (ThemeData darkTheme, ThemeMode mode) = switch (themeSetting) {
      OrvoTheme.system => (AppTheme.dark, ThemeMode.system),
      OrvoTheme.light => (AppTheme.dark, ThemeMode.light),
      OrvoTheme.dark => (AppTheme.dark, ThemeMode.dark),
      OrvoTheme.amoled => (AppTheme.amoled, ThemeMode.dark),
    };

    return MaterialApp.router(
      title: 'Orvo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: darkTheme,
      themeMode: mode,
      routerConfig: router,
      builder: (context, child) =>
          PermissionGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
