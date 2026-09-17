/// Where each segment sits on the timeline, and how long the whole thing runs.
///
/// A transition is an **overlap**: the next clip starts before the previous one
/// ends, so the timeline is shorter than the sum of the clip durations by the
/// total of the transition durations. Anything that lays out, scrubs, or
/// measures the timeline has to go through here, or the playhead and the clips
/// drift apart as soon as a transition is applied.
///
/// This mirrors `VideoEditorTimelineComposer`, which produces the same geometry
/// for the native engine. The two must agree.
library;

import '../../models/video_segment.dart';
import '../transitions/transition_catalog.dart';

/// Effective transition duration leaving each segment, `null` for a hard cut.
///
/// Index `i` is the transition from segment `i` into segment `i + 1`. A segment
/// that is last, carries no transition, or names a transition this build no
/// longer supports produces `null`.
List<double?> segmentTransitionDurations(List<VideoSegment> segments) {
  final durations = List<double?>.filled(segments.length, null);

  for (var index = 0; index < segments.length - 1; index++) {
    final segment = segments[index];
    if (!EditorTransition.isSupported(segment.transitionType)) continue;

    final next = segments[index + 1];
    if (segment.duration <= 0 || next.duration <= 0) continue;

    durations[index] = resolveTransitionDuration(
      requestedSeconds: segment.transitionDuration ?? kDefaultTransitionSeconds,
      leftClipDuration: segment.duration,
      rightClipDuration: next.duration,
    );
  }

  return durations;
}

/// Timeline start time of each segment, accounting for transition overlaps.
List<double> segmentTimelineStarts(List<VideoSegment> segments) {
  final overlaps = segmentTransitionDurations(segments);
  final starts = List<double>.filled(segments.length, 0.0);

  var cursor = 0.0;
  for (var index = 0; index < segments.length; index++) {
    starts[index] = cursor;
    cursor += segments[index].duration - (overlaps[index] ?? 0.0);
  }

  return starts;
}

/// How much of each segment the timeline should *draw*, in seconds.
///
/// A clip that transitions into the next one overlaps it in time, so drawing
/// its full duration would stack the two on top of each other. Each box instead
/// ends where the next clip begins: boxes abut, the seam is exactly where the
/// transition sits, and every x on the timeline stays
/// `timelineSeconds * pixelsPerSecond` — so clips, the transition marker, trim
/// handles and the playhead all agree.
///
/// The overlapped tail is not lost, only shared: both clips are still decoding
/// through it, and the renderer blends them.
List<double> segmentDisplayDurations(List<VideoSegment> segments) {
  if (segments.isEmpty) return const [];

  final starts = segmentTimelineStarts(segments);
  return [
    for (var index = 0; index < segments.length; index++)
      if (index == segments.length - 1)
        segments[index].duration
      else
        (starts[index + 1] - starts[index])
            .clamp(0.0, segments[index].duration)
            .toDouble(),
  ];
}

/// Total video duration, shortened by every transition overlap.
double videoTimelineDuration(List<VideoSegment> segments) {
  if (segments.isEmpty) return 0.0;
  final starts = segmentTimelineStarts(segments);
  return starts.last + segments.last.duration;
}

/// Index of the segment that owns a timeline instant, or `-1` if there are none.
///
/// Inside a transition overlap two segments are live at once; this resolves to
/// the **incoming** one, matching [timelineTimeToSourceTime] and the rule the
/// native engine uses to decide which clip owns an instant.
///
/// Anything acting *on a clip* at the playhead — splitting above all — has to
/// find the clip this way. A timeline instant is not a source instant, and the
/// two only coincide for a single untrimmed clip that starts at zero.
int segmentIndexAt(double timelineSeconds, List<VideoSegment> segments) {
  if (segments.isEmpty) return -1;

  final starts = segmentTimelineStarts(segments);
  for (var index = segments.length - 1; index >= 0; index--) {
    if (timelineSeconds >= starts[index] || index == 0) return index;
  }
  return 0;
}

/// How close, in timeline **pixels**, a scrub release or a trim handle has to
/// land to a snap point to be pulled onto it. 8px at the timeline's 50px/s is
/// 0.16s: close enough to feel magnetic, far enough not to steal an intended
/// near miss. Pixels, not seconds, because the finger's precision is in pixels
/// whatever the zoom.
const double kSnapTolerancePx = 8.0;

/// [value] pulled onto the nearest of [candidates] when one lies within
/// [tolerance]; otherwise [value] itself. A tie goes to the earlier candidate.
///
/// Unit-agnostic on purpose: a scrub release measures in timeline seconds, a
/// trim handle in source seconds, and one helper serves both so the two feel
/// identical under the finger.
double snapToNearest(
  double value,
  Iterable<double> candidates,
  double tolerance,
) {
  double? best;
  var bestDistance = double.infinity;
  for (final candidate in candidates) {
    final distance = (candidate - value).abs();
    if (distance <= tolerance && distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best ?? value;
}

/// Every instant a scrub wants to land on: the start of each clip and the end
/// of the last, in timeline seconds — the seams, with transition overlaps
/// already applied, so a release near a seam parks the playhead exactly where
/// the cut is drawn.
List<double> clipBoundaryTimes(List<VideoSegment> segments) {
  if (segments.isEmpty) return const [];
  return [
    ...segmentTimelineStarts(segments),
    videoTimelineDuration(segments),
  ];
}

/// Maps a timeline instant onto a position in the source media.
///
/// Inside an overlap two segments are live at once; this resolves to the
/// **incoming** one, matching how the native engine decides which clip owns an
/// instant.
double timelineTimeToSourceTime(
  double timelineSeconds,
  List<VideoSegment> segments,
) {
  if (segments.isEmpty) return timelineSeconds;

  final starts = segmentTimelineStarts(segments);

  for (var index = segments.length - 1; index >= 0; index--) {
    final segment = segments[index];
    final start = starts[index];
    final isFirst = index == 0;

    if (timelineSeconds >= start || isFirst) {
      // The segment's own mapping — the one the filmstrip and playback use —
      // so a speed curve, reversal and a trim all resolve in exactly one place.
      return segment.sourceAtOffset(timelineSeconds - start);
    }
  }

  final first = segments.first;
  return first.isReversed ? first.sourceEnd : first.sourceStart;
}
