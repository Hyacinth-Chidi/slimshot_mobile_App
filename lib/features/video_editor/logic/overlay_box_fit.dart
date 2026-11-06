import 'dart:math' as math;
import 'dart:ui';

import '../models/image_overlay_model.dart';
import '../models/video_overlay_model.dart';
import 'animation/animatable_double.dart';
import 'animation/overlay_keyframes.dart';

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

/// [overlay] re-placed for [canvas], where it was placed against its
/// `referenceCanvasSize`: the same share of the frame, centre and size, its
/// keyframed path included. An overlay with no reference is the editor's own
/// and comes back as it is; a canvas not laid out yet leaves the reference
/// for the real one.
///
/// An overlay's place is kept in the pixels of the canvas it was placed on,
/// and its box is a fixed [kVideoOverlayBoxPx], so the same numbers on
/// another canvas would be another place and size. The conversion happens
/// once, when the editor first knows its canvas, after which the overlay is
/// like any other placed there.
VideoOverlayModel fitOverlayToCanvas(VideoOverlayModel overlay, Size canvas) {
  final reference = overlay.referenceCanvasSize;
  if (reference == null || !_isCanvas(canvas)) return overlay;
  final fitted = _fitMotion(overlay.motion, reference, canvas);
  return (fitted == null ? overlay : overlay.withMotion(fitted)).copyWith(clearReferenceCanvasSize: true);
}

/// [fitOverlayToCanvas] for a photo overlay — the same conversion.
ImageOverlayModel fitImageOverlayToCanvas(ImageOverlayModel overlay, Size canvas) {
  final reference = overlay.referenceCanvasSize;
  if (reference == null || !_isCanvas(canvas)) return overlay;
  final fitted = _fitMotion(overlay.motion, reference, canvas);
  return (fitted == null ? overlay : overlay.withMotion(fitted)).copyWith(clearReferenceCanvasSize: true);
}

bool _isCanvas(Size size) => size.width > 0 && size.height > 0;

/// [motion] placed for [reference] re-placed for [canvas]: positions by each
/// axis's ratio, the scale by the smaller. Null for a reference that is no
/// size at all, which is simply dropped.
OverlayMotion? _fitMotion(OverlayMotion motion, Size reference, Size canvas) {
  if (!_isCanvas(reference)) return null;
  final sx = canvas.width / reference.width;
  final sy = canvas.height / reference.height;
  final size = math.min(sx, sy);
  final params = motion.params;
  return OverlayMotion.fromParams({
    ...params,
    OverlayProperty.x: mapAnimatable(params[OverlayProperty.x]!, (v) => v * sx),
    OverlayProperty.y: mapAnimatable(params[OverlayProperty.y]!, (v) => v * sy),
    OverlayProperty.scale: mapAnimatable(params[OverlayProperty.scale]!, (v) => v * size),
  });
}
