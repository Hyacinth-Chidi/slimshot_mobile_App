# Effect Tile Previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every tile in the Effects sheet plays its effect, drawn by the engine on the sample picture, within a fixed memory budget and without racing or stalling the live canvas.

**Architecture:** Dart builds each effect's sample bar (the exact bar `addEffectBar` makes) and asks the engine for one JPEG atlas of 25 frames. Kotlin draws it as a sliced job on the GL thread through `EffectStack.drawnAt` and the effect's own passes, then encodes off the GL thread. The answer is atlas, failed or busy, and is given exactly once. A session cache holds the bytes, one drawing at a time, with tickets that can be withdrawn. Each tile decodes and owns its own `ui.Image` and paints one cell per frame of a shared clock.

**Tech Stack:** Flutter/Dart (Riverpod, `dart:ui`), Kotlin (GLES 2.0, `Handler`), MethodChannel `slimshot_ai/native_timeline_preview`.

**Spec:** `docs/superpowers/specs/2026-10-21-effect-tile-previews-design.md`

## Global Constraints

- Atlas: cell **160 × 144**, **5 columns**, **25 frames** (frame 0 plain, frames 1–24 the bar), **15 fps**, so 800 × 720.
- Loop: **0.4 s** on frame 0, then frames 1–24 at 15 fps; loop **2.0 s**. Frame `k ≥ 1` shows the bar at `t = (k − 1) / 15` s.
- Sample bar: start 0, end `kDefaultEffectBarSeconds` (3.0), the catalog's `defaultIntensity` + `defaultEnvelope`, the catalog's `introSeconds`.
- At most **4 cells per GL turn**. The JPEG encode never runs on the GL thread.
- Answers: atlas → `success(bytes)`; failed → `success(null)`; busy → `error("busy")`. Dart remembers failed, never busy.
- Dart drawing timeout **10 s**, counted as busy. One drawing at a time.
- Grid `cacheExtent: 0`. Decoded atlases are never put in Flutter's `ImageCache`.
- Encoded atlas ≤ 150 KB (measured on the device; tune JPEG quality if over).
- No new dependencies and no assets. Colours from `AppColors` (`panel_theme_test.dart`).
- Before every commit: `flutter analyze --no-pub` stays at **44** issues; the full `flutter test` and `cd android && ./gradlew.bat :app:testDebugUnitTest` both pass.
- Commits via `git commit -F <file>`, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.

## Review Focus

1. **The sheet closed while a category is still drawing.** Remaining asks are dropped, nothing draws for nobody, and no image outlives its tile. Tests: Task 2 (`withdrawn asks are dropped`), Task 5 (`dispose withdraws the ticket`).
2. **The editor closed (renderer released) mid-job.** The Dart future still completes, as busy, and no GL call follows the release. Tests: Task 3 (`abandon mid-job answers busy and touches nothing`), Task 4 (`busy maps to EffectPreviewBusy`).
3. **Category tabs switched back and forth quickly.** No decode leaks, and no duplicate drawing for one effect. Tests: Task 2 (`a second ask shares the first`), Task 5 (`a decode landing after dispose disposes its image`).
4. **Memory pressure while the sheet is open.** The bytes are dropped, and tiles on screen keep painting from their own image. Tests: Task 2 (`clear drops bytes, keeps failures`), Task 5 (`a tile keeps painting after the cache is cleared`).
5. **An effect id the engine does not know** (a catalog newer than the engine). It answers failed, the tile keeps its icon, and it is not asked again. Tests: Task 3 (`parse rejects an effect with no pass cost`), Task 2 (`failed is remembered`).

---

### Task 1: The atlas layout and the sample bar (Dart, pure)

**Files:**
- Create: `lib/features/video_editor/logic/effects/effect_preview_layout.dart`
- Modify: `lib/features/video_editor/logic/effects/effect_bar_placement.dart` (add `freshEffectIntensity`), `lib/features/video_editor/providers/video_editor_notifier.dart` (replace the private `_freshIntensity` with it)
- Test: `test/features/video_editor/logic/effects/effect_preview_layout_test.dart`

**Interfaces:**
- Produces:
  - `const int kEffectPreviewCellWidth = 160, kEffectPreviewCellHeight = 144, kEffectPreviewColumns = 5, kEffectPreviewFrames = 25, kEffectPreviewFps = 15;`
  - `const double kEffectPreviewLeadSeconds = 0.4; const Duration kEffectPreviewLoop = Duration(milliseconds: 2000);`
  - `int effectPreviewFrameAt(double phase)`, where `phase` is the clock's 0..1.
  - `Rect effectPreviewCellRect(int frame)`: the cell in atlas pixels, inset by 1 px on each side.
  - `AnimatableDouble freshEffectIntensity(VideoEffect effect)` in `effect_bar_placement.dart`.
  - `EditorTimelineEffect effectPreviewSampleBar(VideoEffect effect)`.

- [ ] **Step 1: Write the failing tests** in `effect_preview_layout_test.dart`:
  - `the plain beat`: `effectPreviewFrameAt(0.0) == 0`; `effectPreviewFrameAt(0.19) == 0` (0.38 s).
  - `frames advance at 15 fps after the beat`: `effectPreviewFrameAt(0.2) == 1`; `effectPreviewFrameAt((0.4 + 1/15 + 0.001) / 2.0) == 2`.
  - `the loop ends on the last frame and wraps to plain`: `effectPreviewFrameAt(0.999) == 24`; `effectPreviewFrameAt(1.0) == 24`.
  - `cells are row-major and inset`: `effectPreviewCellRect(0) == Rect.fromLTRB(1, 1, 159, 143)`; `effectPreviewCellRect(6) == Rect.fromLTRB(161, 145, 319, 287)`; `effectPreviewCellRect(24).right == 799` and `.bottom == 719`.
  - `cells sit on JPEG block boundaries`: `kEffectPreviewCellWidth % 16 == 0` and `kEffectPreviewCellHeight % 16 == 0`; `kEffectPreviewFrames <= kEffectPreviewColumns * 5`.
  - `the sample bar is the bar addEffectBar makes`: for every `videoEffects` entry, build a project, call `notifier.addEffectBar(e.id)` at playhead 0 on a clip of 10 s, compose with `composeEffects`, and expect `effectPreviewSampleBar(e).toJson()` to equal that bar's JSON with `id`, `start`, `end` and `lane` replaced by `'preview_<id>'`, 0, `kDefaultEffectBarSeconds` and 0.

- [ ] **Step 2: Run** `flutter test test/features/video_editor/logic/effects/effect_preview_layout_test.dart`. Expected: FAIL to compile (`effect_preview_layout.dart` missing).

- [ ] **Step 3: Implement.**
  - `effectPreviewFrameAt`: `seconds = phase × 2.0`; under 0.4 → 0; else `1 + ((seconds − 0.4) × 15).floor()`, clamped to 1..24.
  - `effectPreviewCellRect`: column `frame % 5`, row `frame ~/ 5`, deflated by 1.
  - `freshEffectIntensity` returns `AnimatableDouble(baseValue: defaultIntensity, envelope: defaultEnvelope)`. The notifier's `addEffectBar` and `setEffectBarEffect` call it, and `_freshIntensity` is deleted.
  - `effectPreviewSampleBar` builds `EditorTimelineEffect(id: 'preview_${e.id}', effectId: e.id, start: 0, end: kDefaultEffectBarSeconds, lane: 0, intensity: freshEffectIntensity(e), introSeconds: e.introSeconds)`.

- [ ] **Step 4: Run** the test file, then the effect bar command tests (`flutter test test/features/video_editor/providers/effect_bar_commands_test.dart`). Expected: PASS.

- [ ] **Step 5: Commit** `feat(effects): the preview atlas layout and its sample bar`.

### Task 2: The session cache of atlases (Dart)

**Files:**
- Create: `lib/features/video_editor/logic/effects/effect_preview_atlases.dart`, `lib/features/video_editor/providers/effect_preview_provider.dart`
- Test: `test/features/video_editor/logic/effects/effect_preview_atlases_test.dart`

**Interfaces:**
- Consumes: `effectPreviewSampleBar` (Task 1), `videoEffectById`.
- Produces:
  - `sealed class EffectPreviewResult` with `final class EffectPreviewAtlas(Uint8List bytes)`, `final class EffectPreviewFailed`, `final class EffectPreviewBusy` (const constructors).
  - `typedef EffectPreviewRenderer = Future<EffectPreviewResult> Function(EditorTimelineEffect bar);`
  - `class EffectPreviewAtlases`:
    - `EffectPreviewAtlases(EffectPreviewRenderer render, {Duration timeout = const Duration(seconds: 10)})`
    - `Uint8List? peek(String effectId)`
    - `bool hasFailed(String effectId)`
    - `EffectPreviewTicket request(String effectId)`
    - `void clear()`
  - `class EffectPreviewTicket { Future<Uint8List?> get atlas; void withdraw(); }`
  - `final effectPreviewAtlasesProvider = Provider<EffectPreviewAtlases>(...)`, not autoDispose. It registers a `WidgetsBindingObserver` whose `didHaveMemoryPressure` calls `clear()`, and removes it in `ref.onDispose`. The renderer is `NativeTimelinePreviewService().renderEffectPreview` (Task 4). Until Task 4, the provider passes a renderer that answers `EffectPreviewBusy`.

- [ ] **Step 1: Write the failing tests** with a fake renderer (a map of effect id → `Completer<EffectPreviewResult>`, recording call order):
  - `one drawing at a time`: request `vignette` and `grain`; only `vignette` has been rendered; complete it; then `grain` is rendered.
  - `a second ask shares the first`: two requests for `vignette` → one render call; both tickets complete with the same bytes.
  - `atlas is kept`: after completion, `peek('vignette')` returns the bytes; a later request completes without rendering.
  - `failed is remembered`: `EffectPreviewFailed` → the ticket completes null, `hasFailed` is true, and a later request completes null with no render call.
  - `busy is not remembered`: `EffectPreviewBusy` → the ticket completes null and `hasFailed` is false; a later request renders again.
  - `a timeout counts as busy`: inside `fakeAsync`, a render that never completes yields null after 10 s; `hasFailed` is false; the next queued ask starts.
  - `withdrawn asks are dropped`: request `vignette` (running) and `grain` (queued); withdraw `grain`'s only ticket; complete `vignette`; `grain` is never rendered.
  - `a withdrawn ask still kept by another ticket is drawn`: two tickets for `grain`, withdraw one → `grain` is rendered.
  - `an unknown effect fails without rendering`: `request('from_the_future')` completes null, with no render call and `hasFailed` true.
  - `clear drops bytes, keeps failures`: after an atlas and a failure, `clear()` → `peek` is null and `hasFailed` is still true.
  - `a renderer that throws counts as busy`.

- [ ] **Step 2: Run** `flutter test test/features/video_editor/logic/effects/effect_preview_atlases_test.dart`. Expected: FAIL to compile.

- [ ] **Step 3: Implement.** The queue is a list of pending ids plus a running flag, not a chain of futures, so a withdrawn id can be removed. Each id's tickets share one `Completer<Uint8List?>`. `_pump()` takes the first pending id that still has live tickets. A drawing is `render(bar).timeout(timeout, onTimeout: () => const EffectPreviewBusy())`, guarded by try/catch → busy. A late answer after a timeout is ignored.

- [ ] **Step 4: Run** the test file. Expected: PASS.

- [ ] **Step 5: Commit** `feat(effects): a session cache of effect preview atlases`.

### Task 3: The drawing job and its request (Kotlin, pure)

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/effects/EffectPreviewSpec.kt`, `.../gl/effects/EffectPreviewJob.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/EffectPreviewSpecTest.kt`, `.../EffectPreviewJobTest.kt`

**Interfaces:**
- Consumes: `NativeTimelineEffect.fromMap`, `EffectPassCosts.costOf`.
- Produces:
  - `internal sealed class EffectPreviewAnswer { class Atlas(val jpeg: ByteArray); object Failed; object Busy }`
  - `internal data class EffectPreviewSpec(cellWidth: Int, cellHeight: Int, columns: Int, frameCount: Int, fps: Int)`:
    - `rows`, `atlasWidth`, `atlasHeight`
    - `fun frameSeconds(index: Int): Double?` (null for frame 0; `(index − 1) / fps` otherwise)
    - `fun cellViewport(index: Int): IntArray` (`[x, y, w, h]` in bottom-up GL coordinates, row flipped)
    - `fun slices(): List<IntRange>` (at most `MAX_CELLS_PER_SLICE` = 4 cells each)
    - `companion fun fromArgs(cellWidth: Number?, cellHeight: Number?, columns: Number?, frames: Number?, fps: Number?): EffectPreviewSpec?` (null unless cells are positive multiples of 16 ≤ 512, frames 2..64, columns 1..frames, fps 1..60, atlas ≤ 4096 per side)
  - `internal data class EffectPreviewRequest(val bar: NativeTimelineEffect, val spec: EffectPreviewSpec)` with `companion fun parse(effect: Any?, spec: EffectPreviewSpec?): EffectPreviewRequest?` (null for a malformed map, a null spec, or `EffectPassCosts.costOf(bar.effectId) == 0`)
  - `internal enum class PreviewHost { READY, EXPORTING, RELEASED }`
  - `internal interface EffectPreviewCanvas { fun makeCurrent(): Boolean; fun setUp(): Boolean; fun drawCell(index: Int, seconds: Double?); fun readBack(): java.nio.ByteBuffer; fun tearDown() }`
  - `internal class EffectPreviewJob(spec, canvas, host: () -> PreviewHost, post: (Runnable) -> Boolean, encode: (java.nio.ByteBuffer, (ByteArray?) -> Unit) -> Unit, onDone: (EffectPreviewAnswer) -> Unit)` with `fun start()`, `fun abandon()` and `val isDone: Boolean`. `onDone` is guarded by an `AtomicBoolean`; `abandon()` is safe from any thread.

- [ ] **Step 1: Write the failing tests.**
  - `EffectPreviewSpecTest`:
    - `the default spec lays out 5 by 5`: `atlasWidth == 800`, `atlasHeight == 720`.
    - `frame 0 is plain, then 15 fps`: `frameSeconds(0) == null`, `frameSeconds(1) == 0.0`, `frameSeconds(24) == 23.0 / 15`.
    - `GL rows are flipped`: `cellViewport(0)` is `[0, 576, 160, 144]` and `cellViewport(24)` is `[640, 0, 160, 144]`.
    - `slices cover every cell, at most 4`: union equals `0..24`, in order, each slice size ≤ 4.
    - `fromArgs rejects a cell not on a 16 px boundary`, `zero frames`, and `an atlas over 4096`.
    - `parse rejects an effect with no pass cost`: an `effectId` of `from_the_future` → null; `vignette` → non-null.
  - `EffectPreviewJobTest`, with a fake canvas recording calls and an inline `post` that queues runnables the test runs one by one:
    - `a normal run draws every cell once, reads back once, tears down once, answers an atlas`.
    - `no slice draws more than 4 cells`.
    - `setUp refused → torn down, Failed`.
    - `a cell that throws → torn down, Failed`.
    - `encode giving null → Failed`.
    - `exporting at a slice → torn down, Busy`.
    - `released at a slice → Busy, and that slice makes no canvas call`.
    - `makeCurrent refused → Busy, no tearDown`.
    - `every slice makes the context current before drawing`: in the recorded calls, each slice opens with `makeCurrent`, since an export may have run between two slices and left its encoder surface current.
    - `a refused post mid-job → torn down, Busy`.
    - `a refused first post → Busy, no canvas call`.
    - `abandon mid-job answers busy and touches nothing`: after `abandon()`, the remaining queued slices make no canvas call.
    - `answered exactly once`: in every scenario above, `onDone` ran once; `abandon()` after an atlas changes nothing.

- [ ] **Step 2: Run** `cd android && ./gradlew.bat :app:testDebugUnitTest --tests "*EffectPreview*"`. Expected: FAIL to compile.

- [ ] **Step 3: Implement** both files. Every slice checks `host()` before any canvas call, then calls `makeCurrent`. Slice 0 then calls `setUp` before drawing its cells. After the last slice: `readBack` → `tearDown` → `encode` → answer. Every failure path that still holds a usable context calls `tearDown` exactly once.

- [ ] **Step 4: Run** the same command. Expected: PASS.

- [ ] **Step 5: Commit** `feat(effects): the sliced effect preview job, answered once`.

### Task 4: The engine draws an atlas, and Dart asks for one

**Files:**
- Modify:
  - `.../nativepreview/gl/TransitionPreviewSamples.kt` (add `fun still(width: Int, height: Int): Bitmap`, the sunset)
  - `.../nativepreview/gl/TransitionRenderer.kt`:
    - `fun renderEffectPreview(request: EffectPreviewRequest, onDone: (EffectPreviewAnswer) -> Unit)`
    - a private `GlEffectPreviewCanvas`
    - a live-job set abandoned in `release()`
    - a lazily created single-thread encoder shut down in `release()`
  - `.../nativepreview/NativeTimelinePreviewManager.kt` (`"renderEffectPreview"` handler)
  - `lib/features/video_editor/services/native_timeline_preview_service.dart` (`Future<EffectPreviewResult> renderEffectPreview(EditorTimelineEffect bar)`)
  - `effect_preview_provider.dart` (use it)
- Test: `test/features/video_editor/services/native_timeline_preview_effect_tiles_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: the channel method `renderEffectPreview` with arguments `{effect: bar.toJson(), cellWidth: 160, cellHeight: 144, columns: 5, frames: 25, fps: 15}`.
  - Manager: `EffectPreviewRequest.parse(effect, EffectPreviewSpec.fromArgs(...))`. Null → `success(null)`. No renderer → `error("busy", …)`. Otherwise answers on the main handler: Atlas → `success(jpeg)`, Failed → `success(null)`, Busy → `error("busy", …)`.
  - Renderer: `host()` is `RELEASED` when `released`, `EXPORTING` when `exportSurface != null`, else `READY`. `post` is `handler.post`.
  - `GlEffectPreviewCanvas`:
    - `setUp` creates the sample texture (`TransitionPreviewSamples.still(cellW, cellH)`, uploaded and recycled), the atlas target, a private `EffectPassChain` (log-only `onWarning`) resized to the cell, and `EffectShaders.passesFor(effectId)`. It returns false when any of those fails.
    - `drawCell` disables blend. With `seconds == null` it presents the sample. Otherwise it applies `EffectStack.drawnAt(listOf(bar), seconds)` intensity and progress to the passes and runs the chain. Then it binds the atlas, sets the cell viewport, and calls `presentTexture`.
    - `readBack` calls `glReadPixels` on the atlas.
    - `tearDown` releases the passes, the chain, the target and the texture, binds framebuffer 0 and calls `requestRender()`.
  - Encode: `Bitmap` from the buffer, flipped once, JPEG at `PREVIEW_JPEG_QUALITY`.

- [ ] **Step 1: Write the failing Dart test** with a mock method channel:
  - `bytes map to EffectPreviewAtlas`.
  - `null maps to EffectPreviewFailed`.
  - `busy maps to EffectPreviewBusy`: a `PlatformException(code: 'busy')`.
  - `another PlatformException maps to EffectPreviewFailed`.
  - `MissingPluginException maps to EffectPreviewBusy`.
  - `the request carries the sample bar and the atlas spec`: the arguments equal `{effect: effectPreviewSampleBar(vignette).toJson(), cellWidth: 160, cellHeight: 144, columns: 5, frames: 25, fps: 15}`.

- [ ] **Step 2: Run** `flutter test test/features/video_editor/services/native_timeline_preview_effect_tiles_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** the Dart service method, then the Kotlin pieces above. Point the provider at the service. The GL half has no JVM test; its rules live in the Task 3 job and are exercised there.

- [ ] **Step 4: Run** the Dart file, `cd android && ./gradlew.bat :app:compileDebugKotlin`, and the full Kotlin suite. Expected: PASS, BUILD SUCCESSFUL.

- [ ] **Step 5: Commit** `feat(effects): the engine draws an effect's preview atlas`.

### Task 5: The tile's stage — decode, own, paint (Dart)

**Files:**
- Create: `lib/features/video_editor/widgets/panels/effect_preview_stage.dart`
- Test: `test/features/video_editor/widgets/effect_preview_stage_test.dart`

**Interfaces:**
- Consumes: `EffectPreviewAtlases`, `EffectPreviewTicket` (Task 2), `effectPreviewCellRect` (Task 1).
- Produces:
  - `typedef EffectAtlasDecoder = Future<ui.Image> Function(Uint8List bytes);`
  - `Future<ui.Image> decodeEffectAtlas(Uint8List bytes)`: `ui.instantiateImageCodec` → `getNextFrame` → codec disposed.
  - `class EffectPreviewStage extends StatefulWidget` with `{required String effectId, required IconData icon, required bool isSelected, required EffectPreviewAtlases atlases, required ValueListenable<int> frameIndex, EffectAtlasDecoder decode = decodeEffectAtlas}`.
  - `class EffectPreviewPainter extends CustomPainter` with `(ui.Image image, ValueListenable<int> frameIndex)`. It passes `super(repaint: frameIndex)` and draws `effectPreviewCellRect(frameIndex.value)` cover-fitted with `FilterQuality.low`. `shouldRepaint` compares the image.

- [ ] **Step 1: Write the failing tests.** Images come from `PictureRecorder` → `toImage(800, 720)` inside `tester.runAsync`. Disposal is checked with `ui.Image.debugDisposed`. The decoder is a fake returning a `Completer` per call.
  - `the icon shows while there is no atlas`.
  - `the icon shows for a failed effect`.
  - `the stage is empty, not the icon, while cached bytes decode`.
  - `a decoded atlas paints through EffectPreviewPainter, repainting on the frame index`: the painter's `repaint` is identical to `frameIndex`.
  - `a decode landing after dispose disposes its image`.
  - `a decode for a replaced effect disposes the stale image`: rebuild with another `effectId`; the first decode lands afterwards and is disposed.
  - `dispose disposes the painted image`.
  - `dispose withdraws the ticket`: with a fake renderer, an unstarted ask for this tile's effect is never rendered after the tile is removed.
  - `a tile keeps painting after the cache is cleared`: `atlases.clear()` after the decode; the painter is still present and its image is not disposed.

- [ ] **Step 2: Run** `flutter test test/features/video_editor/widgets/effect_preview_stage_test.dart`. Expected: FAIL to compile.

- [ ] **Step 3: Implement.** A generation counter is bumped on dispose and on an `effectId` change. Every async continuation checks `mounted` and the generation, and disposes any image it no longer wants. The stage's background is `AppColors.previewStage`, and the icon colour follows the transition tile's.

- [ ] **Step 4: Run** the test file. Expected: PASS.

- [ ] **Step 5: Commit** `feat(effects): an effect tile's stage owns and paints its atlas`.

### Task 6: The sheet plays its tiles; notes

**Files:**
- Modify:
  - `lib/features/video_editor/widgets/panels/effects_panel.dart`:
    - `_EffectsPanelState` gets `TickerProviderStateMixin`, a 2.0 s repeating clock, and a `ValueNotifier<int>` frame index set from the clock only when it changes; both are disposed.
    - The grid gets `cacheExtent: 0`, inside `NotificationListener<ScrollNotification>` → `holdPreviewClockWhileScrolling`.
    - `EffectTile` gains a required `Widget stage` that replaces its centred icon, laid out like the transition tile.
    - The panel's doc comment is rewritten.
  - `CLAUDE.md` (an "Effect tile previews" paragraph in the effects track section, and the two transition-tile exposures under "Known broken / not yet done")
  - `docs/roadmap.md` (Stage 6 item 16's line gains the tiles)
  - the spec's status line
- Test: `test/features/video_editor/widgets/effects_panel_test.dart` (extend)

**Interfaces:**
- Consumes: `EffectPreviewStage` (Task 5), `effectPreviewAtlasesProvider` (Task 2, overridden in tests with a fake renderer), `effectPreviewFrameAt` / `kEffectPreviewLoop` (Task 1).

- [ ] **Step 1: Write the failing tests** (extend `effects_panel_test.dart`; keep the existing tests green):
  - `every tile has a stage for its effect`: the count of `EffectPreviewStage` equals `effectsInCategory(first).length`, and each `effectId` matches its tile.
  - `the grid keeps no tiles off screen`: the `GridView`'s `cacheExtent` is 0.
  - `the frame index follows the clock`: it is 0 at first; after pumping 0.5 s it is ≥ 1.
  - `the clock holds still while the grid scrolls`: the frame index is unchanged across 300 ms of pumps during a held drag of the grid.
  - `switching category disposes the old tiles' images`: open Intro, let one decode, switch to Colour; that image is disposed (fake decoder images, `debugDisposed`).
  - `closing the sheet disposes every image`.

- [ ] **Step 2: Run** `flutter test test/features/video_editor/widgets/effects_panel_test.dart`. Expected: the new tests FAIL.

- [ ] **Step 3: Implement** the panel changes, then the notes (device-only checks listed in CLAUDE.md: tiles look right; the canvas does not stutter while tiles draw during playback; memory in the profiler stays ≤ ~28 MB decoded while browsing every category and falls when the sheet closes; atlas JPEGs measured ≤ 150 KB; an export after browsing is unaffected).

- [ ] **Step 4: Run** the test file, then the full `flutter test`, `flutter analyze --no-pub` (44) and the full Kotlin suite. Expected: all pass.

- [ ] **Step 5: Commit** `feat(effects): the Effects sheet plays its tiles`.
