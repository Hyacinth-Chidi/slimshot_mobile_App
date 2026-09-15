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
/// Two deliberate absences. `speed` changes the clip's own duration, so a
/// keyframe on it would move every other keyframe's instant while it was being
/// edited; CapCut gives speed its own curve tool for the same reason. Filter
/// intensity is a colour matrix resolved per lane *before* the blend, on a path
/// with no per-frame parameter hook — keyframing it is a real feature, but a
/// different one.
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
