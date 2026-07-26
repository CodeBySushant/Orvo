import 'package:flutter/material.dart';

/// Orvo design tokens.
///
/// REDESIGN v2: the accent moves from violet to an Apple Music-style
/// pink → red scale on the same midnight-navy base. Field names keep their
/// original "violet" identifiers so every existing reference updates
/// automatically — only the values changed.
abstract final class AppColors {
  // Accent scale — Apple Music pink/red
  static const Color violet = Color(0xFFFA233B); // primary (light surfaces)
  static const Color violetBright = Color(0xFFFF5C74); // primary (dark surfaces)
  static const Color violetDeep = Color(0xFFB80F2E); // pressed / gradients
  static const Color orchid = Color(0xFFFF7A93); // secondary accent

  // Legacy garnet scale (still used by placeholder gradients)
  static const Color garnet = Color(0xFFB4182D);
  static const Color garnetBright = Color(0xFFFF4D63);
  static const Color garnetDeep = Color(0xFF6E0B1A);
  static const Color ember = Color(0xFFFF8A5C);

  // Light surfaces — cool porcelain
  static const Color porcelain = Color(0xFFF7F7FB);
  static const Color porcelainCard = Color(0xFFFFFFFF);
  static const Color inkOnLight = Color(0xFF16141F);

  // Dark surfaces — midnight navy (mockup base)
  static const Color midnight = Color(0xFF0B1023); // scaffold
  static const Color midnightCard = Color(0xFF151B36); // cards / nav
  static const Color midnightRaised = Color(0xFF1F2749); // sheets / raised
  static const Color mistOnDark = Color(0xFFEDEFFA);

  // AMOLED
  static const Color trueBlack = Color(0xFF000000);
  static const Color blackCard = Color(0xFF10121C);

  /// Vivid tile colors for genre chips and playlist gradients (mockup).
  static const List<Color> tileColors = [
    Color(0xFF8B5CF6), // purple
    Color(0xFFEC4899), // pink
    Color(0xFFF59E0B), // orange
    Color(0xFF3B82F6), // blue
    Color(0xFF14B8A6), // teal
    Color(0xFFF43F5E), // rose
    Color(0xFF6366F1), // indigo
    Color(0xFF22C55E), // green
  ];

  static Color tileColorFor(String seed) =>
      tileColors[seed.hashCode.abs() % tileColors.length];

  /// Elegant placeholder gradients for artwork-less tracks.
  static const List<List<Color>> placeholderGradients = [
    [Color(0xFF3D2C8D), Color(0xFF171130)],
    [Color(0xFF6E0B1A), Color(0xFF2A0710)],
    [Color(0xFF0F5257), Color(0xFF06201F)],
    [Color(0xFF7A4419), Color(0xFF2B1607)],
    [Color(0xFF4A1942), Color(0xFF1B0918)],
    [Color(0xFF1F4068), Color(0xFF0B1626)],
  ];

  static List<Color> gradientFor(String seed) =>
      placeholderGradients[seed.hashCode.abs() % placeholderGradients.length];
}
