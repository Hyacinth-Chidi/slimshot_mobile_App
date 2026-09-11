# Text Animation Engine (Stage 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Text animates per character — typing, wave, bounce, colour fill and the rest — identically in the preview and the exported file, with one Speed control that means what it says.

**Architecture:** One pure curve table in Dart (`text_animation_catalog.dart`) is the single definition of what every animation does. Three consumers read it: the canvas preview, the exported frame (via a 1:1 Kotlin port pinned by a shared fixture), and later the animation tab's preview tiles. The glyph atlas from Stage 1 already gives every character its own quad; this stage gives every quad its own transform.

**Tech Stack:** Flutter/Dart, Kotlin, OpenGL ES 2.0, Riverpod.

**Spec:** `docs/superpowers/specs/2026-09-11-text-animation-design.md`

**Depends on:** Stage 1 (`docs/superpowers/plans/2026-09-11-text-glyph-atlas.md`), complete and device-verified — text exports through a glyph atlas matching the preview, emoji included.

## Global Constraints

- **minSdk 24**, GLES 2.0 only. Probe capabilities at runtime; degrade **loudly** (a user-visible `exportWarning`), never silently.
- **No device pixels in the timeline contract.** All geometry is canvas/box fractions.
- **One definition, three consumers.** Anything describing what an animation *does* lives in the catalog. The Kotlin port is pinned to it by a generated fixture, so drift fails the suite rather than shipping a file that differs from the preview.
- **Existing behaviour is a hard constraint**: image and video overlays, and text with no animation, must render exactly as they do today. `Draw.srcRect`/`boxRect` default to null and that path stays byte-for-byte unchanged.
- **Tests that measure text must use `kTestFontFamily`** (`test/support/test_fonts.dart`). `GoogleFonts` throws from an async continuation that cannot be caught at the call site.
- Analyzer baseline is exactly **48** pre-existing issues. Add none; fix none.
- Verify with `flutter analyze --no-pub`, `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.

## The central design decision: per-glyph transforms need their own origin

`OverlayRenderer.Draw` applies `scale` and `rotation` about the **overlay's centre**. That is right for a whole-box animation and wrong for a per-character one: a bouncing letter must hop in place, not swing around the text block. A glyph therefore needs a transform about **its own centre**, composed with the overlay's.

So `Draw` gains `glyphScale`, `glyphRotation` and a glyph-space offset, applied around the glyph quad's own centre *before* the overlay's scale/rotation is applied around the overlay centre. Order matters and is the easiest thing here to get wrong — a test fixture pins it.

## What this stage does NOT touch

- **The animation tab UI.** Three tabs, live preview tiles and the Speed slider's final form are Stage 3. This stage wires Speed into the *model and engine* and leaves the existing panel reading it, so the slider stops lying, but the panel is not redesigned.
- **Blur and Neon Flicker.** Both are multi-pass effects needing an FBO framework that does not exist; they are deferred to the effects pipeline, as the spec records.
- **The flat-raster fallback.** Text too large for the texture limit, and text with a background box, still take it — but see Task 6: once animation exists, a fallback means "no per-character animation" and must now **warn**.

---

### Task 1: The animation catalog

The pure curve table. No Flutter, no rendering — just arithmetic, which is what makes it testable and portable to Kotlin.

**Files:**
- Create: `lib/features/video_editor/logic/text_animation_catalog.dart`
- Test: `test/features/video_editor/logic/text_animation_catalog_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum TextAnimationCategory { inAnim, outAnim, loop }`
  - `class TextGlyphState { const TextGlyphState({this.opacity = 1, this.offsetX = 0, this.offsetY = 0, this.scale = 1, this.rotation = 0, this.fillProgress = 1}); final double opacity, offsetX, offsetY, scale, rotation, fillProgress; }` — `offsetX/Y` in **glyph-height units** (so motion scales with the text), `rotation` in radians, `fillProgress` 0..1 for colour-fill.
  - `class TextAnimation { final String id; final String label; final TextAnimationCategory category; final bool isPerGlyph; final double Function(int glyphCount) naturalDuration; final TextGlyphState Function(double p, int i, int n) stateAt; }`
  - `const List<TextAnimation> kTextAnimations`
  - `TextAnimation? textAnimationById(String id)`
  - `({double inSeconds, double outSeconds}) resolveTextAnimationDurations({required double spanSeconds, required TextAnimation? inAnim, required TextAnimation? outAnim, required int glyphCount, required double speed})`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/video_editor/logic/text_animation_catalog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';

void main() {
  group('catalog shape', () {
    test('every animation has a unique id', () {
      final ids = kTextAnimations.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('lookup finds a known animation and misses an unknown one', () {
      expect(textAnimationById('typing')?.category, TextAnimationCategory.inAnim);
      expect(textAnimationById('no_such_animation'), isNull);
    });

    test('the seven legacy names still resolve', () {
      for (final id in [
        'fade_in', 'zoom_in', 'zoom_out',
        'slide_up', 'slide_down', 'slide_left', 'slide_right',
      ]) {
        expect(textAnimationById(id), isNotNull, reason: '$id must survive');
      }
    });
  });

  group('curve boundaries', () {
    // An in-animation must land exactly on the resting state, or the text
    // visibly jumps the frame after it finishes.
    test('every in-animation rests at p=1', () {
      for (final anim in kTextAnimations.where(
          (a) => a.category == TextAnimationCategory.inAnim)) {
        final s = anim.stateAt(1.0, 2, 5);
        expect(s.opacity, closeTo(1, 1e-6), reason: '${anim.id} opacity');
        expect(s.scale, closeTo(1, 1e-6), reason: '${anim.id} scale');
        expect(s.offsetX, closeTo(0, 1e-6), reason: '${anim.id} offsetX');
        expect(s.offsetY, closeTo(0, 1e-6), reason: '${anim.id} offsetY');
        expect(s.rotation, closeTo(0, 1e-6), reason: '${anim.id} rotation');
        expect(s.fillProgress, closeTo(1, 1e-6), reason: '${anim.id} fill');
      }
    });

    test('every out-animation starts from the resting state at p=0', () {
      for (final anim in kTextAnimations.where(
          (a) => a.category == TextAnimationCategory.outAnim)) {
        final s = anim.stateAt(0.0, 2, 5);
        expect(s.opacity, closeTo(1, 1e-6), reason: '${anim.id} opacity');
        expect(s.scale, closeTo(1, 1e-6), reason: '${anim.id} scale');
        expect(s.offsetX, closeTo(0, 1e-6), reason: '${anim.id} offsetX');
        expect(s.offsetY, closeTo(0, 1e-6), reason: '${anim.id} offsetY');
      }
    });

    test('a loop animation is seamless: p=0 and p=1 agree', () {
      for (final anim in kTextAnimations.where(
          (a) => a.category == TextAnimationCategory.loop)) {
        final a0 = anim.stateAt(0.0, 2, 5);
        final a1 = anim.stateAt(1.0, 2, 5);
        expect(a1.offsetY, closeTo(a0.offsetY, 1e-6), reason: '${anim.id} offsetY seam');
        expect(a1.scale, closeTo(a0.scale, 1e-6), reason: '${anim.id} scale seam');
        expect(a1.opacity, closeTo(a0.opacity, 1e-6), reason: '${anim.id} opacity seam');
      }
    });

    test('states stay in sane ranges across the whole curve', () {
      for (final anim in kTextAnimations) {
        for (var step = 0; step <= 20; step++) {
          final s = anim.stateAt(step / 20, 3, 7);
          expect(s.opacity, inInclusiveRange(0, 1), reason: '${anim.id} opacity');
          expect(s.scale, greaterThanOrEqualTo(0), reason: '${anim.id} scale');
          expect(s.fillProgress, inInclusiveRange(0, 1), reason: '${anim.id} fill');
          expect(s.offsetX.abs(), lessThan(10), reason: '${anim.id} offsetX runaway');
          expect(s.offsetY.abs(), lessThan(10), reason: '${anim.id} offsetY runaway');
        }
      }
    });
  });

  group('typing', () {
    final typing = textAnimationById('typing')!;

    test('is per-glyph', () => expect(typing.isPerGlyph, isTrue));

    test('reveals characters left to right', () {
      // A third of the way through 6 glyphs: early ones visible, late ones not.
      final first = typing.stateAt(0.34, 0, 6);
      final last = typing.stateAt(0.34, 5, 6);
      expect(first.opacity, greaterThan(last.opacity));
    });

    test('every glyph is visible by the end', () {
      for (var i = 0; i < 6; i++) {
        expect(typing.stateAt(1.0, i, 6).opacity, closeTo(1, 1e-6));
      }
    });

    test('a single glyph still animates rather than dividing by zero', () {
      expect(typing.stateAt(0.0, 0, 1).opacity, closeTo(0, 1e-6));
      expect(typing.stateAt(1.0, 0, 1).opacity, closeTo(1, 1e-6));
    });
  });

  group('wave', () {
    final wave = kTextAnimations.firstWhere((a) => a.id == 'wave_loop');

    test('neighbouring glyphs are out of phase', () {
      final a = wave.stateAt(0.25, 0, 8);
      final b = wave.stateAt(0.25, 4, 8);
      expect((a.offsetY - b.offsetY).abs(), greaterThan(0.05));
    });
  });

  group('natural duration', () {
    test('a flat animation ignores glyph count', () {
      final fade = textAnimationById('fade_in')!;
      expect(fade.naturalDuration(3), fade.naturalDuration(30));
    });

    test('typing takes longer for more characters, within bounds', () {
      final typing = textAnimationById('typing')!;
      expect(typing.naturalDuration(30), greaterThan(typing.naturalDuration(5)));
      expect(typing.naturalDuration(500), lessThanOrEqualTo(2.5));
      expect(typing.naturalDuration(1), greaterThanOrEqualTo(0.4));
    });
  });

  group('resolveTextAnimationDurations', () {
    final typing = textAnimationById('typing')!;
    final fadeOut = textAnimationById('fade_out')!;

    test('speed scales duration inversely', () {
      final slow = resolveTextAnimationDurations(
        spanSeconds: 100, inAnim: typing, outAnim: null, glyphCount: 10, speed: 1);
      final fast = resolveTextAnimationDurations(
        spanSeconds: 100, inAnim: typing, outAnim: null, glyphCount: 10, speed: 2);
      expect(fast.inSeconds, closeTo(slow.inSeconds / 2, 1e-9));
    });

    test('compresses proportionally when in+out exceed the span', () {
      // A dropped animation is a silent preview/export mismatch, so both are
      // squeezed instead.
      final r = resolveTextAnimationDurations(
        spanSeconds: 0.5, inAnim: typing, outAnim: fadeOut, glyphCount: 20, speed: 1);
      expect(r.inSeconds + r.outSeconds, closeTo(0.5, 1e-6));
      expect(r.inSeconds, greaterThan(0));
      expect(r.outSeconds, greaterThan(0));
    });

    test('leaves them alone when they fit', () {
      final r = resolveTextAnimationDurations(
        spanSeconds: 10, inAnim: typing, outAnim: fadeOut, glyphCount: 5, speed: 1);
      expect(r.inSeconds, closeTo(typing.naturalDuration(5), 1e-9));
      expect(r.outSeconds, closeTo(fadeOut.naturalDuration(5), 1e-9));
    });

    test('a null animation contributes nothing', () {
      final r = resolveTextAnimationDurations(
        spanSeconds: 10, inAnim: null, outAnim: null, glyphCount: 5, speed: 1);
      expect(r.inSeconds, 0);
      expect(r.outSeconds, 0);
    });

    test('a zero or negative span cannot produce negative durations', () {
      final r = resolveTextAnimationDurations(
        spanSeconds: 0, inAnim: typing, outAnim: fadeOut, glyphCount: 5, speed: 1);
      expect(r.inSeconds, greaterThanOrEqualTo(0));
      expect(r.outSeconds, greaterThanOrEqualTo(0));
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/video_editor/logic/text_animation_catalog_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the catalog**

Write `lib/features/video_editor/logic/text_animation_catalog.dart`. Requirements the tests pin, plus these rules:

- **Pure functions only.** No clock, no state, no Flutter imports beyond `dart:math`.
- **`p` is 0..1 progress** through the animation's own window. `i` is the glyph index, `n` the glyph count.
- **Per-glyph stagger:** a glyph's own sub-progress is derived by splitting `p` across `n` glyphs with overlap, e.g. `glyphP = ((p * (1 + overlap*(n-1))) - i*overlap).clamp(0,1)` — pick one formula, comment it, and use it for every staggered animation so they feel like a family. Guard `n <= 1`.
- **Offsets are in glyph-height units**, so a slide moves the same *visual* distance at any text size.
- Seed the catalog with, at minimum, the ids the tests name plus the spec's set:
  - **in**: `typing`, `fade_in`, `zoom_in`, `zoom_out`, `slide_up`, `slide_down`, `slide_left`, `slide_right`, `bounce_in`, `pop_in`, `wave_in`, `colour_fill`, `rise_in`, `spin_in`
  - **out**: `untyping`, `fade_out`, `zoom_in_out`, `zoom_out_out`, `slide_up_out`, `slide_down_out`, `slide_left_out`, `slide_right_out`, `bounce_out`, `pop_out`, `sink_out`
  - **loop**: `wave_loop`, `pulse_loop`, `shake_loop`, `colour_cycle_loop`, `wiggle_loop`
- **Legacy names must resolve.** Drafts store `fade`, `scale` and the bare slide names. Map them to catalog ids so an existing project keeps its animation; unknown ids return null and animate nothing, never crash.
- **`shake_loop`/`wiggle_loop` must be deterministic** — a hash of the glyph index, not `Random()`, or preview and export disagree every frame.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/video_editor/logic/text_animation_catalog_test.dart`
Expected: PASS.

- [ ] **Step 5: Full gates**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; 48 analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/video_editor/logic/text_animation_catalog.dart test/features/video_editor/logic/text_animation_catalog_test.dart
git commit -m "feat(text): the animation catalog, one definition for three consumers

Pure curve functions with no clock and no state, so the preview, the
export's Kotlin port and the animation tab all read the same arithmetic
rather than each carrying its own.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The shared fixture

A generated table of sampled curve values that both Dart and Kotlin are asserted against. This is what makes "the port drifted" a test failure instead of a device surprise.

**Files:**
- Create: `tool/generate_animation_fixture.dart`
- Create: `test/fixtures/text_animation_fixture.json`
- Create: `android/app/src/test/resources/text_animation_fixture.json` (a copy, so Kotlin reads it too)
- Test: `test/features/video_editor/logic/text_animation_fixture_test.dart`

**Interfaces:**
- Consumes: `kTextAnimations`, `TextGlyphState` (Task 1).
- Produces: a JSON fixture, shape:
  `{"samples":[{"id":"typing","p":0.5,"i":2,"n":5,"opacity":…,"offsetX":…,"offsetY":…,"scale":…,"rotation":…,"fillProgress":…}, …]}`

- [ ] **Step 1: Write the generator**

`tool/generate_animation_fixture.dart` — a `main()` that walks every animation in `kTextAnimations`, samples `p` at 0, 0.25, 0.5, 0.75, 1.0 for `(i,n)` in `(0,1)`, `(0,5)`, `(2,5)`, `(4,5)`, writes the JSON to both paths, and prints the sample count. Values rounded to 6 decimal places so floating-point noise does not make the fixture churn.

- [ ] **Step 2: Generate it**

Run: `dart run tool/generate_animation_fixture.dart`
Expected: writes both files; prints a count (animations × 5 × 4).

- [ ] **Step 3: Write the Dart side of the pin**

```dart
// test/features/video_editor/logic/text_animation_fixture_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';

void main() {
  test('the catalog still matches the committed fixture', () {
    // The fixture is the contract the Kotlin port is held to. If a curve
    // changes deliberately, regenerate it with
    // `dart run tool/generate_animation_fixture.dart` AND re-run the Kotlin
    // test, or preview and export will quietly disagree.
    final raw = File('test/fixtures/text_animation_fixture.json').readAsStringSync();
    final samples = (jsonDecode(raw) as Map<String, dynamic>)['samples'] as List;
    expect(samples, isNotEmpty);

    for (final entry in samples.cast<Map<String, dynamic>>()) {
      final anim = textAnimationById(entry['id'] as String);
      expect(anim, isNotNull, reason: 'fixture names unknown id ${entry['id']}');
      final s = anim!.stateAt(
        (entry['p'] as num).toDouble(),
        entry['i'] as int,
        entry['n'] as int,
      );
      final where = '${entry['id']} p=${entry['p']} i=${entry['i']} n=${entry['n']}';
      expect(s.opacity, closeTo((entry['opacity'] as num).toDouble(), 1e-5), reason: '$where opacity');
      expect(s.offsetX, closeTo((entry['offsetX'] as num).toDouble(), 1e-5), reason: '$where offsetX');
      expect(s.offsetY, closeTo((entry['offsetY'] as num).toDouble(), 1e-5), reason: '$where offsetY');
      expect(s.scale, closeTo((entry['scale'] as num).toDouble(), 1e-5), reason: '$where scale');
      expect(s.rotation, closeTo((entry['rotation'] as num).toDouble(), 1e-5), reason: '$where rotation');
      expect(s.fillProgress, closeTo((entry['fillProgress'] as num).toDouble(), 1e-5), reason: '$where fill');
    }
  });
}
```

- [ ] **Step 4: Run it**

Run: `flutter test test/features/video_editor/logic/text_animation_fixture_test.dart`
Expected: PASS (it was generated from the same code, so this pins future drift).

- [ ] **Step 5: Commit**

```bash
git add tool/generate_animation_fixture.dart test/fixtures/ android/app/src/test/resources/ test/features/video_editor/logic/text_animation_fixture_test.dart
git commit -m "test(text): a shared curve fixture pinning Dart and Kotlin together

Sampled curve values both sides assert against, so a drifted port fails
the suite instead of shipping a file that differs from the preview.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The Kotlin port

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/TextAnimationCurves.kt`
- Create: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/TextAnimationCurvesTest.kt`
- Modify: `android/app/build.gradle.kts` (add `testImplementation` for JUnit if absent)

**Interfaces:**
- Consumes: the fixture JSON at `android/app/src/test/resources/text_animation_fixture.json` (Task 2).
- Produces:
  - `internal data class TextGlyphState(val opacity: Double = 1.0, val offsetX: Double = 0.0, val offsetY: Double = 0.0, val scale: Double = 1.0, val rotation: Double = 0.0, val fillProgress: Double = 1.0)`
  - `internal object TextAnimationCurves { fun stateAt(id: String?, p: Double, i: Int, n: Int): TextGlyphState }` — an unknown or null id returns the resting state.

**This task sets up Kotlin unit testing for the first time in this repo.** Verified before
writing this plan: `android/app/src/` contains only `debug/`, `main/` and `profile/`, and
`android/app/build.gradle.kts` has no `testImplementation` line. So Step 1 is scaffolding, and
it is the one part of this stage most likely to fight the build.

- [ ] **Step 1: Scaffold Kotlin unit tests and write the failing test**

Add to `android/app/build.gradle.kts` inside the existing `dependencies { }` block (line 65):

```kotlin
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
```

(`org.json` is needed because `android.util.JSONObject` is stubbed to throw in local unit
tests — the classic "method not mocked" failure. Using the real `org.json` artifact avoids
`testOptions { unitTests.isReturnDefaultValues = true }`, which would paper over other stubs.)

Create `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/TextAnimationCurvesTest.kt`:
a JUnit test that reads the fixture from test resources
(`javaClass.getResourceAsStream("/text_animation_fixture.json")`), calls
`TextAnimationCurves.stateAt` for each sample, and asserts every field within `1e-5`.

Fail messages must name the animation id, `p`, `i` and `n` — a bare "expected 0.5 got 0.7" in
a table of hundreds of samples is unusable, and this test exists precisely to be read when it
fails.

**If the Gradle source set does not pick up `src/test/kotlin`**, Kotlin's Android plugin expects
`src/test/java` by default for the unit-test source set; either use that directory or add it
explicitly. Do not spend long here — if the scaffolding resists, report BLOCKED with what you
tried rather than burning the task on build configuration.

- [ ] **Step 2: Run it and watch it fail**

Run: `.\android\gradlew.bat -p android testDebugUnitTest --tests "*TextAnimationCurvesTest*"`
Expected: FAIL — unresolved reference `TextAnimationCurves`.

- [ ] **Step 3: Port the curves**

Translate `text_animation_catalog.dart` function for function. Same stagger formula, same constants, same deterministic hash for shake/wiggle. Keep the Kotlin structurally parallel to the Dart — a `when (id)` mirroring the catalog's entries — so a future change can be applied to both by reading them side by side.

- [ ] **Step 4: Run it**

Run: `.\android\gradlew.bat -p android testDebugUnitTest --tests "*TextAnimationCurvesTest*"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/TextAnimationCurves.kt android/app/src/test/ android/app/build.gradle.kts
git commit -m "feat(native): port the animation curves, pinned by the shared fixture

Structurally parallel to the Dart catalog so the two can be diffed by
eye, and asserted against the same sampled values so drift fails the
build.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Per-glyph transforms in the renderer

**Files:**
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayRenderer.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelineOverlay.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/VideoExportEngine.kt`

**Interfaces:**
- Consumes: `TextAnimationCurves.stateAt` (Task 3); `NativeTimelineGlyph`, `Draw.srcRect`/`boxRect` (Stage 1).
- Produces: `Draw` gains `glyphScale: Double = 1.0`, `glyphRotation: Double = 0.0`, `glyphOffsetX: Double = 0.0`, `glyphOffsetY: Double = 0.0` (offsets in **box-height fractions**). `NativeTimelineOverlay` gains `animationLoop: String?` and `speedIn/speedOut/speedLoop: Double`.

- [ ] **Step 1: Apply the glyph transform about the glyph's own centre**

In `writeCorners`, inside the `boxRect != null` branch **only**: before the overlay's rotation is applied, scale the glyph's half-extents by `glyphScale` about the glyph centre, rotate the glyph's corners by `glyphRotation` about that same centre, then add `glyphOffsetX/Y`. The existing overlay-level rotation then applies to the result about the overlay centre.

The order is the crux: **glyph transform in glyph space first, then overlay transform in box space.** Reversed, a bouncing letter swings around the whole text block instead of hopping in place. Comment it.

The null-`boxRect` path must remain untouched.

- [ ] **Step 2: Resolve and pass per-glyph state**

In `VideoExportEngine.textDraws`, for each glyph compute its animation state and put it on the `Draw`:

- Resolve in/out/loop durations the same way `resolveTextAnimationDurations` does — **port that function too** (it is in the catalog, so it belongs in `TextAnimationCurves`), so the compression rule is identical on both sides.
- Work out which window `t` is in: in-animation over the first `inSeconds`, out over the last `outSeconds`, loop continuously between them on its own phase (`((t - start) / loopPeriod) % 1`).
- Multiply the resulting state into the `Draw`: `opacity` multiplies the overlay's, `glyphScale`/`glyphRotation`/`glyphOffset*` carry the glyph's own transform.
- Convert `offsetX/Y` from **glyph-height units** (what the catalog emits) to **box-height fractions** (what `Draw` wants) using the glyph's own box height.

A text overlay with no animation must produce exactly the `Draw`s it produces today.

- [ ] **Step 3: Parse the new fields**

`NativeTimelineOverlay.fromMap` reads `animationLoop`, `speedIn`, `speedOut`, `speedLoop` (defaulting to null / 1.0).

- [ ] **Step 4: Compile**

Run: `.\android\gradlew.bat -p android compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/
git commit -m "feat(native): per-glyph transforms about each glyph's own centre

A glyph's scale and rotation apply in glyph space before the overlay's
apply in box space — reversed, a bouncing letter swings around the whole
text block instead of hopping in place.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Model, contract and Speed

**Files:**
- Modify: `lib/features/video_editor/models/text_overlay_model.dart`
- Modify: `lib/features/video_editor/models/editor_timeline.dart`
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart`
- Test: `test/features/video_editor/models/text_overlay_speed_test.dart`

**Interfaces:**
- Produces: `TextOverlayModel` gains `loopAnimation` (String, default `'none'`) and `loopSpeed` (double, default 1.0); `animationInDuration`/`animationOutDuration` are **reinterpreted as speed multipliers**. `EditorTimelineOverlay` gains `animationLoop`, `speedIn`, `speedOut`, `speedLoop`.

- [ ] **Step 1: Write the failing migration test**

The stored fields change meaning, so a draft written before this stage must not be read as a nonsense speed. Old values were durations in 0.1–2.0s; speeds live in 0.5–3.0. The overlap (0.5–2.0) is genuinely ambiguous, so migrate on a version marker rather than guessing from the value: add `animationSchema` (int, default 0 for old drafts, 1 for new). Schema 0 maps any stored duration to speed 1.0; schema 1 reads the speed as written.

Tests: an old draft (no `animationSchema`) loads at speed 1.0 whatever its stored duration; a new draft round-trips its speed exactly; speed clamps to 0.5–3.0 on read.

- [ ] **Step 2: Implement, then wire the composer**

`_rasterizeTextOverlays` sends `animationLoop`, `speedIn/Out/Loop` and — importantly — **stops hardcoding `animationInSeconds: 0.5`**. Kotlin now resolves durations from the catalog and the speed, so the composer passes the speed, not a duration.

- [ ] **Step 3: Gates and commit**

Run `flutter test`, `flutter analyze --no-pub`, then commit.

---

### Task 6: The preview layer, and a fallback that now warns

**Files:**
- Modify: `lib/features/video_editor/widgets/text_overlay/text_overlay_layer.dart`
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart`

- [ ] **Step 1: Drive the preview from the catalog**

Replace the layer's `flutter_animate` chain with a per-glyph paint driven by `kTextAnimations` and the playhead. The layer already measures glyphs via `TextOverlayLayout`; a `CustomPainter` that walks `layoutTextGlyphs` and applies each glyph's `TextGlyphState` is the natural shape, and it is the same data the atlas path uses.

Keep the existing gesture frame, handles and hit-testing exactly as they are — this changes how the text is *painted*, not how it is manipulated.

- [ ] **Step 2: Make the flat-raster fallback warn**

Stage 1's two fallbacks (atlas too large; text with a background box) were silent **because output was identical**. That is no longer true: a fallback now means the text does not animate per character. Emit an `exportWarning` naming the overlay, per the degrade-loudly rule.

- [ ] **Step 3: Gates and commit**

---

### Task 7: Device verification

- [ ] **Step 1: Build**

Run: `flutter build apk --debug`

- [ ] **Step 2: Verify preview and export agree**

For each of typing, wave, bounce, colour fill, and one legacy animation (fade), with Speed at 0.5×, 1× and 2×:
1. Watch it in the preview.
2. Export it.
3. Confirm the exported animation matches what the preview showed — timing, direction, and per-character stagger.

Then the cases that must be **unchanged**: text with no animation, a video clip with no text, an image overlay with a slide animation.

And the fallbacks: a 200+ character text and a text with a background box must each export correctly **and raise a warning toast** saying it could not animate per character.

- [ ] **Step 3: Update CLAUDE.md**

Record the catalog, the fixture pin, the per-glyph transform order, and that fallbacks now warn.

## Stage 2 exit criteria

- [ ] Every animation matches between preview and export, at every speed.
- [ ] Text with no animation renders exactly as it does today.
- [ ] Image/video overlays and the video engine are untouched.
- [ ] Both fallbacks warn.
- [ ] `flutter test`, `flutter analyze --no-pub` (48), `compileDebugKotlin`, and the new Kotlin fixture test all pass.
