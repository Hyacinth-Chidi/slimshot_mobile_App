# Per-clip effects — CapCut-grade, with keyframes

**Date:** 2026-09-12
**Status:** approved design, not yet implemented

## Problem

The editor has colour *filters* (a 4×5 matrix per clip or per project) and nothing else. CapCut's
appeal is largely its **effects**: glitch, VHS, light leaks, blur, glow, shake, distortions — and
the ability to animate any of them over a clip's duration.

Two audiences have to be served by one feature, and the tension between them shapes the whole
design:

- Someone who wants a good-looking clip in three taps and will never open a parameter panel.
- Someone who wants a glitch that builds to a beat and a blur that clears on a specific frame.

A design that serves only the first is a toy; one that serves only the second is unusable for
most people. **Presets for everyone, keyframes for those who ask.**

## The constraint that shapes everything

The renderer is **GLES 2.0 and single-pass**. `TransitionRenderer` samples source textures,
blends them, and writes one frame. Verified: the only `glBindFramebuffer` call in the codebase
unbinds to the default target — there is **no render-to-texture anywhere**.

That divides effects in two:

| | Definition | Cost today |
| :--- | :--- | :--- |
| **Single-pass** | Each output pixel is a function of the source pixels | One shader. Nearly free, like a transition. |
| **Multi-pass** | The frame must be rendered to a texture and re-processed, often repeatedly | Impossible — needs an FBO framework |

This is why the background tool's `blur` option falls back to black, and why Blur and Neon
Flicker were cut from the text animations. **The FBO framework is the substantive work in this
project**; once it exists, blur, glow, bloom, neon, tilt-shift and soft focus are all just
shaders.

## What is reachable, and what is not

### Single-pass — cheap on the current architecture

Colour grades (LUT-based film looks, teal/orange, vintage, B&W, duotone), vignette, grain,
scanlines, chromatic aberration, VHS, RGB split, glitch, datamosh, sharpen, emboss, edge detect,
fisheye, wave, ripple, swirl, pinch, mirror/kaleidoscope, shake, zoom-pulse, light leaks, dust,
rain, snow, and chroma key with spill suppression.

### Multi-pass — needs the framework, then cheap

Gaussian blur (and tilt-shift, background blur), glow, bloom, neon, dreamy/soft focus, orton,
cinematic haze. Motion blur, echo and trails additionally need previous frames retained.

**These are the effects users notice most.** A pack without blur and glow does not read as
premium, which is why the framework comes first.

### Out of reach, and honestly so

AI segmentation (background removal, sky replacement, body effects), face tracking (beauty, face
warp, AR stickers), optical-flow slow motion, and true 3D or particle simulation. These need an
on-device ML model — the C++/TFLite conversation — or a different engine class. CapCut has them
and they are genuinely part of why it feels magical. They are a later project with a real
dependency, not something to approximate.

**But this stage is their groundwork, and that is deliberate.** The app is SlimShot *AI*, so the
segmentation features are a stated destination rather than a maybe. Every one of them reduces to
the same shape: a model produces a **per-frame mask**, and the renderer composites through it —
background removal is a mask between the clip and a replacement, sky replacement is a mask
between two sources, face beauty is a blur applied *through* a mask. All three need exactly what
Stage 1 builds: render-to-texture, a pass chain, and a shader that can sample a second texture
alongside the frame.

So the multi-pass framework should be designed with a mask input in mind — not implemented, and
not carrying speculative parameters, but shaped so that adding "sample a mask texture" later is
one more pass rather than a re-architecture. The ML model, its threading, and where the mask is
produced are all out of scope here; the **place it plugs into** is what this stage creates.

## Approach

### One effect per clip

A clip carries one effect, as it carries one filter today. This is the simplest contract, the
simplest UI, and how most short-form edits are actually made. **Stacking is deliberately
deferred**: every extra effect in a stack is another render pass, and on the low-end target that
cost is real. The model should not make stacking impossible later, but nothing in this project
builds for it.

Effects live on the **contextual clip menu**, beside Speed and Volume — the clip is the subject,
so the effect belongs where the clip's other properties are.

### Two paths through one feature

**The casual path.** Tap a clip → Effects → tap an effect. It applies with defaults that look
good immediately. One intensity slider if they want to tune it. Most users stop here.

**The envelope, still one tap.** Every effect ships with a default *behaviour* rather than a
static value — a glitch that pulses, a blur that clears, a shake on the beat. The user configures
nothing; the effect simply feels alive. Mechanically this is a curve, exactly like the text
animation catalog.

**The pro path, opt-in.** A "Keyframe" control on the effect panel reveals a keyframe row on that
clip in the timeline: diamonds to drag, add and delete, with an interpolation choice. A user who
never taps it never sees a diamond.

**Keyframes override the envelope, never the reverse.** No keyframes → the envelope plays. The
first keyframe on a parameter means the user has taken manual control, and the envelope steps
aside for that parameter. There is no mode to enter or leave and nothing to switch off.

### The keyframe engine is general from day one

Keyframes are not an effects feature — they are a **timeline** feature. The moment they exist,
users expect them on transform (pan/zoom, Ken Burns), opacity, and volume. Building them inside
the effects system would mean keyframes that work in exactly one place, and a rebuild plus a
draft migration when the next consumer arrives.

So the model is a general **animatable parameter** — a value, an optional envelope, an optional
keyframe list, an interpolation mode — and *effects are its first consumer*. Transform, opacity
and volume plug into the same engine later with no rebuild and no migration. The extra cost now
is small; the UI is the expensive half either way.

### The effect catalog mirrors the animation catalog

`logic/effects/effect_catalog.dart` is the single source of truth: id, label, category, which
pass it needs, its parameters with ranges and defaults, and its default envelope. The panel, the
composer and the Kotlin shader registry all key off it, exactly as `transition_catalog.dart`
works today. Adding an effect is one catalog entry plus one shader.

Effect ids are persisted into drafts, so renaming needs a migration, and an unknown id must
degrade to no effect rather than crashing — the rule unknown transition names already follow.

## Staging

Each stage is independently device-verifiable.

**Stage 1 — the multi-pass framework.** Render-to-texture, a ping-pong pass chain, and one
effect (gaussian blur) end to end in preview and export. Acceptance: blur works, and preview
matches export. Nothing else ships. This is the stage that unblocks everything visual.

**Stage 2 — the effect contract and the casual path.** `VideoSegment.effectId` + parameters, the
catalog, the clip-menu panel, the composer, the Kotlin registry, and ~15 effects spanning both
tiers. Acceptance: every effect looks right on device and identical in the file.

**Stage 3 — envelopes.** Default behaviour per effect, so a one-tap effect feels alive.

**Stage 4 — the keyframe engine.** The general animatable-parameter model, the timeline keyframe
row, and effects as its first consumer.

## Risks

- **GLSL is compiled at runtime**, so no build step can catch a shader error — every effect needs
  device verification. This is the main reason the library starts at ~15 rather than 25.
- **Fill rate on the low-end target.** Each pass re-reads and re-writes a full frame; a blur is
  two passes plus the composite. The framework must cap chain length and degrade loudly, per the
  existing capability rule.
- **Export parity.** Effects must run in the same `composite` path both sides, or preview and
  export diverge — the failure this codebase has hit repeatedly.
- **Texture memory.** Two full-size FBO targets at export resolution are not free on a 2015
  device; they must be allocated once and reused, never per frame.

## Effects come in two kinds, and the difference is a clock

The catalog's first sixteen are **continuous looks**: vignette, VHS, grain, fisheye. They are a
function of the pixel, and a still frame from the middle of the clip shows the whole effect.

The set requested after the first device run is mostly the other kind — **intro effects** that
play once at the clip's start and settle: cinema zoom, camera pan, shutter, circle in, zoom,
blur in, super zoom, handheld, steady in, super shake, fade in, hue shift, B&W fade, echo,
pulse zoom, pixel in, spin, grid, super cut, horizontal opening, roll, bounce, grid collage,
roulette, tilt.

A continuous look needs no clock. An intro effect is **nothing but** a clock: it is a function of
how far through the clip the playhead is. Effects as first built carry no time at all, so none of
these could work, and adding a progress uniform is a contract change rather than another shader.

**The clock is built before any more shaders**, because it is also what Stage 3's envelopes and
Stage 4's keyframes need. Built once, three features use it; built per feature, it is built
three times and they disagree.

`uProgress` is the clip's own 0..1 position, resolved from the **timeline clock** exactly as
per-clip grades are (`laneClipFor(lane, position)`), not from a wall-clock or a frame counter:
export runs faster than realtime, and anything that counts frames or reads the system clock
renders differently in the file than on the canvas. That is the single most repeated bug class
in this codebase.

An intro effect also needs a **duration** — how much of the clip it occupies before settling.
That is a per-effect natural duration scaled by the existing intensity control, the same shape
`naturalDuration` already has in the text animation catalog, so the two read alike.

## Reveals are clip effects, not transitions

Shutter, circle in, horizontal opening, grid collage and roulette all *reveal* a clip from black.
That is nearly a transition, and the app has eleven of those with their own catalog and drawer.

They are built as **clip effects** anyway, deliberately:

- A transition needs two clips. A reveal must work on the **first clip of a project**, which by
  definition has no predecessor.
- The user described them as "black overlay reveals", which is what a clip effect does natively —
  the effect composites the clip against black over its own opening.
- One panel holds every effect, rather than a user hunting two menus for the same visual idea.

A true two-clip wipe remains a transition, and the transition catalog stays where it is. If a
shutter *between shots* is wanted later, that is a transition entry sharing this shader — not a
reason to move the reveal.

## Deferred: animated effect tiles

The panel's tiles are a label and an icon. The user asked for **live previews** — each tile
playing its effect over a sample image, three to a row and taller, so an effect can be judged
without applying it. Text animation tiles already work exactly that way and are the reason the
feature is expected here.

Deferred deliberately, not dropped, and the reason is worth keeping:

**A tile must run the real shader.** Writing 39 Flutter shaders that imitate the Kotlin ones
would be quick and would be a second implementation of every effect, drifting the moment either
is tuned — the "tile that lies" failure the text animation tiles were designed to avoid, where
the tile promises something the export does not deliver.

**The honest route is one shader body, two wrappers.** Flutter's `FragmentProgram` compiles GLSL
(460 down to 100), so a single `.frag` body can serve both sides: Kotlin wraps it for GLES 2.0,
Flutter for `FragmentProgram`. Confirmed against the Flutter docs, with two constraints — the
dialects differ (`texture()`/`fragColor`/`FlutterFragCoord()` against
`texture2D()`/`gl_FragColor`/a `varying`), and **sampling in Flutter on OpenGLES needs the UV
y-flipped**, which Kotlin does not.

**The blocker is sequencing, not difficulty.** Each of the ~28 passes currently writes its own
*complete* shader — its own precision declaration, its own `gl_FragColor`. Sharing bodies means
restructuring all of them, and **35 of the 39 effects have never run on hardware**. Refactoring
them first would mean a broken effect could be the refactor or the shader, with no way to tell
which. Device-verify first, then refactor against known-good behaviour.

**Sample media:** a bundled image, not a video. Each tile needs its own effect applied, so a
video would add a decoder per tile — 13 visible tiles is 13 decoders, well past the low-end
target. One image decoded once serves every tile, and because intros are driven by `uProgress`,
a looping clock makes a still image genuinely animate. Only the pure grades (duotone, vignette,
sharpen) stay still, and those look identical in motion anyway.

## Out of scope

Effect stacking, audio effects, AI-dependent effects, and keyframes on transform/opacity/volume
(the engine supports them; wiring those consumers is a later project).
