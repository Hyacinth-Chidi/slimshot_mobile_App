# Clip Keyframes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A diamond on the clip's thumbnail pins **every** animatable property of that clip at
that instant — placed from the playback control bar, eased from a bottom sheet — and the
effects-panel keyframe UI is deleted.

**Architecture:** `VideoSegment`'s four scalar properties (`canvasScale`, `canvasOffsetX`,
`canvasOffsetY`, `volume`) become `AnimatableDouble` alongside `effectIntensity`, all resolved
against **whole-clip progress**. One notifier function decides whether an edit writes a base
value or a keyframe at the playhead, so every existing control keyframes itself with no UI of
its own. The diamonds are drawn on the filmstrip; the plus/minus and curve controls live in the
playback bar.

**Tech Stack:** Flutter/Dart, Riverpod, Kotlin, OpenGL ES 2.0.

**Spec:** `docs/superpowers/specs/2026-09-15-clip-keyframes-design.md`

## Global Constraints

- **A clip with no keyframes must render byte-identically to today**, and its draft and wire JSON
  must be byte-identical too (`AnimatableDouble.toJson` emits a bare number when not animated).
  Pinned by tests in Tasks 3 and 8, and by device verification in Task 9.
- **One evaluator.** `AnimatableDouble.resolveAt` on both sides; no second interpolation anywhere.
- **Progress is whole-clip** for every property: `(t − timelineStart) / timelineDuration`. The
  shader's `uProgress` keeps the intro window and is untouched.
- **A gesture is one undo step**: `saveStateForUndo()` on gesture start, never per frame.
- **Serialisation hand-written and defensive**; an old draft must load unchanged and never throw.
- Colours from `AppColors`; Lucide icons; dark theme; timeline chrome is square.
- **Never design around one device.** Nothing here is gated on a handset's capability.
- Analyzer baseline is exactly **48** — add none. Gates: `flutter analyze --no-pub`,
  `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.
- Commits end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## File Structure

| File | Responsibility |
| :--- | :--- |
| `lib/features/video_editor/logic/animation/animatable_double.dart` | Modify: easing families. |
| `lib/features/video_editor/logic/animation/clip_keyframes.dart` | **Create.** Pure helpers over a segment's keyframable properties: the diamond set, hit test, capture, remove, re-ease. |
| `lib/features/video_editor/models/video_segment.dart` | Modify: four scalars become `AnimatableDouble`; resolved-value accessors. |
| `lib/features/video_editor/models/editor_timeline.dart` | Modify: the same four fields on `EditorTimelineClip`. |
| `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart` | Modify: pass them through; merge rule refuses animated clips. |
| `lib/features/video_editor/providers/video_editor_notifier.dart` | Modify: `_writeClipValue` edit rule; add/remove/ease diamonds; delete the old keyframe methods. |
| `lib/features/video_editor/models/video_editor_state.dart` | Modify: delete `keyframeEditorSegmentId`, `selectedKeyframeProgress`, `selectedKeyframe`, `showsKeyframeRowFor`; add the four read-only accessors. |
| `lib/features/video_editor/widgets/timeline/clip_keyframe_diamonds.dart` | **Create.** The diamonds drawn over one clip's filmstrip. |
| `lib/features/video_editor/widgets/timeline/keyframe_row.dart` | **Delete.** |
| `lib/features/video_editor/widgets/panels/keyframe_easing_sheet.dart` | **Create.** The 4×4 easing sheet. |
| `lib/features/video_editor/widgets/editor_playback_controls.dart` | Modify: the two keyframe controls. |
| `android/.../nativepreview/AnimatableDouble.kt` | Modify: the easing port. |
| `android/.../nativepreview/NativeTimelineClip.kt` | Modify: four fields become `AnimatableDouble`; `clipProgressAt`. |
| `android/.../nativepreview/TimelinePlaybackEngine.kt`, `android/.../export/VideoExportEngine.kt`, `android/.../export/AudioExportMixer.kt` | Modify: resolve per frame / per block. |
| `tool/generate_envelope_fixture.dart` | Modify: sample every easing. |

---

### Task 1: Easing families

**Files:**
- Modify: `lib/features/video_editor/logic/animation/animatable_double.dart`
- Test: `test/features/video_editor/logic/animation/animatable_double_test.dart`

**Interfaces:**
- Produces: `enum KeyframeInterpolation { linear, hold, sineIn, sineOut, sineInOut, quadIn, quadOut, quadInOut, cubicIn, cubicOut, cubicInOut, bounceIn, bounceOut, bounceInOut }`;
  `double applyKeyframeEasing(KeyframeInterpolation e, double t)`;
  `const KeyframeInterpolation kDefaultKeyframeInterpolation`;
  `const List<KeyframeEasingGroup> kKeyframeEasingGroups`, each
  `KeyframeEasingGroup{String label; KeyframeInterpolation none, easeIn, easeOut, easeInOut;}`.

- [ ] **Step 1: Write the failing tests**

```dart
// in test/features/video_editor/logic/animation/animatable_double_test.dart
group('easing families', () {
  test('every curve starts at 0 and ends at 1', () {
    for (final e in KeyframeInterpolation.values) {
      expect(applyKeyframeEasing(e, 0.0), closeTo(0.0, 1e-9), reason: e.name);
      expect(applyKeyframeEasing(e, 1.0), closeTo(1.0, 1e-9), reason: e.name);
    }
  });

  test('ease is read as cubicInOut, the curve it always was', () {
    final k = Keyframe.fromJson(
        const {'progress': 0.0, 'value': 0.0, 'interpolation': 'ease'});
    expect(k.interpolation, KeyframeInterpolation.cubicInOut);
  });

  test('in-out curves are symmetric about the midpoint', () {
    for (final e in [
      KeyframeInterpolation.sineInOut,
      KeyframeInterpolation.quadInOut,
      KeyframeInterpolation.cubicInOut,
    ]) {
      for (final t in [0.1, 0.25, 0.4]) {
        expect(applyKeyframeEasing(e, t),
            closeTo(1 - applyKeyframeEasing(e, 1 - t), 1e-9),
            reason: '${e.name} @ $t');
      }
    }
  });

  test('an out curve is the reflection of its in curve', () {
    for (final pair in [
      [KeyframeInterpolation.quadIn, KeyframeInterpolation.quadOut],
      [KeyframeInterpolation.cubicIn, KeyframeInterpolation.cubicOut],
      [KeyframeInterpolation.sineIn, KeyframeInterpolation.sineOut],
      [KeyframeInterpolation.bounceIn, KeyframeInterpolation.bounceOut],
    ]) {
      for (final t in [0.15, 0.5, 0.85]) {
        expect(applyKeyframeEasing(pair[0], t),
            closeTo(1 - applyKeyframeEasing(pair[1], 1 - t), 1e-9),
            reason: '${pair[0].name} @ $t');
      }
    }
  });

  test('bounce out actually bounces rather than merely easing', () {
    // Not "is monotone" — a bounce is deliberately not. It reverses direction
    // several times on the way, which is the whole point of the family, and a
    // port that quietly collapsed to a plain ease would still pass a
    // start/end check.
    var reversals = 0;
    var last = applyKeyframeEasing(KeyframeInterpolation.bounceOut, 0.0);
    var rising = true;
    for (var i = 1; i <= 200; i++) {
      final v = applyKeyframeEasing(KeyframeInterpolation.bounceOut, i / 200);
      final nowRising = v >= last;
      if (nowRising != rising) reversals++;
      rising = nowRising;
      last = v;
    }
    expect(reversals, greaterThanOrEqualTo(4));
  });

  test('an unknown interpolation name degrades to linear, never throws', () {
    final k = Keyframe.fromJson(const {
      'progress': 0.5,
      'value': 1.0,
      'interpolation': 'elasticOutFromTheFuture',
    });
    expect(k.interpolation, KeyframeInterpolation.linear);
  });

  test('a keyframe pair travels on the chosen curve', () {
    const p = AnimatableDouble(baseValue: 0, keyframes: [
      Keyframe(
          progress: 0.0, value: 0.0, interpolation: KeyframeInterpolation.quadIn),
      Keyframe(progress: 1.0, value: 1.0),
    ]);
    expect(p.resolveAt(0.5), closeTo(0.25, 1e-9)); // quadIn(0.5) == 0.25
  });

  test('a hold still holds, whatever the easing table says', () {
    const p = AnimatableDouble(baseValue: 0, keyframes: [
      Keyframe(
          progress: 0.0, value: 0.0, interpolation: KeyframeInterpolation.hold),
      Keyframe(progress: 1.0, value: 1.0),
    ]);
    expect(p.resolveAt(0.99), 0.0);
  });

  test('the sheet groups name four curves each and cover every selectable value',
      () {
    expect(kKeyframeEasingGroups.map((g) => g.label).toList(),
        ['Default', 'Quadratic', 'Cubic', 'Bounce']);
    final offered = <KeyframeInterpolation>{
      for (final g in kKeyframeEasingGroups) ...[
        g.none,
        g.easeIn,
        g.easeOut,
        g.easeInOut,
      ],
    };
    // `hold` is deliberately absent from the sheet; everything else is
    // reachable, so no curve can be added to the enum and silently orphaned.
    expect(offered,
        KeyframeInterpolation.values.toSet()..remove(KeyframeInterpolation.hold));
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/video_editor/logic/animation/animatable_double_test.dart`
Expected: FAIL — `applyKeyframeEasing` undefined, `KeyframeInterpolation.sineIn` undefined.

- [ ] **Step 3: Implement**

Replace the enum, add the curves. **`ease` is removed as a value and mapped on read**, so no
draft breaks and the sheet's grid has no cell for a synonym.

```dart
enum KeyframeInterpolation {
  /// A straight line. What a fresh diamond gets, so the easing sheet's
  /// highlighted tile ("None") tells the truth about the diamond just placed.
  linear,

  /// No travel at all: the value stays put until the next keyframe and then
  /// jumps. **Not offered in the sheet** — it is a different kind of thing from
  /// a curve, and a user reaching for "no easing" means linear. Kept because
  /// drafts carry it and step effects need it.
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
/// **`ease` was `_easeInOut`, the standard cubic.** It is no longer a value of
/// the enum, but every draft already written carries the string, so
/// [_interpolationByName] maps it here. Renaming a persisted value is a
/// migration; this *is* the migration, and it is exact — the curve is
/// unchanged, only its name.
const KeyframeInterpolation kDefaultKeyframeInterpolation =
    KeyframeInterpolation.cubicInOut;

/// The eased fraction for [t] (0..1) on [e].
///
/// **Pure `dart:math`**, like everything else in this file: a later task ports
/// it to Kotlin function for function and the shared fixture asserts the two
/// agree. Anything reaching for `Curves` could not be ported and the exported
/// file would move differently from the canvas.
double applyKeyframeEasing(KeyframeInterpolation e, double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  switch (e) {
    case KeyframeInterpolation.linear:
    // `hold` never reaches here — `resolveAt` returns before easing — but the
    // switch must be exhaustive, and linear is the honest answer for a caller
    // asking for a hold's *curve*.
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

/// The standard four-segment bounce — Penner's, the one every toolkit ships,
/// including `Curves.bounceOut`.
///
/// Written out rather than taken from Flutter, for this file's standing reason:
/// Flutter cannot be imported here and Kotlin has no equivalent. The constants
/// are exact so the port can be compared digit for digit.
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
  /// to not ease. Picking None in any group is therefore the same edit, and the
  /// sheet highlights None in whichever group the user happened to open, which
  /// is what stops "no easing" looking like four different states.
  final KeyframeInterpolation none;

  final KeyframeInterpolation easeIn;
  final KeyframeInterpolation easeOut;
  final KeyframeInterpolation easeInOut;
}

/// The families the easing sheet offers, in the order it draws them.
///
/// Sine is labelled **Default** because it is the gentlest of the four and the
/// one a user who has not thought about curves wants; the name is the user's,
/// from the design they described.
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
```

In `_interpolationByName`, add before the loop and change the fallback:

```dart
KeyframeInterpolation _interpolationByName(Object? name) {
  if (name is! String) return KeyframeInterpolation.linear;
  // The one legacy name. See [kDefaultKeyframeInterpolation].
  if (name == 'ease') return kDefaultKeyframeInterpolation;
  for (final value in KeyframeInterpolation.values) {
    if (value.name == name) return value;
  }
  // A curve this build cannot read is a curve it must not pretend to shape.
  return KeyframeInterpolation.linear;
}
```

Change `Keyframe`'s constructor default to `this.interpolation = KeyframeInterpolation.linear`,
and in `resolveAt` replace the linear/`_easeInOut` ternary with:

```dart
      final eased = applyKeyframeEasing(before.interpolation, t);
```

`_easeInOut` **stays** — the envelopes still use it.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/video_editor/logic/animation/`
Expected: PASS. Existing tests naming `KeyframeInterpolation.ease` are updated to `cubicInOut`
as part of this step; existing tests that relied on the old **default** being `ease` are updated
to state the new default explicitly.

- [ ] **Step 5: Gates and commit**

```bash
flutter analyze --no-pub
flutter test
git add -A
git commit -m "feat(keyframes): four families of easing, and ease becomes its real name"
```

---

### Task 2: The keyframable-property helpers

**Files:**
- Create: `lib/features/video_editor/logic/animation/clip_keyframes.dart`
- Test: `test/features/video_editor/logic/animation/clip_keyframes_test.dart`

**Interfaces:**
- Consumes: Task 1's enum, **and Task 3's `VideoSegment` shape** — `canvasScale`,
  `canvasOffsetX`, `canvasOffsetY`, `volume` and `effectIntensity` all `AnimatableDouble`, with
  `copyWith` taking `AnimatableDouble?` for each. Execute Task 3 first if working out of order.
- Produces: `enum ClipProperty { canvasScale, canvasOffsetX, canvasOffsetY, volume, effectIntensity }`;
  `AnimatableDouble clipParameter(VideoSegment s, ClipProperty p)`;
  `VideoSegment withClipParameter(VideoSegment s, ClipProperty p, AnimatableDouble v)`;
  `List<double> keyframeProgresses(VideoSegment s)`;
  `double? keyframeProgressNear(VideoSegment s, double progress, double tolerance)`;
  `VideoSegment captureKeyframe(VideoSegment s, double progress)`;
  `VideoSegment removeKeyframe(VideoSegment s, double progress, double tolerance)`;
  `VideoSegment setKeyframeEasing(VideoSegment s, double progress, double tolerance, KeyframeInterpolation e)`;
  `const double kKeyframeMatchProgress = 0.0005;`

**Note for the implementer:** this file is **pure functions over a segment** — no Riverpod, no
widgets, no clock. Everything about *when* an edit becomes a keyframe is Task 5's job.

- [ ] **Step 1: Write the failing tests**

```dart
VideoSegment _seg({double scale = 1.0, double volume = 1.0}) => VideoSegment(
      id: 'a',
      sourceStart: 0,
      sourceEnd: 10,
      canvasScale: AnimatableDouble(baseValue: scale),
      volume: AnimatableDouble(baseValue: volume),
    );

group('clip keyframes', () {
  test('a fresh clip has no diamonds', () {
    expect(keyframeProgresses(_seg()), isEmpty);
  });

  test('capturing pins every property at its resolved value', () {
    final s = captureKeyframe(_seg(scale: 1.6, volume: 0.4), 0.5);
    for (final p in ClipProperty.values) {
      final param = clipParameter(s, p);
      expect(param.keyframes.length, 1, reason: p.name);
      expect(param.keyframes.single.progress, 0.5, reason: p.name);
      expect(param.keyframes.single.value, param.baseValue, reason: p.name);
      expect(param.keyframes.single.interpolation, KeyframeInterpolation.linear,
          reason: p.name);
    }
    expect(keyframeProgresses(s), [0.5]);
  });

  test('capturing does not change what the clip resolves to anywhere', () {
    final before = _seg(scale: 1.6, volume: 0.4);
    final after = captureKeyframe(before, 0.5);
    for (final t in [0.0, 0.2, 0.5, 0.8, 1.0]) {
      for (final p in ClipProperty.values) {
        expect(clipParameter(after, p).resolveAt(t),
            closeTo(clipParameter(before, p).resolveAt(t), 1e-9),
            reason: '${p.name} @ $t');
      }
    }
  });

  test('a second diamond captures the curve the first one created', () {
    var s = _seg();
    s = withClipParameter(
        s,
        ClipProperty.canvasScale,
        const AnimatableDouble(baseValue: 1.0, keyframes: [
          Keyframe(progress: 0.0, value: 1.0),
          Keyframe(progress: 1.0, value: 3.0),
        ]));
    final captured = captureKeyframe(s, 0.5);
    // Linear between 1 and 3 — the interpolation a placed diamond gets.
    expect(clipParameter(captured, ClipProperty.canvasScale).resolveAt(0.5),
        closeTo(2.0, 1e-9));
    expect(keyframeProgresses(captured), [0.0, 0.5, 1.0]);
  });

  test('the diamond set is the union, so a half-written draft still shows them',
      () {
    var s = _seg();
    s = withClipParameter(
        s,
        ClipProperty.volume,
        const AnimatableDouble(
            baseValue: 1.0, keyframes: [Keyframe(progress: 0.25, value: 0.5)]));
    s = withClipParameter(
        s,
        ClipProperty.canvasScale,
        const AnimatableDouble(
            baseValue: 1.0, keyframes: [Keyframe(progress: 0.75, value: 2.0)]));
    expect(keyframeProgresses(s), [0.25, 0.75]);
  });

  test('the hit test finds a diamond within tolerance and rejects outside it',
      () {
    final s = captureKeyframe(_seg(), 0.5);
    expect(keyframeProgressNear(s, 0.503, 0.01), 0.5);
    expect(keyframeProgressNear(s, 0.6, 0.01), isNull);
  });

  test('the hit test returns the nearest when two are in range', () {
    var s = captureKeyframe(_seg(), 0.50);
    s = captureKeyframe(s, 0.52);
    expect(keyframeProgressNear(s, 0.519, 0.05), 0.52);
  });

  test('removing takes the diamond off every property', () {
    var s = captureKeyframe(_seg(), 0.25);
    s = captureKeyframe(s, 0.75);
    s = removeKeyframe(s, 0.25, 0.01);
    expect(keyframeProgresses(s), [0.75]);
    for (final p in ClipProperty.values) {
      expect(clipParameter(s, p).keyframes.length, 1, reason: p.name);
    }
  });

  test('removing the last diamond keeps the picture: its value becomes the base',
      () {
    var s = _seg();
    s = withClipParameter(
        s,
        ClipProperty.canvasScale,
        const AnimatableDouble(
            baseValue: 1.0, keyframes: [Keyframe(progress: 0.5, value: 2.4)]));
    final cleared = removeKeyframe(s, 0.5, 0.01);
    expect(keyframeProgresses(cleared), isEmpty);
    expect(clipParameter(cleared, ClipProperty.canvasScale).baseValue, 2.4);
    expect(clipParameter(cleared, ClipProperty.canvasScale).resolveAt(0.3), 2.4);
  });

  test('removing a diamond that is not there changes nothing', () {
    final s = captureKeyframe(_seg(), 0.5);
    expect(removeKeyframe(s, 0.1, 0.01), s);
  });

  test('easing is written to every property at that instant only', () {
    var s = captureKeyframe(_seg(), 0.25);
    s = captureKeyframe(s, 0.75);
    s = setKeyframeEasing(s, 0.25, 0.01, KeyframeInterpolation.bounceOut);
    for (final p in ClipProperty.values) {
      final ks = clipParameter(s, p).keyframes;
      expect(ks.firstWhere((k) => k.progress == 0.25).interpolation,
          KeyframeInterpolation.bounceOut,
          reason: p.name);
      expect(ks.firstWhere((k) => k.progress == 0.75).interpolation,
          KeyframeInterpolation.linear,
          reason: p.name);
    }
  });

  test('an envelope survives capturing, even though keyframes now win', () {
    // The envelope is not destroyed by keyframing — removing the last diamond
    // must hand the clip back to it.
    var s = withClipParameter(_seg(), ClipProperty.effectIntensity,
        const AnimatableDouble(baseValue: 0.8, envelope: 'throb'));
    s = captureKeyframe(s, 0.5);
    expect(clipParameter(s, ClipProperty.effectIntensity).envelope, 'throb');
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/video_editor/logic/animation/clip_keyframes_test.dart`
Expected: FAIL — `clip_keyframes.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
/// The clip properties a diamond pins, and the pure functions that move
/// diamonds across all of them at once.
///
/// **A keyframe is an instant, not a parameter.** A diamond at progress `p`
/// means every property in [ClipProperty] carries a keyframe at `p`; that is
/// what makes one diamond on the filmstrip an honest picture of the clip's
/// state at that moment, and what lets the plus button in the playback bar be
/// the only keyframe control in the app. Pinning one property per diamond would
/// need a property picker before a user could place anything — and a row per
/// property under the clip to show them, which is the design that was built,
/// rejected and deleted.
///
/// **Pure: a segment in, a segment out.** Nothing here knows about the
/// playhead, the clock, Riverpod or seconds. [VideoEditorNotifier] owns the
/// decision of *when* an edit becomes a keyframe, and the timeline owns where a
/// diamond is drawn.
library;

import '../../models/video_segment.dart';
import 'animatable_double.dart';

/// Every property a diamond pins.
///
/// **Adding one here is all it takes** for it to be captured, removed, eased and
/// drawn — which is the point of the enum. `speed` is deliberately absent: it
/// changes the clip's own duration, so a keyframe on it would move every other
/// keyframe's instant while it was being edited. Filter intensity is absent
/// because a filter is a colour matrix resolved per lane before the blend, on a
/// path that has no per-frame parameter hook yet.
enum ClipProperty {
  canvasScale,
  canvasOffsetX,
  canvasOffsetY,
  volume,
  effectIntensity,
}

/// Two progresses closer than this are the same diamond.
///
/// **Not the tap tolerance** — that is measured in seconds and lives in the
/// notifier, because how close a *finger* must be is a question about screens
/// and clip lengths. This is only about floating-point identity between a
/// stored progress and one recomputed from a playhead position.
const double kKeyframeMatchProgress = 0.0005;

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

VideoSegment withClipParameter(
    VideoSegment s, ClipProperty p, AnimatableDouble v) {
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
/// The **union** across properties rather than one property's list. The notifier
/// writes all five together, but a draft can arrive hand-edited or from a build
/// that wrote fewer, and a diamond a user can see but not remove is worse than
/// one drawn from a partial row.
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
double? keyframeProgressNear(
    VideoSegment s, double progress, double tolerance) {
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
/// A diamond already at [progress] is replaced, not duplicated.
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
          // Linear by default, so the easing sheet opens on "None" and tells
          // the truth about the diamond just placed.
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
/// old base would jump the picture to a value the user may have set minutes
/// ago, which reads as the editor undoing something it was not asked to undo.
VideoSegment removeKeyframe(
    VideoSegment s, double progress, double tolerance) {
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
                  progress: k.progress, value: k.value, interpolation: easing)
            else
              k,
        ],
      ),
    );
  }
  return out;
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/video_editor/logic/animation/clip_keyframes_test.dart`
Expected: PASS.

- [ ] **Step 5: Gates and commit**

```bash
flutter analyze --no-pub
flutter test
git add -A
git commit -m "feat(keyframes): a diamond is an instant, not a parameter"
```

---

### Task 3: Four scalars become parameters

The contract change, and the one with the widest blast radius. **Behaviour-preserving**: a clip
with no keyframes resolves flat and serialises as a bare number.

**Files:**
- Modify: `lib/features/video_editor/models/video_segment.dart`
- Modify: `lib/features/video_editor/models/editor_timeline.dart`
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart`
- Modify: every Dart call site the compiler names — expect `video_editor_notifier.dart`,
  `video_preview_canvas.dart`, `volume_panel.dart`, `video_editor_screen.dart`
- Test: `test/features/video_editor/models/video_segment_keyframe_test.dart` (create)
- Test: `test/features/video_editor/providers/clip_canvas_transform_test.dart` (update)

**Interfaces:**
- Consumes: Task 1's enum. Task 2's tests are written against this shape.
- Produces: on `VideoSegment` and `EditorTimelineClip`, `canvasScale`, `canvasOffsetX`,
  `canvasOffsetY` and `volume` are `AnimatableDouble`; `copyWith` takes `AnimatableDouble?` for
  each. On `VideoSegment`: `double clipProgressAt(double timelineSeconds, double timelineStart)`,
  `double canvasScaleAt(double p)`, `double canvasOffsetXAt(double p)`,
  `double canvasOffsetYAt(double p)`, `double volumeAt(double p)`, `bool get hasKeyframes`.
  The same five on `EditorTimelineClip`.

- [ ] **Step 1: Write the failing tests**

```dart
group('a clip with no keyframes is exactly what it was', () {
  test('json is bare numbers', () {
    final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5);
    final json = s.toJson();
    expect(json['volume'], 1.0);
    expect(json['canvasScale'], 1.0);
    expect(json['canvasOffsetX'], 0.0);
    expect(json['canvasOffsetY'], 0.0);
    expect(json['volume'], isA<double>());
    expect(json['canvasScale'], isA<double>());
  });

  test('an old draft of plain numbers loads', () {
    final s = VideoSegment.fromJson(const {
      'id': 'a',
      'sourceStart': 0.0,
      'sourceEnd': 5.0,
      'volume': 0.5,
      'canvasScale': 2.0,
      'canvasOffsetX': 0.1,
      'canvasOffsetY': -0.2,
    });
    expect(s.volumeAt(0.0), 0.5);
    expect(s.volumeAt(1.0), 0.5);
    expect(s.canvasScaleAt(0.5), 2.0);
    expect(s.canvasOffsetXAt(0.5), closeTo(0.1, 1e-9));
    expect(s.canvasOffsetYAt(0.5), closeTo(-0.2, 1e-9));
    expect(s.hasKeyframes, isFalse);
  });

  test('a malformed field falls back rather than throwing', () {
    final s = VideoSegment.fromJson(const {
      'id': 'a',
      'sourceStart': 0.0,
      'sourceEnd': 5.0,
      'volume': 'loud',
      'canvasScale': null,
    });
    expect(s.volumeAt(0.5), 1.0);
    expect(s.canvasScaleAt(0.5), 1.0);
  });
});

group('an animated clip', () {
  test('round-trips through json as a map', () {
    var s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5);
    s = withClipParameter(
        s,
        ClipProperty.canvasScale,
        const AnimatableDouble(baseValue: 1.0, keyframes: [
          Keyframe(progress: 0.0, value: 1.0),
          Keyframe(
              progress: 1.0,
              value: 2.0,
              interpolation: KeyframeInterpolation.bounceOut),
        ]));
    final restored =
        VideoSegment.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(restored.canvasScaleAt(0.5), closeTo(1.5, 1e-9));
    expect(restored.canvasScale.keyframes.last.interpolation,
        KeyframeInterpolation.bounceOut);
    expect(restored.hasKeyframes, isTrue);
  });

  test('clip progress is whole-clip and clamped', () {
    final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4); // duration 4
    expect(s.clipProgressAt(10.0, 10.0), 0.0);
    expect(s.clipProgressAt(12.0, 10.0), 0.5);
    expect(s.clipProgressAt(99.0, 10.0), 1.0);
    expect(s.clipProgressAt(0.0, 10.0), 0.0);
  });

  test('clip progress accounts for speed, because duration does', () {
    final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4, speed: 2.0);
    // duration == 2 on the timeline
    expect(s.clipProgressAt(11.0, 10.0), 0.5);
  });

  test('a zero-length clip resolves at progress 0, never NaN', () {
    final s = VideoSegment(id: 'a', sourceStart: 2, sourceEnd: 2);
    expect(s.clipProgressAt(5.0, 5.0), 0.0);
    expect(s.clipProgressAt(5.0, 5.0).isNaN, isFalse);
  });
});

group('the composer', () {
  test('carries an animated parameter onto the timeline clip', () {
    // compose a project whose clip has canvasScale keyframes; assert the
    // EditorTimelineClip resolves the same value at 0.5
  });

  test('refuses to merge clips when either is animated', () {
    // two adjacent same-asset clips, identical but one keyframed ->
    // playbackClips has two entries, not one
  });

  test('an unanimated clip composes bare numbers on the wire', () {
    // the clip map's four fields are num, not Map
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/video_editor/models/video_segment_keyframe_test.dart`
Expected: FAIL — `volumeAt` undefined; `canvasScale` is a `double`.

- [ ] **Step 3: Implement the model**

In `video_segment.dart`, change the four field types to `AnimatableDouble`, default them in the
constructor to `const AnimatableDouble(baseValue: 1.0)` (volume, scale) and
`const AnimatableDouble(baseValue: 0.0)` (offsets), widen `copyWith`, and add:

```dart
  /// This clip's 0..1 position at a timeline instant, given where it starts.
  ///
  /// **Whole-clip, for every keyframable property.** A diamond is one instant of
  /// the clip, so every property must measure progress the same way or one
  /// diamond would sit at two different places depending on which property was
  /// asked. The effect's *intro window* still exists and still drives the
  /// shader's `uProgress` — that is the effect's clock, a different quantity
  /// that happens to share a range.
  ///
  /// [duration] already accounts for speed, so a sped-up clip's keyframes stay
  /// where they were placed on the timeline.
  ///
  /// A zero-length clip is 0, not a division by zero.
  double clipProgressAt(double timelineSeconds, double timelineStart) {
    final d = duration;
    if (d <= 0) return 0.0;
    return ((timelineSeconds - timelineStart) / d).clamp(0.0, 1.0).toDouble();
  }

  double canvasScaleAt(double progress) => canvasScale.resolveAt(progress);
  double canvasOffsetXAt(double progress) => canvasOffsetX.resolveAt(progress);
  double canvasOffsetYAt(double progress) => canvasOffsetY.resolveAt(progress);
  double volumeAt(double progress) => volume.resolveAt(progress);

  /// Whether this clip carries any keyframe at all.
  ///
  /// What the timeline asks before drawing diamonds, what the composer asks
  /// before allowing a merge, and what the notifier's edit rule asks before
  /// deciding whether an edit is a base value or a keyframe.
  bool get hasKeyframes =>
      canvasScale.keyframes.isNotEmpty ||
      canvasOffsetX.keyframes.isNotEmpty ||
      canvasOffsetY.keyframes.isNotEmpty ||
      volume.keyframes.isNotEmpty ||
      effectIntensity.keyframes.isNotEmpty;
```

`toJson` writes `volume.toJson()`, `canvasScale.toJson()`, etc. — bare numbers while flat, so a
project that never keyframed anything has a byte-identical draft. `fromJson` reads
`AnimatableDouble.fromJson(json['volume'], fallback: 1.0)` and `fallback: 0.0` for the offsets.

Mirror all of it on `EditorTimelineClip`, including `clipProgressAt` (which there uses
`timelineEnd - timelineStart`, the value it already carries).

**Call sites.** Each `segment.volume` becomes either:
- `segment.volumeAt(progress)` where a progress is in hand (a renderer, the composer), or
- `segment.volume.baseValue` where the caller is a **control reading what to show** — the volume
  panel's slider, the speed/volume readouts. A slider tracking the resolved value would wander
  while playing and write back whatever the curve happened to be at when grabbed.

The compiler names every one; there are 13 `.volume` reads and 24 transform reads in `lib/`.

In the composer's `_canMergeForPlayback`, extend the existing animated-parameter refusal:

```dart
    // The same rule `effectIntensity` already follows, for the same reason: a
    // curve is measured across *a clip*, so a merged media item would resolve
    // one curve over the pair and the second clip's keyframes would never land
    // where the user put them.
    if (previous.hasKeyframes || next.hasKeyframes) return false;
```

…and change the epsilon comparisons in that function to read `.baseValue` on the four fields.

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS. `clip_canvas_transform_test.dart` needs its `canvasScale: 2.0` literals wrapped
as `AnimatableDouble(baseValue: 2.0)` and its assertions to read `.baseValue`; that update is
part of this step.

- [ ] **Step 5: Gates and commit**

```bash
flutter analyze --no-pub
flutter test
git add -A
git commit -m "feat(keyframes): a clip's transform and volume can move"
```

---

### Task 4: The Kotlin side

**Files:**
- Modify: `tool/generate_envelope_fixture.dart`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/AnimatableDouble.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelineClip.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/TimelinePlaybackEngine.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/VideoExportEngine.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/AudioExportMixer.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/AnimatableDoubleTest.kt`

**Interfaces:**
- Consumes: the wire shapes Task 3 writes.
- Produces: `KeyframeInterpolation` with fourteen values whose `wireName`s are the Dart enum's
  `.name` exactly; `applyKeyframeEasing(e: KeyframeInterpolation, t: Double): Double`; on
  `NativeTimelineClip`, `canvasScale`/`canvasOffsetX`/`canvasOffsetY`/`volume` as
  `AnimatableDouble` plus `clipProgressAt(t)`, `canvasScaleAt(p)`, `canvasOffsetXAt(p)`,
  `canvasOffsetYAt(p)`, `volumeAt(p)`.

- [ ] **Step 1: Extend the fixture generator**

In `tool/generate_envelope_fixture.dart` add an `easings` section — every
`KeyframeInterpolation` value sampled at `_progressSamples` — and three keyframe cases using
`bounceOut`, `quadIn` and `sineInOut`, plus one whose JSON carries the **legacy string `'ease'`**
so the alias is pinned on both sides. Then:

```bash
dart run tool/generate_envelope_fixture.dart
```

That rewrites `test/fixtures/animatable_fixture.json` **and** the copy under
`android/app/src/test/resources/`. Both are committed.

- [ ] **Step 2: Run the Kotlin test to verify it fails**

Run: `.\android\gradlew.bat -p android :app:testDebugUnitTest --tests "*AnimatableDoubleTest*"`
Expected: FAIL — the new keyframe cases name interpolations Kotlin does not know, so they
resolve linearly and diverge from the fixture.

- [ ] **Step 3: Port the easings**

Mirror Task 1 exactly: same function names, same constant values, same order, `Double`
throughout and never `Float` (this file's standing rule — Dart has no `float`, and the
difference compounds through a cubic).

```kotlin
internal enum class KeyframeInterpolation(val wireName: String) {
    LINEAR("linear"),
    HOLD("hold"),
    SINE_IN("sineIn"),
    SINE_OUT("sineOut"),
    SINE_IN_OUT("sineInOut"),
    QUAD_IN("quadIn"),
    QUAD_OUT("quadOut"),
    QUAD_IN_OUT("quadInOut"),
    CUBIC_IN("cubicIn"),
    CUBIC_OUT("cubicOut"),
    CUBIC_IN_OUT("cubicInOut"),
    BOUNCE_IN("bounceIn"),
    BOUNCE_OUT("bounceOut"),
    BOUNCE_IN_OUT("bounceInOut"),
}

/**
 * An interpolation name this build does not know degrades to [LINEAR] rather
 * than throwing, and the legacy `"ease"` resolves to the cubic it always was.
 */
internal fun keyframeInterpolationByName(name: String?): KeyframeInterpolation {
    if (name == null) return KeyframeInterpolation.LINEAR
    if (name == "ease") return KeyframeInterpolation.CUBIC_IN_OUT
    for (value in KeyframeInterpolation.entries) {
        if (value.wireName == name) return value
    }
    return KeyframeInterpolation.LINEAR
}
```

`applyKeyframeEasing` and `bounceOut` translate line for line. In `resolveAt`, replace the
linear/`easeInOut` ternary with `applyKeyframeEasing(b.interpolation, t)`. `easeInOut` stays —
the envelopes use it.

Add to `AnimatableDoubleTest.kt`:

```kotlin
@Test
fun `easing samples match the shared fixture`() {
    val rows = fixture().array("easings")
    assertTrue("fixture has no easing samples", rows.isNotEmpty())
    for (row in rows) {
        val name = row.string("interpolation")
        val e = keyframeInterpolationByName(name)
        for (sample in row.array("samples")) {
            assertClose(
                "$name @ ${sample.progress("t")}",
                sample.number("value"),
                applyKeyframeEasing(e, sample.progress("t")),
            )
        }
    }
}

@Test
fun `every interpolation name in the fixture is one this build knows`() {
    // A name that falls through to LINEAR would still pass the samples test for
    // a linear curve. This is what catches a wireName typo.
    for (row in fixture().array("easings")) {
        val name = row.string("interpolation")
        assertTrue(
            "unknown interpolation name in fixture: $name",
            KeyframeInterpolation.entries.any { it.wireName == name },
        )
    }
}
```

Keep `assertClose`'s `isFinite()` guard — NaN passes `abs(a-b) > tol`, which is how a broken
port once went green.

- [ ] **Step 4: Port the clip fields**

In `NativeTimelineClip`, the four fields become `AnimatableDouble`, read with
`AnimatableDouble.fromWire(map["volume"], fallback = 1.0)` and `fallback = 0.0` for the offsets.
Add:

```kotlin
    /**
     * This clip's 0..1 position at [timelineSeconds] — **whole-clip, for every
     * keyframable property**.
     *
     * Distinct from [effectProgressAt], which measures across the effect's intro
     * window. Both exist on purpose: a diamond is an instant of the *clip*,
     * while an intro's clock is an instant of the *effect*. Resolving a keyframe
     * against the intro window would put one diamond at two different places
     * depending on which property asked.
     */
    fun clipProgressAt(timelineSeconds: Double): Double {
        val d = timelineDuration
        if (d <= 0.0) return 0.0
        return ((timelineSeconds - timelineStart) / d).coerceIn(0.0, 1.0)
    }

    fun canvasScaleAt(p: Double): Double = canvasScale.resolveAt(p).coerceIn(0.05, 16.0)

    fun canvasOffsetXAt(p: Double): Double = canvasOffsetX.resolveAt(p)

    fun canvasOffsetYAt(p: Double): Double = canvasOffsetY.resolveAt(p)

    fun volumeAt(p: Double): Double = volume.resolveAt(p).coerceIn(0.0, 1.0)
```

**The scale clamp moves from `fromMap` to `canvasScaleAt`**, for the reason the intensity clamp
already moved: a keyframe changes the value after parsing, so a clamp at parse time clamps the
wrong number.

- [ ] **Step 5: Resolve per frame in both engines**

- `TimelinePlaybackEngine.applyLaneFits` — `val p = clip.clipProgressAt(position)`, then
  `clip.canvasScaleAt(p)` / `canvasOffsetXAt(p)` / `canvasOffsetYAt(p)`. The live transform
  override still wins: a gesture in flight is not yet in the timeline.
- `TimelinePlaybackEngine.applyAudio` — `clip.volumeAt(clip.clipProgressAt(position))` in both
  the plain branch and the crossfade branch. **`Lane.applyVolume` already change-guards on
  `VOLUME_EPSILON`**, so a keyframed volume does not rebuild the `AudioTrack` every tick. That
  guard is what makes a keyframed fade smooth rather than a source of the exact
  "volume re-applied at 60Hz" fault this engine already fixed once; say so in a comment at the
  call site.
- `VideoExportEngine` — `val p = clip.clipProgressAt(t)` before the transform block, same
  substitutions for scale and the two offsets.
- `AudioExportMixer` — `gainAt = { t -> masterVolume * clip.volumeAt(clip.clipProgressAt(t)) * crossfadeGain(clip, t) }`.
  And the silent-clip skip becomes:

```kotlin
            // **A clip keyframed up from silence is not a silent clip.** The old
            // check read the base value, which for a fade-in from 0 is 0 — so
            // the whole clip would be skipped and export with no sound at all.
            if (!clip.volume.isAnimated && clip.volume.baseValue <= 0.0) {
                skipped += "${clip.id}:vol0"
                continue
            }
```

- [ ] **Step 6: Gates and commit**

```bash
.\android\gradlew.bat -p android :app:testDebugUnitTest --tests "*AnimatableDoubleTest*"
.\android\gradlew.bat -p android compileDebugKotlin
flutter test
flutter analyze --no-pub
git add -A
git commit -m "feat(keyframes): the engines resolve a clip's moving values per frame"
```

---

### Task 5: The edit rule

**The heart of the feature.** No control gains a keyframe UI; the notifier decides.

**Files:**
- Modify: `lib/features/video_editor/models/video_editor_state.dart`
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart`
- Test: `test/features/video_editor/providers/clip_keyframe_edit_test.dart` (create)

**Interfaces:**
- Consumes: Task 2's helpers, Task 3's model.
- Produces: on `VideoEditorNotifier` — `void addKeyframeAtPlayhead()`,
  `void removeKeyframeAtPlayhead()`,
  `void setKeyframeEasingAtPlayhead(KeyframeInterpolation e)`,
  `void seekToKeyframe(double progress)`.
  On `VideoEditorState` — `String? get keyframeClipId`, `double? get keyframeClipProgress`,
  `bool get playheadIsOnKeyframe`, `List<double> get selectedClipKeyframes`,
  `KeyframeInterpolation get playheadKeyframeEasing`.
  In the state file: `const double kKeyframeHitSeconds = 0.05;`

- [ ] **Step 1: Write the failing tests**

```dart
group('the edit rule', () {
  test('with no diamonds, an edit writes the base value', () {
    // select a clip, begin/update/end a canvas transform at scale 2.0
    final s = notifier.state.segments.first;
    expect(s.canvasScale.baseValue, 2.0);
    expect(s.canvasScale.keyframes, isEmpty);
  });

  test('with diamonds, an edit at the playhead writes that keyframe', () {
    // diamond at 0.0 and at 1.0, seek to the clip's end, pinch to 3.0
    final s = notifier.state.segments.first;
    expect(s.canvasScale.keyframes.last.value, 3.0);
    expect(s.canvasScale.keyframes.length, 2);
    expect(s.canvasScale.baseValue, 1.0); // untouched
  });

  test('with diamonds, an edit away from any diamond places one first', () {
    // diamonds at 0.0 and 1.0, seek to the middle, commit volume 0.2
    final s = notifier.state.segments.first;
    expect(keyframeProgresses(s).length, 3);
    for (final p in ClipProperty.values) {
      expect(clipParameter(s, p).keyframes.length, 3, reason: p.name);
    }
    expect(s.volumeAt(0.5), closeTo(0.2, 1e-9));
  });

  test('placing a diamond changes nothing the renderer resolves', () {
    // capture every property's resolveAt over a sweep before and after
    // addKeyframeAtPlayhead; assert equal
  });

  test('the playhead is on a diamond within a tolerance measured in seconds',
      () {
    // a 10s clip with a diamond at progress 0.5 (5.0s):
    // playhead 5.03s -> true, 5.2s -> false.
    // Then a 1s clip: the same 0.05s is progress 0.05, so 0.52 -> true.
  });

  test('a whole gesture is one undo step even when it keyframes', () {
    // begin + N updates + end -> one undo restores the pre-gesture state
  });

  test('removing the last diamond keeps the picture', () {
    // scale keyframed to 2.4 at the playhead; remove -> baseValue 2.4
  });

  test('the easing writes to the diamond under the playhead only', () {});

  test('choosing an easing with the playhead between diamonds places one', () {
    // the sheet and the plus button must agree about what "here" means
  });

  test('with no clip selected there is no keyframe clip', () {
    expect(notifier.state.keyframeClipId, isNull);
    expect(notifier.state.playheadIsOnKeyframe, isFalse);
  });

  test('effect intensity keyframes through the same rule as everything else',
      () {
    // set an effect, place a diamond, move the playhead to it, set intensity
    // -> the keyframe's value changed, the base did not
  });

  test('seeking to a keyframe puts the playhead exactly on it', () {
    // seekToKeyframe(0.25) on a clip starting at 4.0s of duration 8.0
    // -> currentPlaybackPosition == 6.0
  });

  test('clearing an effect leaves transform keyframes alone', () {
    // the old design dropped keyframes with the effect; they are not the
    // effect's property any more
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/video_editor/providers/clip_keyframe_edit_test.dart`
Expected: FAIL — `addKeyframeAtPlayhead` undefined.

- [ ] **Step 3: Delete the old surface**

From `video_editor_state.dart`: `keyframeEditorSegmentId`, `selectedKeyframeProgress`,
`selectedKeyframe`, `showsKeyframeRowFor`, and the matching `copyWith` parameters
(`clearKeyframeEditorSegmentId`, `clearSelectedKeyframeProgress`) — 17 references.

From `video_editor_notifier.dart`: `openKeyframeEditor`, `closeKeyframeEditor`,
`toggleKeyframeEditor`, `selectKeyframe`, `addEffectIntensityKeyframe`,
`moveEffectIntensityKeyframe`, `removeEffectIntensityKeyframe`,
`setEffectIntensityKeyframeInterpolation`, `setEffectIntensityKeyframeValue`, and the two
`clearSelectedKeyframeProgress:` sites at ~532 and ~552. Keep `_updateEffectIntensity` but route
it through the new rule in Step 5.

**In `setClipEffect`, delete the "a changed effect drops its keyframes" branch.** Keyframes are
the clip's, not the effect's; changing an effect must leave the transform and volume keyframes
standing. The effect intensity's *own* keyframes still reset with the effect — that part is
right and stays.

- [ ] **Step 4: Add the state accessors**

```dart
/// How close the playhead must be to a diamond to count as sitting on it.
///
/// **Seconds, not progress.** The same progress tolerance is a different number
/// of frames on a 1s clip and a 30s one, so a fixed progress window would make
/// diamonds unhittable on long clips and impossible to step off on short ones.
/// 0.05s is about a frame and a half at 30fps — tight enough that two diamonds
/// a user placed deliberately stay distinct, loose enough that a playhead
/// parked by a tap lands on one.
const double kKeyframeHitSeconds = 0.05;
```

On `VideoEditorState`:

```dart
  /// The clip diamonds are drawn on and the playback-bar controls act on.
  ///
  /// Null with nothing selected, which is what takes the plus button out of the
  /// bar — a keyframe belongs to a clip, and a control with nothing to act on is
  /// the "slider that lies" problem in a smaller package.
  String? get keyframeClipId =>
      isClipSelected ? selectedSegmentId : null;

  /// The playhead's progress through that clip, or null.
  ///
  /// Resolved through `segmentTimelineStarts` and `VideoSegment.clipProgressAt`
  /// — the same geometry the filmstrip and playback use, so a diamond drawn at
  /// progress p sits under the playhead that reports p, through trims, speed
  /// and transition overlaps.
  double? get keyframeClipProgress { … }

  /// The diamond under the playhead, or null. The **selection is the playhead**:
  /// nothing is stored, which is what makes the plus/minus flip and the easing
  /// sheet agree about what "here" means without a third piece of state to keep
  /// in step.
  double? get playheadKeyframeProgress { … }

  bool get playheadIsOnKeyframe => playheadKeyframeProgress != null;

  /// Every diamond on the selected clip, for the timeline to draw.
  List<double> get selectedClipKeyframes { … }

  /// The easing of the diamond under the playhead, or [KeyframeInterpolation.linear]
  /// when there is none — which is what a fresh diamond would get, so the sheet
  /// opens showing what choosing a curve here would replace.
  KeyframeInterpolation get playheadKeyframeEasing { … }
```

- [ ] **Step 5: Write the edit rule**

```dart
  /// **The one place an edit decides whether it is a base value or a keyframe.**
  ///
  /// This is what makes the plus button the only keyframe control in the app.
  /// Every existing control — the pinch gesture, the volume slider, the effect
  /// intensity slider — calls this and inherits keyframing without knowing the
  /// feature exists. The alternative, a keyframe-aware variant of each control,
  /// is exactly how the rejected design ended up able to animate one number.
  ///
  /// - **No diamonds:** write the base. Byte-identical to what each control did
  ///   before this existed, which is what keeps an unkeyframed project
  ///   unchanged.
  /// - **Diamonds, playhead on one:** write that keyframe's value, leaving the
  ///   base alone.
  /// - **Diamonds, playhead between them:** place a diamond first — capturing
  ///   every other property at that instant so nothing else moves — then write.
  ///
  /// Takes no undo snapshot: the caller's gesture already did, once.
  VideoSegment _writeClipValue(
    VideoSegment segment,
    ClipProperty property,
    double value, {
    required double? playheadProgress,
  }) {
    final param = clipParameter(segment, property);
    if (!segment.hasKeyframes || playheadProgress == null) {
      return withClipParameter(
          segment, property, param.copyWith(baseValue: value));
    }

    final tolerance = _keyframeHitTolerance(segment);
    var out = segment;
    var target = keyframeProgressNear(segment, playheadProgress, tolerance);
    if (target == null) {
      out = captureKeyframe(segment, playheadProgress);
      target = playheadProgress;
    }

    final p = clipParameter(out, property);
    return withClipParameter(
      out,
      property,
      AnimatableDouble.sorted(
        baseValue: p.baseValue,
        envelope: p.envelope,
        keyframes: [
          for (final k in p.keyframes)
            if ((k.progress - target!).abs() <= kKeyframeMatchProgress)
              Keyframe(
                  progress: k.progress,
                  value: value,
                  interpolation: k.interpolation)
            else
              k,
        ],
      ),
    );
  }

  /// [kKeyframeHitSeconds] expressed as progress on this clip.
  ///
  /// Capped at 0.5 so a clip shorter than a tenth of a second cannot make every
  /// point on it "on" every diamond.
  double _keyframeHitTolerance(VideoSegment s) => s.duration <= 0
      ? 1.0
      : (kKeyframeHitSeconds / s.duration).clamp(0.0, 0.5).toDouble();
```

Route through it: `updateClipCanvasTransform` (three properties, `takeUndoSnapshot` already
handled by `beginClipCanvasTransform`), `commitPreviewVolume`, `resetClipCanvasTransform`, and
`_updateEffectIntensity`. Then add the four public methods:

```dart
  /// Places a diamond at the playhead, pinning every property at the value it
  /// already has there — so the picture does not change.
  void addKeyframeAtPlayhead() { /* saveStateForUndo, captureKeyframe */ }

  /// Removes the diamond under the playhead from every property.
  void removeKeyframeAtPlayhead() { /* saveStateForUndo, removeKeyframe */ }

  /// Re-eases the diamond under the playhead, **placing one first if there is
  /// none** — the same rule [_writeClipValue] follows, so the two controls can
  /// never disagree about what "here" means.
  void setKeyframeEasingAtPlayhead(KeyframeInterpolation easing) { … }

  /// Moves the playhead onto a diamond.
  ///
  /// What makes tapping a diamond then tapping minus remove it — which is the
  /// interaction the plus/minus flip promises, and it needs the playhead to
  /// actually be on the diamond for the flip to happen.
  void seekToKeyframe(double progress) { /* timelineStart + progress * duration */ }
```

`seekToKeyframe` writes `updatePlaybackPosition` **and** issues the preview seek, the same pair
any other programmatic playhead move makes; find that pairing at the existing scrub call site
rather than inventing a second one.

- [ ] **Step 6: Run the tests, then the suite**

Run: `flutter test`
Expected: PASS. `effects_panel_test.dart`'s five keyframe assertions fail here because the state
fields are gone; they are deleted in Task 7 along with the button they test, so **stub them out
with a `skip:` in this task and delete them in Task 7** rather than leaving the suite red.

- [ ] **Step 7: Gates and commit**

```bash
flutter analyze --no-pub
flutter test
git add -A
git commit -m "feat(keyframes): one rule decides base value or keyframe"
```

---

### Task 6: Diamonds on the thumbnail

**Files:**
- Create: `lib/features/video_editor/widgets/timeline/clip_keyframe_diamonds.dart`
- Delete: `lib/features/video_editor/widgets/timeline/keyframe_row.dart`
- Delete: `test/features/video_editor/widgets/keyframe_row_test.dart`
- Modify: `lib/features/video_editor/widgets/timeline/scrollable_timeline.dart`
- Test: `test/features/video_editor/widgets/clip_keyframe_diamonds_test.dart` (create)

**Interfaces:**
- Consumes: `state.selectedClipKeyframes`, `notifier.seekToKeyframe`.
- Produces: `class ClipKeyframeDiamonds extends ConsumerWidget` taking
  `{required VideoSegment segment, required double widthPx, required double height}`;
  `class KeyframeDiamond extends StatelessWidget` taking `{required bool isSelected, double size}`
  — moved out of the deleted file so widget tests can still find a diamond by type.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('no diamonds on an unkeyframed clip', (t) async {
  // pump with a fresh segment
  expect(find.byType(KeyframeDiamond), findsNothing);
});

testWidgets('a diamond sits at its progress across the clip width', (t) async {
  // one diamond at progress 0.25 on a 200px-wide clip
  final centre = tester.getCenter(find.byType(KeyframeDiamond));
  expect(centre.dx, closeTo(50.0, 0.5)); // relative to the clip's own box
});

testWidgets('diamonds are vertically centred on the thumbnail', (t) async {
  // centre y == height / 2 — not above the filmstrip and not below it
});

testWidgets('tapping a diamond seeks the playhead onto it', (t) async {
  // tap -> currentPlaybackPosition == clipStart + 0.25 * duration
});

testWidgets('the diamond under the playhead reads as selected', (t) async {
  // isSelected true for the one the playhead is on, false for the others
});

testWidgets('several diamonds draw at several places', (t) async {
  // three progresses -> three diamonds, x-ordered
});
```

And in the timeline's own test file:

```dart
testWidgets('keyframes do not change the timeline height', (t) async {
  // measure the lane stack top with and without keyframes on the selected clip
  // -> identical. The rejected row pushed every lane down.
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/video_editor/widgets/clip_keyframe_diamonds_test.dart`
Expected: FAIL — `clip_keyframe_diamonds.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
/// The diamonds that mark a clip's keyframed instants, drawn **on the
/// filmstrip**.
///
/// On the thumbnail rather than in a row of its own, for two reasons. It is
/// where the user pictured them — and a row is a lie about what a keyframe is
/// here: a row implies one lane per animated property, while a diamond pins
/// every property at once. It also costs the timeline no height; the row this
/// replaces pushed every lane down whenever it opened.
///
/// **Drawn inside the clip's own layout box**, so it inherits the filmstrip's
/// position through trims, reorders and transition overlaps without a second
/// copy of the geometry — positioned by `_clipLayouts()` like everything else
/// on the clip track.
///
/// **The selection is the playhead.** A diamond draws as selected when the
/// playhead is on it; there is no stored selection to fall out of step with the
/// playback-bar controls.
class ClipKeyframeDiamonds extends ConsumerWidget { … }
```

Body: a `Stack` of `Positioned` hit boxes at `progress * widthPx - _kHitSize / 2`, vertically
centred (`top: (height - _kHitSize) / 2`), each a `GestureDetector(behavior:
HitTestBehavior.opaque, onTap: () { HapticFeedback.selectionClick(); notifier.seekToKeyframe(p); })`
wrapping a `KeyframeDiamond`. `_kHitSize` 32, `_kDiamondSize` 11.

`KeyframeDiamond` is the 45°-rotated square from the deleted file, with **a dark outline as well
as a light fill** — a plain white diamond is invisible on a bright thumbnail, and this now draws
over arbitrary footage rather than over a dark row.

Mount it in `scrollable_timeline.dart` inside the clip-track stack, directly after the filmstrip,
only for the clip `keyframeClipId` names. Then **delete**: `_keyframeClipLayout`,
`_effectProgressAtPlayhead`, `_keyframeRowHeight`, `keyframeRowTop`, `keyframeRowSpace`, the
`KeyframeRow` mount, the pinned `KeyframeRowControls` overlay and the `keyframe_row.dart` import.
`lanesTop` goes back to `filmstripTop + _filmstripHeight`.

- [ ] **Step 4: Run the tests and the suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Gates and commit**

```bash
flutter analyze --no-pub
flutter test
git add -A
git commit -m "feat(keyframes): diamonds on the thumbnail, and the row is gone"
```

---

### Task 7: The playback-bar controls and the easing sheet

**Files:**
- Modify: `lib/features/video_editor/widgets/editor_playback_controls.dart`
- Create: `lib/features/video_editor/widgets/panels/keyframe_easing_sheet.dart`
- Modify: `lib/screens/video_editor_screen.dart` (`_buildPlaybackControls`, ~line 1241)
- Modify: `lib/features/video_editor/widgets/panels/effects_panel.dart`
- Modify: `test/features/video_editor/widgets/effects_panel_test.dart`
- Test: `test/features/video_editor/widgets/editor_playback_controls_test.dart` (create)
- Test: `test/features/video_editor/widgets/keyframe_easing_sheet_test.dart` (create)

**Interfaces:**
- Consumes: Task 5's notifier methods and state accessors; Task 1's `kKeyframeEasingGroups`.
- Produces: `EditorPlaybackControls` gains
  `{bool showsKeyframeControls = false, bool isOnKeyframe = false, VoidCallback? onToggleKeyframe, VoidCallback? onOpenEasing}`;
  `Future<void> showKeyframeEasingSheet(BuildContext context, {required KeyframeInterpolation current, required ValueChanged<KeyframeInterpolation> onSelected})`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('no clip selected, no keyframe controls', (t) async {
  // showsKeyframeControls: false -> neither icon is in the tree
});

testWidgets('the controls sit between the play button and the time', (t) async {
  final play = tester.getCenter(find.byIcon(LucideIcons.play));
  final add = tester.getCenter(find.byKey(const Key('keyframe_toggle')));
  final ease = tester.getCenter(find.byKey(const Key('keyframe_easing')));
  final label = tester.getCenter(find.text('00:02 / 00:10'));
  expect(play.dx, lessThan(add.dx));
  expect(add.dx, lessThan(ease.dx));
  expect(ease.dx, lessThan(label.dx));
});

testWidgets('off a diamond the control adds; on one it removes', (t) async {
  // isOnKeyframe false -> tapping calls onToggleKeyframe, and the widget
  // reports its add/remove state through a findable marker
});

testWidgets('the easing sheet shows four groups of four', (t) async {
  expect(find.text('Default'), findsOneWidget);
  expect(find.text('Quadratic'), findsOneWidget);
  expect(find.text('Cubic'), findsOneWidget);
  expect(find.text('Bounce'), findsOneWidget);
  expect(find.text('None'), findsNWidgets(4));
  expect(find.text('Ease in'), findsNWidgets(4));
  expect(find.text('Ease out'), findsNWidgets(4));
  expect(find.text('Ease'), findsNWidgets(4));
});

testWidgets('the current easing is highlighted and a tap reports it', (t) async {
  // open with current: bounceOut -> that tile is marked; tap Cubic's "Ease"
  // -> onSelected(KeyframeInterpolation.cubicInOut)
});

testWidgets('the effects panel has no keyframe button', (t) async {
  expect(find.byIcon(LucideIcons.diamond), findsNothing);
  expect(find.text('Intensity'), findsOneWidget);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/video_editor/widgets/editor_playback_controls_test.dart`
Expected: FAIL — no such parameters on `EditorPlaybackControls`.

- [ ] **Step 3: Implement the controls**

The row keeps `MainAxisAlignment.spaceBetween`; the play button and the two new icons go into
one leading `Row`, so the time label keeps its position and the trailing undo/redo group is
untouched.

```dart
          Row(
            children: [
              GestureDetector(
                onTap: onTogglePreview,
                child: Icon(isPlaying ? LucideIcons.pause : LucideIcons.play, …),
              ),
              // **Only while a clip is selected.** A keyframe belongs to a clip;
              // with none selected there is nothing for the button to act on,
              // and a control that is present but inert is a control that lies.
              if (showsKeyframeControls) ...[
                const SizedBox(width: 18),
                GestureDetector(
                  key: const Key('keyframe_toggle'),
                  onTap: onToggleKeyframe,
                  // One control, not two: "add" and "remove" are never both
                  // available at the same instant, so a second button would
                  // always have one of them dead.
                  child: _KeyframeToggleIcon(isOnKeyframe: isOnKeyframe),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  key: const Key('keyframe_easing'),
                  onTap: onOpenEasing,
                  child: const Icon(LucideIcons.spline, …),
                ),
              ],
            ],
          ),
```

**`lucide_icons` 0.257.0 has `diamond`, `plus` and `minus` but no `diamondPlus`/`diamondMinus`**
— checked against the installed package while writing this plan, so the composite is the route,
not a fallback. `_KeyframeToggleIcon` lives in this file and draws a `Stack`: the same
45°-rotated square `KeyframeDiamond` uses, with a small `LucideIcons.plus` / `LucideIcons.minus`
centred on it, sized to match the bar's other 24px icons. **Do not substitute an unrelated
icon** — the diamond is how the user recognises the control, and it must match the diamonds on
the thumbnail.

It needs `import 'package:flutter/services.dart';` for `HapticFeedback`, which this file does
not currently import.

Wire it in `_buildPlaybackControls`:

```dart
      showsKeyframeControls: editorState.keyframeClipId != null,
      isOnKeyframe: editorState.playheadIsOnKeyframe,
      onToggleKeyframe: () {
        HapticFeedback.selectionClick();
        final notifier = ref.read(videoEditorProvider.notifier);
        if (editorState.playheadIsOnKeyframe) {
          notifier.removeKeyframeAtPlayhead();
        } else {
          notifier.addKeyframeAtPlayhead();
        }
      },
      onOpenEasing: () => showKeyframeEasingSheet(
        context,
        current: editorState.playheadKeyframeEasing,
        onSelected: (e) =>
            ref.read(videoEditorProvider.notifier).setKeyframeEasingAtPlayhead(e),
      ),
```

- [ ] **Step 4: Implement the sheet**

A `showModalBottomSheet` with `mainAxisSize: MainAxisSize.min` — **the small sheet the user
described**, not a half-screen panel. Four labelled groups, each a row of four tiles: None,
Ease in, Ease out, Ease. The current curve's tile is outlined in the accent colour. Square
chrome, `AppColors`, dark theme.

Each tile is a small **curve preview** painted from `applyKeyframeEasing` — a 24×16
`CustomPaint` plotting the curve — rather than a text-only chip. It costs one tiny painter and
it is the only way "Quadratic ease out" and "Cubic ease out" are distinguishable before you use
them.

```dart
/// The easing sheet: four families, four cells each.
///
/// **It acts on the diamond under the playhead**, and places one if there is
/// none — the same rule the intensity slider and the pinch gesture follow, so
/// no two controls can disagree about what "here" means.
Future<void> showKeyframeEasingSheet(…)
```

- [ ] **Step 5: Delete the panel button**

From `effects_panel.dart`: `KeyframeToggleButton` (the whole class), the `keyframesOpen` and
`keyframe:` parameters of `_intensityRow`, the two-subject label logic and the
`LucideIcons.diamond` swap. The row returns to a plain `'Intensity'` label and its slider writes
through the notifier's effect-intensity path, which Task 5 routed through `_writeClipValue` — so
it keyframes itself when the clip has diamonds, with no control of its own.

Delete the five keyframe assertions from `effects_panel_test.dart` (the ones stubbed with
`skip:` in Task 5).

- [ ] **Step 6: Run the suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Gates and commit**

```bash
flutter analyze --no-pub
flutter test
git add -A
git commit -m "feat(keyframes): the diamond lives in the playback bar"
```

---

### Task 8: The edges — split, merge, undo, round-trip

**Files:**
- Test: `test/features/video_editor/providers/clip_keyframe_integration_test.dart` (create)
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart:650` (`splitAtPosition`
  — it already copies the transform to both halves at ~line 718, which is the line that has to
  learn about keyframes)
- Modify: whatever else these find.

- [ ] **Step 1: Write the tests**

```dart
test('a Ken Burns move survives a draft round-trip', () {
  // diamond at 0.0 scale 1.0, diamond at 1.0 scale 1.8; save, load
  expect(restored.segments.first.canvasScaleAt(0.5), closeTo(1.4, 1e-9));
});

test('splitting a keyframed clip keeps each half telling the same story', () {
  // scale 1.0 -> 3.0 across a 10s clip, split at 5s.
  // The left half at its own end and the right half at its own start must both
  // resolve to 2.0 — the value the unsplit clip had at the seam.
  expect(left.canvasScaleAt(1.0), closeTo(2.0, 1e-6));
  expect(right.canvasScaleAt(0.0), closeTo(2.0, 1e-6));
  // and every keyframe is inside 0..1 on its own half
  for (final half in [left, right]) {
    for (final p in ClipProperty.values) {
      for (final k in clipParameter(half, p).keyframes) {
        expect(k.progress, inInclusiveRange(0.0, 1.0));
      }
    }
  }
});

test('a keyframed clip is never merged for playback', () {
  // two adjacent same-asset clips, one keyframed -> two playbackClips
});

test('undo walks back a whole keyframing gesture, not a frame of it', () {});

test('deleting the effect leaves transform keyframes alone', () {});

test('a clip with no keyframes composes bare numbers on the wire', () {
  final map = timeline.toJson()['videoClips'][0] as Map<String, dynamic>;
  expect(map['volume'], isA<num>());
  expect(map['canvasScale'], isA<num>());
  expect(map['canvasOffsetX'], isA<num>());
  expect(map['canvasOffsetY'], isA<num>());
});
```

- [ ] **Step 2: Run, implement what fails, re-run**

The split is the case needing real work. `splitAtPosition` copies the transform to both halves
and must now **rescale each property's keyframes into the half's own 0..1**:

```dart
    // **A keyframe's progress is clip-relative, so a split must rescale it.**
    // Copying the lists verbatim would leave the left half's later keyframes
    // sitting past its own end (where they hold, silently freezing the move)
    // and the right half's earlier ones bunched before its start.
    //
    // Capture at the cut on both halves *first*, so the value at the seam is
    // identical either side and the split is invisible. Then, for the left
    // half, keep p <= cut and map p -> p / cut; for the right, keep p >= cut
    // and map p -> (p - cut) / (1 - cut).
```

Write it as a helper next to the split rather than inline, and test the degenerate cuts (at 0
and at 1) — both must leave one half unkeyframed rather than dividing by zero.

- [ ] **Step 3: Gates and commit**

```bash
flutter analyze --no-pub
flutter test
.\android\gradlew.bat -p android compileDebugKotlin
git add -A
git commit -m "test(keyframes): the edges — split, merge, undo, round-trip"
```

---

### Task 9: Device verification

Build and hand over. **Nothing here is verifiable on a desktop** — the preview engine, the
export and the audio path all need hardware, and GLSL is only ever proven on a device.

- [ ] **Step 1: Build**

```bash
flutter build apk --debug
```

- [ ] **Step 2: The checklist to hand the user**

1. **No clip selected:** no diamond icons in the playback bar. Select a clip and they appear,
   between the play button and the time.
2. **Tap the plus:** a diamond appears on the thumbnail, vertically centred, at the playhead.
   **The picture does not change.**
3. **The icon flips to minus** while the playhead is on it; scrub away and it is a plus again.
4. **Tap the diamond on the thumbnail:** the playhead jumps onto it and the icon flips.
5. **Tap minus:** the diamond goes, and the picture still does not change.
6. **A Ken Burns move:** diamond at the clip's start, seek to the end, pinch to zoom in, play.
   The clip should push in smoothly across its whole length.
7. **Easing:** put the playhead on the second diamond, open the curve sheet, choose
   Bounce ▸ Ease out, replay. The move should overshoot and settle.
8. **Volume:** two diamonds, volume 1.0 at the first and 0 at the second. The clip should fade
   out over its length with **no crackle and no stepping**.
9. **Effect intensity** keyframes the same way from the effects sheet's slider — and there is
   **no keyframe button on that sheet**.
10. **Export** items 6, 7 and 8 and confirm the file matches the canvas.
11. **Unchanged:** a project with no keyframes — playback, transitions, filters, text overlays,
    export — behaves exactly as before.
12. **A split across a keyframed move** leaves both halves moving continuously, with no jump at
    the seam.

- [ ] **Step 3: Update CLAUDE.md**

A "Keyframes — a diamond is an instant of a clip" section covering: the edit rule and why no
control has a keyframe UI of its own; whole-clip progress versus the effect's intro window; the
easing families and the `ease` → `cubicInOut` alias; `kKeyframeHitSeconds` being seconds, not
progress; the split rescale; the `AudioExportMixer` silent-skip subtlety; and the record that the
effects-panel row was built and deleted.

- [ ] **Step 4: Update `docs/dead-ends.md`**

One entry: the effects-panel keyframe row — what was built, why it was rejected (a deliberately
general model put behind a feature-specific UI, so it could animate exactly one number), and the
rule it produces: **a keyframe control belongs to the clip, never to a tool panel.**

## Exit criteria

- [ ] The diamond-with-plus appears in the playback bar only while a clip is selected, between
      the play button and the time readout.
- [ ] A diamond draws on the thumbnail, vertically centred, at the playhead; the timeline gains
      no height.
- [ ] The icon flips to minus when the playhead is on a diamond, and removes it.
- [ ] The easing sheet offers Default / Quadratic / Cubic / Bounce × (None, Ease in, Ease out,
      Ease) and applies to the diamond at the playhead.
- [ ] Transform, volume and effect intensity all keyframe through the same rule, with no
      keyframe control on any tool panel.
- [ ] A clip with no keyframes renders, serialises and composes byte-identically.
- [ ] Dart and Kotlin agree on every easing curve, pinned by the regenerated fixture.
- [ ] `flutter test`, `flutter analyze --no-pub` (48), `compileDebugKotlin` all pass.
- [ ] Device-verified against the checklist in Task 9.
