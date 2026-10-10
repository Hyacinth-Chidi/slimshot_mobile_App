# Transitions round two, part 1 — lane layers and Zoom Blur

Stage 2 of `docs/roadmap.md`, first of three parts (engine, then the ports and the sheet, then
easing). Agreed with the user 2026-10-10: engine first, proven on a phone by one new transition.

## Why

A transition today reads each clip through `incomingAt` / `outgoingAt`, which fit, crop, grade,
mask and key the source on **every** read. A dissolve reads once per pixel and pays it once. The
GL Transitions the roadmap ports read many times — CrossZoom about 80, FilmBurn about 100 — and
through that helper they would crawl on the low-end target.

## What changes

**A layered transition draws each clip once, then blends the results.** Per frame inside its
window the renderer draws each lane's finished picture into a texture of its own (a *layer*), and
the transition reads only those two plain textures:

- **A layer is premultiplied, with no background**: `rgb = picture × coverage`, `a = coverage`,
  where coverage is the clip's opacity × mask × chroma key inside its fitted frame and 0 outside.
  The transition's result is laid over `backgroundAt()` at the fragment's own position. For any
  blend that is linear in its inputs this is **exactly** today's arithmetic
  (`mix(bg, picture, coverage)`), so masks, keys, opacity and a background photo or blur behave as
  they always have, and the background stays put while the clips move.
- **GL Transitions port nearly verbatim.** The layered header gives each port the library's own
  API — `getFromColor`, `getToColor`, `progress`, `ratio` — over the two layers. A port must keep
  alpha through its arithmetic (a premultiplied layer is transparent where no clip is); where the
  original forces `a = 1.0` the port carries the real alpha and says so.
- **The existing 11 transitions do not change at all.** They keep the old path, and a test pins
  their shader sources byte for byte.
- **Zoom Blur** (`zoomBlur`, CrossZoom by rectalogic, MIT) is the first layered transition and the
  proof of the path: the tutorial's zoom blur, the heaviest kind (41 steps × two layers), and the
  first transition with a loop — the only other loop is the effect blur, still unproven on a phone.

## Every phone

- **Layers are allocated only when a layered transition is drawn**, sized to the frame and reused;
  dropped when a timeline no longer uses one, and at export end like the effect buffers.
- **A device that refuses the buffers** gets a dissolve in their place and is told once.
- **A preview that cannot keep up** drops to a lighter Zoom Blur (12 steps instead of 40), same
  look, less smooth, and is told once (`TransitionQualityGovernor`: the median of 12 layered
  frames over 45 ms). **The export always renders the full version.**
- **The blurred background** keeps drawing lanes the old way: under a layered transition its
  cover picture is the two clips dissolved, which the blur makes indistinguishable.

## Tests

- `TransitionShadersGoldenTest` — the existing fragment sources, hashed, unchanged.
- `TransitionShadersLayeredTest` — Zoom Blur is supported and layered, its full and light sources
  differ only in the step count, and the layered main lays the result over the background.
- `TransitionQualityGovernorTest` — the speed decision.
- `test/fixtures/transition_names.json`, read by a Dart test and a Kotlin test, so the catalog and
  the shader registry cannot drift apart.
- Shaders are validated with `glslangValidator`; how they look is a device fact.

## Device test

Two clips with Zoom Blur between them: preview, then export, compared. Then a masked clip over a
background photo across a Zoom Blur, and an existing transition, to see it unchanged.
