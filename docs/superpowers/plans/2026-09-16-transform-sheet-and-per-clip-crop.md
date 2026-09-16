# Transform Sheet and Per-Clip Crop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform becomes a **tool with a three-tab sheet** (Scale / Rotate / Position, each driven by a draggable ruler) instead of a submenu, and a clip can carry its **own freehand crop** independent of the project's.

**Architecture:** The sheet is presentation over parameters that mostly exist — `canvasScale` and `canvasOffsetX/Y` are already keyframable `AnimatableDouble`s written by the pinch gesture. Rotation is genuinely new and goes the full route: model → contract → shader → both engines → export. Per-clip crop splits `contentRect` from **one canvas uniform into one per lane**, mirroring what `uFitIncoming`/`uFitOutgoing` already do.

**Tech Stack:** Flutter/Dart, Kotlin, OpenGL ES 2.0, Riverpod.

**Depends on:** the menu flattening (done — Crop, Zoom and Background are root tools, the `transform` submenu is deleted, and the dead `rotate` tool is gone).

## Global Constraints

- **A project that never opens these tools must render byte-identically.** Rotation defaults to 0, per-clip crop to the full frame, and both serialise as the bare values they replace — no draft migration.
- **One definition of geometry.** `logic/canvas_geometry.dart` already collapses crop/zoom/pan into one rect; per-clip crop composes *through* it, never beside it.
- **The timeline contract is the only channel.** `VideoSegment` → composer → clip JSON → `NativeTimelineClip`. No second interpretation.
- **Preview and export share the compositing.** Anything added to the shader must be set by *both* `TimelinePlaybackEngine` and `VideoExportEngine`, or the file will differ from the canvas.
- **GLSL is compiled at runtime.** `flutter analyze` and `compileDebugKotlin` cannot catch a shader error — device is the only real test, and **both sampler variants** (`sampler2D` for photos, `samplerExternalOES` for video) need checking.
- Undo is manual: `saveStateForUndo()` once per gesture, never per frame.
- Analyzer baseline is exactly **48**. Add none.
- Verify with `flutter analyze --no-pub`, `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.

---

### Task 1: The ruler control

The one genuinely new *widget*. Built and tested alone before anything depends on it.

**Files:**
- Create: `lib/features/video_editor/widgets/panels/value_ruler.dart`
- Test: `test/features/video_editor/widgets/value_ruler_test.dart`

- [x] **Step 1: Write the failing tests**

```dart
testWidgets('dragging right raises the value, left lowers it', (tester) async {
  var value = 1.0;
  await pump(tester, value: value, min: 0.1, max: 8.0,
      onChanged: (v) => value = v);

  await tester.drag(find.byType(ValueRuler), const Offset(60, 0));
  expect(value, greaterThan(1.0));

  final raised = value;
  await tester.drag(find.byType(ValueRuler), const Offset(-60, 0));
  expect(value, lessThan(raised));
});

testWidgets('the value is clamped to its range', (tester) async {
  var value = 1.0;
  await pump(tester, value: value, min: 0.5, max: 2.0,
      onChanged: (v) => value = v);
  await tester.drag(find.byType(ValueRuler), const Offset(5000, 0));
  expect(value, 2.0);
});

testWidgets('a drag is one gesture, reported at its ends', (tester) async {
  // **One undo step per drag**, the rule every gesture in this codebase
  // follows. The ruler reports start and end; the notifier snapshots once.
  var starts = 0;
  var ends = 0;
  await pump(tester, value: 1.0, min: 0, max: 2,
      onChangeStart: () => starts++, onChangeEnd: () => ends++);
  await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
  expect(starts, 1);
  expect(ends, 1);
});

testWidgets('it tracks an anchor, not accumulated deltas', (tester) async {
  // A delta dropped at a clamp is lost for good, leaving the ruler offset
  // from the finger — the fault the trim handles already fixed once.
  var value = 1.0;
  await pump(tester, value: value, min: 0.0, max: 2.0,
      onChanged: (v) => value = v);
  final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ValueRuler)));
  await gesture.moveBy(const Offset(4000, 0)); // slams into max
  await gesture.moveBy(const Offset(-4000, 0)); // all the way back
  await gesture.up();
  expect(value, closeTo(1.0, 0.05),
      reason: 'returning to the start position returns the start value');
});
```

- [x] **Step 2: Run them, watch them fail**

Run: `flutter test test/features/video_editor/widgets/value_ruler_test.dart`
Expected: FAIL, `ValueRuler` undefined.

- [x] **Step 3: Build it**

A horizontal strip of tick marks with a fixed centre indicator, dragged under the finger. Requirements the tests above pin:

- **Anchor-based**: `anchorValue + (fingerX - anchorX) * unitsPerPixel`, never a running sum. The trim handles and every text-overlay handle already follow this rule for the reason the fourth test states.
- `onChangeStart` / `onChangeEnd` so the caller takes **one** undo snapshot.
- Ticks drawn with `CustomPaint`; the centre indicator in `AppColors.primaryStart`.
- A numeric readout (`1.4×`, `-12°`, `0.20`) — a ruler with no number cannot be set precisely.

- [x] **Step 4: Gates and commit**

---

### Task 2: Clip rotation reaches the shader

**Rotation does not exist today.** The `rotate` tool was a menu entry with no handler, and the only `rotation` in the contract belongs to *overlays*. This is the full route, done before the sheet so the Rotate tab has something real to write.

**Files:**
- Modify: `lib/features/video_editor/models/video_segment.dart`
- Modify: `lib/features/video_editor/models/editor_timeline.dart`
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart`
- Modify: `android/.../nativepreview/NativeTimelineClip.kt`
- Modify: `android/.../gl/TransitionShaders.kt`, `gl/TransitionRenderer.kt`
- Modify: `android/.../nativepreview/TimelinePlaybackEngine.kt`, `export/VideoExportEngine.kt`
- Test: extend `test/features/video_editor/models/video_segment_keyframe_test.dart`

- [x] **Step 1: The model**

`VideoSegment.canvasRotation`, an `AnimatableDouble` in **degrees**, default 0.

Degrees not radians: it is what the UI shows and what a draft should be readable as. The shader converts once.

**A sixth `ClipProperty`**, so it keyframes itself through `setClipProperty` with no new UI — the rule that already gave scale and position their keyframes. Add it to `ClipProperty`, `clipParameter` and `withClipParameter`; `hasKeyframes` picks it up automatically.

Serialises as a bare `0.0` when unanimated, so no draft migration.

- [x] **Step 2: Through the contract**

`EditorTimelineClip.canvasRotation` + `canvasRotationAt(progress)`, composed straight through like the transform already is. **The merge rule must refuse two clips rotated differently** — `_canMergeForPlayback` already compares the transform; rotation joins that comparison, or a merged media item would take the first clip's angle for both.

- [x] **Step 3: The shader**

Two uniforms, `uRotationIncoming`/`uRotationOutgoing` (radians), applied inside `incomingAt`/`outgoingAt` — the same place the pan and fit already act, so all eleven transitions inherit it.

**Rotate about the clip's centre, in an aspect-true space.** Rotating in normalised coordinates on a non-square canvas *shears* — `OverlayRenderer.writeCorners` already documents this exact trap for overlays, and the same one applies here:

```glsl
vec2 rotateAboutCentre(vec2 uv, float radians, float aspect) {
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);   // into square space
    float s = sin(radians);
    float c = cos(radians);
    p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
    return p / vec2(aspect, 1.0) + 0.5;        // back out
}
```

**Order: rotate, then fit, then pan.** The clip spins about its own centre, the fit keeps it inside the canvas, and the pan moves where it sits — any other order rotates the *letterbox* rather than the picture.

Corners rotated outside the fitted rect return `uBackground`, which the existing bounds check already does.

- [x] **Step 4: Both engines**

`applyLaneFits` (preview) and `prepareLane` (export) each push the angle resolved at the clip's own progress — `canvasRotationAt(clipProgressAt(t))` — beside the scale and pan they already push. **Both, or the file will not match the canvas.**

- [x] **Step 5: Tests**

Round-trip, a keyframed rotation resolving mid-clip, the merge refusal, and an unrotated clip serialising as a bare number.

- [x] **Step 6: Gates and commit** (including `compileDebugKotlin`)

---

### Task 3: The Transform sheet

**Files:**
- Create: `lib/features/video_editor/widgets/panels/transform_sheet.dart`
- Modify: `lib/screens/video_editor_screen.dart`
- Test: `test/features/video_editor/widgets/transform_sheet_test.dart`

- [x] **Step 1: Write the failing tests**

```dart
testWidgets('three tabs, one shown at a time', (tester) async {
  await openSheet(tester);
  expect(find.text('Scale'), findsOneWidget);
  expect(find.text('Rotate'), findsOneWidget);
  expect(find.text('Position'), findsOneWidget);
  // Scale opens first and shows one ruler.
  expect(find.byType(ValueRuler), findsOneWidget);
});

testWidgets('Position shows two rulers, X and Y', (tester) async {
  await openSheet(tester);
  await tester.tap(find.text('Position'));
  await tester.pumpAndSettle();
  expect(find.byType(ValueRuler), findsNWidgets(2));
});

testWidgets('with no clip selected it says so rather than lying',
    (tester) async {
  // Every tab writes a *clip* property, so with nothing selected there is
  // nothing to write — the same rule the volume panel follows.
  await openSheet(tester, selectedSegmentId: null);
  expect(find.byType(ValueRuler), findsNothing);
  expect(find.textContaining('Select a clip'), findsOneWidget);
});

testWidgets('dragging Scale writes through the edit rule', (tester) async {
  // Which means it keyframes itself on a keyframed clip, with no keyframe
  // UI of its own — `setClipProperty`, like every other control.
  final notifier = notifierWith([clip('a')], selectedSegmentId: 'a');
  await openSheet(tester, notifier: notifier);
  await tester.drag(find.byType(ValueRuler), const Offset(50, 0));
  expect(notifier.state.segments.first.canvasScale.baseValue,
      greaterThan(1.0));
});

testWidgets('a drag is one undo step', (tester) async {
  final notifier = notifierWith([clip('a')], selectedSegmentId: 'a');
  await openSheet(tester, notifier: notifier);
  final before = notifier.state.segments.first.canvasScale;
  await tester.drag(find.byType(ValueRuler), const Offset(50, 0));
  notifier.undo();
  expect(notifier.state.segments.first.canvasScale, before);
});

testWidgets('each ruler shows the value the write will target',
    (tester) async {
  // The rule `clipEditValue` states: with diamonds, the value at the
  // playhead, not the base — or the ruler is a control that lies, which is
  // the volume-slider bug from before.
  ...
});
```

- [x] **Step 2: Run them, watch them fail**

- [x] **Step 3: Build the sheet**

**Styled from the curve sheet**, which is itself styled from the effects sheet: `AppColors.background`, `BorderRadius.vertical(top: Radius.circular(24))`, the standard grab handle, the **pill row** for tabs (not a Material `TabBar`), and one `_kEdge` aligning everything. That pattern is now established in three places — do not invent a fourth.

| Tab | Writes | Range |
| :--- | :--- | :--- |
| **Scale** | `ClipProperty.canvasScale` | `kMinClipCanvasScale`–`kMaxClipCanvasScale` (0.1–8.0) |
| **Rotate** | `ClipProperty.canvasRotation` | −180°–180° |
| **Position** | `canvasOffsetX`, `canvasOffsetY` | −1.5–1.5, two rulers |

Every write goes through **`setClipProperty`**, so all three inherit keyframing without knowing the feature exists — and every ruler *displays* `clipEditValue`, so it shows what its write will target.

- [x] **Step 4: Wire it**

`'transform'` in the panel dispatch opens the sheet, exactly as `'effects'` does. The root tool no longer has `hasSubMenu`.

- [x] **Step 5: Gates and commit**

---

### Task 4: `contentRect` becomes per-lane

The contract change that per-clip crop needs. **Behaviour-preserving on its own** — every clip gets the project rect until Task 5 gives it its own.

**Files:**
- Modify: `android/.../gl/TransitionShaders.kt`, `gl/TransitionRenderer.kt`
- Modify: `android/.../nativepreview/TimelinePlaybackEngine.kt`, `export/VideoExportEngine.kt`

- [x] **Step 1: Split the uniform**

`uContentRect` becomes `uContentRectIncoming`/`uContentRectOutgoing`, set per lane rather than bound once in `bindCanvas`.

This mirrors `uFitIncoming`/`uFitOutgoing` exactly, which is the precedent to copy — including that a lane holding a photo samples through it identically.

- [x] **Step 2: Both engines push it per lane**

A new `setLaneContentRect(laneIndex, …)` beside `setLaneFit`, change-guarded the way every lane setter is. `bindCanvas` stops carrying the rect.

- [x] **Step 3: Gates, and a device check before Task 5**

**This step alone is worth verifying on device**, because it changes the sampling path for *every* clip while intending to change nothing: crop, zoom and pan must all still behave, on video and on photos, in preview and in export. A regression here would otherwise be discovered later and blamed on per-clip crop.

---

### Task 5: Per-clip freehand crop

**Files:**
- Modify: `lib/features/video_editor/models/video_segment.dart`, `editor_timeline.dart`
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart`
- Modify: `lib/screens/video_editor_screen.dart` (add Crop to `_editMenu`)
- Modify: `android/.../nativepreview/NativeTimelineClip.kt` + both engines
- Test: extend the segment and composer tests

- [x] **Step 1: The model**

`VideoSegment.cropRect`, a `Rect` in **source fractions**, default `Rect.fromLTWH(0, 0, 1, 1)`.

Fractions, like every other geometry in this codebase: a trimmed or differently-sized source keeps its crop, and a draft renders identically on any device.

**Not an `AnimatableDouble`** — a rect is four numbers, and an animated crop is a different feature (a pan-and-scan) with its own design. Deliberately out of scope; say so at the field.

- [x] **Step 2: Composed per clip**

The composer resolves each clip's rect **through `resolveContentRect`**, composing the clip's crop with the project's crop/zoom/pan rather than replacing it — one geometry definition, as the constraint requires. A clip with the default rect resolves to exactly what it gets today.

- [x] **Step 3: The entry point**

Crop joins `_editMenu` — the clip's contextual menu, beside Filters and Effects, which is where per-clip things live. It opens the **existing** custom-crop surface with the clip's own rect, **freehand only**: no ratio row, because a per-clip ratio would fight the project canvas that every clip is fitted into.

- [x] **Step 4: The merge rule**

`_canMergeForPlayback` refuses two clips cropped differently — a merged media item can only carry one rect. Same rule the transform and the grade already follow.

- [x] **Step 5: Tests**

An uncropped clip composes identically to today; a cropped clip reaches the timeline clip; two differently-cropped clips do not merge; a crop survives a draft round-trip and a split (both halves keep it — they are the same footage).

- [x] **Step 6: Gates and commit**

---

### Task 6: Device verification

Nothing here is provable on a desktop: the shader is compiled at runtime, and the whole point is what the picture looks like.

- [ ] **Step 1: The menu**

1. Crop, Transform, Zoom and Background are all on the root toolbar; no Transform submenu; no Rotate tool.
2. Crop, Zoom and Background still work from their new home.

- [ ] **Step 2: The sheet**

3. Scale drags up and down and the clip scales about its centre.
4. Rotate spins the clip about its own centre — **not** the letterbox, and **no shear** on a 9:16 canvas.
5. Position moves the clip on both axes, and the direction matches the finger.
6. Each tab's ruler shows the current value when opened.
7. A drag is one undo step.

- [ ] **Step 3: Keyframes, which come free**

8. With two diamonds, a Scale drag writes a keyframe rather than the base, and the move plays.
9. The same for Rotate — the sixth property.

- [ ] **Step 4: Per-clip crop**

10. Cropping one clip leaves its neighbours untouched.
11. The project crop still works and composes with a clip's own.
12. **Photos and video both**, in preview *and* in the exported file.
13. A transition between a cropped clip and an uncropped one blends correctly.

- [ ] **Step 5: Unchanged**

14. A project touching none of this renders exactly as before, exported.

- [ ] **Step 6: Update CLAUDE.md**

## Exit criteria

- [ ] Transform is a tool with a three-tab ruler sheet; its children are root tools.
- [ ] Clip rotation exists end to end and keyframes like every other property.
- [ ] `contentRect` is per-lane, with crop/zoom/pan unchanged for existing projects.
- [ ] A clip can carry its own freehand crop, composed with the project's.
- [ ] `flutter test`, `flutter analyze --no-pub` (48), `compileDebugKotlin` all pass.
- [ ] Device-verified, both sampler variants, preview and export.
