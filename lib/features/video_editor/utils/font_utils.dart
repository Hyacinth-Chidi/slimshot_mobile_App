import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Custom fonts bundled in assets/fonts/ and registered in pubspec.yaml.
/// These use TextStyle(fontFamily: ...) directly, NOT GoogleFonts.getFont().
const List<String> customBundledFonts = [
  'Ariana Violeta',
  'Believe It',
  'Chrusty Rock',
  'Debrosee',
  'New Retro Style 3d',
  'Shade Blue',
  'Short Baby',
  'Super Kindly',
];

/// Google Fonts that are loaded on-demand via the google_fonts package.
const List<String> googleFontsList = [
  'Roboto',
  'Montserrat',
  'Lato',
  'Oswald',
  'Bebas Neue',
  'Playfair Display',
  'Pacifico',
  'Dancing Script',
  'Poppins',
  'Raleway',
  'Inter',
  'Nunito',
  'Lobster',
  'Caveat',
  'Abril Fatface',
  'Righteous',
  'Permanent Marker',
  'Press Start 2P',
  'Cinzel',
  'Sacramento',
];

/// Combined list: Google Fonts first, then custom bundled fonts.
const List<String> allFonts = [
  ...googleFontsList,
  ...customBundledFonts,
];

/// Returns true if the font is a custom bundled font (not a Google Font).
bool isCustomFont(String fontFamily) {
  return customBundledFonts.contains(fontFamily);
}

/// Returns a TextStyle that works for both Google Fonts and custom bundled fonts.
/// For Google Fonts, it uses GoogleFonts.getFont().
/// For custom bundled fonts, it uses TextStyle(fontFamily: ...).
TextStyle getFontStyle(
  String fontFamily, {
  double? fontSize,
  Color? color,
  FontWeight? fontWeight,
  double? height,
  List<Shadow>? shadows,
  Paint? foreground,
  double? letterSpacing,
}) {
  if (isCustomFont(fontFamily)) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: foreground == null ? color : null,
      fontWeight: fontWeight,
      height: height,
      shadows: shadows,
      foreground: foreground,
      letterSpacing: letterSpacing,
    );
  }

  return GoogleFonts.getFont(
    fontFamily,
    fontSize: fontSize,
    color: foreground == null ? color : null,
    fontWeight: fontWeight,
    height: height,
    shadows: shadows,
    foreground: foreground,
    letterSpacing: letterSpacing,
  );
}
