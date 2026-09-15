# Effect Slots, Outros and Duration (Effects Stage 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A clip carries an **intro**, a **look** and an **outro** independently, organised into categories that match what each effect actually does, with a duration control on every timed effect. Plus two device-reported bugs fixed.

**Architecture:** `VideoSegment` gains three effect slots where it had one. The renderer composes their passes into the existing chain, which already caps and warns. Categories are reorganised so a tab means something.

**Tech Stack:** Flutter/Dart, Kotlin, OpenGL ES 2.0, Riverpod.

**Spec:** `docs/superpowers/specs/2026-09-12-clip-effects-design.md`

**Depends on:** the effect clock, `AnimatableDouble` (Dart + Kotlin + fixture), and 39 wired effects — all landed. Four are device-verified; the rest were checked in this round and produced the two bugs below.

## Global Constraints

- **A clip with no effects must render byte-identically to today.** Most of the catalog is still only partly device-verified; this stage must not add a second variable to any bug report.
- **One evaluator.** Intensity and progress resolve through `AnimatableDouble` and `effectProgressAt`, never a second path.
- **The timeline clock is the only clock**, in both engines. Export runs faster than realtime.
- **`MAX_EFFECT_PASSES` is 4.** The worst realistic stack is glow (3 passes) + an intro (1) = 4. The chain already truncates and warns past the cap — do not raise it silently.
- Undo is manual: `saveStateForUndo()` once per gesture, never per frame.
- Serialisation hand-written and defensive; a pre-stage draft must load with its single effect intact and **must never throw**.
- Analyzer baseline is exactly **48**. Add none.
- Verify with `flutter analyze --no-pub`, `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.

---

### Task 1: The two device-reported bugs

Fixed first and separately, so a bisect can tell a bug fix from the restructure that follows.

**Files:**
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/effects/RetroLookPasses.kt`

- [ ] **Step 1: Glitch bursts are one frame long**

Diagnosed by computing it, not guessing. The *rate* is fine: at intensity 0.5 the gate
`step(1 - MAX_RATE * uIntensity, roll)` fires on ~21% of steps, about 12 bursts per clip. The
**duration** is the bug — a burst lasts exactly one step, and `STEPS = 60` makes that **17ms on a
1s clip, a single frame at 60fps**; 83ms even on a 5s clip. It is glitching, just never long
enough to see.

Fix by **decoupling burst duration from step granularity**. Lowering `STEPS` alone is wrong: it
makes bursts longer *and* rarer together, when only the first is wanted. A burst should hold for
roughly 100–200ms of clip time — long enough to read, short enough to still feel like a fault.

Note the constraint this creates: burst length in *clip fractions* is not constant in seconds
across clips of different lengths. Decide deliberately whether a burst is a fixed fraction (so a
long clip glitches for longer) or approximates a fixed time, and write the reasoning down.

- [ ] **Step 2: Compile, and commit alone**

---

### Task 2: Categories that mean something

**Files:**
- Modify: `lib/features/video_editor/logic/effects/effect_catalog.dart`
- Modify: `lib/features/video_editor/widgets/panels/effects_panel.dart`
- Test: extend `test/features/video_editor/logic/effects/effect_catalog_test.dart`

The current `EffectCategory.motion` is labelled **"Focus"** and holds `sharpen`, `blur`,
`camera_pan`, `handheld`, `super_shake` — sharpness mixed with camera movement, three of five
nothing to do with focus. That is the "not that active" report: the tab is incoherent, so nothing
in it feels like it belongs.

- [ ] **Step 1: Re-categorise by what an effect *does***

Proposed shape, adjust if reading the catalog suggests better:

| Category | Holds |
| :--- | :--- |
| **Intro** | timed openers: cinema zoom, zoom in, super zoom, spin, roll, bounce, tilt, blur in, pixel in, steady in, fade in |
| **Outro** | timed closers (Task 4) |
| **Reveal** | from black: shutter, horizontal open, circle in, grid, grid collage, roulette |
| **Colour** | duotone, hue shift, B&W fade, light leak, vignette |
| **Retro** | grain, VHS, scanlines, glitch, RGB split, chromatic |
| **Distort** | fisheye, ripple, swirl, mirror, pixel |
| **Camera** | camera pan, handheld, super shake |
| **Focus** | blur, sharpen, glow — and *only* things about sharpness |

- [ ] **Step 2: A test pinning the taxonomy**

Assert every category is non-empty and that **no category mixes timed and continuous effects**
(`introSeconds != null` versus null) — that mixing is what made "Focus" incoherent, and a test
stops it recurring as the catalog grows.

- [ ] **Step 3: Gates and commit**

---

### Task 3: Three slots

The contract change. Behaviour-preserving on its own — a clip with one effect keeps rendering it.

**Files:**
- Modify: `lib/features/video_editor/models/video_segment.dart`
- Modify: `lib/features/video_editor/models/editor_timeline.dart`
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart`
- Modify: `android/app/src/main/kotlin/.../NativeTimelineClip.kt`, `TimelinePlaybackEngine.kt`, `VideoExportEngine.kt`, `gl/effects/ClipEffectController.kt`
- Test: extend the segment and composer tests

- [ ] **Step 1: The model**

`VideoSegment` carries three slots — intro, look, outro — each an id plus its own
`AnimatableDouble` intensity, and timed slots plus a duration.

**Migration:** a draft holds one `effectId`. Load it into the slot its **category** names, so an
existing project keeps looking as it does. A draft with an unknown id loads as no effect, the
rule unknown ids already follow. Test each case; **never throw.**

- [ ] **Step 2: The renderer composes the slots**

`ClipEffectController` builds the pass list from up to three effects rather than one. Order is
**look, then intro, then outro** — a look treats the picture and a timed effect acts on the
result, so a clip fading out fades out its *graded* self.

Past `MAX_EFFECT_PASSES` the chain truncates and warns. Verify a glow + intro stack (4 passes)
still fits and does not warn; a glow + intro + outro (5) should truncate loudly rather than
silently.

**The change guard must key on all three slots**, or switching an intro while a look is active
will not rebuild.

- [ ] **Step 3: Gates and commit**

---

### Task 4: Outro effects

**Files:**
- Modify: `lib/features/video_editor/logic/effects/effect_catalog.dart`
- Create: `android/app/src/main/kotlin/.../gl/effects/OutroPasses.kt`
- Modify: `gl/effects/EffectShaders.kt`

- [ ] **Step 1: Progress runs backwards for an outro**

An intro's progress runs 0→1 over its opening window. **An outro's window is the clip's
*closing*** — progress must reach 1 at the clip's last frame, having started at 0 when the outro
began. Add that to `effectProgressAt` (or a sibling), and test the boundary: an outro on a clip
shorter than its own duration must still finish exactly at the end, not get cut off mid-way.

- [ ] **Step 2: The outros**

Mirror the intros: `fade_out`, `zoom_out`, `spin_out`, `blur_out`, `pixel_out`, plus reveal-style
closers `shutter_close`, `circle_out`, `horizontal_close`.

Many can **reuse an intro's shader with progress inverted** — a shutter closing is a shutter
opening played backwards. Prefer that over a second shader: one source, and the two can never
drift. Say in the report which reuse and which needed their own.

- [ ] **Step 3: Compile, gates, commit**

---

### Task 5: The panel — three tabs and a duration slider

**Files:**
- Modify: `lib/features/video_editor/widgets/panels/effects_panel.dart`
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart`
- Test: extend `test/features/video_editor/widgets/effects_panel_test.dart`

- [ ] **Step 1: Slot tabs**

**Intro / Look / Outro**, mirroring the text editor's In/Out/Loop — users have already learned
that shape, and a second idiom for the same concept is a tax.

Each tab shows its categories and a None tile. Selecting writes that slot only, leaving the
others intact — that is the whole point of three slots.

- [ ] **Step 2: The duration slider**

On **timed** effects only (`introSeconds != null`): how long the intro or outro takes before
settling. A continuous look has no duration, and showing a dead slider is the "control that lies"
problem the Speed slider already had once.

Range from the effect's own natural duration; clamp to the clip's length, since an intro longer
than its clip can never finish.

Intensity stays on every effect. **A drag is one undo step.**

- [ ] **Step 3: Tests**

Assert: three tabs; each lists its own categories; selecting one slot leaves the others; the
duration slider appears for a timed effect and **not** for a continuous one; both sliders write
their values; a stored effect shows selected in its own tab.

- [ ] **Step 4: Gates and commit**

---

### Task 6: Device verification

- [ ] **Step 1: The two bugs**

1. **Glitch visibly glitches** — bursts long enough to see, still reading as a fault.
2. **Every category is coherent** — a tab's contents plainly belong together.

- [ ] **Step 2: Slots**

3. An intro **and** a look **and** an outro on one clip, all visible, in that order.
4. Glow (3 passes) + an intro (4 total) renders; adding an outro (5) warns rather than failing silently.
5. A clip with one effect from an older draft looks unchanged.

- [ ] **Step 3: Duration**

6. The duration slider changes how long an intro runs, and reaches the export.
7. It does not appear on a continuous look.

- [ ] **Step 4: Unchanged**

8. A clip with no effect, filters, transitions, text overlays.

- [ ] **Step 5: Update CLAUDE.md**

## Exit criteria

- [ ] Glitch reads as a glitch.
- [ ] No category mixes timed and continuous effects, pinned by a test.
- [ ] Intro, look and outro coexist on one clip and export as previewed.
- [ ] Old drafts load into the right slot and look unchanged.
- [ ] The duration slider appears only where it means something.
- [ ] `flutter test`, `flutter analyze --no-pub` (48), `compileDebugKotlin` all pass.
