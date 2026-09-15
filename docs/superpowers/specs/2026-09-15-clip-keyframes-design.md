# Clip Keyframes — Design (supersedes the effects-panel keyframe row)

**Status:** awaiting approval. Nothing in this document is built. The previous keyframe UI —
a Keyframe button on the effects sheet, a row of diamonds under the clip, effects-only — was
rejected and is deleted by the plan that implements this.

## What was wrong with the first design

The model (`AnimatableDouble`) was built general on purpose — its own header says keyframes are
a *timeline* feature that the transform, opacity and volume will want. The UI then contradicted
that: it was reachable only from the effects sheet, drew a row that existed only while an effect
was applied, and could keyframe exactly one number. A user wanting a Ken Burns move had no way in.
The fault was the design brief, not its execution.

## The picture (the user's, verbatim in substance)

1. **With a clip selected, a diamond-with-plus icon appears in the playback control bar, after
   the play button and before the time readout.** With no clip selected it is not there.
2. **Tapping it places a diamond on the clip's filmstrip — on the thumbnail itself, vertically
   centred, at the playhead.** Not above the clip, not below it.
3. **When the playhead sits on a diamond the icon becomes diamond-with-minus** — tap to remove.
   Tapping a diamond on the filmstrip moves the playhead onto it, so tap-diamond then tap-minus
   removes it.
4. **Next to it, a curve icon opens a small bottom sheet of easings:** Default, Quadratic, Cubic,
   Bounce — each offering none, ease in, ease out, ease (in & out). It applies to the keyframe
   under the playhead.
5. **A keyframe is for everything.** One diamond is one moment of the clip; every animatable
   property of the clip has a value at that moment — position, scale, volume, effect strength,
   and any property added later.

## Rules

### One diamond, every property

A `VideoSegment` has a set of keyframable properties, each an `AnimatableDouble`:
`canvasScale`, `canvasOffsetX`, `canvasOffsetY`, `volume`, `effectIntensity` (and `opacity` once
it exists). **A diamond at progress `p` means every one of those carries a keyframe at `p`.**
Adding a diamond writes a keyframe at `p` to every property with its value *as resolved at `p`*,
so the picture does not change when a diamond is placed; removing one removes at `p` from every
property; an easing chosen from the sheet is written to every property's keyframe at `p`; moving
a diamond moves them all. The set of diamonds a clip shows is the union of its properties'
keyframe progresses — robust even if a draft arrives with them out of step.

### Progress is whole-clip, for every property

`Keyframe.progress` is `(t − clipTimelineStart) / clipTimelineDuration`, 0..1, for **all**
properties including `effectIntensity`. Until now intensity resolved against the effect's *intro
window*; that cannot survive one diamond meaning one instant. The shader's own `uProgress` keeps
the window — that is the effect's clock, not the keyframe's. No shipped draft carries keyframes,
and the only two enveloped effects (`glow`/throb, `blur`/ramp_out) are continuous, so their
window already equals the clip: this rebasing changes no rendered pixel today.

### The edit rule — what makes the plus button the only keyframe UI

Every write to a keyframable property (pinch/drag commit, volume slider, effect intensity
slider, reset transform) goes through one function:

- **No diamonds on the clip:** write the base value. Exactly today's behaviour.
- **Diamonds on the clip:** write the value into the keyframe at the playhead. If there is none
  there, place a diamond first (capturing every other property at that instant), then write.

This is CapCut's rule, and it is why a user never has to think about "keyframe mode": place two
diamonds, pinch at each, and the clip moves between them.

Removing the **last** diamond writes each property's base value from the removed keyframe, so
the picture the user is looking at is the one that stays.

### "On a keyframe" is a time tolerance

The playhead is on a diamond when it lies within `kKeyframeHitSeconds` (0.05s) of one, converted
to progress through the clip's duration. No selection state is stored; the selected keyframe *is*
the one under the playhead, which is what makes the plus/minus flip and the curve sheet coherent.

### Easing

`KeyframeInterpolation` grows from `{linear, ease, hold}` to one family per group: sine
(Default), quadratic, cubic, bounce — each in, out, in-out — plus `linear` (the sheet's "None")
and `hold` (kept for drafts and step effects; not in the sheet). `ease` is a read alias for
`cubicInOut`, the curve it always was. **A fresh keyframe is linear**, so the sheet's highlighted
tile matches what a new diamond does. Every curve exists twice — Dart and Kotlin — and the
fixture samples all of them.

### What does not change

- `AnimatableDouble.resolveAt` order: keyframes, else envelope, else base.
- Envelopes. A preset still shapes a clip that has no diamonds.
- A clip with no keyframes serialises as bare numbers and renders byte-identically — in the
  draft, on the wire, and in both engines. Tests pin all three.
- `MAX_EFFECT_PASSES`, the effect chain, the transition rules.

### Not in this plan

Speed (changes the clip's duration — CapCut gives it its own curve tool), filter intensity,
overlay/text keyframes (overlays have their own animation system), dragging a diamond
vertically to set a value.
