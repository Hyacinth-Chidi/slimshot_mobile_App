/// What a diamond does, for any set of named keyframable parameters.
///
/// **A keyframe is an instant, not a parameter.** A diamond at progress `p`
/// means every parameter in the set carries a keyframe at `p`. That is what
/// makes one mark on the timeline an honest picture of an item's state at that
/// moment, and what lets one plus button serve every property with no picker.
///
/// Clips (`clip_keyframes.dart`) and overlays (`overlay_keyframes.dart`) are
/// thin adapters over these functions: each reads its parameters into a
/// [KeyframeParams] map, applies one of these, and writes the map back. One
/// set of rules for both, so a diamond behaves identically on a clip's
/// filmstrip and on an overlay's bar.
///
/// **Pure: a map in, a map out.** Nothing here knows about the playhead, the
/// clock, Riverpod, seconds or what an item is. Every function returns **the
/// same map instance** when it changes nothing, so an adapter can hand back
/// its own input unchanged — and a caller can tell a refused edit from a done
/// one by identity.
library;

import 'animatable_double.dart';

/// Two progresses closer than this are the same diamond.
///
/// **Not the tap tolerance.** How close a *finger* has to be is a question
/// about screens and item lengths, is measured in seconds, and lives with the
/// state. This is only about floating-point identity between a progress
/// stored in a keyframe and one recomputed from a playhead position — the same
/// instant arrived at by two routes.
const double kKeyframeMatchProgress = 0.0005;

/// An item's keyframable parameters, by name.
///
/// Iteration order is the order the adapter built the map in (its enum's
/// declaration order), which keeps every write deterministic.
typedef KeyframeParams<P> = Map<P, AnimatableDouble>;

bool _sameInstant(double a, double b) =>
    (a - b).abs() <= kKeyframeMatchProgress;

/// Whether any parameter carries a keyframe.
///
/// **Envelopes do not count.** A catalog envelope is not the user placing
/// anything, so an item shaped only by one is treated as untouched by the edit
/// rule.
bool hasKeyframesIn<P>(KeyframeParams<P> params) =>
    params.values.any((p) => p.keyframes.isNotEmpty);

/// Every instant the set has a diamond at, sorted and de-duplicated.
///
/// The **union** across parameters rather than any one parameter's list. The
/// edits write all of them together, but a draft can arrive hand-edited or
/// from a build that wrote fewer, and a diamond a user can see but not remove
/// is worse than one drawn from a partial row.
List<double> keyframeProgressesIn<P>(KeyframeParams<P> params) {
  final out = <double>[];
  for (final param in params.values) {
    for (final k in param.keyframes) {
      if (!out.any((v) => _sameInstant(v, k.progress))) out.add(k.progress);
    }
  }
  out.sort();
  return out;
}

/// The diamond nearest [progress] within [tolerance], or null.
///
/// Nearest rather than first: two diamonds can both be in range when they were
/// placed close together, and "the one I am standing on" is the nearer.
double? keyframeProgressNearIn<P>(
  KeyframeParams<P> params,
  double progress,
  double tolerance,
) {
  double? best;
  var bestDistance = double.infinity;
  for (final p in keyframeProgressesIn(params)) {
    final d = (p - progress).abs();
    if (d <= tolerance && d < bestDistance) {
      best = p;
      bestDistance = d;
    }
  }
  return best;
}

/// Pins every parameter at the value it **already resolves to** at
/// [progress].
///
/// Capturing the *resolved* value is what makes placing a diamond invisible:
/// the frame on screen does not change, in the preview or in the file.
/// Capturing the base value instead would snap an animated parameter back to
/// its base the moment a second diamond was placed.
///
/// **A diamond already at [progress] is kept as it is**, value and curve, so
/// capturing twice at one instant is idempotent. That matters most to a split
/// that lands exactly on a diamond — a tapped diamond parks the playhead there
/// — which pins the cut on it: replacing it with a fresh linear keyframe
/// straightened the curve leaving it, changing travel the cut never touched.
/// A fresh keyframe is linear, so the easing sheet opens showing "None" and
/// tells the truth about it.
KeyframeParams<P> captureKeyframeIn<P>(
  KeyframeParams<P> params,
  double progress,
) {
  return {
    for (final e in params.entries)
      e.key: e.value.keyframes.any((k) => _sameInstant(k.progress, progress))
          ? e.value
          : AnimatableDouble.sorted(
              baseValue: e.value.baseValue,
              envelope: e.value.envelope,
              keyframes: [
                ...e.value.keyframes,
                Keyframe(
                  progress: progress,
                  value: e.value.resolveAt(progress),
                  interpolation: KeyframeInterpolation.linear,
                ),
              ],
            ),
  };
}

/// Takes the diamond nearest [progress] off every parameter.
///
/// **The last diamond hands its value back as the base**, so the frame the
/// user is looking at when they remove it is the frame that stays. Dropping to
/// the old base would jump the picture to a value they may have set minutes
/// ago, which reads as the editor undoing something it was not asked to undo.
///
/// No diamond near [progress] returns [params] itself.
KeyframeParams<P> removeKeyframeIn<P>(
  KeyframeParams<P> params,
  double progress,
  double tolerance,
) {
  final target = keyframeProgressNearIn(params, progress, tolerance);
  if (target == null) return params;

  return {
    for (final e in params.entries)
      e.key: () {
        final param = e.value;
        final removed = [
          for (final k in param.keyframes)
            if (_sameInstant(k.progress, target)) k,
        ];
        final kept = [
          for (final k in param.keyframes)
            if (!_sameInstant(k.progress, target)) k,
        ];
        return AnimatableDouble.sorted(
          baseValue: kept.isEmpty && removed.isNotEmpty
              ? removed.first.value
              : param.baseValue,
          envelope: param.envelope,
          keyframes: kept,
        );
      }(),
  };
}

/// Slides the diamond nearest [from] to [to] on every parameter, each keyframe
/// keeping its value and its curve.
///
/// A diamond is an *instant*, so the move is of the instant: every
/// parameter's keyframe at it travels together, or the one mark would stop
/// being an honest picture of the item's state. Clamped to 0..1.
///
/// **Null when refused**: no diamond near [from], the destination is where it
/// already is, or **another diamond already sits at the destination** — two
/// instants must never collapse into one because a finger overshot, so the
/// dragged diamond stops short of its neighbour instead.
KeyframeParams<P>? moveKeyframeIn<P>(
  KeyframeParams<P> params,
  double from,
  double to,
  double tolerance,
) {
  final target = keyframeProgressNearIn(params, from, tolerance);
  if (target == null) return null;
  final dest = to.clamp(0.0, 1.0).toDouble();
  if (_sameInstant(dest, target)) return null;
  final occupied = keyframeProgressesIn(params).any(
    (p) => !_sameInstant(p, target) && _sameInstant(p, dest),
  );
  if (occupied) return null;

  return {
    for (final e in params.entries)
      e.key: e.value.keyframes.isEmpty
          ? e.value
          : AnimatableDouble.sorted(
              baseValue: e.value.baseValue,
              envelope: e.value.envelope,
              keyframes: [
                for (final k in e.value.keyframes)
                  if (_sameInstant(k.progress, target))
                    Keyframe(
                      progress: dest,
                      value: k.value,
                      interpolation: k.interpolation,
                    )
                  else
                    k,
              ],
            ),
  };
}

/// Which diamond's outgoing curve the curve control edits at [progress], or
/// null when there is nothing to ease.
///
/// **A curve shapes travel between two diamonds**, and the interpolation lives
/// on the diamond a segment *starts* at. So the target is the latest diamond at
/// or before the playhead — provided a later one exists to travel towards.
///
/// Null in three cases, each a real "nothing to shape here": fewer than two
/// diamonds (one point is a value held, with no travel), before the first, and
/// after the last. The one concession to the finger: **on the last diamond the
/// target is the segment arriving at it** — an icon that went inert the moment
/// a user landed on the final diamond would read as broken.
double? keyframeCurveTargetIn<P>(
  KeyframeParams<P> params,
  double progress,
  double tolerance,
) {
  final all = keyframeProgressesIn(params);
  if (all.length < 2) return null;

  final onDiamond = keyframeProgressNearIn(params, progress, tolerance);
  if (onDiamond != null) {
    final index = all.indexWhere((p) => _sameInstant(p, onDiamond));
    if (index == all.length - 1) return all[index - 1];
    return all[index];
  }

  if (progress < all.first || progress > all.last) return null;
  double? target;
  for (final p in all) {
    if (p <= progress) target = p;
  }
  return target;
}

/// The curve on the diamond at [target], or linear when none carries one.
///
/// Linear doubles as "None" in the easing sheet, which is honest: a segment
/// with no curve chosen travels in a straight line.
KeyframeInterpolation keyframeCurveAtIn<P>(
  KeyframeParams<P> params,
  double target,
) {
  for (final param in params.values) {
    for (final k in param.keyframes) {
      if (_sameInstant(k.progress, target)) return k.interpolation;
    }
  }
  return KeyframeInterpolation.linear;
}

/// Re-eases the diamond nearest [progress], on every parameter.
///
/// The interpolation belongs to the segment that *starts* at a keyframe, so
/// this changes how the value travels from here to the next diamond. No
/// diamond near [progress] returns [params] itself.
KeyframeParams<P> setKeyframeEasingIn<P>(
  KeyframeParams<P> params,
  double progress,
  double tolerance,
  KeyframeInterpolation easing,
) {
  final target = keyframeProgressNearIn(params, progress, tolerance);
  if (target == null) return params;
  return {
    for (final e in params.entries)
      e.key: AnimatableDouble.sorted(
        baseValue: e.value.baseValue,
        envelope: e.value.envelope,
        keyframes: [
          for (final k in e.value.keyframes)
            if (_sameInstant(k.progress, target))
              Keyframe(
                progress: k.progress,
                value: k.value,
                interpolation: easing,
              )
            else
              k,
        ],
      ),
  };
}

/// Sets the curve on the segment the playhead is inside, on every parameter.
///
/// **Never places a diamond.** That is the whole distinction from
/// [captureKeyframeIn]: the plus button creates instants, the curve control
/// shapes travel that already exists. No target returns [params] itself.
KeyframeParams<P> setKeyframeCurveIn<P>(
  KeyframeParams<P> params,
  double progress,
  double tolerance,
  KeyframeInterpolation curve,
) {
  final target = keyframeCurveTargetIn(params, progress, tolerance);
  if (target == null) return params;
  return setKeyframeEasingIn(params, target, tolerance, curve);
}

/// The edit rule: whether a write to [property] is a base value or a
/// keyframe.
///
/// - **No diamonds, or no playhead on the item** ([playheadProgress] null):
///   write the base value. Exactly what every control did before keyframes.
/// - **Diamonds, playhead on one:** write that keyframe's value and leave the
///   base alone.
/// - **Diamonds, playhead between them:** place a diamond first — capturing
///   every *other* parameter at that instant so nothing else moves — then
///   write into it.
///
/// Folding several writes through this one after another at the same instant
/// places at most one diamond: the first write captures it, the rest find it.
KeyframeParams<P> writeKeyframedValueIn<P>(
  KeyframeParams<P> params,
  P property,
  double value, {
  required double? playheadProgress,
  required double tolerance,
}) {
  final param = params[property];
  if (param == null) return params;
  if (!hasKeyframesIn(params) || playheadProgress == null) {
    return {...params, property: param.copyWith(baseValue: value)};
  }

  var out = params;
  var target = keyframeProgressNearIn(out, playheadProgress, tolerance);
  if (target == null) {
    out = captureKeyframeIn(out, playheadProgress);
    target = playheadProgress;
  }
  final resolved = target;
  final p = out[property]!;
  return {
    ...out,
    property: AnimatableDouble.sorted(
      baseValue: p.baseValue,
      envelope: p.envelope,
      keyframes: [
        for (final k in p.keyframes)
          if (_sameInstant(k.progress, resolved))
            // The easing belongs to the keyframe, not to the edit: retuning a
            // value must not silently straighten the curve leaving it.
            Keyframe(
              progress: k.progress,
              value: value,
              interpolation: k.interpolation,
            )
          else
            k,
      ],
    ),
  };
}

/// One half of a split item's parameters, every keyframe rescaled into the
/// half's own 0..1.
///
/// **A keyframe's progress is item-relative, so a split has to rescale it.**
/// Copying the lists verbatim leaves the left half's later keyframes past its
/// own end — where the value holds, silently freezing the move — and bunches
/// the right half's earlier ones before its start.
///
/// [cut] is where the split falls in the *original* item's progress. For the
/// left half keyframes at or before it map `p -> p / cut`; for the right,
/// those at or after map `p -> (p - cut) / (1 - cut)`. **A keyframe is
/// captured at the cut first**, so the value at the seam is identical on
/// either side and the split is invisible in the picture.
///
/// No keyframes, or a degenerate cut (at 0 or 1), returns [params] itself —
/// a split guard makes the latter unreachable in practice, but this must not
/// be the thing that divides by zero if that ever changes.
KeyframeParams<P> splitKeyframesIn<P>(
  KeyframeParams<P> params,
  double cut, {
  required bool isLeft,
}) {
  if (!hasKeyframesIn(params)) return params;
  if (cut <= 0.0 || cut >= 1.0) return params;

  final pinned = captureKeyframeIn(params, cut);
  return {
    for (final e in pinned.entries)
      e.key: AnimatableDouble.sorted(
        baseValue: e.value.baseValue,
        envelope: e.value.envelope,
        keyframes: [
          for (final k in e.value.keyframes)
            if (isLeft && k.progress <= cut + kKeyframeMatchProgress)
              Keyframe(
                progress: (k.progress / cut).clamp(0.0, 1.0).toDouble(),
                value: k.value,
                interpolation: k.interpolation,
              )
            else if (!isLeft && k.progress >= cut - kKeyframeMatchProgress)
              Keyframe(
                progress:
                    ((k.progress - cut) / (1 - cut)).clamp(0.0, 1.0).toDouble(),
                value: k.value,
                interpolation: k.interpolation,
              ),
        ],
      ),
  };
}
