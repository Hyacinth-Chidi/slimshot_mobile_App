# Preview text drawn by the engine — captions on the frame

Date: 2026-10-31. Branch: `feat/preview-text-in-engine` (on top of `feat/push-notifications`;
both ship in 2.0.1, which is held for this).

## Why

The owner noticed captions in the preview landing a little after the words, while the exported
file is exact. Measured on the Infinix (Android 12) in a profile build, 12 s of caption playback,
with timing probes on one monotonic clock (engine send, Dart receive, each Flutter frame's
timings, each video frame's latch and hand-over):

| | median | 1 in 10 frames | worst |
|---|---|---|---|
| caption behind the picture shown in the same frame | 38 ms | 70 ms | 128 ms |
| caption behind the sound (frame on screen) | 50 ms | 108 ms | 184 ms |
| picture behind the sound | ~4 ms | 30 ms | — |
| engine report → Dart (the channel) | 1.9 ms | 3.4 ms | — |
| Flutter frame interval during playback | 33 ms | 50 ms | — |

The picture and the sound are in step; the captions are not. The channel is not the cause. The
cause is the split: the engine draws the picture, while **Flutter draws text on top of it**, at a
playhead read when a Flutter frame starts and shown one to two frames later. The editor screen
also manages only ~30 frames a second on this phone while captions play, partly because every
visible caption is repainted every frame with a blurred shadow per letter
(`TextOverlayPainter`). The export cannot drift: it bakes each text into the frames through the
engine (`OverlayDrawBuilder.textDraws` → `TextQuads`), from atlases made by
`TextOverlayRasterizer`.

The owner's words: they never want slow editing — "things reflect as user is editing and things
feel smooth" — and they asked whether this is how CapCut works or over-engineering. It is how
such editors draw text (inside the video renderer, with the app's UI drawing only the selection
chrome), and it is the last piece of this app's own direction: photos, video overlays and effects
already moved into the engine for the same reason.

## Goals

1. **During playback every text overlay and caption is drawn by the engine**, in the same GL
   frame as the picture, at that frame's own time — word highlights, per-letter animations,
   in/out animations and keyframed motion included. It is the export's own drawing
   (`OverlayDrawBuilder` in realtime mode already has the text path), so the preview and the file
   cannot differ.
2. **Editing is exactly as immediate as today.** The text being edited is drawn by Flutter while
   it is edited, exactly as now.
3. **No text is ever missing.** At every moment each visible text is drawn by the engine or by
   Flutter. Overlap at a hand-over is allowed for at most two frames; a gap is not.
4. **Playback gets lighter**: Flutter paints no text the engine is drawing.
5. **Bounded and smooth**: GPU memory for text stays within a budget whatever the number of
   captions, and preparing atlases never makes the UI stutter.

## Non-goals

- Text layout stays in Flutter (`TextOverlayLayout`, `paintTextOverlayInk`). Laying text out in
  Kotlin would drift from the canvas and the export (CLAUDE.md: reimplementing text layout in
  Android `Canvas` does not match).
- The export does not change.
- Effects over text ("Whole frame" effect bars) — made possible by this, not part of it.
- The style, template, animation and caption-style tiles keep the Flutter painter.
- The selection frame and handles stay Flutter widgets, unchanged.

## Anti-goals — failure even if it works

- Typing, styling, resizing, moving or pinching a text shows its change later than today.
- A text flickers, vanishes, or shows its previous look at a hand-over.
- A caption appears late when playback starts or after a seek because its atlas was not ready
  (Flutter must cover instead).
- The UI stutters while atlases are prepared — restyling a 100-caption set included.
- GPU memory grows with the number of captions or with every edit.
- Anything tuned to the Infinix. Budgets are in bytes and milliseconds and must hold on any phone.

## How it works

### Who draws a text — one rule

A pure Dart function decides, for each text overlay `T`:

- **Flutter draws `T`** when `T` is **selected and playback is paused** (it is being edited —
  every edit already pauses playback through `beginLiveEdit`), **or** when the engine has not
  reported `T`'s **current** atlas as on screen (not prepared yet, still loading, evicted, failed,
  or the native preview is unavailable for this project).
- **Otherwise the engine draws `T`**, and the text layer still lays `T` out — for taps, gestures
  and the selection frame — but paints nothing for it.

During playback the engine draws every text whose atlas is on screen, a selected one included,
so timing is exact while playing. The moment playback pauses, a selected text goes back to
Flutter for editing.

### Atlases for the preview (Dart)

- Made by the export's own `TextOverlayRasterizer.rasterizeAtlas`, at the **preview's** density
  (the preview texture's pixels per canvas pixel, never more than the export's), so a preview
  atlas costs a fraction of an export one. A text whose atlas cannot be made (over the 4096 px
  limit even at floor density, the rare case the export falls back to a flat raster for) stays
  drawn by Flutter.
- **Keyed by everything the atlas depends on** — the words, every `TextLook` field, Size, box
  width, the caption's words and highlight, the scale that sets its density, the canvas size, the
  preview density, and whether its font is registered yet — and by nothing else. Moving, turning,
  fading, retiming or animating a text needs no new atlas; changing how it looks does.
- **Prepared in the background, nearest the playhead first** (texts visible now, then those coming
  up in the direction of play), at most a few milliseconds of UI-thread work per frame, so a big
  restyle never stutters. The text being edited is prepared once its edit settles (the gesture
  ends, typing pauses, it is deselected, or play is pressed); until its atlas is on screen,
  Flutter keeps drawing it.
- Files in temp with the app's prefix (swept at launch like every temp file), deleted only once no
  text uses them **and** the engine's list no longer names them — a file the engine may still be
  loading is never pulled from under it.

### The engine (Kotlin)

- The preview's overlay list (`setOverlays`) carries a text as the export does — kind `text`, its
  glyph table, highlight and background cells — but only when Dart has an atlas for its current
  look **and** it is not being edited. The realtime `OverlayDrawBuilder` already draws such
  entries.
- **Reports readiness**: an event when a text's atlas texture is uploaded — from then on the engine
  draws that text whenever it is on screen (`id` + atlas path) — and one when it no longer can
  (evicted, removed from the list, or failed). Dart's rule reads these, which is what keeps a text
  from being drawn by nobody: Flutter stops drawing a text only after the engine says it has it,
  so a hand-over overlaps for a frame or two and never leaves a gap.
- **Frees textures it no longer needs.** Today the preview keeps every still texture it ever
  uploaded; with an atlas per edit that grows forever. Textures for paths no longer in the list
  are released, and text atlases are kept within a memory budget: those visible now and those
  starting soon are kept and loaded ahead of time while playing; the furthest away go first, and
  **a text on screen at the engine's clock is never evicted.**
- Respects the export hold (`exportOwnsRenderer`) exactly as overlays and effects already do.

### The text layer (Flutter)

For an engine-drawn text, `TextOverlayLayer` builds the same box, transforms and gesture
detector, with nothing painted in it. The selection frame, handles and the editor's behaviour are
untouched. The captions-from-Home screen and recording mode use the same layer and get the same
behaviour.

## Acceptance

- Re-measured with the same probe method, in a profile build on the Infinix: caption against
  picture within one frame (median and 1-in-10) during caption playback.
- The editor's frame interval during caption playback no worse than the 33 ms measured
  (expected better).
- Editing a text — typing, a style, Size, width, move, pinch, turn — shows each change in the same
  frame as today.
- Device checks: play a caption set from the start, after a seek, after a scrub; restyle a set
  with Caption style and play straight away; edit a caption's words and press play at once;
  undo/redo a look change; a project with 100+ captions; a text with a font still downloading;
  the tail past the last clip; an export after all of it (unchanged).

## Left to the plan

Exact memory budget and preload window, the per-frame time slice, the settle delay after an edit,
the event names, and file naming — each to be chosen against the goals above, with a test where
it carries a rule.

## Calls made without the owner (theirs to overrule)

- Flutter draws a text only while it is selected **and** paused; during playback the engine draws
  everything.
- A hand-over may overlap for up to two frames, never leave a gap.
- Preview atlases at the preview's resolution, not the export's.
- A text too large for an atlas stays drawn by Flutter (rare).
