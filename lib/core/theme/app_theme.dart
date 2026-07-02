import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// The three Orvo appearances. `system` follows the OS between light/dark.
enum OrvoTheme { system, light, dark, amoled }

abstract final class AppTheme {
  static ThemeData get light => _base(
        brightness: Brightness.light,
        primary: AppColors.garnet,
        scaffold: AppColors.porcelain,
        card: AppColors.porcelainCard,
        raised: const Color(0xFFF1EBE8),
        onSurface: AppColors.inkOnLight,
      );

  static ThemeData get dark => _base(
        brightness: Brightness.dark,
        primary: AppColors.garnetBright,
        scaffold: AppColors.charcoal,
        card: AppColors.charcoalCard,
        raised: AppColors.charcoalRaised,
        onSurface: AppColors.mistOnDark,
      );

  static ThemeData get amoled => _base(
        brightness: Brightness.dark,
        primary: AppColors.garnetBright,
        scaffold: AppColors.trueBlack,
        card: AppColors.blackCard,
        raised: const Color(0xFF1A1A1D),
        onSurface: AppColors.mistOnDark,
      );

  static ThemeData _base({
    required Brightness brightness,
    required Color primary,
    required Color scaffold,
    required Color card,
    required Color raised,
    required Color onSurface,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.garnet,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      secondary: AppColors.ember,
      surface: scaffold,
      surfaceContainer: card,
      surfaceContainerHigh: raised,
      onSurface: onSurface,
    );

    final textTheme = _typography(onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        height: 64,
        elevation: 0,
        indicatorColor: primary.withOpacity(.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall!.copyWith(letterSpacing: .4),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: primary,
        inactiveTrackColor: onSurface.withOpacity(.14),
        thumbColor: primary,
        overlayColor: primary.withOpacity(.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      dividerTheme: DividerThemeData(
        color: onSurface.withOpacity(.08),
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: raised,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// Editorial type scale: tight display weights, relaxed body.
  static TextTheme _typography(Color onSurface) {
    final muted = onSurface.withOpacity(.62);
    return TextTheme(
      displayLarge: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          height: 1.05,
          color: onSurface),
      headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
          color: onSurface),
      titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
          color: onSurface),
      titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -.2,
          color: onSurface),
      titleSmall:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
      bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: onSurface),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: onSurface),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
      labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
          color: onSurface),
      labelMedium:
          TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: muted),
      labelSmall:
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
    );
  }
}
