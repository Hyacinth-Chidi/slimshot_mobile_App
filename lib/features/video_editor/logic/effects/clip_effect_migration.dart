/// Turns the effects old drafts stored on their clips into effect bars.
///
/// Before the effects track a clip carried at most one effect
/// (`effectId` / `effectIntensity` in its JSON), drawn wherever that clip was
/// on screen — except inside a transition window, which the **outgoing**
/// clip's effect owned. A bar must look the same, so it covers exactly the
/// stretch where the clip's effect showed: from the end of the window into the
/// clip (its start, at a plain cut) to the clip's end.
///
/// The strength comes across whole — base value and envelope — and every
/// keyframe is moved to the **same timeline instant** it marked, re-expressed
/// on the bar's own 0..1. Keyframes that fall before the bar's start (inside
/// the window the clip did not own) are dropped, and one is pinned at the
/// bar's start carrying the value there, so the curve the user sees on the
/// picture is the one they had.
///
/// One accepted difference: a *timed* effect on a clip entered through a
/// transition used to join its intro part-way through; its bar plays the intro
/// whole from the window's end.
library;

import '../../models/effect_bar_model.dart';
import '../../models/video_segment.dart';
import '../animation/animatable_double.dart';
import '../timeline/lane_layout.dart';
import '../timeline/timeline_geometry.dart';
import 'effect_catalog.dart';

/// The bars [rawSegments] — the draft's clip JSON, which still holds the old
/// effect fields — call for, on lanes free of [occupied] and of each other.
///
/// [segments] are the same clips parsed, for their timeline geometry; a raw
/// clip is matched to its parsed one by id.
List<EffectBarModel> migrateClipEffects({
  required List<Map<String, dynamic>> rawSegments,
  required List<VideoSegment> segments,
  required List<LaneSpan> occupied,
}) {
  final rawById = {
    for (final raw in rawSegments)
      if (raw['id'] is String) raw['id'] as String: raw,
  };
  final starts = segmentTimelineStarts(segments);
  final overlaps = segmentTransitionDurations(segments);
  final spans = [...occupied];
  final bars = <EffectBarModel>[];

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final raw = rawById[segment.id];
    final effectId = raw?['effectId'];
    if (effectId is! String || effectId.isEmpty || effectId == 'none') continue;

    final clipStart = starts[i];
    final clipLength = segment.duration;
    final window = i > 0 ? (overlaps[i - 1] ?? 0.0) : 0.0;
    final start = clipStart + window;
    final end = clipStart + clipLength;
    if (end - start <= 0) continue;

    final intensity = _reTimed(
      AnimatableDouble.fromJson(
        raw!['effectIntensity'],
        fallback: defaultEffectIntensity,
      ),
      clipStart: clipStart,
      clipLength: clipLength,
      barStart: start,
      barEnd: end,
    );

    final lane = firstFreeLane(spans, start, end);
    final id = 'effect_${segment.id}';
    bars.add(EffectBarModel(
      id: id,
      effectId: effectId,
      start: start,
      end: end,
      laneIndex: lane,
      intensity: intensity,
    ));
    spans.add(LaneSpan(id: id, lane: lane, start: start, end: end));
  }
  return bars;
}

/// [param]'s keyframes, moved from the clip's 0..1 to the bar's, each on the
/// instant it marked. Flat or enveloped parameters come back unchanged.
AnimatableDouble _reTimed(
  AnimatableDouble param, {
  required double clipStart,
  required double clipLength,
  required double barStart,
  required double barEnd,
}) {
  if (param.keyframes.isEmpty || clipLength <= 0) return param;
  final barLength = barEnd - barStart;
  double toBar(double clipProgress) =>
      (clipStart + clipProgress * clipLength - barStart) / barLength;

  const epsilon = 1e-9;
  final kept = <Keyframe>[];
  var dropped = false;
  for (final k in param.keyframes) {
    final p = toBar(k.progress);
    if (p < -epsilon) {
      dropped = true;
      continue;
    }
    kept.add(Keyframe(
      progress: p.clamp(0.0, 1.0).toDouble(),
      value: k.value,
      interpolation: k.interpolation,
    ));
  }
  if (dropped && !kept.any((k) => k.progress.abs() <= epsilon)) {
    final atStart = param.resolveAt((barStart - clipStart) / clipLength);
    kept.add(Keyframe(progress: 0, value: atStart));
  }
  return AnimatableDouble.sorted(
    baseValue: param.baseValue,
    envelope: param.envelope,
    keyframes: kept,
  );
}
