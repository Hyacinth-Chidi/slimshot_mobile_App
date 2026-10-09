import 'dart:ui';

/// The square a photo overlay's picture is fitted into, in the preview
/// canvas's pixels — the editor's layout, the composer's conversion to
/// fractions and a clip moved onto the overlay track all read this one value.
const double kImageOverlayBoxPx = 200.0;

/// A video overlay's square, as [kImageOverlayBoxPx] is a photo's.
const double kVideoOverlayBoxPx = 240.0;

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
