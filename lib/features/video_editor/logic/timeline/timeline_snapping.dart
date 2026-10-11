import 'lane_layout.dart';
import 'timeline_geometry.dart';

/// Where a snap landed: the adjusted [value], and the timeline instant it was
/// pulled to ([guide], for the guide line), or null when nothing was in reach.
class SnapResult {
  const SnapResult(this.value, this.guide);

  final double value;
  final double? guide;
}

/// The reach of a snap in timeline seconds at [pixelsPerSecond]: a fixed
/// [kSnapTolerancePx] of screen, so it feels the same at every zoom — and
/// zoomed in, something can still sit a frame off a cut on purpose.
double snapToleranceSeconds(double pixelsPerSecond) =>
    kSnapTolerancePx / pixelsPerSecond;

/// Everything on the timeline that a move or a trim is pulled to, in timeline
/// seconds, sorted and without repeats: 0:00, the playhead, the cuts between
/// clips ([clipBoundaries]) and the start and end of every item on every lane
/// — except [excludeId], the item being moved, which must not snap to itself.
List<double> timelineSnapTargets({
  required double playheadSeconds,
  required List<double> clipBoundaries,
  required Iterable<LaneSpan> items,
  String? excludeId,
}) {
  final targets = <double>{
    0.0,
    playheadSeconds,
    ...clipBoundaries,
    for (final item in items)
      if (item.id != excludeId) ...[item.start, item.end],
  }.toList()
    ..sort();
  return targets;
}

/// A span of [length] being moved with its start at [start]: whichever of its
/// two edges is nearer a target within [tolerance] lands on it, and the span
/// moves with it. Never before 0:00.
SnapResult snapMovingSpan({
  required double start,
  required double length,
  required List<double> targets,
  required double tolerance,
}) {
  double? bestShift;
  double? bestTarget;
  var bestDistance = double.infinity;
  void consider(double edge) {
    for (final target in targets) {
      final distance = (target - edge).abs();
      if (distance <= tolerance && distance < bestDistance) {
        bestDistance = distance;
        bestShift = target - edge;
        bestTarget = target;
      }
    }
  }

  consider(start);
  consider(start + length);
  if (bestShift == null) return SnapResult(start, null);
  final moved = start + bestShift!;
  if (moved < 0) return SnapResult(start, null);
  return SnapResult(moved, bestTarget);
}

/// One edge at [value] — a trim — pulled onto the nearest target within
/// [tolerance].
SnapResult snapEdge({
  required double value,
  required List<double> targets,
  required double tolerance,
}) {
  final snapped = snapToNearest(value, targets, tolerance);
  return SnapResult(snapped, snapped == value && !targets.contains(value) ? null : snapped);
}
