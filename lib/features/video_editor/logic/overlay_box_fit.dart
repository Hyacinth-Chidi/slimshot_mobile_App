import 'dart:ui';

/// The size a picture of [contentAspect] takes when contain-fitted into a
/// square [box] — the Dart half of what `OverlayRenderer.writeCorners` does
/// for an overlay's quad.
///
/// The selection frame and its handles are Flutter widgets while the picture
/// is drawn by GL, so they only line up if both fit the content the same way.
/// An unknown shape is the whole box: a slightly loose frame for a moment
/// beats no gesture target at all.
Size fittedOverlayBox({required double? contentAspect, required double box}) {
  final a = contentAspect;
  if (a == null || !a.isFinite || a <= 0) return Size(box, box);
  return a >= 1 ? Size(box, box / a) : Size(box * a, box);
}
