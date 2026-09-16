/// The clip properties a diamond pins, and the pure functions that move
/// diamonds across all of them at once.
///
/// **A keyframe is an instant, not a parameter.** A diamond at progress `p`
/// means every property in [ClipProperty] carries a keyframe at `p`. That is
/// what makes one diamond on the filmstrip an honest picture of the clip's
/// state at that moment, and what lets the plus button in the playback bar be
/// the only keyframe control in the app.
///
/// The alternative — a diamond per property — needs a property picker before a
/// user can place anything, and a row per property under the clip to show what
/// they placed. That is the design that was built, rejected and deleted; see
/// `docs/dead-ends.md`.
///
/// **Pure: a segment in, a segment out.** Nothing here knows about the
/// playhead, the clock, Riverpod or seconds. `VideoEditorNotifier` owns the
/// decision of *when* an edit becomes a keyframe, and the timeline owns where a
/// diamond is drawn.
library;

import '../../models/video_segment.dart';
import 'animatable_double.dart';

/// Every property a diamond pins.
///
/// **Adding a value here is all it takes** for a property to be captured,
/// removed, eased and drawn — which is the point of naming them in one place.
///
/// **`speed` cannot join this list, and the reason is structural rather than a
/// matter of effort.** Every other property here is read *at* a progress; speed
/// decides what progress even means. `VideoSegment.duration` is
/// `(sourceEnd - sourceStart) / speed`, and `clipProgressAt` divides by that
/// duration — so a keyframed speed would make progress a function of itself,
/// and every diamond on the clip would slide as the speed curve was edited.
/// The timeline's own geometry (`segmentTimelineStarts`,
/// `timelineTimeToSourceTime`) multiplies by a scalar speed too, as does
/// `Lane.applySpeed` in the engine.
///
/// A ramp is a real feature and it is a **different** one: it needs
/// source-time to be the integral of the speed curve, which is its own model,
/// its own Kotlin port and its own UI. That is why CapCut ships speed as a
/// separate curve tool rather than as a keyframable parameter, and why putting
/// it here would produce diamonds that move while you edit them.
///
/// Filter intensity is absent for a smaller reason: it is a colour matrix
/// resolved per lane *before* the blend, on a path with no per-frame parameter
/// hook. Keyframing it is a genuine addition, just not a free one.
enum ClipProperty {
  canvasScale,
  canvasOffsetX,
  canvasOffsetY,
  volume,
  effectIntensity,
}

/// Two progresses closer than this are the same diamond.
///
/// **Not the tap tolerance.** How close a *finger* has to be is a question
/// about screens and clip lengths, is measured in seconds, and lives with the
/// notifier. This is only about floating-point identity between a progress
/// stored in a keyframe and one recomputed from a playhead position — the same
/// instant arrived at by two routes.
const double kKeyframeMatchProgress = 0.0005;

/// The parameter [p] names on [s].
AnimatableDouble clipParameter(VideoSegment s, ClipProperty p) {
  switch (p) {
    case ClipProperty.canvasScale:
      return s.canvasScale;
    case ClipProperty.canvasOffsetX:
      return s.canvasOffsetX;
    case ClipProperty.canvasOffsetY:
      return s.canvasOffsetY;
    case ClipProperty.volume:
      return s.volume;
    case ClipProperty.effectIntensity:
      return s.effectIntensity;
  }
}

/// [s] with the parameter [p] names replaced by [v].
VideoSegment withClipParameter(
  VideoSegment s,
  ClipProperty p,
  AnimatableDouble v,
) {
  switch (p) {
    case ClipProperty.canvasScale:
      return s.copyWith(canvasScale: v);
    case ClipProperty.canvasOffsetX:
      return s.copyWith(canvasOffsetX: v);
    case ClipProperty.canvasOffsetY:
      return s.copyWith(canvasOffsetY: v);
    case ClipProperty.volume:
      return s.copyWith(volume: v);
    case ClipProperty.effectIntensity:
      return s.copyWith(effectIntensity: v);
  }
}

/// Every instant this clip has a diamond at, sorted and de-duplicated.
///
/// The **union** across properties rather than any one property's list. The
/// notifier writes all of them together, but a draft can arrive hand-edited or
/// from a build that wrote fewer, and a diamond a user can see but not remove
/// is worse than one drawn from a partial row.
List<double> keyframeProgresses(VideoSegment s) {
  final out = <double>[];
  for (final property in ClipProperty.values) {
    for (final k in clipParameter(s, property).keyframes) {
      if (!out.any((v) => (v - k.progress).abs() <= kKeyframeMatchProgress)) {
        out.add(k.progress);
      }
    }
  }
  out.sort();
  return out;
}

/// The diamond nearest [progress] within [tolerance], or null.
///
/// Nearest rather than first: two diamonds can both be in range when they were
/// placed close together, and "the one I am standing on" is the nearer.
double? keyframeProgressNear(
  VideoSegment s,
  double progress,
  double tolerance,
) {
  double? best;
  var bestDistance = double.infinity;
  for (final p in keyframeProgresses(s)) {
    final d = (p - progress).abs();
    if (d <= tolerance && d < bestDistance) {
      best = p;
      bestDistance = d;
    }
  }
  return best;
}

/// Pins every property at the value it **already resolves to** at [progress].
///
/// Capturing the *resolved* value is what makes placing a diamond invisible:
/// the frame on screen does not change, in the preview or in the file.
/// Capturing the base value instead would snap an animated property back to its
/// base the moment a second diamond was placed — and a control that changes the
/// picture when the user only meant to mark a moment is the fastest way to make
/// the feature feel broken.
///
/// A diamond already at [progress] is replaced rather than duplicated, so
/// capturing twice at one instant is idempotent.
VideoSegment captureKeyframe(VideoSegment s, double progress) {
  var out = s;
  for (final property in ClipProperty.values) {
    final param = clipParameter(out, property);
    final value = param.resolveAt(progress);
    final kept = [
      for (final k in param.keyframes)
        if ((k.progress - progress).abs() > kKeyframeMatchProgress) k,
    ];
    out = withClipParameter(
      out,
      property,
      AnimatableDouble.sorted(
        baseValue: param.baseValue,
        envelope: param.envelope,
        keyframes: [
          ...kept,
          // Linear, so the easing sheet opens showing "None" and tells the
          // truth about the diamond just placed.
          Keyframe(
            progress: progress,
            value: value,
            interpolation: KeyframeInterpolation.linear,
          ),
        ],
      ),
    );
  }
  return out;
}

/// Takes the diamond nearest [progress] off every property.
///
/// **The last diamond hands its value back as the base**, so the frame the user
/// is looking at when they remove it is the frame that stays. Dropping to the
/// old base would jump the picture to a value they may have set minutes ago,
/// which reads as the editor undoing something it was not asked to undo.
///
/// A [progress] with no diamond near it returns [s] unchanged.
VideoSegment removeKeyframe(
  VideoSegment s,
  double progress,
  double tolerance,
) {
  final target = keyframeProgressNear(s, progress, tolerance);
  if (target == null) return s;

  var out = s;
  for (final property in ClipProperty.values) {
    final param = clipParameter(out, property);
    final removed = [
      for (final k in param.keyframes)
        if ((k.progress - target).abs() <= kKeyframeMatchProgress) k,
    ];
    final kept = [
      for (final k in param.keyframes)
        if ((k.progress - target).abs() > kKeyframeMatchProgress) k,
    ];
    out = withClipParameter(
      out,
      property,
      AnimatableDouble.sorted(
        baseValue: kept.isEmpty && removed.isNotEmpty
            ? removed.first.value
            : param.baseValue,
        envelope: param.envelope,
        keyframes: kept,
      ),
    );
  }
  return out;
}

/// Which diamond's outgoing curve the curve control edits at [progress], or
/// null when there is nothing to ease.
///
/// **A curve shapes travel between two diamonds**, and the interpolation lives
/// on the diamond a segment *starts* at. So the target is the latest diamond at
/// or before the playhead — provided a later one exists to travel towards.
///
/// Null in three cases, and each is a real "nothing to shape here":
///
/// - **Fewer than two diamonds.** One point is a value held across the whole
///   clip; there is no travel, and a curve would change nothing.
/// - **Before the first diamond.** The value holds back to the clip's start.
/// - **After the last.** It holds to the end.
///
/// The one concession to the finger: **on the last diamond the target is the
/// segment arriving at it**, not the nothing that follows. A user who taps the
/// final diamond and reaches for the curve icon means the curve they can see,
/// and an icon that went inert the moment they landed on a diamond would read
/// as broken.
double? keyframeCurveTarget(
  VideoSegment s,
  double progress,
  double tolerance,
) {
  final all = keyframeProgresses(s);
  // A curve needs two points to run between.
  if (all.length < 2) return null;

  final onDiamond = keyframeProgressNear(s, progress, tolerance);
  if (onDiamond != null) {
    final index = all.indexWhere((p) => (p - onDiamond).abs() <= kKeyframeMatchProgress);
    // On the last diamond, edit the segment that arrives at it; on any other,
    // the one that leaves it.
    if (index == all.length - 1) return all[index - 1];
    return all[index];
  }

  // Between diamonds: the segment the playhead is inside.
  if (progress < all.first || progress > all.last) return null;
  double? target;
  for (final p in all) {
    if (p <= progress) target = p;
  }
  return target;
}

/// Sets the curve on the segment the playhead is inside, on every property.
///
/// **Never places a diamond.** That is the whole distinction from
/// [captureKeyframe]: the plus button creates instants, the curve control
/// shapes travel that already exists. A curve picker that quietly added a
/// keyframe was the device-reported fault — the user tapped it expecting to
/// choose a shape and got a new point on their timeline.
///
/// No target — fewer than two diamonds, or the playhead outside them — returns
/// [s] unchanged.
VideoSegment setKeyframeCurve(
  VideoSegment s,
  double progress,
  double tolerance,
  KeyframeInterpolation curve,
) {
  final target = keyframeCurveTarget(s, progress, tolerance);
  if (target == null) return s;
  return setKeyframeEasing(s, target, tolerance, curve);
}

/// Re-eases the diamond nearest [progress], on every property.
///
/// The interpolation belongs to the segment that *starts* at a keyframe, so
/// this changes how the value travels from here to the next diamond — which is
/// what the easing sheet's cells describe.
VideoSegment setKeyframeEasing(
  VideoSegment s,
  double progress,
  double tolerance,
  KeyframeInterpolation easing,
) {
  final target = keyframeProgressNear(s, progress, tolerance);
  if (target == null) return s;

  var out = s;
  for (final property in ClipProperty.values) {
    final param = clipParameter(out, property);
    out = withClipParameter(
      out,
      property,
      AnimatableDouble.sorted(
        baseValue: param.baseValue,
        envelope: param.envelope,
        keyframes: [
          for (final k in param.keyframes)
            if ((k.progress - target).abs() <= kKeyframeMatchProgress)
              Keyframe(
                progress: k.progress,
                value: k.value,
                interpolation: easing,
              )
            else
              k,
        ],
      ),
    );
  }
  return out;
}
