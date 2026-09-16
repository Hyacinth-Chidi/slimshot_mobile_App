/// Resolves crop, zoom and pan into the single source rect that is actually
/// shown.
///
/// The editor keeps three separate controls — a crop rect, a zoom scale and a
/// pan offset — but they all narrow the same thing: which part of the source
/// frame reaches the canvas. Collapsing them here means preview and export
/// sample the same rectangle instead of each composing the controls in its own
/// order and drifting apart.
library;

import 'dart:ui';

/// Keeps a normalised rect inside `0..1` and non-degenerate.
Rect clampNormalizedRect(Rect rect) {
  // The near edge stops one minimum extent short of the far side, so the far
  // edge's lower bound below can never exceed its upper bound. Without that, a
  // rect pushed wholly past the frame — a hand-edited draft, or a crop dragged
  // off the edge — made `clamp(1.0001, 1.0)` throw, and a throw inside compose
  // takes the whole timeline with it.
  final left = rect.left.clamp(0.0, 1.0 - _kMinExtent).toDouble();
  final top = rect.top.clamp(0.0, 1.0 - _kMinExtent).toDouble();
  final right = rect.right.clamp(left + _kMinExtent, 1.0).toDouble();
  final bottom = rect.bottom.clamp(top + _kMinExtent, 1.0).toDouble();
  return Rect.fromLTRB(left, top, right, bottom);
}

/// True when a rect covers essentially the whole frame, so it can be skipped.
bool isFullFrame(Rect rect) {
  return rect.left.abs() < _kEpsilon &&
      rect.top.abs() < _kEpsilon &&
      (1.0 - rect.right).abs() < _kEpsilon &&
      (1.0 - rect.bottom).abs() < _kEpsilon;
}

/// The portion of the source frame the canvas shows, in normalised source
/// coordinates.
///
/// [previewCanvasSize] is needed because pan is stored in preview-canvas
/// pixels; without it, panning is ignored rather than applied at the wrong
/// scale.
/// [inner], expressed as fractions **of [outer]**, resolved to fractions of
/// the whole frame.
///
/// A clip's own crop is drawn over what the project crop already shows, so it
/// is a sub-rectangle of that rect rather than of the source frame: cropping a
/// clip to its middle half means the middle half *of what the project lets
/// through*. Composing here — and then handing the result to
/// [resolveContentRect] for zoom and pan — keeps geometry in one place, which
/// is what the constraint on this file demands.
///
/// Both inputs are clamped first, so a hand-edited draft cannot produce a rect
/// outside the frame or one that is inside-out.
Rect composeCropRects(Rect outer, Rect inner) {
  final o = clampNormalizedRect(outer);
  final i = clampNormalizedRect(inner);
  return Rect.fromLTWH(
    o.left + i.left * o.width,
    o.top + i.top * o.height,
    i.width * o.width,
    i.height * o.height,
  );
}

Rect resolveContentRect({
  required Rect cropRect,
  required double videoScale,
  required Offset videoPan,
  Size? previewCanvasSize,
}) {
  final base = clampNormalizedRect(cropRect);

  final canvas = previewCanvasSize;
  if (videoScale <= 1.0 + _kEpsilon ||
      canvas == null ||
      canvas.width <= 0 ||
      canvas.height <= 0) {
    return base;
  }

  // Zooming in shows less of the frame: the sampled rect shrinks about the
  // point the user panned to.
  final scale = videoScale.clamp(1.0, _kMaxZoom);
  final width = base.width / scale;
  final height = base.height / scale;

  final centerX =
      base.center.dx - (videoPan.dx * base.width) / (canvas.width * scale);
  final centerY =
      base.center.dy - (videoPan.dy * base.height) / (canvas.height * scale);

  final left = (centerX - width / 2)
      .clamp(base.left, base.right - width)
      .toDouble();
  final top = (centerY - height / 2)
      .clamp(base.top, base.bottom - height)
      .toDouble();

  return clampNormalizedRect(Rect.fromLTWH(left, top, width, height));
}

/// Aspect ratio of the visible content once [contentRect] is applied to a
/// source of [sourceSize].
///
/// Returns null when it cannot be determined, so callers fall back rather than
/// dividing by zero.
double? contentAspectRatio(Rect contentRect, Size sourceSize) {
  if (sourceSize.height <= 0 || contentRect.height <= 0) return null;
  final width = contentRect.width * sourceSize.width;
  final height = contentRect.height * sourceSize.height;
  if (height <= 0) return null;
  return width / height;
}

/// Where a picture of [contentAspect] sits inside a canvas box of
/// [canvasSize] once scaled to *contain* — full width with bars above and
/// below when it is wider than the box, full height with bars either side when
/// taller. The Dart half of Kotlin's `LaneFit.of`, in box pixels rather than
/// canvas fractions.
///
/// The clip-crop editor draws its handles over this rect: a clip's crop is a
/// fraction of the clip's *picture*, and handles spread over the whole box
/// would map a rectangle drawn on the letterbox bars to a region of the source
/// the user never pointed at. An unknown shape (`null` or `<= 0`) fills the
/// box, the same rule the engine follows for an unprobed clip.
Rect fittedFrameRect({
  required double? contentAspect,
  required Size canvasSize,
}) {
  final whole = Offset.zero & canvasSize;
  if (contentAspect == null || contentAspect <= 0) return whole;
  if (canvasSize.width <= 0 || canvasSize.height <= 0) return whole;
  final canvasAspect = canvasSize.width / canvasSize.height;
  if (contentAspect > canvasAspect) {
    final height = canvasSize.width / contentAspect;
    return Rect.fromLTWH(
        0, (canvasSize.height - height) / 2, canvasSize.width, height);
  }
  final width = canvasSize.height * contentAspect;
  return Rect.fromLTWH(
      (canvasSize.width - width) / 2, 0, width, canvasSize.height);
}

const double _kEpsilon = 0.0001;
const double _kMinExtent = 0.0001;
const double _kMaxZoom = 5.0;
