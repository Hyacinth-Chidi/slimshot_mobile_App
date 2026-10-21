# Effect tile previews — design

**Date:** 2026-10-21 · **Branch:** `effect-tile-previews` (off `effects-track`) · **Status:** awaiting the owner's review

Marked **(owner)** where the owner decided, **(my call)** where I decided and the owner has not
yet ruled, and **(builder's call)** where the detail is left to whoever implements it.

## Intent

The Effects sheet shows 39 tiles that are an icon and a name. Neither says what an effect looks
like: "Dreamy", "Roulette" and "Grid Collage" give no idea, and **20 of the 39 are intros or
reveals whose whole point is motion**. Finding out by tapping is poor. A tap adds a bar at the
paused playhead, so the canvas shows only the effect's first instant: a fade-in shows black and a
reveal shows its starting frame. Every tap also takes an undo step.

So each tile plays its effect, the way the transition tiles play theirs. **(owner: "go ahead")**

**"Do it perfectly, so it will not cause memory issues or race conditions" (owner).** That is
the bar this design is held to, and most of it is about lifecycles. The look is the easy half.

## Goals

1. Each effect tile plays the effect **as the engine draws it**: the same shaders, the same
   drawing rule (`EffectStack.drawnAt`) and the same defaults a newly added bar gets. A tile
   cannot promise a look the canvas and the file do not deliver.
2. The loop reads like the transition tiles' rest → play shape: **a beat of the plain picture,
   then the opening of a new bar, in real time**. **(owner, from the chat description)**
3. Smooth: **15 frames a second**, the rate the transition tiles already play at. One shared
   clock drives every tile and holds still while the grid scrolls.
4. **Bounded memory**: decoded pictures exist only for tiles on screen and are freed when the
   sheet closes or the category changes. The encoded cache is small, kept for the session, and
   dropped under memory pressure.
5. **No stutter on the canvas**: tile drawing never holds the GL thread long enough to drop
   live preview frames, even while the video plays under the sheet.
6. **No races**: every request is answered exactly once, every GL object is freed on every
   path, and no decoded picture outlives the tile that asked for it.

## Non-goals

- **The user's own footage** in the tiles. Effects need the GPU, and every effect would have to
  be redrawn whenever the playhead moved: slow on the low-end target and against "smooth".
  **(owner agreed, from the chat description)**
- The transition tiles. They share two exposures with what is designed here (below), and are a
  follow-up, not this change.
- The intensity slider changing the tiles. Tiles show the default strength.
- Playing the bar on the canvas when a tile is tapped (the transitions sheet does this). It
  would fix "the canvas shows only the first instant", but the tiles already answer that
  question, and it is a separate behaviour change.

## Anti-goals — failures even if it "works"

- **The canvas stutters** while the sheet draws tiles, during playback or a scrub.
- **Memory grows as the user browses** categories, or stays held after the sheet closes.
- **A decode finishes after its tile is gone** and the picture is never freed.
- **A lost answer wedges the queue**: one request that never completes stops every later tile
  from ever drawing.
- **An export is disturbed**, or the live preview's own effect passes or effect chain are touched.
- **A tile shows something the engine does not draw**: a hand-made animation, a pre-rendered
  video, or a different strength from what a new bar gets.

## What exists (for the builder)

- **Transition tiles** (`widgets/panels/transitions_drawer.dart`): `TransitionRenderer.renderTransitionPreview`
  draws N frames on the GL thread between two sample pictures (`TransitionPreviewSamples`, drawn
  in code and stored upside down so GL's bottom-up read-back comes out upright). It reads each
  frame back and encodes it as a JPEG on the GL thread. `TransitionPreviewFrames` asks one
  transition at a time, shares an in-flight request, remembers failures and keeps the frames for
  the session (`transitionPreviewFramesProvider`, not autoDispose). The tile shows
  `Image.memory(frames[i])` over one `AnimationController`, held while the grid scrolls
  (`holdPreviewClockWhileScrolling`).
- **The effects stack** (effects track): `NativeTimelineEffect.fromMap`, `EffectStack.drawnAt`
  (intensity at whole-bar progress, shader progress over `introSeconds` from the bar's start),
  `EffectShaders.passesFor` / `applyIntensity` / `applyProgress` / `releasePasses`,
  `EffectPassChain` (two ping-pong targets per size), and `TransitionRenderer.presentTexture`
  (draws a texture over the bound framebuffer through the cached passthrough program). Effect
  programs link **when built** (`FullFrameProgram` links in its constructor).
- **The Effects sheet** (`widgets/panels/effects_panel.dart`): category tabs over a 4-column grid
  of `EffectTile` (icon + label). A tap adds a bar or changes the selected one.

## How it works

### What a tile plays

- **The picture is the transition tiles' sunset** (`TransitionPreviewSamples`), one picture, not
  two. It has a sun disc, a horizon and gradients, enough for distortion, glow and grading to
  read. **(my call; the device look decides)**
- **The effect is a new bar**: start 0, end `kDefaultEffectBarSeconds` (3), the catalog's
  `defaultIntensity` and `defaultEnvelope`, and the catalog's `introSeconds`. In other words,
  exactly what `addEffectBar` creates, sent as the composer's own `EditorTimelineEffect` JSON.
  Kotlin parses it with `NativeTimelineEffect.fromMap` and draws every frame through
  `EffectStack.drawnAt([bar], t)`, the rule both engines draw by. A Dart test pins the sample bar
  to what `addEffectBar` + `composeEffects` produce, so the tile and a real bar cannot drift.
- **Frames:** frame 0 is the plain picture with no passes. Frames 1–24 are the bar at
  `t = (k − 1) / 15` seconds, its first 1.6 s, in real time. Intros (0.5–1.2 s) play and land.
  Looping effects (grain, VHS, handheld, camera pan) move at the speed a real 3 s bar moves; a
  compressed bar would play them faster than the canvas does. Envelopes (blur's ramp, glow's
  throb) show their opening. **(my call)**
- **The loop:** 0.4 s on frame 0, then frames 1–24 at 15 fps, a 2.0 s loop. Plain then effect is
  the bar's own story: before a bar the clip is plain, at its start the effect begins. Every tile
  shares this one loop. **(my call on the numbers)**

### One picture per effect: an atlas

All 25 frames of an effect are drawn into **one image**, a 5 × 5 grid of 160 × 144 cells
(800 × 720), encoded as **one JPEG**. Why one image and not 25:

- **One decode and one picture per tile**, with one owner and one `dispose`. Twenty-five separate
  images are twenty-five lifecycles to get right.
- **It stays out of Flutter's shared image cache.** `Image.memory` puts every decoded frame into
  the global `ImageCache`, which keeps up to 100 MB of decoded pictures until something evicts
  them. The transition tiles grow it this way. The atlas is decoded directly
  (`ui.instantiateImageCodec`) into a `ui.Image` the tile owns and frees.
- **Cells sit on 16-pixel boundaries** (160 = 10 × 16, 144 = 9 × 16), so no JPEG block straddles
  two frames. The painter samples each cell inset by a pixel, so filtering cannot bleed a
  neighbour's edge into the frame shown.

The tile paints its current cell with `canvas.drawImageRect`, cover-fitted to the stage. It
repaints only when the frame index changes (15 times a second), not on every vsync: the sheet
turns the clock into one shared `ValueListenable<int>` frame index, and each tile's painter
listens to that.

### Memory budget **(my call)**

| What | Size | Lifetime |
| :--- | :--- | :--- |
| Decoded atlas | 800 × 720 × 4 ≈ **2.3 MB** per tile on screen | From the tile appearing until it is disposed |
| Tiles alive | At most what is visible: the grid has **`cacheExtent: 0`**, about 8–12 tiles at 45% of a phone screen | Freed on scroll-out, category change and sheet close |
| **Decoded total** | **≈ 28 MB worst case** (12 tiles), typically 18–23 MB | **Zero once the sheet is closed** |
| Encoded atlases | A JPEG per effect; the builder measures and tunes quality so each stays **≤ 150 KB** | The app session, so reopening is instant; **cleared on `didHaveMemoryPressure`** |
| **Encoded total** | **≤ 6 MB** with all 39 drawn | — |
| Kotlin, transient | Sample texture, the atlas target, a cell-sized effect chain, the effect's passes, one 2.3 MB read-back buffer | One drawing job; freed when it ends on every path |

A tile scrolled out and back decodes its atlas again from the bytes cache, a few milliseconds off
the UI thread. Until the decode lands it shows the empty stage, never the icon, so nothing
flickers to a different picture. The icon shows only while an effect has no atlas yet, or could
not be drawn.

### Drawing on the GL thread without stalling the canvas

`TransitionRenderer.renderEffectPreview(effect, cellW, cellH, onDone)` runs as a **job in slices**:

1. **Start** (one GL turn): refuse with **busy** if the renderer is released or an export holds it
   (`exportSurface != null`). Make the context current. Create the sample texture, the 800 × 720
   atlas target, a private `EffectPassChain` sized to one cell, and the effect's passes
   (`EffectShaders.passesFor`; linking happens here, in the job, never in a live frame). Draw
   cell 0, the plain picture. **If the private chain refuses its targets the job answers
   failed**: `EffectPassChain.run` hands back the unprocessed picture when it has no targets,
   and a tile drawn from that would show the plain sunset as if it were the effect. The private
   chain's warnings are logged only, never toasted: a tile is not the user's file. **(my call)**
2. **Draw** in slices of **at most 4 cells per GL turn**, each slice posted behind whatever the
   live preview has queued. So a 15 ms-ish slice is the most the canvas ever waits, never a whole
   effect's 25 frames. Per cell: `EffectStack.drawnAt([bar], t)` → `applyIntensity` /
   `applyProgress` → the private chain over the sample → bind the atlas target, **then** set the
   cell's viewport (binding a target sets its full-size viewport) → `presentTexture`. A cell's GL viewport row is flipped (`rows − 1 − row`) so the
   whole atlas reads upright after one flip.
3. **Finish:** one `glReadPixels` of the atlas into a buffer. Free every GL object. Bind
   framebuffer 0 and `requestRender()`, as the transition preview does. Hand the buffer to a
   **single background thread** that flips and JPEG-encodes it. The encode never runs on the GL
   thread. The thread belongs to the renderer and is shut down in `release()`, after the live jobs
   have been answered.

**Every slice re-checks** before touching GL. If the renderer is released it touches nothing (the
context and every object in it are going) and answers **busy**. Each slice makes the context
current again, because an export may have run between two slices and left its encoder surface
current.

**Answered exactly once.** The job guards `onDone` with an atomic flag, and the manager answers
the channel on the main thread. `Handler.post` returning **false** (the GL thread has quit)
answers busy at once. The renderer keeps its live jobs and **answers busy for all of them in
`release()`**, since `quitSafely` drops anything posted after it. Without this a release mid-job
would leave the Dart future, and the queue behind it, waiting forever.

**Three answers, not two.** An atlas, or **failed** (the effect id is unknown, a program would not
build, a buffer was refused), or **busy** (no renderer yet, released, export, GL thread gone). Dart remembers
**failed** and keeps that tile's icon for the session, as the transitions do. It never remembers
**busy**: the next ask retries. On the channel: `success(bytes)`, `success(null)` for failed,
`error("busy")` for busy.

### The Dart side

- **`EffectPreviewAtlases`** (the counterpart of `TransitionPreviewFrames`, held by a provider
  that is **not** autoDispose): the bytes per effect id, in-flight sharing, failures remembered
  and busy not. **One drawing at a time.**
  - **Cancellable:** a tile's ask is a ticket it withdraws on dispose. An ask that has not started
    when every ticket for it is gone is dropped. Scrolling fast through a category, or closing
    the sheet, never leaves a backlog of effects being drawn for nobody.
  - **A timeout** (10 s) per drawing. A lost answer cannot wedge the queue; a timeout counts as
    busy. **A busy answer leaves that tile on its icon until the tile is next built** (scrolled
    back, the category reopened, the sheet reopened), which asks again. No timer re-asks on its
    own. **(my call)**
  - **Memory pressure** clears the bytes; tiles alive keep their decoded pictures.
- **The tile's stage** (`EffectPreviewStage` inside `EffectTile`): it peeks the bytes or asks,
  then decodes. Every async step is checked against a **generation counter** bumped on dispose and
  on a change of effect. A decode that lands for a stale generation **disposes the image it got**
  rather than drop it. `dispose` frees the current image and withdraws the ticket. Decoding goes
  through an injected decoder so a test can make it land after the tile is gone.
- **The sheet** owns the clock (`AnimationController`, 2.0 s, repeating) and the frame index
  derived from it. It holds the clock while the grid scrolls (`holdPreviewClockWhileScrolling`,
  the shared helper). The grid sets `cacheExtent: 0`. The tile takes the transition tile's look:
  the stage on top, the name under it, the selected border. The icon becomes the stage's
  fallback. **(my call)**

### What changes in the tile and panel

`EffectTile` gains the stage. Its tap is unchanged: add a bar, or change the selected one. The
panel's doc comment, "tiles are a label and an icon, not a preview", is rewritten to explain why
they are now previews and why the canvas is not enough on its own.

## The transition tiles share two exposures

Not fixed here **(non-goal)**, written down so they are not lost:

1. **Memory:** `Image.memory` per frame grows the global `ImageCache`, up to about 88 MB if every
   category is browsed.
2. **A lost answer:** `renderTransitionPreview` posts to the GL thread, and a release in between
   leaves the channel unanswered and `TransitionPreviewFrames`' queue waiting forever.

Once this lands, moving the transition tiles onto the same atlas, job and cache would fix both.

## Testing

Test-first, as the project works. Everything a test can reach is pinned in Dart or JVM Kotlin.

- **Dart, pure:** the frame index at a loop phase (plain beat, each frame, the wrap); the atlas
  cell rects (row-major, inset); the sample bar equals what `addEffectBar` + `composeEffects`
  produce for every catalog effect.
- **Dart, cache:** one at a time; shared in-flight; failed remembered and busy not; timeout is
  busy; an unstarted ask with no tickets is dropped; memory pressure clears.
- **Dart, tile:** a decode landing after dispose disposes its image; a decode for a changed effect
  disposes the stale one; dispose withdraws the ticket; the icon shows with no atlas or on failure;
  the empty stage shows while decoding cached bytes.
- **Dart, sheet:** the grid's `cacheExtent` is 0; every tile gets a stage; the clock holds while
  scrolling; tiles repaint on frame change only.
- **JVM Kotlin (pure parts):** the slice plan (cells per slice, the frame times); the cell
  viewport with its flipped row; the exactly-once guard (post refused, release mid-job, normal
  finish); the request parse (unknown effect → failed; malformed → failed).
- **Device only** (GL and timing): tiles play and look right; the canvas does not stutter while
  tiles draw during playback; memory in the profiler stays within the budget while browsing every
  category, and falls when the sheet closes; an export run while the sheet was open is unaffected.

## Left to the builder

The class and channel names; the JPEG quality (within the 150 KB per atlas cap); how the slice
size is tuned on the device (at most 4 cells per turn); the fallback icon's styling within the
existing tile look.
