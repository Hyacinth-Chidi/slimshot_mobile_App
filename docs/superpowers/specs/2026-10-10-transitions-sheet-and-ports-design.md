# Transitions round two, part 2a — categories, moving tiles, Basic/Motion/Blur ports

Stage 2 of `docs/roadmap.md`, part 2a. Agreed with the user 2026-10-10: the list and grouping
below, and previews drawn by the engine (option A). Part 2b ports Light, Glitch and 3D; part 3 is
easing.

## The sheet

- **Category pills** over the grid — Basic, Motion, Blur, Light, Glitch, 3D, in that order; a
  category with nothing in it yet is not shown. The sheet opens on the category of the seam's
  current transition (Basic when there is none). Pills are the easing sheet's pills.
- **Four tiles to a row** (`kTransitionGrid`), a None tile first in every category. *Changed
  while building:* the text grids' three left about one and a half rows under the header in a
  sheet held to 45% of the screen. Apply to all and the duration slider stay as they are.
- **Each tile is the real transition**: the engine plays it between two built-in sample pictures at
  tile size (16 frames) and the tile loops them — a short hold on the first picture, the
  transition, a hold on the second. One clock for every tile, held still while the grid scrolls
  (`holdPreviewClockWhileScrolling`). Frames are rendered for the visible category only, one
  transition at a time, and kept for the session. Until a tile's frames arrive it shows the icon.
- **A tap applies the transition and plays it on the canvas**: the playhead goes to just before the
  seam, plays through the window, and stops just after it.

## The engine's half of the tiles

`renderTransitionPreview` on the native channel → `TransitionRenderer.renderTransitionPreview`, on
the GL thread, into a target of its own, returning JPEG frames. The two sample pictures are drawn
in code (`TransitionPreviewSamples`) — no asset, no licence. A layered transition is drawn straight
over the two pictures as its layers; one of the original eleven through its own program with the
pictures as two photo lanes. Nothing is drawn while an export owns the renderer.

## New transitions (all layered, appended to the catalog)

| Category | Type | From |
| :--- | :--- | :--- |
| Motion | `slideScaleLeft`, `slideScaleRight`, `slideScaleUp`, `slideScaleDown` | DirectionalScaled (Thibaut Foussard, MIT) |
| Motion | `splitIn`, `splitOut` | splitSlideIn/OutHorizontal (OllyOllyOlly, MIT) |
| Motion | `bounce` | Bounce (Adrian Purser, MIT) |
| Motion | `swirl` | Swirl (Sergey Kosarevsky, MIT) |
| Motion | `spinAway` | RotateScaleVanish (Mark Craig, MIT) |
| Motion | `zoomInOut` | zoomInOut (OllyOllyOlly, MIT) |
| Motion | `whipPan`, `shake`, `zoomBounce` | ours |
| Blur | `dreamyZoom` | DreamyZoom (Zeh Fernando, MIT) |
| Blur | `motionBlur` | tangentMotionBlur (chenkai, MIT) |
| Blur | `defocus` | DefocusBlur (Sergey Kosarevsky, MIT) |

Each port keeps its credit and lists its changes, which are only: parameters as constants at the
library default; integer loops; interleaved gradient noise in place of the sin-fract hash; alpha
carried through (premultiplied layers). Bounce's shadow darkens the picture under it rather than
blending toward a translucent black; DreamyZoom's flash is added to the colour and leaves alpha
alone, which over the background is exactly the original. Light versions: Motion Blur and Whip Pan
(fewer steps), beside Zoom Blur.

The existing twelve keep their categories: Basic — Dissolve, Fade Black, Fade White, Wipe, Smooth
×4; Motion — Slide, Push, Zoom In; Blur — Zoom Blur.

## Tests

The names fixture grows by sixteen; each new type is supported and layered; the light versions
differ only in their step counts; every shader is validated with `glslangValidator`. Dart: every
transition has a category, the sheet shows only non-empty categories, opens on the current one,
lists exactly the catalog's transitions plus None, applies on tap and asks the canvas to play it.
How each transition looks is a device fact.
