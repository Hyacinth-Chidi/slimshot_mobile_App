# Overlay Keyframes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keyframes on text, photo and video overlays — position, scale, rotation, opacity — with the clip keyframe rules, identical in preview and export.

**Architecture:** The clip keyframe functions are generalised into a pure core over a map of named `AnimatableDouble` parameters; clips and overlays are thin adapters over it. Overlays keep their plain fields as base values and gain an `OverlayKeyframes` track set beside them. The composer sends each transform parameter as an `AnimatableDouble` (a bare number when static), and Kotlin's `NativeTimelineOverlay` resolves them per frame before applying preset animations.

**Tech Stack:** Flutter/Dart (Riverpod `StateNotifier`), Kotlin (Media3/OpenGL engine), existing `AnimatableDouble` in both languages.

**Spec:** `docs/superpowers/specs/2026-09-25-overlay-keyframes-design.md`

## Global Constraints

- Properties keyframed: position (x, y), scale, rotation, opacity. Nothing else.
- Keyframe progress is overlay-relative: `(t − start) / (end − start)`, 0..1.
- One diamond holds every property; capture writes the *resolved* value, so placing a diamond never changes the picture.
- An overlay without keyframes serialises exactly as today — in the draft and on the wire.
- Interpolation and easing come only from the existing `AnimatableDouble` (Dart) and `AnimatableDouble.kt` — no second copy.
- `flutter analyze --no-pub` stays at 48 issues. Every existing clip keyframe test passes unchanged.
- Colours from `AppColors`; sheets through `showEditorSheet`; one undo step per gesture.

## Review Focus

1. **A drag on a keyframed overlay while the video plays** — the playhead moves each frame, so without a pause one drag would leave a trail of diamonds. Expected: the gesture pauses playback first and adds at most one diamond. (Task 3)
2. **Grabbing a keyframed overlay mid-motion** — gestures anchored on the stored base would jump the overlay to its base the moment it is touched. Expected: it stays exactly where it is drawn. (Tasks 3 and 6)
3. **An overlay trimmed to almost nothing, or a zero-length span in a hand-edited draft** — progress divides by the span. Expected: no NaN, progress 0. (Task 2)
4. **A hand-edited or future draft** with an unknown property name or a malformed keyframe entry. Expected: it opens; the bad entry is ignored. (Task 2)
5. **✕ on the Opacity panel for a text** — the discard record knew only clips and photo/video overlays. Expected: the text's opacity and any keyframe the drag placed are put back. (Task 3)

---

### Task 1: The shared keyframe core

**Files:**
- Create: `lib/features/video_editor/logic/animation/keyframe_core.dart`
- Modify: `lib/features/video_editor/logic/animation/clip_keyframes.dart` (functions become wrappers; `kKeyframeMatchProgress` moves to the core and is re-exported)
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart` (`_writeClipValue`, `_splitKeyframes` use the core)
- Test: `test/features/video_editor/logic/animation/keyframe_core_test.dart`

**Interfaces — Produces:**
```dart
typedef KeyframeParams<P> = Map<P, AnimatableDouble>;
bool hasKeyframesIn<P>(KeyframeParams<P> params);
List<double> keyframeProgressesIn<P>(KeyframeParams<P> params);
double? keyframeProgressNearIn<P>(KeyframeParams<P> params, double progress, double tolerance);
KeyframeParams<P> captureKeyframeIn<P>(KeyframeParams<P> params, double progress);
KeyframeParams<P> removeKeyframeIn<P>(KeyframeParams<P> params, double progress, double tolerance);
KeyframeParams<P>? moveKeyframeIn<P>(KeyframeParams<P> params, double from, double to, double tolerance); // null = refused
double? keyframeCurveTargetIn<P>(KeyframeParams<P> params, double progress, double tolerance);
KeyframeParams<P> setKeyframeEasingIn<P>(KeyframeParams<P> params, double progress, double tolerance, KeyframeInterpolation easing);
KeyframeParams<P> setKeyframeCurveIn<P>(KeyframeParams<P> params, double progress, double tolerance, KeyframeInterpolation curve);
KeyframeInterpolation keyframeCurveAtIn<P>(KeyframeParams<P> params, double target);
KeyframeParams<P> writeKeyframedValueIn<P>(KeyframeParams<P> params, P property, double value, {required double? playheadProgress, required double tolerance});
KeyframeParams<P> splitKeyframesIn<P>(KeyframeParams<P> params, double cut, {required bool isLeft});
```
Every function returns the **same map instance** when it changes nothing, so adapters can return their input unchanged.

- [ ] **Step 1: Write the failing core tests** over a toy enum `enum _P { a, b }`:
  capture pins the resolved value on every param and changes no resolved value at five progresses;
  capture at an existing diamond replaces rather than duplicates;
  remove of the last diamond hands its value back as base;
  remove with nothing near returns the identical map;
  move refuses onto an occupied instant (returns null) and moves every param's keyframe together;
  the edit rule's three cases (no keyframes → base; on a diamond → that keyframe; between → exactly one new diamond, others captured);
  split pins the cut on both halves and rescales `p/cut` and `(p−cut)/(1−cut)`, degenerate cuts return the input.
- [ ] **Step 2:** Run `flutter test test/features/video_editor/logic/animation/keyframe_core_test.dart` — FAIL (file missing).
- [ ] **Step 3: Implement `keyframe_core.dart`** by lifting the bodies of `keyframeProgresses`, `keyframeProgressNear`, `captureKeyframe`, `removeKeyframe`, `moveKeyframe`, `keyframeCurveTarget`, `setKeyframeCurve`, `setKeyframeEasing` from `clip_keyframes.dart`, the edit rule from `_writeClipValue`, and the split from `_splitKeyframes`, replacing `ClipProperty.values` loops with `params.entries` and `clipParameter/withClipParameter` with map reads/writes. Keep every doc comment's substance on the core function.
- [ ] **Step 4: Make `clip_keyframes.dart` wrappers:**
```dart
KeyframeParams<ClipProperty> clipParams(VideoSegment s) =>
    {for (final p in ClipProperty.values) p: clipParameter(s, p)};

VideoSegment withClipParams(VideoSegment s, KeyframeParams<ClipProperty> params) {
  var out = s;
  for (final e in params.entries) {
    out = withClipParameter(out, e.key, e.value);
  }
  return out;
}

VideoSegment captureKeyframe(VideoSegment s, double progress) {
  final params = clipParams(s);
  final out = captureKeyframeIn(params, progress);
  return identical(out, params) ? s : withClipParams(s, out);
}
```
  …and likewise for every other clip function; `moveKeyframe` returns `s` when the core returns null. `_writeClipValue` becomes `withClipParams(segment, writeKeyframedValueIn(clipParams(segment), property, value, playheadProgress: playheadProgress, tolerance: keyframeHitToleranceFor(segment)))`, preserving its `!segment.hasKeyframes` early base write. `_splitKeyframes` uses `splitKeyframesIn` for the params and writes them onto `half`.
- [ ] **Step 5:** Run the core tests, then every existing clip keyframe test (`test/features/video_editor/logic/animation/` and `test/features/video_editor/providers/clip_keyframe*`) — all PASS unchanged.
- [ ] **Step 6:** Commit `refactor(keyframes): one core for what a diamond does`.

### Task 2: Overlay motion model

**Files:**
- Create: `lib/features/video_editor/logic/animation/overlay_keyframes.dart`
- Modify: `lib/features/video_editor/models/text_overlay_model.dart`, `image_overlay_model.dart`, `video_overlay_model.dart`
- Test: `test/features/video_editor/logic/animation/overlay_keyframes_test.dart`

**Interfaces — Consumes:** Task 1 core. **Produces:**
```dart
enum OverlayProperty { x, y, scale, rotation, opacity }
class OverlayKeyframes {                       // tracks by property; empty = none
  const OverlayKeyframes([Map<OverlayProperty, List<Keyframe>> tracks]);
  static const none;
  bool get isEmpty;
  List<Keyframe> of(OverlayProperty p);
  Map<String, dynamic>? toJson();              // null when empty
  factory OverlayKeyframes.fromJson(dynamic json); // defensive
}
class OverlayMotion {                          // base values + keyframes
  const OverlayMotion({required Offset position, required double scale, required double rotation, required double opacity, OverlayKeyframes keyframes});
  KeyframeParams<OverlayProperty> get params;
  factory OverlayMotion.fromParams(KeyframeParams<OverlayProperty> params);
  bool get hasKeyframes;
  OverlayMotion at(double progress);           // resolved, no keyframes
}
double overlayProgressAt(Duration start, Duration end, double seconds); // 0 when span <= 0
// On each overlay model:
OverlayKeyframes keyframes;                    // + copyWith, toJson ('keyframes' only when non-empty), fromJson
OverlayMotion get motion;
<Model> withMotion(OverlayMotion motion);
<Model> shownAt(double seconds);               // this, or withMotion(motion.at(progress)) when keyframed
// TextOverlayModel only:
double opacity;                                // default 1.0, always written, clamped on read
```

- [ ] **Step 1: Write failing tests:** `OverlayKeyframes` JSON round trip; `toJson` null when empty; unknown property key ignored; malformed entry skipped; non-map input → none. `OverlayMotion.params`/`fromParams` round trip; `at()` interpolates and a static motion returns its base. `overlayProgressAt` clamps and returns 0 for a zero span (Review Focus 3). Each model: an old draft (no `keyframes`, text no `opacity`) loads with none and opacity 1.0; round trip keeps keyframes; the draft JSON of an un-keyframed overlay has no `keyframes` key (unchanged format); `copyWith` carries keyframes; `shownAt` resolves between two keyframes and returns `this` when un-keyframed; `TextTemplate.restyle` leaves keyframes untouched.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** `overlay_keyframes.dart`, then add the fields and methods to the three models. `OverlayMotion.at` fast-paths `!hasKeyframes` to `this`. `params` builds each property as `AnimatableDouble.sorted(baseValue: <base>, keyframes: keyframes.of(p))`.
- [ ] **Step 4:** Run — PASS; run the model and template suites — PASS.
- [ ] **Step 5:** Commit `feat(overlays): keyframe tracks beside the base values`.

### Task 3: State and notifier — the keyframe target, the edit rule, discard

**Files:**
- Modify: `lib/features/video_editor/models/video_editor_state.dart`
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart`
- Test: `test/features/video_editor/providers/overlay_keyframe_edit_test.dart`

**Interfaces — Produces (state):**
```dart
enum OverlayKind { text, image, video }
typedef KeyframeOverlayRef = ({OverlayKind kind, String id, OverlayMotion motion, Duration start, Duration end});
KeyframeOverlayRef? get keyframeOverlay;     // the selected overlay
double? get selectedOverlayProgress;         // null outside its span (never clamped)
double overlayKeyframeTolerance(KeyframeOverlayRef ref); // kKeyframeHitSeconds / span, clamped 0..0.5
bool get hasKeyframeTarget;                  // clip or overlay selected
double? get keyframeTargetProgress;          // overlay progress, else selectedClipProgress
List<double> get keyframeDiamonds;           // overlay's, else selectedClipKeyframes
double overlayEditValue(OverlayProperty p);  // what a control shows (resolved when keyframed)
// Existing getters dispatch to the overlay when one is selected:
// playheadKeyframeProgress, playheadIsOnKeyframe, keyframeCurveTargetProgress,
// canEditKeyframeCurve, keyframeCurve.
```
**Produces (notifier):**
```dart
void beginOverlayEdit();                     // pause + one undo snapshot
void setOverlayMotionLive({Offset? position, double? scale, double? rotation, double? opacity}); // edit rule, no snapshot
// Existing methods dispatch to the selected overlay:
// addKeyframeAtPlayhead, removeKeyframeAtPlayhead, setKeyframeCurve, moveKeyframeLive, seekToKeyframe
```

- [ ] **Step 1: Write failing tests** for a text, a photo and a video overlay each: the edit rule's three cases through `setOverlayMotionLive`; add/remove/curve/move/seek dispatch to the overlay and never touch clips; `hasKeyframeTarget` and `keyframeTargetProgress` (null outside the span). **Review Focus 1:** with playback on, `beginOverlayEdit` sets `isPlaying` false, and 30 `setOverlayMotionLive` frames between two diamonds add exactly one diamond; the whole drag undoes in one step. **Review Focus 2:** `overlayEditValue` returns the resolved value between diamonds and the base with none. **Review Focus 5:** open Opacity on a text, drag, ✕ → opacity and keyframes restored, no undo entry left. `setOverlayOpacity` routes through the edit rule. `splitVideoOverlay` pins at the cut and rescales each half; `duplicateVideoOverlay` copies keyframes.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement.** A private `_replaceOverlayMotion(KeyframeOverlayRef ref, OverlayMotion motion)` writes through `updateTextOverlayLive`/`updateImageOverlayLive`/`updateVideoOverlayLive` by kind. `setOverlayMotionLive` folds each given property through `writeKeyframedValueIn` on one params map (position writes x then y into the same map, so between diamonds the capture happens once), then replaces. `openRevertibleTool`'s record gains the selected text; `discardActiveTool` restores it by id. `splitVideoOverlay` applies `splitKeyframesIn` with `cut = (cutTime − start) / span` to each half.
- [ ] **Step 4:** Run — PASS; run all provider tests — PASS.
- [ ] **Step 5:** Commit `feat(overlays): keyframe target and the edit rule`.

### Task 4: Wire format (Dart)

**Files:**
- Modify: `lib/features/video_editor/models/editor_timeline.dart` (`EditorTimelineOverlay.centerX/centerY/scale/rotation/opacity` become `AnimatableDouble`; `toJson` writes `.toJson()`)
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart` (`build` takes `OverlayMotion`)
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart` (text export path)
- Test: `test/features/video_editor/logic/timeline/overlay_motion_wire_test.dart`

**Interfaces — Produces:**
```dart
/// [a] with every value passed through [f]. Only for affine [f]: interpolation
/// commutes with an affine map, so resolving the mapped parameter equals mapping
/// the resolved value.
AnimatableDouble mapAnimatable(AnimatableDouble a, double Function(double) f);
```

- [ ] **Step 1: Write failing tests:** an un-keyframed photo, video and text overlay produce JSON byte-identical to a golden captured from the current composer before the change (capture it first in this step); a keyframed overlay's `centerX` is a map whose resolved value at 0, 0.25, 0.5, 1 equals `0.5 + x/canvasWidth` of the model's resolved x; text export sends `opacity` from the model (was a constant 1.0) and maps its centre through `textOverlayCenter`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement.** Composer: `centerX: mapAnimatable(params[x]!, (v) => 0.5 + v / canvas.width)` etc. Text export: `mapAnimatable(params[x]!, (v) => textOverlayCenter(text.copyWith(position: Offset(v, text.position.dy)), canvas, rs).dx / canvas.width)` (the clamp is per axis, so each axis maps alone). Fix every Dart reader of the five fields to `.baseValue` or `.resolveAt` (grep `\.centerX\b|\.centerY\b` in `lib/` and `test/`).
- [ ] **Step 4:** Run — PASS; full `flutter test` — PASS.
- [ ] **Step 5:** Commit `feat(overlays): keyframed transform on the wire`.

### Task 5: Kotlin — resolve per frame, redraw, parity fixture

**Files:**
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelineOverlay.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayDrawBuilder.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/OverlayClock.kt`
- Create: `test/fixtures/overlay_motion_fixture.json` and `android/app/src/test/resources/overlay_motion_fixture.json`
- Test: `test/features/video_editor/logic/timeline/overlay_motion_fixture_test.dart`, `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/OverlayMotionTest.kt`, extend `OverlayClockTest.kt`

**Interfaces — Produces (Kotlin):**
```kotlin
val centerX: AnimatableDouble; val centerY: AnimatableDouble
val scale: AnimatableDouble; val rotation: AnimatableDouble; val opacity: AnimatableDouble
val hasKeyframes: Boolean
fun progressAt(timelineSeconds: Double): Double        // 0 when span <= 0
data class FrameState(opacity, scale, offsetX, offsetY, centerX, centerY, rotation)
fun restingStateAt(timelineSeconds: Double): FrameState // keyframes resolved, no preset
fun stateAt(timelineSeconds: Double): FrameState        // keyframes resolved, then presets
```

- [ ] **Step 1: Write failing Kotlin tests:** a numeric wire map resolves exactly as before (static overlay unchanged); a keyframed `centerX` map resolves at progress; `stateAt` applies `fade_in` on top of a keyframed opacity (multiplied) and `slide_left` on top of a keyframed centre (added); `restingStateAt` resolves without presets; `needsRedraw` true for a keyframed overlay when the clock moves inside its span, false when it doesn't move, false for a static overlay mid-span. Dart fixture test: builds three keyframed overlays through the composer, samples resolved placement at 7 progresses, and compares with the committed fixture (regenerate with `UPDATE_OVERLAY_FIXTURE=1 flutter test <file>`, which writes both copies); Kotlin `OverlayMotionTest` parses each fixture overlay with `fromMap` and matches `restingStateAt` to 1e-9.
- [ ] **Step 2:** Run `.\android\gradlew.bat -p android :app:testDebugUnitTest` — FAIL.
- [ ] **Step 3: Implement.** `fromMap` reads the five through `AnimatableDouble.fromWire(map[key], default)`; clamps move to the resolved values (`scale ≥ 0`, `opacity 0..1`). Replace every `overlay.centerX/centerY/rotation/scale/opacity` read in `gl/` with the frame state's; `textState` calls `restingStateAt(t)`. Verify with `grep -rn "overlay\.\(centerX\|centerY\|rotation\|scale\|opacity\)" android/app/src/main/kotlin` → no draw-path hits. `needsRedraw`: after the `contains(now)` check, `if (overlay.hasKeyframes && previous != now) return true`.
- [ ] **Step 4:** Run Kotlin tests and the Dart fixture test — PASS; `flutter build apk --debug` — builds.
- [ ] **Step 5:** Commit `feat(engine): overlays resolve their keyframes per frame`.

### Task 6: Canvas layers — shown where resolved, edited through the rule

**Files:**
- Modify: `lib/features/video_editor/widgets/text_overlay/text_overlay_layer.dart`
- Modify: `lib/features/video_editor/widgets/image_overlay/image_overlay_layer.dart`
- Modify: `lib/features/video_editor/widgets/video_overlay/video_overlay_layer.dart`
- Test: `test/features/video_editor/widgets/overlay_layer_keyframes_test.dart`

- [ ] **Step 1: Write failing widget tests:** a text keyframed x 0→100 over its span, playhead at the midpoint → the painted body's centre is at x 50 (reference px × render scale); opacity keyframed 1→0 → an `Opacity` of 0.5 wraps the body at the midpoint; a one-finger drag on that text writes a keyframe (not the base) and the body does not jump on the first frame (Review Focus 2). For the photo layer: the selection frame sits at the resolved position.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement.** Each layer draws `overlay.shownAt(position)`; text wraps its body content in `Opacity` when below 1. Gesture starts call `beginOverlayEdit()` (after selecting) and anchor on the *shown* values; updates call `setOverlayMotionLive`. Text width pills keep `updateTextOverlayLive` for `boxWidth` and send the centre shift through `setOverlayMotionLive(position:)`.
- [ ] **Step 4:** Run — PASS; all widget tests — PASS.
- [ ] **Step 5:** Commit `feat(overlays): the canvas shows and edits keyframed overlays`.

### Task 7: Timeline diamonds, playback bar, text Opacity

**Files:**
- Modify: `lib/features/video_editor/widgets/timeline/clip_keyframe_diamonds.dart` (reads `keyframeDiamonds`; no segment dependency)
- Modify: `lib/features/video_editor/widgets/timeline/scrollable_timeline.dart` (diamonds on the selected overlay's bar)
- Modify: `lib/screens/video_editor_screen.dart` (bar wiring; `_buildOpacityPanel`; text menu `opacity`)
- Test: `test/features/video_editor/widgets/overlay_keyframe_diamonds_test.dart`, `editor_menu_test.dart`

- [ ] **Step 1: Write failing tests:** the diamonds widget draws one diamond per `keyframeDiamonds` entry at `progress × width` for a selected text, and tapping one seeks the playhead to `start + progress × span`; the text menu declares `opacity`; the screen wires `showsKeyframeControls: editorState.hasKeyframeTarget` and `canToggleKeyframe: editorState.keyframeTargetProgress != null` (source pin, like the menu tests); the Opacity panel shows `overlayEditValue(OverlayProperty.opacity)` for any selected overlay, text included.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement.** Add the diamonds `Positioned` on the selected overlay's bar in `_buildTextTracks/_buildImageTracks/_buildVideoTracks`, at the same `left/width/top` the bar uses, stacked the way the clip's diamonds are relative to its trim handles.
- [ ] **Step 4:** Run — PASS; full `flutter test`, `flutter analyze --no-pub` (48).
- [ ] **Step 5:** Commit `feat(overlays): diamonds on the overlay's bar, Opacity for text`.

### Task 8: Documentation and verification

- [ ] Update `CLAUDE.md`: a section on overlay keyframes (core, adapters, wire, Kotlin resolution, redraw rule, the gesture pause and anchor rules, text opacity), and amend the clip keyframe section's "not in this plan" note.
- [ ] Run the full Dart suite, the Kotlin suite and `flutter build apk --debug`.
- [ ] Commit `docs: overlay keyframes`.
- [ ] Device checklist for the user: a text gliding and fading; a photo growing; a video overlay spinning — each in preview, then export; one project with clip and overlay keyframes over the same seconds; a drag while playing; ✕ on text Opacity.
