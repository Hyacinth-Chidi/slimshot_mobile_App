import 'dart:math' as math;

/// The timeline's scale for a short project, in pixels per second — the scale
/// it had before it could zoom, and the closest it opens. A longer project
/// opens fitted, at [minPixelsPerSecond].
const double kDefaultPixelsPerSecond = 50.0;

/// The furthest a pinch zooms in: ~20px per frame at 30fps, so a cut or a
/// trim can land on an exact frame.
const double kMaxPixelsPerSecond = 600.0;

/// How much of the viewport the whole project fills at the furthest zoom out.
const double kZoomOutFitFraction = 0.8;

/// The closest two ruler labels may sit.
const double kRulerMinLabelSpacingPx = 70.0;

/// The furthest a pinch zooms out, and the scale the timeline opens at: until
/// the whole project fills [kZoomOutFitFraction] of the viewport, and never
/// closer than the default — a short project has nothing to zoom out to.
double minPixelsPerSecond({
  required double viewportWidth,
  required double durationSeconds,
}) {
  if (durationSeconds <= 0 || viewportWidth <= 0) return kDefaultPixelsPerSecond;
  return math.min(
    kDefaultPixelsPerSecond,
    viewportWidth * kZoomOutFitFraction / durationSeconds,
  );
}

/// The scale a pinch gives: the scale it [start]ed from times the fingers'
/// [scale], held between [min] and [kMaxPixelsPerSecond].
double zoomedPixelsPerSecond({
  required double start,
  required double scale,
  required double min,
}) =>
    (start * scale).clamp(min, kMaxPixelsPerSecond).toDouble();

/// Ruler steps, finest first, in seconds.
const List<double> _kRulerSteps = [
  0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600,
];

/// The ruler's label interval at [pixelsPerSecond]: the finest step whose
/// labels sit at least [kRulerMinLabelSpacingPx] apart. Chosen from the zoom,
/// not the project's length, so labels never crowd or thin out as it changes.
double rulerTickInterval(double pixelsPerSecond) {
  for (final step in _kRulerSteps) {
    if (step * pixelsPerSecond >= kRulerMinLabelSpacingPx) return step;
  }
  return _kRulerSteps.last;
}
