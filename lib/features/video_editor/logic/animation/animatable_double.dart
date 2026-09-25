/// A number that may change over the length of a clip, and the one function
/// that reads it.
///
/// Two things are wanted from the same place. A user who taps one preset wants
/// an effect that *feels designed* — a glitch that pulses, a blur that clears —
/// without placing anything by hand; that is an **envelope**, a named curve
/// from the table below. A user who wants exact control wants to put a value at
/// a moment and another somewhere else; those are **keyframes**. Both are the
/// same question — "what is this value at this instant?" — so they get one
/// model and one evaluator rather than two subsystems that would each need
/// their own serialisation, their own Kotlin port and their own fixture.
///
/// **This knows nothing about effects.** Effects are merely its first consumer.
/// Keyframes are a timeline feature, and the moment they exist a user expects
/// them on the clip transform (Ken Burns), on opacity and on volume. Built
/// inside the effects system this would work in exactly one place and need a
/// rebuild — plus a draft migration — the first time a second consumer asked
/// for it.
///
/// **Pure Dart, `dart:math` only, no state and no clock.** A later task ports
/// this to Kotlin function for function and a shared fixture asserts the two
/// sides agree, exactly as `text_animation_catalog.dart` and
/// `TextAnimationCurves.kt` already do. Anything that reached for `Curves`,
/// `DateTime.now()` or a `Random` could not be ported, and the preview and the
/// exported file would differ with nothing on screen explaining why.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Keyframes
// ---------------------------------------------------------------------------

/// How a keyframe's value travels towards the next one.
///
/// The name is persisted into drafts and crosses the channel to Kotlin.
/// **Renaming one is a migration, not an edit** — the same rule effect ids,
/// transition names and text animation ids already follow.
enum KeyframeInterpolation {
  /// A straight line, and **what a freshly placed keyframe gets**.
  ///
  /// The easing sheet's highlighted cell has to tell the truth about the
  /// diamond the user just placed, and "None" is the honest answer for a point
  /// nobody has shaped yet. A default of *some* curve would mean every new
  /// keyframe silently carried an easing the sheet then showed as already
  /// chosen.
  linear,

  /// No travel at all: the value stays put until the next keyframe and then
  /// jumps. This is what makes step effects — a strobe, a hard cut in intensity
  /// — expressible, and a linear ramp could never approximate one.
  ///
  /// **Deliberately absent from the easing sheet.** It is a different kind of
  /// thing from a curve, and a user reaching for "no easing" means [linear].
  /// Kept because drafts carry it and step effects need it.
  hold,

  sineIn,
  sineOut,
  sineInOut,
  quadIn,
  quadOut,
  quadInOut,
  cubicIn,
  cubicOut,
  cubicInOut,
  bounceIn,
  bounceOut,
  bounceInOut,
}

/// The curve the legacy name `ease` resolves to.
///
/// **`ease` was `_easeInOut`, the standard cubic in-out.** It is no longer a
/// value of the enum — the easing sheet is a grid of families, and a cell for a
/// synonym of `cubicInOut` would be a second name for one curve — but every
/// draft written before the families existed carries the string, so
/// [_interpolationByName] maps it here.
///
/// **Renaming a persisted value is a migration, and this is it.** The migration
/// is exact: the curve is unchanged, only what it is called. A draft written
/// yesterday resolves to the same numbers today.
const KeyframeInterpolation kDefaultKeyframeInterpolation =
    KeyframeInterpolation.cubicInOut;

/// The eased fraction for [t] (0..1) on [e].
///
/// **Pure `dart:math`**, like everything else in this file: `AnimatableDouble.kt`
/// ports it function for function and the shared fixture asserts the two agree.
/// Anything reaching for `Curves` could not be ported, and the exported file
/// would move differently from the canvas with nothing on screen explaining it.
///
/// **Every curve here lands on exactly 0 at t == 0 and 1 at t == 1, and stays
/// inside that range throughout.** A keyframe pair means "this value here, that
/// value there"; a curve that overshot would send the parameter somewhere the
/// user never placed — past the maximum its own slider offers, which for a
/// clamped consumer (a volume, an opacity) silently flattens into a plateau.
/// That is why the bounce family bounces *within* the range rather than
/// overshooting the way an elastic ease would.
double applyKeyframeEasing(KeyframeInterpolation e, double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  switch (e) {
    case KeyframeInterpolation.linear:
    // `hold` never actually reaches here — [AnimatableDouble.resolveAt] returns
    // the held value before easing — but the switch must be exhaustive, and a
    // straight line is the honest answer for a caller asking a hold for its
    // *curve*.
    case KeyframeInterpolation.hold:
      return t;
    case KeyframeInterpolation.sineIn:
      return 1 - math.cos((t * math.pi) / 2);
    case KeyframeInterpolation.sineOut:
      return math.sin((t * math.pi) / 2);
    case KeyframeInterpolation.sineInOut:
      return -(math.cos(math.pi * t) - 1) / 2;
    case KeyframeInterpolation.quadIn:
      return t * t;
    case KeyframeInterpolation.quadOut:
      return 1 - (1 - t) * (1 - t);
    case KeyframeInterpolation.quadInOut:
      if (t < 0.5) return 2 * t * t;
      final u = -2 * t + 2;
      return 1 - (u * u) / 2;
    case KeyframeInterpolation.cubicIn:
      return t * t * t;
    case KeyframeInterpolation.cubicOut:
      final u = 1 - t;
      return 1 - u * u * u;
    case KeyframeInterpolation.cubicInOut:
      if (t < 0.5) return 4 * t * t * t;
      final u = -2 * t + 2;
      return 1 - (u * u * u) / 2;
    case KeyframeInterpolation.bounceIn:
      return 1 - _bounceOut(1 - t);
    case KeyframeInterpolation.bounceOut:
      return _bounceOut(t);
    case KeyframeInterpolation.bounceInOut:
      return t < 0.5
          ? (1 - _bounceOut(1 - 2 * t)) / 2
          : (1 + _bounceOut(2 * t - 1)) / 2;
  }
}

/// The standard four-segment bounce — Penner's, the curve every toolkit ships
/// as `bounceOut`, Flutter's `Curves.bounceOut` included.
///
/// Written out rather than taken from Flutter for this file's standing reason:
/// Flutter cannot be imported here and Kotlin has no equivalent. **The
/// constants are exact and deliberately unrounded** so the port can be compared
/// against this digit for digit — a "tidied" 0.98 in one of the two would be a
/// divergence the fixture catches but nobody could explain.
double _bounceOut(double t) {
  const n1 = 7.5625;
  const d1 = 2.75;
  if (t < 1 / d1) return n1 * t * t;
  if (t < 2 / d1) {
    final u = t - 1.5 / d1;
    return n1 * u * u + 0.75;
  }
  if (t < 2.5 / d1) {
    final u = t - 2.25 / d1;
    return n1 * u * u + 0.9375;
  }
  final u = t - 2.625 / d1;
  return n1 * u * u + 0.984375;
}

/// One row of the easing sheet: a family, and its four cells.
class KeyframeEasingGroup {
  const KeyframeEasingGroup({
    required this.label,
    required this.none,
    required this.easeIn,
    required this.easeOut,
    required this.easeInOut,
  });

  final String label;

  /// **Every group's None is [KeyframeInterpolation.linear]** — there is one way
  /// not to ease.
  ///
  /// So picking None in any group is the same edit, and the sheet highlights
  /// None in whichever group the user happened to open. Giving each family its
  /// own "none" would make one state look like four different ones.
  final KeyframeInterpolation none;

  final KeyframeInterpolation easeIn;
  final KeyframeInterpolation easeOut;
  final KeyframeInterpolation easeInOut;
}

/// The families the easing sheet offers, in the order it draws them.
///
/// Sine is labelled **Default** because it is the gentlest of the four and the
/// one a user who has not thought about curves wants. The four labels are the
/// user's own, from the design they described.
///
/// A test pins this table against [KeyframeInterpolation.values], so a curve
/// added to the enum cannot be silently orphaned somewhere no user can pick it.
const List<KeyframeEasingGroup> kKeyframeEasingGroups = [
  KeyframeEasingGroup(
    label: 'Default',
    none: KeyframeInterpolation.linear,
    easeIn: KeyframeInterpolation.sineIn,
    easeOut: KeyframeInterpolation.sineOut,
    easeInOut: KeyframeInterpolation.sineInOut,
  ),
  KeyframeEasingGroup(
    label: 'Quadratic',
    none: KeyframeInterpolation.linear,
    easeIn: KeyframeInterpolation.quadIn,
    easeOut: KeyframeInterpolation.quadOut,
    easeInOut: KeyframeInterpolation.quadInOut,
  ),
  KeyframeEasingGroup(
    label: 'Cubic',
    none: KeyframeInterpolation.linear,
    easeIn: KeyframeInterpolation.cubicIn,
    easeOut: KeyframeInterpolation.cubicOut,
    easeInOut: KeyframeInterpolation.cubicInOut,
  ),
  KeyframeEasingGroup(
    label: 'Bounce',
    none: KeyframeInterpolation.linear,
    easeIn: KeyframeInterpolation.bounceIn,
    easeOut: KeyframeInterpolation.bounceOut,
    easeInOut: KeyframeInterpolation.bounceInOut,
  ),
];

/// One value pinned at one moment of a clip.
class Keyframe {
  const Keyframe({
    required this.progress,
    required this.value,
    this.interpolation = KeyframeInterpolation.linear,
  });

  /// Where in the clip this value sits, **0..1, never seconds**.
  ///
  /// Every other geometry in this codebase is a fraction for the same reason:
  /// a trimmed or sped-up clip keeps its keyframes where they were placed
  /// rather than having them slide out from under the edit, and a draft renders
  /// identically on any device. Seconds would also make the Kotlin port carry a
  /// clip's duration into a curve that has no business knowing it.
  final double progress;

  /// The parameter's value at [progress]. Deliberately unclamped: this model is
  /// general, and a consumer's range is the consumer's business — a volume is
  /// 0..1, a scale is not.
  final double value;

  /// How the value travels **from here to the next keyframe**.
  ///
  /// The interpolation belongs to the segment that *starts* at this keyframe,
  /// not the one that ends at it. That is the convention every editor uses for
  /// a hold: dropping a hold on a keyframe means "stay here until the next
  /// one", which is only true if the flag describes the outgoing segment.
  final KeyframeInterpolation interpolation;

  Map<String, dynamic> toJson() => {
        'progress': progress,
        'value': value,
        'interpolation': interpolation.name,
      };

  /// Defensive on every field: a draft can arrive hand-edited, truncated, or
  /// written by a build that stored something this one does not know.
  /// `is num` rather than the house `as num?`: the cast throws on a value that
  /// is present and of the wrong type, and a hand-edited draft with a quoted
  /// number is exactly that. A malformed field degrades to its default here, in
  /// keeping with the rest of this file.
  factory Keyframe.fromJson(Map<String, dynamic> json) {
    final rawProgress = json['progress'];
    final rawValue = json['value'];
    return Keyframe(
      // Progress is clip-relative 0..1 by definition, so a value outside it is
      // meaningless rather than merely unusual — it would sit off the end of
      // every timeline row that draws it.
      progress: _clamp01(rawProgress is num ? rawProgress.toDouble() : 0.0),
      value: rawValue is num ? rawValue.toDouble() : 0.0,
      interpolation: _interpolationByName(json['interpolation']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Keyframe &&
          other.progress == progress &&
          other.value == value &&
          other.interpolation == interpolation;

  @override
  int get hashCode => Object.hash(progress, value, interpolation);

  @override
  String toString() =>
      'Keyframe($progress -> $value, ${interpolation.name})';
}

/// An interpolation name that this build does not know degrades to the default
/// rather than throwing — a draft from a newer build must still open.
KeyframeInterpolation _interpolationByName(Object? name) {
  if (name is! String) return KeyframeInterpolation.linear;
  // The one legacy name. See [kDefaultKeyframeInterpolation].
  if (name == 'ease') return kDefaultKeyframeInterpolation;
  for (final value in KeyframeInterpolation.values) {
    if (value.name == name) return value;
  }
  // **Linear, not the default curve.** A name this build cannot read is a shape
  // it has no idea about, and guessing a curve would move the value along a
  // path nobody chose. A straight line between the two points the user did
  // place is the answer that adds nothing of its own.
  return KeyframeInterpolation.linear;
}

// ---------------------------------------------------------------------------
// The parameter
// ---------------------------------------------------------------------------

/// A double that may be constant, shaped by a named envelope, or keyframed.
///
/// **Resolution order is not negotiable: keyframes, else envelope, else the
/// flat base value.** One keyframe means the user has taken manual control, and
/// the envelope steps aside *entirely* — it does not blend in, scale the
/// result, or contribute at the ends. There is no mode to enter, nothing to
/// switch off, and deliberately no state in which both are half-applied: a
/// parameter that multiplied a keyframed curve by a pulsing envelope would give
/// a user who placed two points a value that matches neither of them, and no
/// control anywhere to explain it.
class AnimatableDouble {
  const AnimatableDouble({
    required this.baseValue,
    this.envelope,
    this.keyframes = const [],
  });

  /// The value when nothing animates it, and the magnitude an envelope scales.
  final double baseValue;

  /// A name from [kEnvelopeNames], or null for a constant.
  ///
  /// A name rather than a curve so it survives serialisation and the channel
  /// crossing: a closure cannot be written into a draft or sent to Kotlin, and
  /// a name means both sides look the effect up in their own copy of one table
  /// that a fixture pins together.
  final String? envelope;

  /// The keyframes. Normally sorted by progress — [AnimatableDouble.sorted] and
  /// [AnimatableDouble.fromJson] both sort, and anything editing a row should
  /// keep them that way so a UI drawing the list and the evaluator agree about
  /// which keyframe is which.
  ///
  /// **[resolveAt] does not depend on it.** The `const` constructor cannot sort
  /// — it is `const`, and it is the one a caller reaches for by default — so a
  /// contract that said "always sorted" would be one the type could not keep.
  /// The evaluator finds its bracketing pair by comparing progress rather than
  /// by trusting position, which costs nothing on a linear walk it was doing
  /// anyway and removes an entire class of "built through the wrong
  /// constructor" bug.
  final List<Keyframe> keyframes;

  /// Builds a parameter from keyframes that may arrive in any order, and stores
  /// them sorted.
  ///
  /// **Input order is not trusted**, because the timeline row that will edit
  /// these lets a user drag one keyframe past another — after which the list is
  /// in the order the points were created rather than the order they now sit in
  /// on screen. Sorting here is what keeps the stored list and the drawn row
  /// telling the same story; correctness of the *value* does not depend on it
  /// (see [keyframes]), only legibility of the model does.
  factory AnimatableDouble.sorted({
    required double baseValue,
    String? envelope,
    List<Keyframe> keyframes = const [],
  }) {
    if (keyframes.length <= 1) {
      return AnimatableDouble(
        baseValue: baseValue,
        envelope: envelope,
        keyframes: List<Keyframe>.unmodifiable(keyframes),
      );
    }
    final sorted = List<Keyframe>.of(keyframes)
      ..sort((a, b) => a.progress.compareTo(b.progress));
    return AnimatableDouble(
      baseValue: baseValue,
      envelope: envelope,
      keyframes: List<Keyframe>.unmodifiable(sorted),
    );
  }

  /// Whether anything at all varies this value over the clip.
  ///
  /// True for a *set* envelope even when the name is one this build cannot
  /// resolve: the model's job is to report what the draft says, and the
  /// degrade-to-base rule lives in [resolveAt]. A UI showing "animated" for a
  /// parameter whose preset came from a newer build is telling the truth about
  /// the project.
  bool get isAnimated =>
      keyframes.isNotEmpty || (envelope != null && envelope!.isNotEmpty);

  /// The value at [progress] (0..1 through the clip).
  ///
  /// **Runs per frame in both the preview and the export**, so it allocates
  /// nothing, does no string work beyond the envelope lookup's map hit, and
  /// walks the keyframes linearly — a keyframe row a user can actually manage
  /// holds a handful of points, and a binary search would cost more in branches
  /// than it saved.
  double resolveAt(double progress) {
    final p = _clamp01(progress);

    // Keyframes first, and exclusively. See the class note.
    final count = keyframes.length;
    if (count > 0) {
      // One pass, picking out the two keyframes that bracket `p`: the latest at
      // or before it and the earliest at or after it. Comparing progress rather
      // than walking adjacent pairs is what makes the result independent of the
      // list's order — see the note on [keyframes] — and it is the same single
      // linear scan either way, with no allocation.
      Keyframe? before;
      Keyframe? after;
      for (var i = 0; i < count; i++) {
        final k = keyframes[i];
        if (k.progress <= p) {
          // `>=` rather than `>`: with several keyframes on the same instant
          // the last one written wins, consistently on both sides of the pair,
          // so the value never depends on which duplicate the scan met first.
          if (before == null || k.progress >= before.progress) before = k;
        }
        if (k.progress >= p) {
          if (after == null || k.progress <= after.progress) after = k;
        }
      }

      // Before the first keyframe and after the last, the value **holds** —
      // there is no extrapolation. A curve that ran on past its last keyframe
      // would send the value somewhere the user never placed, and a single
      // keyframe would have no defined direction to run in at all; holding makes
      // one keyframe mean "this value, for the whole clip", which is what
      // placing one point obviously means.
      if (before == null) return after!.value;
      if (after == null) return before.value;

      // `p` landed exactly on a keyframe, or on a stack of them.
      if (identical(before, after)) return before.value;

      // A held keyframe keeps its value right up to the next one. The flag
      // belongs to the segment that *starts* at `before`; see
      // [Keyframe.interpolation].
      if (before.interpolation == KeyframeInterpolation.hold) return before.value;

      final span = after.progress - before.progress;
      // Two keyframes can sit on the same instant — a user can drag one onto
      // another, and rejecting that is a UI concern, not this evaluator's.
      // Dividing by the span here would produce NaN and paint a black frame.
      if (span <= 0) return after.value;

      final t = (p - before.progress) / span;
      final eased = applyKeyframeEasing(before.interpolation, t);
      return before.value + (after.value - before.value) * eased;
    }

    final name = envelope;
    if (name == null || name.isEmpty) return baseValue;
    return baseValue * resolveEnvelope(name, p);
  }

  AnimatableDouble copyWith({
    double? baseValue,
    String? envelope,
    bool clearEnvelope = false,
    List<Keyframe>? keyframes,
  }) {
    return AnimatableDouble.sorted(
      baseValue: baseValue ?? this.baseValue,
      envelope: clearEnvelope ? null : (envelope ?? this.envelope),
      keyframes: keyframes ?? this.keyframes,
    );
  }

  /// Writes a **bare number** when nothing is animated.
  ///
  /// The field this replaces is a plain `double` in every draft already saved,
  /// and the overwhelming majority of parameters will never be animated. Keeping
  /// the unanimated case as the number it has always been means those drafts do
  /// not grow a map each, and a build that has not learned about this model yet
  /// still reads the value it expects rather than a map it would discard.
  /// [fromJson] takes `dynamic` for the same reason, from the other direction.
  dynamic toJson() {
    if (!isAnimated) return baseValue;
    return <String, dynamic>{
      'baseValue': baseValue,
      if (envelope != null && envelope!.isNotEmpty) 'envelope': envelope,
      // Written in order even when the in-memory list is not (the `const`
      // constructor cannot sort). A draft is read by people as well as by
      // `fromJson`, and an out-of-order list on disk looks like corruption.
      if (keyframes.isNotEmpty)
        'keyframes': (List<Keyframe>.of(keyframes)
              ..sort((a, b) => a.progress.compareTo(b.progress)))
            .map((k) => k.toJson())
            .toList(),
    };
  }

  /// Reads either shape, and **never throws on a draft written before this
  /// stage**.
  ///
  /// [json] is `dynamic` deliberately: the field it replaces is currently a
  /// bare `double` in every saved project (read as
  /// `(json['effectIntensity'] as num?)?.toDouble()`), so a number has to load
  /// as a plain value with no envelope and no keyframes, while a map loads
  /// fully. [fallback] is the value a caller's own default would have supplied
  /// — the field being absent entirely is the ordinary case for any draft older
  /// than the field.
  ///
  /// Everything below the top level is defensive too. A draft can be
  /// hand-edited or truncated, and a saved project turning into a crash on open
  /// is the worst failure this file could have.
  factory AnimatableDouble.fromJson(dynamic json, {double fallback = 0.0}) {
    if (json is num) {
      return AnimatableDouble(baseValue: json.toDouble());
    }
    if (json is! Map) {
      // Null, absent, a string, a list — nothing readable. The caller's default
      // is a better answer than a throw, and better than zero.
      return AnimatableDouble(baseValue: fallback);
    }

    // `as num?` would be the house spelling, but it *throws* on a value that is
    // present and of the wrong type — a hand-edited draft with a quoted number
    // is exactly that. `is num` degrades instead, which is what the rest of this
    // file promises.
    final rawBase = json['baseValue'];
    final baseValue = rawBase is num ? rawBase.toDouble() : fallback;

    final rawEnvelope = json['envelope'];
    final envelope =
        rawEnvelope is String && rawEnvelope.isNotEmpty ? rawEnvelope : null;

    final rawKeyframes = json['keyframes'];
    final keyframes = <Keyframe>[];
    if (rawKeyframes is List) {
      for (final entry in rawKeyframes) {
        // A malformed entry is skipped rather than failing the whole
        // parameter: losing one keyframe leaves a project openable, and
        // throwing loses the project.
        if (entry is Map) {
          keyframes.add(Keyframe.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }

    return AnimatableDouble.sorted(
      baseValue: baseValue,
      envelope: envelope,
      keyframes: keyframes,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnimatableDouble) return false;
    if (other.baseValue != baseValue || other.envelope != envelope) {
      return false;
    }
    if (other.keyframes.length != keyframes.length) return false;
    for (var i = 0; i < keyframes.length; i++) {
      if (other.keyframes[i] != keyframes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(baseValue, envelope, Object.hashAll(keyframes));

  @override
  String toString() => isAnimated
      ? 'AnimatableDouble($baseValue, envelope: $envelope, '
          'keyframes: ${keyframes.length})'
      : 'AnimatableDouble($baseValue)';
}

/// [a] with its base and every keyframe value passed through [f], each
/// keyframe keeping its progress and its curve.
///
/// **Only for an affine [f]** (`v -> k·v + c`). Interpolation, eased or not,
/// is a weighted average of two neighbouring values, and an affine map
/// commutes with a weighted average — so resolving the mapped parameter
/// equals mapping the resolved value, at every progress. That is what lets a
/// change of units (an overlay's canvas pixels to canvas fractions) travel
/// with a keyframe track once, instead of being redone per frame on the far
/// side of the channel.
///
/// An unkeyframed parameter stays unkeyframed, so it still goes on the wire as
/// a bare number. An envelope does not commute with an offset — it *scales*
/// the base — so a parameter carrying one must not be mapped; none of the
/// callers' parameters can carry one.
AnimatableDouble mapAnimatable(
  AnimatableDouble a,
  double Function(double) f,
) {
  assert(
    a.envelope == null,
    'An envelope scales its base; an affine map with an offset does not '
    'commute with it.',
  );
  return AnimatableDouble.sorted(
    baseValue: f(a.baseValue),
    envelope: a.envelope,
    keyframes: [
      for (final k in a.keyframes)
        Keyframe(
          progress: k.progress,
          value: f(k.value),
          interpolation: k.interpolation,
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Envelopes
// ---------------------------------------------------------------------------

// Every envelope is a pure function of progress returning a **0..1 multiplier**
// of the base value, so an envelope can only ever take strength away from what
// the user chose with the intensity slider. That is the whole contract: an
// envelope shapes an intensity, it does not exceed it. Returning more than 1
// would push a parameter past the maximum its own UI offers, which for a clamped
// consumer (a volume, an opacity) silently flattens into a plateau and for an
// unclamped one produces a value no slider could reach.
//
// **Every envelope lands on exactly 1.0 at p == 1, and this is the deliberate
// endpoint decision.** An effect caught mid-transition on a clip's final frame
// visibly pops the instant the next clip starts: the frame after it either has
// a different clip's effect or none, and the discontinuity lands exactly on the
// cut where the eye is already looking. Resting at full strength means the last
// frame an envelope draws is the clip's own unmodulated intensity — identical to
// what the clip would look like with no envelope at all — so the handover is
// continuous by construction whatever follows.
//
// The cost is paid where it is invisible instead. `ramp_out` is the case that
// shows it most clearly: a "clears away" envelope would naturally end at 0, but
// ending at 0 means the effect is *absent* on the final frame and present on the
// first frame of anything that looks like it — so it clears to nothing early,
// holds there through the middle, and returns to 1 across the clip's own tail,
// where the picture is already settling. `pulse` and `throb` are periodic and
// solve it by construction: both are a whole number of cycles in `p`, so
// `p == 0` and `p == 1` are the same instant of the wave, which is the identical
// rule the text animation loops follow.
//
// The start is not symmetric with the end and does not need to be: a clip's
// first frame is preceded by a transition, a cut, or nothing at all, and an
// effect that is *already* running when the clip appears reads as intentional.
// That is why `ramp_in` may open from 0 while `ramp_out` may not close there.

double _clamp01(double v) {
  // NaN fails every comparison, so it falls through to the explicit check
  // rather than propagating into a keyframe search or a shader uniform. A
  // caller turning seconds into progress divides by a clip duration, and a
  // zero-length clip hands one over.
  if (v.isNaN) return 0;
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

/// Slow at both ends, quick through the middle. The default keyframe ease, and
/// the shaping ramps below share it so a keyframed ramp and an enveloped one
/// move with the same character.
///
/// Written out rather than taken from `Curves.easeInOut` — Flutter cannot be
/// imported here and Kotlin has no equivalent. The standard cubic form, exactly
/// symmetric about 0.5, which the tests pin.
double _easeInOut(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  if (t < 0.5) return 4 * t * t * t;
  final u = -2 * t + 2;
  return 1 - u * u * u / 2;
}

// Both periodic envelopes below are written as `cos` over a **whole number** of
// cycles of `p`, never as `sin(p * something)` picked by eye. `cos` starts and
// ends at 1 and a whole cycle count makes `p == 0` and `p == 1` the same instant
// of the wave, so the endpoint rule holds by construction rather than by a
// correction term — the identical rule the text animation loops follow, for the
// identical reason.

/// **A beat.** The effect drops out and slams back, three times over the clip —
/// what a user means by "make the glitch hit on the rhythm" without placing a
/// single keyframe.
///
/// A raised cosine rather than a bare sine so the peaks are held and the troughs
/// are narrow: an effect that spends equal time on and off reads as a flicker,
/// whereas one that mostly sits at full strength and briefly drops reads as a
/// pulse landing.
double _pulse(double p) {
  // `cos` of a whole number of cycles starts and ends at 1, which is the
  // endpoint rule for free.
  final wave = math.cos(2 * math.pi * _kPulseBeats * p);
  // Map -1..1 onto 0..1 and bias towards the top so the effect is present more
  // of the time than it is absent.
  final unit = (wave + 1) * 0.5;
  return unit * unit;
}

/// How many times a `pulse` beats over a clip.
///
/// Three reads as deliberate rhythm on clips of the length short-form video
/// actually uses; one reads as a mistake and six as a strobe.
const double _kPulseBeats = 3;

/// **The effect arrives.** Nothing at the first frame, full strength by the
/// last — a glitch that builds, a blur that closes in.
///
/// Monotonic on purpose: this is the envelope a user picks when they want a
/// sense of something approaching, and any dip on the way would read as the
/// effect stuttering rather than growing.
double _rampIn(double p) => _easeInOut(p);

/// **The effect clears.** Full strength at the first frame, gone by the time the
/// clip is a third through — a blur that resolves into a sharp picture, a
/// distortion that settles.
///
/// It returns to 1 across the clip's own tail rather than ending at 0; see the
/// endpoint note above. The return is placed in the last 15% and eased, so on a
/// clip of any usable length it is a slow re-arrival the eye reads as the next
/// shot beginning rather than as the effect coming back.
double _rampOut(double p) {
  if (p <= _kRampOutClearBy) {
    return 1 - _easeInOut(p / _kRampOutClearBy);
  }
  if (p < _kRampOutReturnFrom) return 0;
  final t = (p - _kRampOutReturnFrom) / (1 - _kRampOutReturnFrom);
  return _easeInOut(t);
}

/// `ramp_out` is gone by a third of the clip: the point of it is a picture that
/// resolves and then plays clean, so the effect must be out of the way while
/// most of the clip runs.
const double _kRampOutClearBy = 1 / 3;

/// …and comes back over the last 15%, which is where the endpoint rule is paid
/// for. Short enough not to be the clip's story, long enough not to be a snap.
const double _kRampOutReturnFrom = 0.85;

/// **The effect arrives and leaves.** Builds from nothing over the first half of
/// the clip, then releases over the second — a look that swells through a shot
/// and lets go of it.
///
/// The release is a **dip**, not a ramp down to zero, and that is the endpoint
/// rule doing its work: the effect falls almost all the way away through the
/// clip's last third and is back at the clip's own intensity on the final frame,
/// so there is nothing to pop when the next clip starts. One sine hump covers
/// the fall and the return together rather than a ramp down followed by a
/// separate ramp up, so there is no flat stretch at the bottom and no corner at
/// either end of it for the eye to catch.
double _rampInOut(double p) {
  if (p <= 0.5) return _easeInOut(p / 0.5);
  final t = (p - 0.5) / 0.5;
  return 1 - _kRampInOutReleaseDepth * math.sin(math.pi * t);
}

/// How far `ramp_in_out` releases at the deepest point of its dip.
///
/// Nearly all the way: the name promises the effect leaves, so a shallow dip
/// would read as a wobble. Not *quite* zero, because the curve is only at its
/// floor for an instant — bottoming out at exactly 0 makes the difference
/// between "briefly absent" and "briefly almost absent" invisible while costing
/// the curve its smoothness at the one frame it matters.
const double _kRampInOutReleaseDepth = 0.95;

/// **A slow breath.** The effect never leaves; it swells and eases twice over
/// the clip, which is what makes a static look feel alive without ever drawing
/// attention to itself.
///
/// The distinction from `pulse` is the floor: `throb` never reaches 0, so the
/// effect is continuously present and only its weight changes. A user wanting
/// the effect to actually drop out picks `pulse`.
double _throb(double p) {
  // `sin` of a whole number of cycles is 0 at both ends, so the dip is
  // `(1 - cos)`-shaped: zero depth at p == 0 and p == 1, deepest at each
  // half-cycle. Subtracting it from 1 gives a curve that rests at full strength
  // on the clip's first and last frames by construction, which is the endpoint
  // rule.
  final dip = (1 - math.cos(2 * math.pi * _kThrobBreaths * p)) * 0.5;
  return 1 - _kThrobDepth * dip;
}

/// How far below full strength a breathing envelope dips.
///
/// 0.45 is enough to be felt on a subtle grade and not so much that the effect
/// reads as switching off — that is `pulse`'s job.
const double _kThrobDepth = 0.45;

/// Two breaths over a clip. A whole number, so the wave's start and end are the
/// same instant and the endpoint rule holds for free.
const double _kThrobBreaths = 2;

/// Every envelope name, in the order a preset list should offer them.
///
/// **A name here with no curve behind it degrades silently to the base value**,
/// which on screen looks like a preset that does nothing — so the list and
/// [resolveEnvelope] are pinned together by a test rather than being two things
/// to keep in step by hand.
const List<String> kEnvelopeNames = [
  'pulse',
  'ramp_in',
  'ramp_out',
  'ramp_in_out',
  'throb',
];

/// The multiplier [name] gives at [progress].
///
/// **An unknown name resolves to 1.0** — the base value, unmodulated — never a
/// throw. A draft can carry an envelope from a newer build, from a rename that
/// was not migrated, or from a hand-edited file, and the same rule unknown
/// effect ids and unknown transition names already follow: degrade to the
/// unaffected thing, keep the project openable.
double resolveEnvelope(String name, double progress) {
  final p = _clamp01(progress);
  switch (name) {
    case 'pulse':
      return _pulse(p);
    case 'ramp_in':
      return _rampIn(p);
    case 'ramp_out':
      return _rampOut(p);
    case 'ramp_in_out':
      return _rampInOut(p);
    case 'throb':
      return _throb(p);
    default:
      return 1.0;
  }
}
