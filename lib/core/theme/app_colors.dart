import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF09090B); // Zinc 950 (Deep Neutral Black)
  static const Color surface = Color(0xFF18181B); // Zinc 900
  static const Color surfaceLight = Color(0xFF27272A); // Zinc 800

  // The new signature purple accent based on the logo
  static const Color primaryStart = Color(0xFF9333EA); // Rich Purple (toned down)
  static const Color primaryEnd = Color(0xFF6B21A8); // Deep Purple

  static const Color textPrimary = Color(0xFFFAFAFA); // Zinc 50
  static const Color textSecondary = Color(0xFFA1A1AA); // Zinc 400
  static const Color textTertiary = Color(0xFF71717A); // Zinc 500

  static const Color error = Color(0xFFEF4444); // Red 500
  static const Color success = Color(0xFF22C55E); // Green 500
  static const Color warning = Color(0xFFEAB308); // Yellow 500

  static const Color border = Color(0xFF3F3F46); // Zinc 700
  static const Color highlight = Color(0x269333EA); // Purple @ 15% opacity

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
