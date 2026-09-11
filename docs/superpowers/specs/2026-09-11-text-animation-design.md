# Text animation — CapCut-style per-character animation

**Date:** 2026-09-11
**Status:** approved design, not yet implemented

## Problem

Text overlays today animate as a whole rectangle: fade, zoom and four slides. CapCut and
InShot animate **per character** — typing, wave, bounce, colour fill — and offer a **Loop**
category that runs continuously while the text is on screen. We have neither.

Two further faults sit in the same surface and are fixed here because they share its code:

1. **The duration slider does nothing.** `animationInDuration`/`animationOutDuration` are
   stored, serialised and shown on a 0.1–2.0s slider, but `text_overlay_layer.dart` plays
   flutter_animate's stock 0.5s and the export hardcodes `animationInSeconds: 0.5`. The UI
   promises control it does not have.
2. **The animation tab is unpreviewable.** Tiles are text labels; the only way to see what
   `slide_up` does is to apply it, close the sheet and scrub.

## Why the current export path cannot do it

An exported text is **one flat PNG** appended to the timeline as an image overlay.
`OverlayRenderer` draws it as a single quad, and `NativeTimelineOverlay.stateAt` can only
produce a whole-overlay opacity, scale and offset. Per-character motion is not expressible.

Three routes were considered:

| Route | Verdict |
| :--- | :--- |
| Rasterise a fresh PNG in Flutter every output frame | **No.** Export runs faster than realtime; a 30s export becomes ~900 PNG encodes plus file writes, on exactly the low-end hardware we target. |
| Re-implement text layout in Android `Canvas` | **No.** Ruled out in CLAUDE.md — font metrics, stroke and shadow all drift. Rasterising in Flutter is *why* text matches today. |
| **Glyph atlas + per-glyph quads** | **Yes.** See below. |

## Approach: glyph atlas + per-glyph quads

This is the standard real-time text pipeline — a rasteriser produces a glyph atlas once and
the GPU draws one quad per glyph. Games, browsers and After Effects' per-character animators
all work this way. The only unusual part here is that our rasteriser is **Flutter** rather
than FreeType, which is deliberate: it is what keeps preview and export identical.

Flutter rasterises the text **once** into a sprite sheet plus a table of per-glyph source
rects and layout positions. Kotlin draws one quad per glyph and asks a shared curve table
what each glyph's transform, opacity and colour are at time `t`.

- Pixels still come from Flutter's text engine → parity preserved.
- Animation is pure GL transform → no per-frame encoding.
- The existing `OverlayPass.drawsFor(t)` already returns a **list** of `Draw`s, so a
  per-glyph overlay returns N draws where an image returns 1. This is an extension point,
  not a rewrite.

### The whole-box parts stay whole

The background box and the selection frame are **not** sliced per glyph. The background is
one quad drawn behind the glyph quads, so a per-glyph animation moves the letters over a
stationary (or whole-box-animated) background — which is what CapCut does and what looks
right.

### Shadow bleed

Shadows and strokes extend past a glyph's ink box and would bleed between neighbouring atlas
cells. Each glyph cell is padded by the shadow blur radius plus the stroke width, and cells
are laid out in the atlas with that padding included.

## Component design

### 1. `logic/text_animation_catalog.dart` — the single source of truth

One entry per animation. Three consumers read it, which is the whole reason it exists
(CLAUDE.md records "four disagreeing transition lists" as a real past failure):

1. the canvas preview (`text_overlay_layer.dart`),
2. the export (Kotlin `TextAnimationCurves.kt`, a 1:1 port),
3. the animation tab's looping preview tiles.

```dart
class TextAnimation {
  final String id;              // persisted; renaming needs a migration
  final String label;
  final TextAnimationCategory category;   // inAnim | outAnim | loop
  final bool isPerGlyph;
  final double Function(int glyphCount) naturalDuration;
  final TextGlyphState Function(double progress, int glyphIndex, int glyphCount) glyphStateAt;
}

class TextGlyphState {
  final double opacity;
  final Offset offset;      // in box-relative units, so it scales with the text
  final double scale;
  final double rotation;
  final double fillProgress; // 0..1, for colour-fill animations
}
```

`glyphStateAt` is a **pure function** — no clock, no state — which is what makes it testable
and portable to Kotlin.

### 2. The Kotlin port, pinned by a fixture test

`TextAnimationCurves.kt` mirrors the catalog. A generated fixture table samples every
animation at a grid of `(progress, glyphIndex, glyphCount)` and both sides are asserted
against it, so a drift between Dart and Kotlin **fails the suite** rather than shipping a
file that differs from the preview.

### 3. Timeline contract — a `text` overlay kind

`EditorTimelineOverlay` gains an optional glyph table. The `kind` becomes `text` when it is
present; existing `image` and `video` overlays are untouched.

```
glyphs: [ { srcX, srcY, srcW, srcH, boxX, boxY, boxW, boxH }, ... ]
animationIn / animationOut / animationLoop : String?
speedIn / speedOut / speedLoop : double
```

Geometry stays **normalised to canvas fractions** — the existing rule, so the renderer never
sees a device pixel.

### 4. The Speed slider

One slider labelled **Speed**, 0.5×–3×, default 1×, replacing the two duration sliders.
Each catalog entry declares a *natural* duration which may depend on content length:

| Animation | Natural duration |
| :--- | :--- |
| fade / zoom / slide | 0.5s flat |
| typing | `0.04s × chars`, clamped 0.4–2.5s |
| wave / bounce | `0.5s + 0.02s × chars` |
| colour fill | `0.06s × chars` |

Effective duration = natural ÷ speed. A long line genuinely types longer than a short one,
and the slider scales whatever that is — CapCut's behaviour.

**When the animations do not fit the overlay.** A 1.2s typing-in on a 0.8s text, or an in
and an out that together exceed the span, must not be resolved by dropping one — a dropped
animation is a silent difference between what the tile previewed and what the file shows.
Both are **compressed proportionally** to fit the span: if `in + out > span`, each is scaled
by `span / (in + out)`. They may therefore run faster than the Speed slider asks on a very
short overlay, which is visible and self-explanatory, where a vanished animation is not.
The preview layer, the export and the tiles all apply this same clamp, so it belongs in the
catalog (`resolveDurations(span, inAnim, outAnim, speeds)`) rather than in any one consumer.

**Migration:** `animationInDuration`/`animationOutDuration` are repurposed to hold the speed
multiplier. A stored value that is not a plausible speed (the old 0.1–2.0s range, where
values below 0.5 are unreachable as speeds) maps to 1×. `loopSpeed` is new.

### 5. Loop category

A third tab beside In and Out. Loop animations run continuously between the in-animation
ending and the out-animation starting, on their own phase clock (`(t - start) / period`),
so they are seamless regardless of overlay length.

### 6. Animation tab — live looping preview tiles

Each tile is the **same body widget** the canvas draws, at small scale, driven by a looping
local ticker instead of the playhead. Not a separate rendering path — that is what keeps a
tile honest about what the animation will actually do.

Cost control, since ~20 tiles tick at once:
- Only the visible category's tiles are built and ticked.
- Tiles use the user's real text truncated to ~8 characters (enough to show a per-glyph
  stagger, cheap to lay out); empty text falls back to a sample word.
- One shared `Ticker` drives every tile rather than one each.
- A tile off-screen in the grid's scroll viewport is not ticked.

## Catalog seed

Extensible by design — adding another is one catalog entry plus its Kotlin twin, no new
mechanism. Unknown ids degrade to no animation, the same rule unknown transitions follow.

**In:** Typing, Fade, Zoom In, Zoom Out, Slide ×4, Bounce In, Pop, Wave In, Colour Fill,
Blur In, Rise (per-word), Spin In
**Out:** Un-typing, Fade Out, Zoom In/Out variants, Slide-out ×4, Bounce Out, Pop Out,
Blur Out, Sink
**Loop:** Wave, Pulse, Shake, Colour Cycle, Wiggle, Neon Flicker

## Staging

Each stage is independently verifiable on device.

**Stage 1 — glyph atlas + contract.** The rasteriser emits an atlas and glyph table; Kotlin
draws N quads. **No animation yet.** Acceptance: a text project exports *pixel-identical* to
today. A fixture test compares a flat raster against the reassembled atlas at rest — if those
do not match, the atlas is wrong before any animation is layered on it.

**Stage 2 — curve table, Kotlin port, preview.** Animations become real in canvas and export,
with the Speed slider live. Acceptance: typing/wave/bounce/colour-fill look the same on
canvas as in the exported file.

**Stage 3 — animation tab.** Looping preview tiles, the three category tabs, the Speed
slider in its final form.

## Risks

- **Atlas fidelity** is the main one, and Stage 1's pixel-identical gate is the mitigation.
- **Glyph count on long text** — a 200-character overlay means 200 quads. Cheap on a GPU, but
  the atlas has a 4096px texture cap; beyond it the text falls back to a single-quad flat
  raster with whole-box animation only, **with a warning**, per the degrade-loudly rule.
- **GLSL is runtime-compiled**, so any shader change (the colour-fill wipe) can only be
  verified on device.

## Out of scope

Word-level animation granularity (only per-character and whole-box here), text templates,
and animated backgrounds.
