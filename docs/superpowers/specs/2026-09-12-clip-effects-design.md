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

## Out of scope

Effect stacking, audio effects, AI-dependent effects, and keyframes on transform/opacity/volume
(the engine supports them; wiring those consumers is a later project).
