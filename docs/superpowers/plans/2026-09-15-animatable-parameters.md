# Animatable Parameters (Effects Stages 3 & 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An effect's intensity can vary over the clip — automatically from the effect's own envelope, or manually from keyframes the user drags on the timeline. Presets for everyone, keyframes for those who ask.

**Architecture:** One general **animatable parameter** — a base value, an optional envelope, an optional keyframe list — evaluated by a single function shared by Dart and Kotlin. Effects are its first consumer; transform, opacity and volume plug into the same model later with no rebuild and no draft migration.

**Tech Stack:** Flutter/Dart, Kotlin, Riverpod.

**Spec:** `docs/superpowers/specs/2026-09-12-clip-effects-design.md`

**Depends on:** the effect clock (`uProgress`, timeline-resolved in both engines) and the per-clip effect contract, both landed. **35 of 39 effects are not yet device-verified** — see the constraint below.

## Global Constraints

- **This stage must not change how any existing effect renders.** A clip whose effect has no envelope and no keyframes must produce the byte-identical frame it produces today. 35 effects are awaiting a device check; if this stage alters them, a later bug report cannot be attributed.
- **Evaluation happens once, in one place.** Keyframes override the envelope, which overrides nothing — a single evaluator, ported to Kotlin and pinned by a fixture, exactly as `TextAnimationCurves` is. Two implementations of "what is the intensity now" is the drift this codebase keeps paying for.
- **Intensity reaches the renderer as a resolved scalar per frame.** `ClipEffectController.apply(effectId, intensity, progress)` already takes a per-frame intensity, so an animated one needs **no new uniform and no shader change**. Do not add a second animation path inside the shaders.
- **The timeline clock is the only clock.** Evaluate against the same position `effectProgressAt` uses. A frame counter or `System.nanoTime` makes the export differ from the preview.
- **Undo:** `saveStateForUndo()` once per gesture, never per frame.
- **Serialisation is hand-written and defensive**; a draft written before this stage must load with no envelope, no keyframes, and no error.
- Analyzer baseline is exactly **48**. Add none.
- Verify with `flutter analyze --no-pub`, `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.

## The model, and why it is general

Keyframes are a **timeline** feature, not an effects feature. The moment they exist users expect
them on transform (Ken Burns), opacity and volume. Built inside the effects system they would
work in exactly one place and need a rebuild plus a draft migration when the next consumer
arrives — so the model is general from the first commit and effects merely happen to be first.

```
AnimatableDouble
  baseValue      the scalar the user set (today's effectIntensity)
  envelope       optional, named: a curve over the clip, from the catalog
  keyframes      optional, ordered [(progress 0..1, value)]
  interpolation  linear | ease | hold
```

**Resolution order, and it is not negotiable:** keyframes if any exist, else the envelope if the
effect declares one, else the base value flat. The first keyframe on a parameter means the user
has taken manual control and the envelope steps aside — no mode to enter, nothing to switch off,
and no state where both are half-applied.

**Keyframe positions are clip-relative `0..1`, not seconds.** A clip that is trimmed or sped up
keeps its keyframes where they look right, and a draft renders identically on any device. This is
the same reason every other geometry in this codebase is a fraction.

---

### Task 1: The animatable parameter and its evaluator

Pure Dart. No UI, no rendering, nothing wired — the model and the one function that reads it.

**Files:**
- Create: `lib/features/video_editor/logic/animation/animatable_double.dart`
- Test: `test/features/video_editor/logic/animation/animatable_double_test.dart`

**Interfaces:**
- Produces:
  - `enum KeyframeInterpolation { linear, ease, hold }`
  - `class Keyframe { const Keyframe({required this.progress, required this.value, this.interpolation = KeyframeInterpolation.ease}); … }`
  - `class AnimatableDouble { const AnimatableDouble({required this.baseValue, this.envelope, this.keyframes = const []}); final double baseValue; final String? envelope; final List<Keyframe> keyframes; bool get isAnimated; double resolveAt(double progress); Map<String, dynamic> toJson(); factory AnimatableDouble.fromJson(Map<String, dynamic>); }`
  - `double resolveEnvelope(String name, double progress)` — the named envelope curves.

- [ ] **Step 1: Write the failing tests**

Cover, at minimum:

```dart
group('resolveAt', () {
  test('a plain value is flat across the clip', () {
    const p = AnimatableDouble(baseValue: 0.6);
    for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      expect(p.resolveAt(t), 0.6);
    }
    expect(p.isAnimated, isFalse);
  });

  test('keyframes override an envelope entirely', () {
    // The whole rule of the feature: one keyframe means the user has taken
    // control, and the envelope must not blend into the result.
    const p = AnimatableDouble(
      baseValue: 0.5,
      envelope: 'pulse',
      keyframes: [Keyframe(progress: 0, value: 0.1), Keyframe(progress: 1, value: 0.9)],
    );
    expect(p.resolveAt(0), closeTo(0.1, 1e-9));
    expect(p.resolveAt(1), closeTo(0.9, 1e-9));
    // Mid-clip must sit between the two keyframes, never wander off on the
    // envelope's curve.
    expect(p.resolveAt(0.5), inInclusiveRange(0.1, 0.9));
  });

  test('a single keyframe holds its value everywhere', () {
    const p = AnimatableDouble(baseValue: 0.5, keyframes: [Keyframe(progress: 0.5, value: 0.2)]);
    expect(p.resolveAt(0), closeTo(0.2, 1e-9));
    expect(p.resolveAt(1), closeTo(0.2, 1e-9));
  });

  test('before the first and after the last keyframe, the value holds', () {
    const p = AnimatableDouble(baseValue: 0, keyframes: [
      Keyframe(progress: 0.3, value: 0.2),
      Keyframe(progress: 0.7, value: 0.8),
    ]);
    expect(p.resolveAt(0.0), closeTo(0.2, 1e-9));
    expect(p.resolveAt(1.0), closeTo(0.8, 1e-9));
  });

  test('hold interpolation steps rather than ramps', () { … });

  test('unordered keyframes are sorted, not trusted', () { … });

  test('an unknown envelope name resolves to the base value', () {
    // Same rule unknown effect and transition ids follow: degrade, never throw.
  });

  test('progress outside 0..1 is clamped', () { … });
});

group('serialisation', () {
  test('a plain value round-trips', () { … });
  test('an envelope and keyframes round-trip in order', () { … });
  test('a pre-stage draft (a bare number) loads as a plain value', () {
    // The field was a double before this stage. Reading one must not throw.
  });
});
```

- [ ] **Step 2: Run them and watch them fail**

- [ ] **Step 3: Implement**

Rules: pure functions, `dart:math` only; `resolveAt` must be cheap (it runs per frame); an empty
keyframe list is not animated; sort defensively on construction rather than trusting input.

Seed the envelopes with the shapes the spec names — `pulse`, `ramp_in`, `ramp_out`,
`ramp_in_out`, `throb` — each a pure function of progress returning a 0..1 multiplier of the base
value. Comment what each is *for*, not what it computes.

- [ ] **Step 4: Tests, full gates, commit**

---

### Task 2: The Kotlin port, pinned by a fixture

The evaluator runs in the export too, and a divergence is a file that differs from the canvas.

**Files:**
- Create: `tool/generate_envelope_fixture.dart`
- Create: `test/fixtures/animatable_fixture.json` + a copy under `android/app/src/test/resources/`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/AnimatableDouble.kt`
- Create: `android/app/src/test/kotlin/…/AnimatableDoubleTest.kt`
- Test: `test/features/video_editor/logic/animation/animatable_fixture_test.dart`

- [ ] **Step 1: Generate the fixture**

Sample every envelope, and a set of representative keyframe configurations, across
`progress ∈ {0, 0.1, 0.25, 0.5, 0.75, 0.9, 1}`. Round to 6 decimals.

**This is the same mechanism `text_animation_fixture.json` uses**, including its caveat: the
fixture is generated from the code it pins, so it catches *divergence tomorrow*, never a wrong
curve today. Say so in the test's comment, as the text one does.

- [ ] **Step 2: Port, assert both sides against the fixture, commit**

The Kotlin must be structurally parallel to the Dart so the two can be diffed by eye.

---

### Task 3: Effects use it

Replace the scalar `effectIntensity` with an `AnimatableDouble`, end to end.

**Files:**
- Modify: `lib/features/video_editor/models/video_segment.dart`
- Modify: `lib/features/video_editor/models/editor_timeline.dart`
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart`
- Modify: `lib/features/video_editor/logic/effects/effect_catalog.dart` (a `defaultEnvelope` per effect)
- Modify: `android/app/src/main/kotlin/…/NativeTimelineClip.kt`, `TimelinePlaybackEngine.kt`, `VideoExportEngine.kt`
- Test: extend the composer and segment tests

- [ ] **Step 1: Carry the parameter through the contract**

`effectIntensity` becomes an `AnimatableDouble` in the model and serialises as an object. **A
draft holding a bare number must still load** — read defensively.

- [ ] **Step 2: Resolve per frame in both engines**

Both already call `clipEffects.apply(effectId, intensity, progress)` with a per-frame progress, so
the animated intensity is `parameter.resolveAt(progress)` — **no new uniform, no shader change.**

- [ ] **Step 3: Fix the merge guard**

`_canMergeForPlayback` (composer ~line 383) compares intensity with an epsilon. Two clips whose
intensity *animates* can never merge, because a merged media item plays one effect at one
strength for both. Extend the guard and test it.

- [ ] **Step 4: Give each effect a default envelope**

In the catalog, so a one-tap effect feels designed rather than static — a glitch that pulses, a
blur that clears. A static grade (duotone, vignette) declares none and stays flat, which is
correct: a pulsing vignette would be a gimmick.

**This is the change most likely to alter how an existing effect looks**, so it is the last step
and it is explicitly on the device-verification list.

- [ ] **Step 5: Gates and commit**

---

### Task 4: The keyframe UI

The expensive half, and the only part a casual user ever sees — if they ask for it.

**Files:**
- Modify: `lib/features/video_editor/widgets/panels/effects_panel.dart` (a Keyframe control)
- Create: a keyframe row in `lib/features/video_editor/widgets/timeline/`
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart`
- Test: widget tests for both

- [ ] **Step 1: The opt-in control**

A "Keyframe" button on the effects panel. **A user who never taps it never sees a diamond** —
that is the whole design of the two paths, and a keyframe row that appears unbidden breaks it.

- [ ] **Step 2: The timeline row**

Diamonds at their clip-relative positions on the selected clip: tap the button to add one at the
playhead, drag to move, tap to select, delete to remove, and an interpolation choice.

Read `ScrollableTimeline`'s existing gesture rules before starting — **a handle inside a
horizontally scrolling timeline loses `kTouchSlop` to the scroll arena** unless it claims the
pointer on down (`_ImmediateHorizontalDragRecognizer`), and **drags track an anchor, not a running
sum of deltas**, or a clamped drag leaves the handle offset from the finger. Both rules are
written down because both were bugs.

- [ ] **Step 3: One undo step per gesture**

`saveStateForUndo()` on drag start, live updates per frame. The canvas handles are the reference.

- [ ] **Step 4: Tests, gates, commit**

---

### Task 5: Device verification

- [ ] **Step 1: Build, and verify nothing changed**

An effect with no envelope and no keyframes must look exactly as it did. **This is the gate**:
35 effects are already awaiting verification, and this stage must not add a second variable.

- [ ] **Step 2: Envelopes**

A one-tap effect that declares an envelope should feel alive, and the export must match.

- [ ] **Step 3: Keyframes**

Add, drag, delete. Keyframes override the envelope. Export matches the preview. Undo is one step
per gesture. A draft saved before this stage opens unchanged.

- [ ] **Step 4: Update CLAUDE.md**

## Exit criteria

- [ ] An effect with neither envelope nor keyframes renders identically to today.
- [ ] Envelopes play in preview and export alike.
- [ ] Keyframes override envelopes, and the row is invisible until asked for.
- [ ] Old drafts load with no envelope, no keyframes, no error.
- [ ] `flutter test`, `flutter analyze --no-pub` (48), `compileDebugKotlin`, and the Kotlin fixture test all pass.
