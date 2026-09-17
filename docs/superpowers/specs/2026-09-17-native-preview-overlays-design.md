# Native preview overlays — one renderer for the picture

**Status:** design, not started.
**Supersedes:** the "Video overlays still play through a Flutter player in the *preview*" entry in
CLAUDE.md's Known broken list, which this closes.

## The problem, stated once

Photo and video overlays are drawn **twice, by two different implementations**: in the export by
`gl/OverlayRenderer.kt`, and in the preview by two Flutter widget layers
(`image_overlay/image_overlay_layer.dart`, `video_overlay/video_overlay_layer.dart`). That is the
last place in the app where preview and export use different code to draw the same thing, and it
is the direct cause of every overlay limitation we have hit:

- **Feather is approximate.** The overlay mask clips the widget to a hard-edged path because a
  widget has no shader; the export ramps over the feather. Documented as the accepted gap in the
  overlay mask section, and it only exists because of the split.
- **A chroma key on an overlay is impossible.** A key is a per-pixel colour decision. The widget
  layer cannot make it, so a key would drop the green in the file and leave it on the canvas —
  the mismatch this pipeline is built to avoid. This is why the overlay key was deliberately not
  built.
- **Blend modes are impossible** for the same reason.
- **The drift machinery exists at all.** `VideoPlayerController.value.position` is polled roughly
  twice a second, so `_syncPlayback` had to grow extrapolation, strike counting and a cooldown to
  stop a seek storm that was measuring the poll interval rather than real divergence. None of it
  would exist if the overlay read the engine's own clock.

## What is already built

This is the reason the change is worth doing now rather than later. The native half is **not**
speculative:

- `gl/OverlayRenderer.kt` draws overlays with transform, rotation, opacity, premultiplied
  blending, glyph-atlas text and now masking. Device-verified through export.
- It **already lives on the preview renderer** (`TransitionRenderer.overlays`). The only thing
  stopping the preview drawing overlays is that `drawExportFrame` calls `overlays.draw(...)` and
  `composite()` does not.
- `NativeTimelineOverlay.kt` parses the wire format and evaluates the in/out/loop animations per
  frame (`stateAt`), on whatever clock it is given.
- `NativeTimelinePreviewManager` **already parses overlays on every `setTimeline`**
  (`NativeTimelineOverlays.fromTimeline`) and hands them to the export request. The preview engine
  simply never receives them.

What is missing is the bridge, and one structural problem: the per-frame builder that turns
overlays into draws is `VideoExportEngine.OverlayPass`, a **private inner class**, so the preview
cannot reach it.

## Design

### 1. Lift `OverlayPass` out of the export engine

It becomes its own file, `nativepreview/gl/OverlayDrawBuilder.kt` (name chosen so it sits beside
the renderer it feeds, not inside either engine). Its real dependencies are small and both engines
have them:

| Dependency | Export today | Preview |
| :--- | :--- | :--- |
| the overlay list | `Request.overlays` | already parsed by the manager |
| a renderer | `renderer` | the same `TransitionRenderer` |
| a clock, in timeline seconds | the export clock | `timelinePositionSeconds()` |
| a decoder factory | `ExportClipDecoder` | the same class |
| a failure counter | `VideoDiagnostics` | a warning callback |

**`VideoDiagnostics` does not move.** It is export bookkeeping. The builder takes an
`onOverlayFailed: (String) -> Unit` instead, which export wires to its counter and the preview
wires to the existing `onWarning` channel — so a preview overlay that cannot decode says so, the
same way a failed transition lane does.

Everything else — `releaseExpired` at the top of each frame, `MAX_OVERLAY_DECODERS`, the
skip-with-a-warning past the cap, the text/image/video branch, the `restingState` rule for
animating text — moves **verbatim**. This is a lift, not a rewrite. The export's behaviour must be
byte-identical after it; that is the first stage's gate.

### 2. The preview engine drives it

`TimelinePlaybackEngine` gains an overlay list (set by the manager alongside the clip list) and
calls the builder each tick, exactly where it already calls `applyLaneFits` and friends. The draws
go to the renderer, which draws them in `composite` **after** the effect chain, matching export —
that is what keeps a sticker on a blurred clip sharp.

**The export hold still applies.** `exportOwnsRenderer` already makes `tick()` return during an
export, so there is no second writer; overlays inherit that for free.

### 3. `composite` draws overlays

The `overlays.draw(...)` call moves from `drawExportFrame` into `composite`, which both paths run.
The list is a field the engine sets per tick and export sets per output frame, so **one call site
serves both** and the draw cannot diverge again.

### 4. Delete the Flutter layers

Once the native path is verified on device: delete `image_overlay_layer.dart`'s and
`video_overlay_layer.dart`'s **drawing**, the `video_player` controllers, and the whole drift
apparatus. The `video_player` dependency goes with them if nothing else uses it.

**The gesture layer stays in Flutter, and this is the part that needs care.** The selection frame,
the corner dots, the rotate/scale handle and the floating action bar are all widgets, and they
must keep lining up with a picture now drawn by GL. They already position themselves from the same
geometry the composer converts (`position`, `scale`, `rotation`, the fixed 200/240 boxes), so the
arithmetic is shared — but it is the one place a one-frame disagreement would show as handles
sliding against their overlay. The body becomes a transparent hit-target of the same size: it
catches the finger, GL draws the picture.

## Staging, each gated on a device run

The order is chosen so that nothing is deleted before its replacement is proven, and so a failure
at any stage leaves a working app.

**Stage 1 — the lift.** Extract `OverlayDrawBuilder`, export uses it, nothing else changes.
*Gate:* an export with photo, video and text overlays is identical to before. No preview change,
so nothing can regress there.

**Stage 2 — photo overlays in the preview.** Engine holds the list, calls the builder, `composite`
draws. The Flutter image layer keeps its handles but **stops drawing the image**.
*Gate:* a photo overlay appears, animates and masks identically to the export; handles still line
up while dragging, scaling and rotating.

**Stage 3 — video overlays in the preview.** The same, plus decoders under the existing cap.
*Gate:* one video overlay plays in step with the clip under it. Then **two at once**, then a video
overlay over a clip that also has a transition — the codec-pressure cases. A device at its codec
limit must warn and degrade, never stall.

**Stage 4 — deletions.** Remove the drawing, the controllers, the drift machinery, and
`video_player` if unused.
*Gate:* the full matrix again, plus scrubbing and pause/resume, which is where a decoder lifecycle
bug would show.

**Stage 5 — what this unlocks.** The overlay chroma key, and blend modes. Each its own work, and
each now a shader line rather than an impossibility.

## Risks, and what each costs if wrong

| Risk | Why it is real | Mitigation |
| :--- | :--- | :--- |
| Codec pressure with several video overlays | Preview already runs two clip lanes; overlays add more, on a device that may be near its limit | `MAX_OVERLAY_DECODERS` moves with the builder; the preview enforces it and warns past it, exactly as export does |
| Handles drift from the picture | Two renderers, one frame apart | Both read the same composer geometry; stage 2 gates on it specifically, with the image still small and static enough to see a one-pixel slip |
| A decoder left open on scrub or pause | The export clock only ever moves forward; the preview scrubs backwards | `releaseExpired` is window-based, not direction-based, so it already handles a backwards playhead; stage 4 gates on scrubbing |
| The lift changes export behaviour | It is the app's most important operation | Stage 1 changes nothing else and is gated on an identical export before anything else proceeds |

## What this is not

- **Not** replacing ExoPlayer for clip playback. That is the separate, larger question in the
  preview-audio note, and it is not required for any of this.
- **Not** a change to the overlay *model*, the composer, or the wire format. Every stage consumes
  what `setTimeline` already sends.
- **Not** a fix for preview audio. A video overlay's sound keeps its current path in this work;
  moving it belongs with the audio-mix change.

## Expected outcome

Correctness: preview and export draw overlays with one implementation, so feather is exact, a
chroma key becomes possible, and the last preview/export gap in the picture closes.

Performance: the overlay widget rebuild at ~30Hz disappears, several compositing layers collapse
into one frame, and a video overlay costs one decoder rather than a decoder plus a player plus a
texture. The GL thread does modestly more work — a few textured quads on a thread already drawing
— in exchange for work leaving the UI thread. That is the right direction for how the app feels.
