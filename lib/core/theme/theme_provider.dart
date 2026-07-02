import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

/// Overridden in main() with the real instance.
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

const _kThemeKey = 'orvo.theme';

class ThemeNotifier extends Notifier<OrvoTheme> {
  @override
  OrvoTheme build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_kThemeKey);
    return OrvoTheme.values.firstWhere(
      (t) => t.name == stored,
      orElse: () => OrvoTheme.system,
    );
  }

  void set(OrvoTheme theme) {
    state = theme;
    ref.read(sharedPreferencesProvider).setString(_kThemeKey, theme.name);
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, OrvoTheme>(ThemeNotifier.new);
