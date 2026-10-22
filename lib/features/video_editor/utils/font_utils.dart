import 'package:flutter/material.dart';

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
