# Preview text drawn by the engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the preview, text and captions are drawn by the native engine at the picture's own time, as the export draws them, while the text being edited stays drawn by Flutter so editing is as immediate as today.

**Architecture:** Dart prepares each nearby text's atlas with the export's own `TextOverlayRasterizer.rasterizeAtlas`, at the preview texture's density, one at a time in the background, and sends the texts near the playhead on the existing `setOverlays` channel as `text` entries built by the export's own entry code. The engine's realtime `OverlayDrawBuilder` already draws such entries; it gains readiness events, texture release for paths no longer listed, preloading, and a clock that times overlays by the video frame being composited. `TextOverlayLayer` paints nothing for a text the engine has confirmed, and keeps every gesture and handle.

**Tech Stack:** Flutter 3.47 / Dart 3.13 (Riverpod, `flutter_test`, `fake_async`), Kotlin (Media3, GLES2, JUnit 4).

**Spec:** `docs/superpowers/specs/2026-10-31-preview-text-in-engine-design.md`

## Global Constraints

- Editing a text (typing, styling, Size, width, move, pinch, turn) shows each change in the same frame as today: the selected text, while paused, is drawn by Flutter.
- No visible text is ever drawn by nobody: Flutter stops drawing a text only two Flutter frames after the engine reported its current atlas; the reverse hand-over is immediate. Overlap at most two frames, never a gap.
- Preview atlases come from `TextOverlayRasterizer.rasterizeAtlas` (no second text layout) at `previewRasterScale` = the preview texture's pixels per canvas pixel, never below 1.
- The export's output does not change.
- Nothing tuned to one phone: windows in seconds, waits in frames or milliseconds.
- A preview-only fallback is logged, never toasted (the owner's rule): a text the engine cannot draw goes back to Flutter silently.
- While an export holds the renderer (`exportOwnsRenderer`), nothing here writes renderer state.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; stage files by name; `flutter analyze --no-pub` stays at 43 issues.

## Review Focus

1. **A jump while paused** into texts the engine does not hold: they show at once, drawn by Flutter until the engine reports them. Pinned in Task 5 (`a jump into new texts draws them with Flutter until the engine has them`).
2. **Undo of a look change on a visible engine-drawn caption**: the new look shows at once (Flutter), and the old entry leaves the payload in the same update. Pinned in Task 5 (`a look change hands the text back to Flutter at once`).
3. **Captions over a photo clip**, where ExoPlayer's position holds one value for most of a second: the caption's highlight keeps moving. Pinned in Task 8 (`over a photo it runs on from the last change of the clock`).
4. **The keyboard or a tool panel resizing the canvas**: no atlas is made again and nothing flips back to Flutter. Pinned in Tasks 1, 3 and 5 (`the canvas size is not part of the key`, `an atlas made at another canvas size places the same box`, `a canvas resize keeps every atlas`).
5. **An export while captions are engine-drawn**: afterwards the captions still show, drawn by Flutter until the engine reloads them. Pinned in Task 7 (`textsIn keeps only text`) and checked on the device in Task 11.

---

## File map

| File | Responsibility |
|---|---|
| `lib/features/video_editor/logic/preview_text/preview_text_atlas_key.dart` (new) | What a preview atlas depends on; the scale it is drawn at |
| `lib/features/video_editor/logic/preview_text/preview_text_rules.dart` (new) | Windows, preparation order, who draws a text, raster scale, entry ids |
| `lib/features/video_editor/services/text_atlas_overlay.dart` | + the one builder of a text's overlay entry, for export and preview |
| `lib/features/video_editor/services/native_timeline_preview_service.dart` | export uses the shared builder; payload takes text entries; events carry `overlayId`/`path` |
| `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart` | `composeOverlays` takes `extraOverlays` |
| `lib/features/video_editor/services/preview_text_atlases.dart` (new) | The preview's atlases: preparation, cache, files, readiness, who draws |
| `lib/core/utils/file_utils.dart` | the launch sweeps text atlases |
| `lib/features/video_editor/widgets/text_overlay/text_overlay_layer.dart` | paints nothing for engine-drawn texts |
| `lib/features/video_editor/widgets/canvas/video_preview_canvas.dart` | passes the engine-drawn set to the text layers |
| `lib/screens/video_editor_screen.dart` | wiring |
| `android/.../nativepreview/gl/StillResidency.kt` (new) | which still textures to free, which texts to preload, in what order |
| `android/.../nativepreview/gl/PictureClock.kt` (new) | the timeline instant overlays are drawn at |
| `android/.../nativepreview/OverlayClock.kt` | a live text redraws on every clock step |
| `android/.../nativepreview/gl/OverlayDrawBuilder.kt` | ready/gone events, `preloadTexts` |
| `android/.../nativepreview/gl/TransitionRenderer.kt` | residency, picture clock, draw order, events out |
| `android/.../nativepreview/TimelinePlaybackEngine.kt` | one "advancing" rule; clock read time |
| `android/.../nativepreview/NativeTimelinePreviewManager.kt` | sends `textReady`/`textGone` |

(`android/...` = `android/app/src/main/kotlin/com/techfamz/slimshotai`; Kotlin tests mirror it under `android/app/src/test/kotlin/...`.)

---

### Task 1: The atlas key and the drawing scale

**Files:**
- Create: `lib/features/video_editor/logic/preview_text/preview_text_atlas_key.dart`
- Test: `test/features/video_editor/logic/preview_text/preview_text_atlas_key_test.dart`

**Interfaces:**
- Produces: `double previewAtlasScale(TextOverlayModel text)`; `String previewTextAtlasKey(TextOverlayModel text, {required Size textureSize, required bool fontReady})`.

**Why no canvas size in the key:** the atlas is drawn at `canvas × previewRasterScale` = the texture's pixels, and text layout is canvas-relative, so the same text on a resized canvas is the same atlas. The keyboard and tool panels resize the canvas constantly; keying on it would make every atlas again each time.

- [ ] **Step 1: Write the failing tests**

Build `rich` as `text_look_test.dart` does (every field set).
- `every field a text serialises affects its atlas, its density, or neither`: classify `rich.toJson().keys` into
  - `drawnKeys = {text, color, fontFamily, backgroundColor, strokeColor, strokeWidth, shadowColor, shadowBlurRadius, shadowOpacity, shadowDistance, shadowAngle, borderRadius, backgroundPadding, textAlign, fontSize, boxWidth, refWidth, refHeight, highlight, captionWords}`
  - `densityKeys = {scale, keyframes}`
  - `placementKeys = {id, positionX, positionY, rotation, opacity, startTimeMs, endTimeMs, laneIndex, inAnimation, outAnimation, loopAnimation, animationInDuration, animationOutDuration, loopSpeed, animationSchema, captionSetId}`

  Expect the remainder empty (`reason: 'classify the new field'`) and the three sets disjoint.
- `placement, timing and animation leave the key alone`: changing position, rotation, opacity, start/end, lane, any animation id or speed, captionSetId, a position keyframe, or the times of `captionWords` (same `textStart`/`textEnd`) gives the same key.
- `anything drawn changes the key`: text, each look field, `fontSize`, `boxWidth`, the highlight, a word's `textStart`/`textEnd`, `textureSize` and `fontReady` each change it.
- `the canvas size is not part of the key`: `previewTextAtlasKey` takes no canvas; the same text gives the same key whatever canvas it is later drawn on (asserted by the signature compiling and one equality).
- `the scale is drawn in quarter steps, never below the text's own`:
  - `previewAtlasScale` of scale 1.0 → 1.0;
  - 1.05 and 1.18 → `pow(2, 0.25)`;
  - 2.0 → 2.0;
  - `previewAtlasScale(t) >= textOverlayPeakScale(t)` for 50 scales from 0.2 to 6;
  - 1.05 and 1.18 give the same key; 1.0 and 1.05 do not.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/features/video_editor/logic/preview_text/preview_text_atlas_key_test.dart`
Expected: FAIL — the functions do not exist.

- [ ] **Step 3: Implement**
  - `previewAtlasScale`: `textOverlayPeakScale(text)` rounded up to `2^(k/4)`, where `k = (4 * log2(s) - 1e-9).ceil()`. The epsilon keeps an exact step from rounding up one more.
  - The key: `jsonEncode` of the `drawnKeys` fields from `text.toJson()`, with `captionWords` reduced to `[textStart, textEnd]` pairs, plus `previewAtlasScale(text)`, `textureSize.width`, `textureSize.height` and `fontReady`.

- [ ] **Step 4: Run to see them pass.** Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/logic/preview_text/preview_text_atlas_key.dart test/features/video_editor/logic/preview_text/preview_text_atlas_key_test.dart
git commit -m "feat(preview-text): what a preview text atlas depends on"
```

---

### Task 2: Windows, order and who draws

**Files:**
- Create: `lib/features/video_editor/logic/preview_text/preview_text_rules.dart`
- Test: `test/features/video_editor/logic/preview_text/preview_text_rules_test.dart`

**Interfaces:**
- Produces:
  - Window constants:
    - `kPreviewTextPrepareBehindSeconds = 5.0`, `kPreviewTextPrepareAheadSeconds = 30.0`: which texts get atlases.
    - `kPreviewTextSendBehindSeconds = 0.5`, `kPreviewTextSendAheadSeconds = 2.0`: which go to the engine. This window is the GPU budget: only what is near the playhead is resident.
  - `Set<String> textsNear(Iterable<TextOverlayModel> texts, double playhead, {required double behind, required double ahead})`: the ids where `start <= playhead + ahead && end > playhead - behind`.
  - `List<String> previewAtlasOrder(Iterable<TextOverlayModel> texts, double playhead)`, in this order:
    1. live (`start <= playhead < end`), by start;
    2. then ahead, by start ascending;
    3. then behind, by end descending.
  - `bool isTextBeingEdited(String textId, {required String? selectedTextId, required bool isPlaying})`: selected and not playing.
  - `double previewRasterScale({required Size textureSize, required Size canvasSize})`: `max(1, texture.shortestSide / canvas.shortestSide)`, and 1 for an empty size.
  - `String previewTextEntryId(String textId)` returns `'text_$textId'`. `String? previewTextIdOf(String entryId)` returns the id, or null without the prefix.

- [ ] **Step 1: Write the failing tests**
  - `near keeps what is near and drops what is far`: texts [0,1], [5,6], [9,10] and [20,21], playhead 5, behind 2, ahead 8 → {[5,6], [9,10]}. A text spanning [0, 60] is in at playhead 30.
  - `the window edges`: a text ending exactly at `playhead − behind` is out; one starting exactly at `playhead + ahead` is in.
  - `live first, then ahead, then behind`: playhead 5; A[4,6], B[7,8], C[6.5,7], D[2,3], E[0,1] → [A, C, B, D, E].
  - `being edited is selected and paused`:
    - selected, paused → true;
    - selected, playing → false;
    - another text selected, paused → false;
    - nothing selected, paused → false.
  - `preview raster scale`:
    - texture 720×1280 over canvas 270×480 → 8/3;
    - a canvas larger than the texture → 1.0;
    - a zero-size canvas → 1.0.
  - `entry ids round-trip`: `previewTextIdOf(previewTextEntryId('a')) == 'a'`; `previewTextIdOf('img_1') == null`.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/features/video_editor/logic/preview_text/preview_text_rules_test.dart`
Expected: FAIL — the functions do not exist.

- [ ] **Step 3: Implement the functions.** Times come from `startTime`/`endTime`, in seconds.

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/logic/preview_text/preview_text_rules.dart test/features/video_editor/logic/preview_text/preview_text_rules_test.dart
git commit -m "feat(preview-text): which texts the preview prepares and sends, in what order, and who draws"
```

---

### Task 3: One builder of a text's overlay entry

**Files:**
- Modify: `lib/features/video_editor/services/text_atlas_overlay.dart`
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart:457-540` (the entry construction in `_rasterizeTextOverlays`)
- Test: `test/features/video_editor/services/text_atlas_overlay_test.dart`

**Interfaces:**
- Consumes: `previewTextEntryId` (Task 2).
- Produces: `EditorTimelineOverlay textAtlasOverlayEntry(TextOverlayModel text, RasterizedTextAtlas atlas, Size canvasSize, {Size? atlasCanvasSize, bool hidden = false})`. It returns exactly the atlas-path entry the export builds today:
  - id `previewTextEntryId(text.id)`, kind `text`, and the atlas's path;
  - glyphs, background, `backgroundAtlas` and highlight;
  - placement from `textOverlayWirePlacement(text, canvasSize)`;
  - box, background rect and slide offsets as fractions of `atlasCanvasSize ?? canvasSize`, the canvas the atlas was made at;
  - lane `1000 + laneIndex`;
  - catalog animation ids and speeds, and `0.5` s in/out.

  `hidden: true` replaces opacity with a constant `AnimatableDouble(0)`. The entry stays resident in the engine and draws nothing there.

- [ ] **Step 1: Write the failing tests**

Rasterize a text with `kTestFontFamily` at canvas 360×640 and `rasterScale` 2.
- `the entry is the export's atlas entry`:
  - id `'text_<id>'`, kind `'text'`, the atlas path;
  - glyph count equals `atlas.glyphs.length`;
  - laneIndex `1000 + lane`;
  - `boxWidth == textOverlayBoxPx(atlas.canvasPxSize, usingAtlas: true).width / 360`;
  - an in-animation of `'none'` sends null;
  - `animationInSeconds == 0.5`.
- `hidden keeps everything but opacity`: the two entries' `toJson()` are equal except `opacity`, which is 0.
- `an atlas made at another canvas size places the same box`: rasterize at canvas 270×480 (`rasterScale` 8/3) and at 360×640 (`rasterScale` 2). Build both entries at canvas 360×640, each with its own `atlasCanvasSize`. `boxWidth`, `boxHeight`, `slideOffsetX` and `slideOffsetY` agree within 0.5%.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/features/video_editor/services/text_atlas_overlay_test.dart`
Expected: FAIL — `textAtlasOverlayEntry` does not exist.

- [ ] **Step 3: Move the export's atlas-branch entry construction into `textAtlasOverlayEntry`** and call it from `_rasterizeTextOverlays`. The flat-raster fallback stays where it is. `_catalogTextAnimation` moves with it.

- [ ] **Step 4: Run the new tests and the export's text tests**

Run: `flutter test test/features/video_editor/services/`
Expected: PASS, the existing text export tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/services/text_atlas_overlay.dart lib/features/video_editor/services/native_timeline_preview_service.dart test/features/video_editor/services/text_atlas_overlay_test.dart
git commit -m "refactor(text-export): one builder of a text's overlay entry, for export and preview"
```

---

### Task 4: The overlay payload takes text, the events carry ids

**Files:**
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart` (`composeOverlays`)
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart` (`overlayPayload`, `NativeTimelinePreviewEvent`)
- Test: `test/features/video_editor/services/native_preview_event_test.dart`, `test/features/video_editor/services/native_overlay_sync_test.dart`

**Interfaces:**
- Produces:
  - `composeOverlays(state, {Size? previewCanvasSize, List<EditorTimelineOverlay> extraOverlays = const []})`, merged and lane-sorted as the export's extra overlays are;
  - `overlayPayload(state, {Size? previewCanvasSize, List<EditorTimelineOverlay> textEntries = const []})`;
  - `NativeTimelinePreviewEvent.overlayId` and `.path` (`String?`), read from the `overlayId` and `path` keys.

- [ ] **Step 1: Write the failing tests**
  - `textReady and textGone carry the overlay and its atlas`: `fromPlatformEvent({'type': 'textReady', 'overlayId': 'text_a', 'path': '/x.png'})` gives that type, overlayId and path.
  - `text entries ride the payload above every other overlay`: a state with one photo overlay on lane 0 and one text entry on lane 1000. The payload lists the photo first, then the text entry's JSON unchanged.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/features/video_editor/services/native_preview_event_test.dart test/features/video_editor/services/native_overlay_sync_test.dart`
Expected: FAIL — the parameters and fields do not exist.

- [ ] **Step 3: Add the parameters and fields.**

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart lib/features/video_editor/services/native_timeline_preview_service.dart test/features/video_editor/services/native_preview_event_test.dart test/features/video_editor/services/native_overlay_sync_test.dart
git commit -m "feat(preview-text): the overlay payload carries text entries; readiness events"
```

---

### Task 5: `PreviewTextAtlases`: preparation, cache and who draws

**Files:**
- Create: `lib/features/video_editor/services/preview_text_atlases.dart`
- Modify: `lib/core/utils/file_utils.dart` (`textRasterPrefix`, `isAppTempName`), `lib/features/video_editor/services/text_overlay_rasterizer.dart:284` (names its file with `FileUtils.textRasterPrefix`)
- Test: `test/features/video_editor/services/preview_text_atlases_test.dart`, `test/core/utils/file_utils_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  ```dart
  typedef PreviewAtlasRasterizer = Future<RasterizedTextAtlas?> Function(
      TextOverlayModel text, Size canvasSize, double rasterScale);

  const Duration kPreviewAtlasSettle = Duration(milliseconds: 250);
  const Duration kPreviewAtlasFileGrace = Duration(seconds: 2);
  const int kPreviewAtlasCacheSize = 120;

  class PreviewTextAtlases extends ChangeNotifier {
    PreviewTextAtlases({
      required PreviewAtlasRasterizer rasterize,
      required bool Function(String fontFamily) fontReady,
      Future<void> Function()? nextFrame,             // default SchedulerBinding.instance.endOfFrame
      Future<void> Function(String path)? deleteFile, // default FileUtils.deleteFile
      Duration settle = kPreviewAtlasSettle,
      Duration fileGrace = kPreviewAtlasFileGrace,
      int cacheSize = kPreviewAtlasCacheSize,
    });

    void update({
      required List<TextOverlayModel> texts,
      required double playhead,
      required String? selectedTextId,
      required bool isPlaying,
      required Size? canvasSize,
      required Size textureSize,
      required bool engineAvailable,
    });

    /// Same instance until it changes, so callers compare by identity.
    List<EditorTimelineOverlay> get payload;

    /// Model ids of the texts the engine draws. The layer paints nothing for them.
    ValueListenable<Set<String>> get engineDrawn;

    void engineReady(String entryId, String path);
    void engineGone(String entryId, String path);
  }
  ```
  `FileUtils.textRasterPrefix = 'text_overlay_'`.

The rules it holds:

- **Preparation.**
  - What: the texts in the prepare window that have no atlas for their current key and no failure recorded for that key, taken in `previewAtlasOrder`.
  - Pace: one atlas at a time, and one `nextFrame` between atlases. That caps the UI work at one atlas per frame.
  - When: only once `texts` has kept its identity for `settle`. A drag or typing therefore prepares nothing until it stops. Playback never changes `texts`.
  - How: the raster input is `text.copyWith(scale: previewAtlasScale(text))`, with the canvas of that moment and `previewRasterScale(textureSize, canvas)`. The atlas records the canvas it was made at.
- **Keys** are memoized per `TextOverlayModel` instance (an edited text is a new object), so an update that only moves the playhead computes none.
- **Failure.** A null result, or one with no glyphs, is a failure for that key and is not retried until the key changes. A result whose key is no longer current is thrown away and its file deleted.
- **Payload.** The texts in the send window with a current atlas, built by `textAtlasOverlayEntry` with the atlas's own canvas; `hidden` while the text is being edited. The payload is empty without an engine or a canvas.
- **Who draws.**
  - A text joins `engineDrawn` two `nextFrame`s after all four hold:
    - the engine has reported its current path,
    - the text is in the payload,
    - it is not hidden,
    - an engine is present.

    All four are checked again at the end of the wait.
  - It leaves at once when any of them stops holding.
- **Files and cache.**
  - The cache is least-recently-used, holds `cacheSize` atlases, and marks payload atlases as used on every update.
  - A file is deleted once its atlas has left the cache and has been absent from the payload for `fileGrace`.
  - `dispose` deletes every file; a rasterize that lands after `dispose` deletes its own.
- **Notification.** Listeners are told whenever `payload` or `engineDrawn` changes.

- [ ] **Step 1: Write the failing tests**

Set-up: a fake rasterizer returning a fake `RasterizedTextAtlas` (one glyph, from the glyph fixture of `text_atlas_overlay_test.dart`) with a unique `pngPath`, counting its calls. `fakeAsync`. `nextFrame` completes queued completers the test releases one by one.
- `nothing is prepared before the edits settle`: one live text; no call at 200 ms, one call at 260 ms.
- `typing never prepares mid-word`: ten updates with new text objects 100 ms apart; no call until 250 ms after the last.
- `one atlas at a time, a frame between them`: two texts; the second call starts only after the first returns and one frame is released.
- `nearest first`: three window texts are prepared in `previewAtlasOrder`.
- `far texts are neither prepared nor sent`: playhead 0, texts at 20 s and 60 s. The 20 s text is prepared but not in the payload; the 60 s text is not prepared.
- `a prepared text rides the payload but Flutter draws it until the engine has it`:
  - after preparation the payload holds `text_a` and `engineDrawn` is empty;
  - after `engineReady('text_a', path)` and one frame, still empty;
  - after the second frame, `{a}`.
- `the edited text stays Flutter's and is sent hidden`:
  - selected and paused: the entry's opacity is 0, and `engineDrawn` stays empty after `engineReady`;
  - `update` with `isPlaying: true`: `{a}` after two frames.
- `a look change hands the text back to Flutter at once`: an engine-drawn text gets a new colour. In that same `update`, `engineDrawn` loses it and the payload no longer holds the old entry. A new atlas is prepared after the settle.
- `moving a text needs no new atlas`: changing position, rotation or opacity makes no new call; the payload's placement follows.
- `a canvas resize keeps every atlas`: a new `canvasSize` alone makes no new call and `engineDrawn` is unchanged.
- `a jump into new texts draws them with Flutter until the engine has them`: playhead 0 → 30 over prepared texts at 30 s; they stay out of `engineDrawn` until their ready events.
- `the engine losing an atlas gives the text back to Flutter`: `engineGone` with the current path takes it out at once; with an older path, nothing changes.
- `a failed atlas stays with Flutter until the text changes`: a null result once; no second call over 10 updates; a text change calls again.
- `a font arriving prepares the text again`: `fontReady` false, then true with a new `update`, makes a second call.
- `a stale result is thrown away`: the text changes while its call is pending; the result is not used and its file is deleted.
- `files go when nothing uses them`: with `cacheSize: 1`, the evicted atlas's file is deleted only once `fileGrace` has passed outside the payload. `dispose` deletes the rest, and a call landing after `dispose` deletes its own.
- `no engine, nothing sent and Flutter draws everything`: `engineAvailable: false` gives an empty payload and an empty `engineDrawn` in that update.
- In `file_utils_test.dart`, `the launch sweeps text atlases`: `isAppTempName('text_overlay_a_1.png')` is true.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/features/video_editor/services/preview_text_atlases_test.dart test/core/utils/file_utils_test.dart`
Expected: FAIL — the class and the prefix do not exist.

- [ ] **Step 3: Implement `PreviewTextAtlases`, the prefix, and the rasterizer's file name.**

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/services/preview_text_atlases.dart lib/core/utils/file_utils.dart lib/features/video_editor/services/text_overlay_rasterizer.dart test/features/video_editor/services/preview_text_atlases_test.dart test/core/utils/file_utils_test.dart
git commit -m "feat(preview-text): prepare, keep and hand over the preview's text atlases"
```

---

### Task 6: The text layer paints nothing the engine draws

**Files:**
- Modify: `lib/features/video_editor/widgets/text_overlay/text_overlay_layer.dart`, `lib/features/video_editor/widgets/canvas/video_preview_canvas.dart:297`
- Test: `test/features/video_editor/widgets/text_layer_engine_drawn_test.dart`

**Interfaces:**
- Produces: `TextOverlayLayer(..., ValueListenable<Set<String>>? engineDrawn)` and `VideoPreviewCanvas(..., ValueListenable<Set<String>>? engineDrawnTexts)`, which passes it to every lane's `TextOverlayLayer`.

- [ ] **Step 1: Write the failing tests** (the layer pumped as `text_layer_drawn_playhead_test.dart` does)
  - `an engine-drawn text paints nothing but still takes a tap`: with `engineDrawn = {a}`, the tree holds no `TextOverlayPainter` for `a`, and a tap on `a`'s box selects it.
  - `the selection frame stays`: `a`, selected and engine-drawn, still shows its frame's handles.
  - `handing back repaints`: setting `engineDrawn` to `{}` brings `a`'s painter back with no other rebuild.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/features/video_editor/widgets/text_layer_engine_drawn_test.dart`
Expected: FAIL — the parameter does not exist.

- [ ] **Step 3: Implement.** In `_buildBody`, a text whose id is in `engineDrawn` gets a `SizedBox` of the box's size in place of the painter, with no `Opacity`. The layer listens to `engineDrawn` as it listens to `playhead`.

- [ ] **Step 4: Run to see them pass**, then `flutter test test/features/video_editor/widgets/`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/widgets/text_overlay/text_overlay_layer.dart lib/features/video_editor/widgets/canvas/video_preview_canvas.dart test/features/video_editor/widgets/text_layer_engine_drawn_test.dart
git commit -m "feat(preview-text): the text layer paints nothing the engine draws"
```

---

### Task 7: Which stills to free, which texts to preload (Kotlin, pure)

**Files:**
- Create: `android/.../nativepreview/gl/StillResidency.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/gl/StillResidencyTest.kt`

**Interfaces:**
- Produces:
  ```kotlin
  internal object StillResidency {
      /** Photo and text overlays of [previous] whose path [next] no longer names; one per path. */
      fun released(previous: List<NativeTimelineOverlay>, next: List<NativeTimelineOverlay>): List<NativeTimelineOverlay>
      /** Text overlays in the order to load them: live at [t] first, then by start. */
      fun preloadOrder(overlays: List<NativeTimelineOverlay>, t: Double): List<NativeTimelineOverlay>
      /** Every text overlay in [list] — what an export's texture purge takes from the preview. */
      fun textsIn(list: List<NativeTimelineOverlay>): List<NativeTimelineOverlay>
  }
  ```
  Live comes first because a hidden text (opacity 0) is live, but `drawsFor` skips it before uploading. Only the preload ever loads it.

- [ ] **Step 1: Write the failing tests.** Overlays are built with `NativeTimelineOverlay.fromMap`, as `OverlayClockTest` builds them; a text takes `kind: "text"` and one glyph map.
  - `a path the new list drops is released once`: previous {photo /a, text /b, text /b again}, next {photo /a} → [/b], once.
  - `video overlays are never released here`: dropping a video overlay releases nothing.
  - `an unchanged path stays`: a text moved, same path → nothing released.
  - `live first, then by start`: t = 1; texts at 5 s, 3 s and a live one at [0, 2] → [live, 3 s, 5 s]; photo overlays are left out.
  - `textsIn keeps only text`: a mixed list gives its texts only.

- [ ] **Step 2: Run to see them fail**

Run (from `android/`): `./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.nativepreview.gl.StillResidencyTest"`
Expected: FAIL — unresolved reference.

- [ ] **Step 3: Implement `StillResidency`.**

- [ ] **Step 4: Run to see them pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/StillResidency.kt android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/gl/StillResidencyTest.kt
git commit -m "feat(preview-text): which still textures the preview frees and preloads"
```

---

### Task 8: When text redraws, and at what instant (Kotlin, pure)

**Files:**
- Modify: `android/.../nativepreview/OverlayClock.kt` (`needsRedraw`)
- Create: `android/.../nativepreview/gl/PictureClock.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/OverlayClockTest.kt`, `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/gl/PictureClockTest.kt`

**Interfaces:**
- Produces:
  - `OverlayClock.needsRedraw` gains one case: a text overlay redraws on every clock step inside its span. A highlight, a per-letter animation or a loop changes it continuously. Its windows come from the catalog in `TextAnimationTiming`, not from `animationInSeconds`.
  - ```kotlin
    internal class PictureClock {   // every method @Synchronized: the engine writes from main, the renderer reads on GL
        fun onClock(seconds: Double, readNs: Long, advancing: Boolean)
        fun onVideoFrame(dueNs: Long, latchedNs: Long)   // a frame of the clock's lane: SurfaceTexture timestamp, latch time
        fun overlayTime(nowNs: Long): Double
        fun framesDriveDraws(nowNs: Long): Boolean
        companion object {
            const val FRESH_FRAME_NS = 100_000_000L
            const val MAX_LEAD_NS = 150_000_000L
            const val LEAD_SMOOTHING = 0.2
            const val SAMPLE_EPSILON_SECONDS = 0.001
        }
    }
    ```
  The rules:
  - **Sampling.**
    - Not advancing: the sample is `seconds`, taken at `readNs`.
    - Advancing: a new sample is taken only when `seconds` moves by more than `SAMPLE_EPSILON_SECONDS`, or when the clock was not advancing before. This is `smoothedPosition`'s rule: over a photo the player holds one value for most of a second, so extrapolating from when it last *changed* is what keeps text moving.
    - `extrapolated(at)` is `sample + (at − sampleAt)/1e9` while advancing, and the sample otherwise.
  - **`overlayTime(now)`.**
    - Not advancing: the sample.
    - A fresh frame (latched within `FRESH_FRAME_NS`, with `|due − now| ≤ MAX_LEAD_NS`): `extrapolated(due)`, the picture's own instant.
    - Otherwise: `extrapolated(now) + lead`. The lead is the smoothed `due − latched` of frames latched while advancing, each clamped to `[0, MAX_LEAD_NS]`, and 0 before any.
  - **`framesDriveDraws(now)`** = advancing and a fresh frame. Each new video frame already asks for a draw, so a tick need not.

- [ ] **Step 1: Write the failing tests**

`OverlayClockTest`:
- `text redraws on every step inside its span`: a text at [1, 5]; previous 2.00, now 2.01 → true.
- `text outside its span asks nothing`: a text at [1, 5]; previous 6.0, now 6.1 → false.

`PictureClockTest`:
- `paused draws at the clock`: any frames; with `advancing` false, `overlayTime` equals `seconds` exactly.
- `over video it draws at the frame's own time`: `onClock(10.0, 1_000 ms, true)`, then `onVideoFrame(due 1_042 ms, latched 1_002 ms)`; `overlayTime(1_003 ms)` is 10.042 (±1e-9).
- `a due time out of reach is not the picture`: due = now + 1 s → `extrapolated(now) + lead`.
- `over a photo it runs on from the last change of the clock`: `onClock(5.0, 0, true)`, then `onClock(5.0, 200 ms, true)`; `overlayTime(400 ms)` is 5.4.
- `over a photo it adds the lead video taught it`: frames with 40 ms leads while advancing, then none fresh; `overlayTime` is `extrapolated(now) + 0.040` (±0.002).
- `frames latched while paused teach nothing`: a lead-0 frame while not advancing leaves the learned lead unchanged.
- `video frames drive the draws only while fresh and playing`:
  - fresh and advancing → true;
  - paused → false;
  - the last frame `FRESH_FRAME_NS` + 1 old → false.

- [ ] **Step 2: Run to see them fail**

Run: `./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.nativepreview.OverlayClockTest" --tests "com.techfamz.slimshotai.nativepreview.gl.PictureClockTest"`
Expected: FAIL. The text case returns false; `PictureClock` is unresolved.

- [ ] **Step 3: Implement the case and `PictureClock`.**

- [ ] **Step 4: Run to see them pass.** Expected: PASS, the existing `OverlayClockTest` cases included.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/OverlayClock.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/PictureClock.kt android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/OverlayClockTest.kt android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/gl/PictureClockTest.kt
git commit -m "feat(preview): overlays drawn at the picture's own time; live text redraws"
```

---

### Task 9: The engine draws preview text (Kotlin wiring)

**Files:**
- Modify: `android/.../nativepreview/gl/OverlayDrawBuilder.kt`, `android/.../nativepreview/gl/TransitionRenderer.kt`, `android/.../nativepreview/TimelinePlaybackEngine.kt`, `android/.../nativepreview/NativeTimelinePreviewManager.kt`

**Interfaces:**
- Consumes: `StillResidency` (Task 7) and `PictureClock` (Task 8).
- Produces:
  - `OverlayDrawBuilder.Events.onTextAtlasReady(id: String, path: String) {}` and `onTextAtlasGone(id: String, path: String) {}`, with default bodies, so the export's events compile unchanged.
  - `OverlayDrawBuilder.preloadTexts(t: Double): Boolean`.
  - `TransitionRenderer(..., onTextAtlas: (ready: Boolean, id: String, path: String) -> Unit = { _, _, _ -> })`.
  - `TransitionRenderer.setOverlayClock(seconds: Double, redraw: Boolean, readAtNs: Long, advancing: Boolean)`.
  - Engine events `{"type": "textReady" | "textGone", "overlayId": id, "path": path}`.

- [ ] **Step 1: The builder**
  - `textDraws`: right after a first upload, `events.onTextAtlasReady(overlay.id, overlay.path)`.
  - A text whose still is `Failed` in a realtime builder reports `onTextAtlasGone` once per path, kept in a set, and **not** `onOverlayFailed`: Flutter draws it, so nothing is toasted. The export's path is unchanged.
  - `preloadTexts(t)` (realtime only) walks `StillResidency.preloadOrder(overlays, t)` and skips paths already in `renderer.overlays.cachedImageTexture`:
    - `Ready`: upload, report ready, and return whether any later candidate is still not uploaded;
    - `Pending`: go on to the next candidate;
    - `Failed`: report gone (once), and go on.

    It uploads at most one atlas per call, and returns false when it uploaded none. A pending decode asks for its own draw when it lands, so nothing spins.

- [ ] **Step 2: The renderer**
  - `renderFrame`: call `updateLaneTextures()` **before** `buildPreviewOverlayDraws()`, so the overlays are timed by the frame just latched.
  - `updateLaneTextures`: on the clock's lane (`transition?.outgoingLane ?: activeLane`), when `surfaceTexture.timestamp` differs from that lane's last, call `pictureClock.onVideoFrame(timestamp, System.nanoTime())`.
  - `setOverlayClock(seconds, redraw, readAtNs, advancing)`: call `pictureClock.onClock(seconds, readAtNs, advancing)`, then request a render when `redraw && !pictureClock.framesDriveDraws(System.nanoTime())`.
  - `buildPreviewOverlayDraws`, on adopting a list, for each `StillResidency.released(adopted, list)`:
    - `overlays.releaseImageTexture(path)`;
    - `previewStillsReady.remove(path)?.recycle()`;
    - `previewStillsFailed.remove(path)`;
    - and, for a text, `onTextAtlas(false, id, path)`.

    The previous list is a GL-thread `adoptedPreviewOverlays`. Then the overlays are drawn at `pictureClock.overlayTime(System.nanoTime())`, used by `releaseExpired`, `drawsFor` and `preloadTexts`; a render is requested when `preloadTexts` returns true.
  - `previewStillSource`: a decode that lands for a path `previewOverlayList` no longer names recycles its bitmap instead of storing it.
  - `endExport`: after `overlays.releaseAll()`, `onTextAtlas(false, id, path)` for every `StillResidency.textsIn(previewOverlayList)`.
  - `previewOverlayEvents` forwards the builder's ready and gone events to `onTextAtlas`.

- [ ] **Step 3: The engine**
  - Pull out `private fun overlaysAdvancing(): Boolean`, the expression in `applyOverlayAudio` (scrubbing false; in the tail, `OverlayAudioSync.tailIsAdvancing`; otherwise playing and the master lane's player `isPlaying`). `applyOverlayAudio` then uses it: one rule for the sound and the picture.
  - `applyOverlays` passes `System.nanoTime()` and `overlaysAdvancing()` to `setOverlayClock`, after `tailActive` has been updated.

- [ ] **Step 4: The manager.** Construct the renderer with `onTextAtlas = { ready, id, path -> sendEvent(mapOf("type" to if (ready) "textReady" else "textGone", "overlayId" to id, "path" to path)) }`.

- [ ] **Step 5: Build and run the Kotlin suite**

Run: `flutter build apk --debug`, then (from `android/`) `./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.nativepreview.*"`
Expected: the build succeeds and every Kotlin test passes; the export's use of the builder is unchanged.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayDrawBuilder.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/TransitionRenderer.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/TimelinePlaybackEngine.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelinePreviewManager.kt
git commit -m "feat(preview-text): the engine draws, preloads and frees preview text atlases"
```

---

### Task 10: The editor wires it together

**Files:**
- Modify: `lib/screens/video_editor_screen.dart`
- Test: `test/features/video_editor/services/native_overlay_sync_test.dart` (extended)

**Interfaces:**
- Consumes: Tasks 2, 4, 5, 6 and 9.

- [ ] **Step 1: Write the failing test**
  - `text entries are pushed when they change, and only then`: with the existing harness, a `PreviewTextAtlases` whose payload changes once gives one `setOverlays` call per change, and none for a change that moves only the playhead.

- [ ] **Step 2: Run to see it fail**

Run: `flutter test test/features/video_editor/services/native_overlay_sync_test.dart`
Expected: FAIL.

- [ ] **Step 3: Wire the screen**
  - **Lifetime.** `_previewTexts = PreviewTextAtlases(rasterize: (t, canvas, scale) => TextOverlayRasterizer.rasterizeAtlas(overlay: t, canvasSize: canvas, rasterScale: scale), fontReady: FontRegistry.instance.isAvailable)` in `initState`, disposed in `dispose`.
  - **Updates.** In the state listener, before `_syncNativeOverlays`, and on `FontRegistry.instance.changes`, call `update`:
    - `texts: state.textOverlays`, `playhead: state.currentPlaybackPosition`;
    - `selectedTextId: state.selectedTextId`, `isPlaying: state.isPlaying`;
    - `canvasSize: ref.read(videoCanvasSizeProvider)`, `textureSize: state.projectCanvasSize`;
    - `engineAvailable: _canUseNativeTimelinePreview(state) && state.sourceVideo != null`.
  - **Sync.** `_syncNativeOverlays` sends `_previewTexts.payload` as `textEntries`, adds `identical(_previewTexts.payload, _syncedTextEntries)` to its early return, and also runs when the controller notifies.
  - **Events.** `_handleNativePreviewEvent`: `textReady` calls `engineReady(event.overlayId!, event.path!)`; `textGone` calls `engineGone(...)`.
  - **Canvases.** Both `VideoPreviewCanvas(...)` sites pass `engineDrawnTexts: _previewTexts.engineDrawn`.

- [ ] **Step 4: Run the whole suite and the analyzer**

Run: `flutter test`, then `flutter analyze --no-pub`
Expected: all pass; 43 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/video_editor_screen.dart test/features/video_editor/services/native_overlay_sync_test.dart
git commit -m "feat(preview-text): the editor hands its text to the engine"
```

---

### Task 11: Measure on the phone, then write it down

**Files:**
- Modify: `CLAUDE.md` (a section beside the native-preview overlays one), `docs/superpowers/specs/2026-10-31-preview-text-in-engine-design.md` (status line)

- [ ] **Step 1: Re-add the timing probes, uncommitted.** The 2026-10-31 set, plus one line per draw in `buildPreviewOverlayDraws`: `SlimTiming OVERLAY mono=<nanoTime/1000> time=<overlay time> due=<last clock-lane frame due/1000>`. The scratch analysis reports the frame's instant minus the overlay time (caption against picture), Flutter's frame intervals, and Flutter frames over 66 ms.

- [ ] **Step 2: Profile build on the Infinix.** The owner plays a captioned project for about 20 s, then restyles the set and plays at once.

Run: `flutter build apk --profile --dart-define-from-file=env/env.json`, then `adb install -r …`, capturing `adb logcat SlimTiming:I flutter:I '*:S'`.
Expected:
- caption against picture within ±17 ms, median and 1 in 10;
- the Flutter frame interval median at most 33 ms;
- no Flutter frame over 66 ms while the restyled atlases are prepared.

If that last one fails, rule a slower pace (only while paused, or one atlas per N frames) and measure again.

- [ ] **Step 3: Remove the probes** (`git checkout --` each probed file) and confirm `git status` lists none of them.

- [ ] **Step 4: Device checks with the owner**, the spec's list:
  - play from the start, after a seek, after a scrub;
  - restyle, then play at once; edit words, then play at once;
  - undo and redo a look change;
  - a project with 100+ captions;
  - a font still downloading;
  - the tail;
  - an export after all of it;
  - the keyboard opening on a caption;
  - editing as instant as before.

- [ ] **Step 5: CLAUDE.md.**
  - What draws text in the preview now, and who draws a text.
  - The two windows.
  - The canvas-free key.
  - The picture clock and why (the 42 ms measurement; the photo-clip hold).
  - The known follow-ups: effect bars still on the tick clock; a photo-only project's lead stays 0 until a video frame teaches one.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-10-31-preview-text-in-engine-design.md
git commit -m "docs: the preview's text is drawn by the engine"
```
