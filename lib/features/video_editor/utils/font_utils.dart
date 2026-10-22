import 'package:flutter/material.dart';

import '../../fonts/font_names.dart';

/// The fonts bundled in the app. **Goes in Task 11 of the server-fonts plan**
/// with its last users; read `kBundledFontNames`.
const List<String> customBundledFonts = kBundledFontNames;

/// Every font the built-in looks name. **Goes in Task 11** with its last
/// users; the Font tab lists the server's fonts.
const List<String> allFonts = [
  kSystemFontName,
  ...kBundledFontNames,
  ...kServerTemplateFontNames,
];

/// Whether [fontFamily] needs no download. **Goes in Task 11**; read
/// `isLocalFontName`.
bool isCustomFont(String fontFamily) => isLocalFontName(fontFamily);

/// The style a text in [fontFamily] draws with.
///
/// **One plain `TextStyle`, at once** — the text geometry measures during
/// layout, so this cannot wait. A bundled font is in the app; a server font
/// is registered under its name once it is on the phone (`FontRegistry`);
/// until then the engine draws the System font, and the text is laid out
/// again when the font lands.
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
