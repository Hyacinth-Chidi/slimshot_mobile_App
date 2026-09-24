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
///
/// **What a diamond does is not defined here.** Every function below is a thin
/// adapter over `keyframe_core.dart`, which overlays share, so a diamond obeys
/// one set of rules on a clip's filmstrip and on an overlay's bar. This file
/// only says which parameters a clip has and how to read and write them.
library;

import '../../models/video_segment.dart';
import 'animatable_double.dart';
import 'keyframe_core.dart';

export 'keyframe_core.dart' show KeyframeParams, kKeyframeMatchProgress;

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
  canvasRotation,
  volume,
  effectIntensity,

  /// How present the clip is, 0..1 — a mix toward the letterbox fill in the
  /// engine, never alpha. The seventh property; a fade is two diamonds.
  opacity,
}

/// The parameter [p] names on [s].
AnimatableDouble clipParameter(VideoSegment s, ClipProperty p) {
  switch (p) {
    case ClipProperty.canvasScale:
      return s.canvasScale;
    case ClipProperty.canvasOffsetX:
      return s.canvasOffsetX;
    case ClipProperty.canvasOffsetY:
      return s.canvasOffsetY;
    case ClipProperty.canvasRotation:
      return s.canvasRotation;
    case ClipProperty.volume:
      return s.volume;
    case ClipProperty.effectIntensity:
      return s.effectIntensity;
    case ClipProperty.opacity:
      return s.opacity;
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
    case ClipProperty.canvasRotation:
      return s.copyWith(canvasRotation: v);
    case ClipProperty.volume:
      return s.copyWith(volume: v);
    case ClipProperty.effectIntensity:
      return s.copyWith(effectIntensity: v);
    case ClipProperty.opacity:
      return s.copyWith(opacity: v);
  }
}

/// The clip's keyframable parameters, in [ClipProperty] order.
KeyframeParams<ClipProperty> clipParams(VideoSegment s) =>
    {for (final p in ClipProperty.values) p: clipParameter(s, p)};

/// [s] with every parameter in [params] written back.
VideoSegment withClipParams(
  VideoSegment s,
  KeyframeParams<ClipProperty> params,
) {
  var out = s;
  for (final e in params.entries) {
    out = withClipParameter(out, e.key, e.value);
  }
  return out;
}

/// [s] after [edit] — or [s] itself when [edit] changed nothing, so a caller
/// comparing by identity can tell.
VideoSegment _applied(
  VideoSegment s,
  KeyframeParams<ClipProperty> Function(KeyframeParams<ClipProperty>) edit,
) {
  final params = clipParams(s);
  final out = edit(params);
  return identical(out, params) ? s : withClipParams(s, out);
}

/// Every instant this clip has a diamond at — see [keyframeProgressesIn].
List<double> keyframeProgresses(VideoSegment s) =>
    keyframeProgressesIn(clipParams(s));

/// The diamond nearest [progress] within [tolerance] — see
/// [keyframeProgressNearIn].
double? keyframeProgressNear(
  VideoSegment s,
  double progress,
  double tolerance,
) =>
    keyframeProgressNearIn(clipParams(s), progress, tolerance);

/// Pins every property at the value it already resolves to at [progress] —
/// see [captureKeyframeIn].
VideoSegment captureKeyframe(VideoSegment s, double progress) =>
    _applied(s, (p) => captureKeyframeIn(p, progress));

/// Takes the diamond nearest [progress] off every property; the last one
/// hands its value back as the base — see [removeKeyframeIn].
VideoSegment removeKeyframe(
  VideoSegment s,
  double progress,
  double tolerance,
) =>
    _applied(s, (p) => removeKeyframeIn(p, progress, tolerance));

/// Slides the diamond nearest [from] to [to] on every property. Returns [s]
/// itself when refused — see [moveKeyframeIn].
VideoSegment moveKeyframe(
  VideoSegment s,
  double from,
  double to,
  double tolerance,
) =>
    _applied(s, (p) => moveKeyframeIn(p, from, to, tolerance) ?? p);

/// Which diamond's outgoing curve the curve control edits — see
/// [keyframeCurveTargetIn].
double? keyframeCurveTarget(
  VideoSegment s,
  double progress,
  double tolerance,
) =>
    keyframeCurveTargetIn(clipParams(s), progress, tolerance);

/// Sets the curve on the segment the playhead is inside, never placing a
/// diamond — see [setKeyframeCurveIn].
VideoSegment setKeyframeCurve(
  VideoSegment s,
  double progress,
  double tolerance,
  KeyframeInterpolation curve,
) =>
    _applied(s, (p) => setKeyframeCurveIn(p, progress, tolerance, curve));

/// Re-eases the diamond nearest [progress] — see [setKeyframeEasingIn].
VideoSegment setKeyframeEasing(
  VideoSegment s,
  double progress,
  double tolerance,
  KeyframeInterpolation easing,
) =>
    _applied(s, (p) => setKeyframeEasingIn(p, progress, tolerance, easing));
