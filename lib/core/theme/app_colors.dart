import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF020617); // Slate 950
  static const Color surface = Color(0xFF0F172A); // Slate 900
  static const Color surfaceLight = Color(0xFF1E293B); // Slate 800

  static const Color primaryStart = Color(0xFF6366F1); // Indigo 500
  static const Color primaryEnd = Color(0xFF8B5CF6); // Violet 500

  static const Color textPrimary = Color(0xFFF8FAFC); // Slate 50
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textTertiary = Color(0xFF64748B); // Slate 500

  static const Color error = Color(0xFFEF4444); // Red 500
  static const Color success = Color(0xFF22C55E); // Green 500
  static const Color warning = Color(0xFFEAB308); // Yellow 500

  static const Color border = Color(0xFF334155); // Slate 700
  static const Color highlight = Color(0x266366F1); // Indigo 500 @ 15% opacity

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
