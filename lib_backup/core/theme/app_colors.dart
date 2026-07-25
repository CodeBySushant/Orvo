import 'package:flutter/material.dart';

/// Orvo design tokens.
///
/// The identity is built around a deep "garnet" red — richer and darker than
/// the usual vivid red family — paired with warm near-black surfaces so the
/// accent reads as lacquer rather than alarm.
abstract final class AppColors {
  // Accent scale
  static const Color garnet = Color(0xFFB4182D); // primary (light surfaces)
  static const Color garnetBright = Color(0xFFFF4D63); // primary (dark surfaces)
  static const Color garnetDeep = Color(0xFF6E0B1A); // pressed / gradients
  static const Color ember = Color(0xFFFF8A5C); // secondary warm accent

  // Light surfaces — warm porcelain, not pure white
  static const Color porcelain = Color(0xFFFAF7F5);
  static const Color porcelainCard = Color(0xFFFFFFFF);
  static const Color inkOnLight = Color(0xFF1C1416);

  // Dark surfaces — warm charcoal with a hint of red undertone
  static const Color charcoal = Color(0xFF141012);
  static const Color charcoalCard = Color(0xFF1F181B);
  static const Color charcoalRaised = Color(0xFF2A2126);
  static const Color mistOnDark = Color(0xFFF2EAEC);

  // AMOLED
  static const Color trueBlack = Color(0xFF000000);
  static const Color blackCard = Color(0xFF101012);

  /// Elegant placeholder gradients for artwork-less tracks.
  static const List<List<Color>> placeholderGradients = [
    [Color(0xFF6E0B1A), Color(0xFF2A0710)],
    [Color(0xFF3D2C8D), Color(0xFF171130)],
    [Color(0xFF0F5257), Color(0xFF06201F)],
    [Color(0xFF7A4419), Color(0xFF2B1607)],
    [Color(0xFF4A1942), Color(0xFF1B0918)],
    [Color(0xFF1F4068), Color(0xFF0B1626)],
  ];

  static List<Color> gradientFor(String seed) =>
      placeholderGradients[seed.hashCode.abs() % placeholderGradients.length];
}
