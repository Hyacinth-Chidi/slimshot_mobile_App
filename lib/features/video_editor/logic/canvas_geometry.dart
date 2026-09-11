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
  final left = rect.left.clamp(0.0, 1.0).toDouble();
  final top = rect.top.clamp(0.0, 1.0).toDouble();
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

const double _kEpsilon = 0.0001;
const double _kMinExtent = 0.0001;
const double _kMaxZoom = 5.0;
