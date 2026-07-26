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

// FEATURE (#12): Material You — seed the app's accent colors from the
// user's wallpaper (Android 12+). Persisted, off by default so the Orvo
// violet identity stays the out-of-the-box look.
const _kDynamicColorKey = 'orvo.dynamicColor';

class DynamicColorNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_kDynamicColorKey) ?? false;

  void set(bool value) {
    state = value;
    ref.read(sharedPreferencesProvider).setBool(_kDynamicColorKey, value);
  }
}

final dynamicColorProvider =
    NotifierProvider<DynamicColorNotifier, bool>(DynamicColorNotifier.new);
