# Effect Catalog and Clip Effects (Effects Stage 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A clip can carry an effect, chosen from the clip's contextual menu, rendering identically in preview and export — with ~15 effects spanning both the single-pass and multi-pass tiers.

**Architecture:** One catalog in Dart is the single source of truth (id, label, category, parameters, pass count), mirrored by a Kotlin shader registry. `VideoSegment.effectId` + `effectIntensity` travel the existing clip JSON route, exactly as `filterId` → `colorMatrix` does today. The multi-pass framework from Stage 1 runs the passes; a single-pass effect is simply a chain of one.

**Tech Stack:** Flutter/Dart, Kotlin, OpenGL ES 2.0, Riverpod.

**Spec:** `docs/superpowers/specs/2026-09-12-clip-effects-design.md`

**Depends on:** Effects Stage 1 (`docs/superpowers/plans/2026-09-12-effects-multipass.md`) — `RenderTarget`, `EffectPassChain`, `TransitionRenderer.setEffectPasses`, and a working `BlurPass`, all committed. **Not yet device-verified**, so Task 1 of this plan carries that verification.

## Global Constraints

- **minSdk 24, GLES 2.0 only.** No MRT, no `textureSize()`, no variable loop bounds, `attribute`/`varying` not `in`/`out`, and an explicit float precision in every fragment shader.
- **GLSL compiles at runtime.** `compileDebugKotlin` cannot catch a shader error — it surfaces as a black frame or an `error` event. Every effect needs device verification, which is why this stage ships ~15 and not 25.
- **Preview and export share `composite`.** An effect that renders differently in the two is the failure mode this codebase has hit most often.
- **Effect parameters are normalised** (0..1 or canvas fractions), never device pixels. A radius in pixels blurs the preview and the file differently — Stage 1 already hit this.
- **Degrade loudly.** A device that cannot allocate the chain renders unprocessed and warns; the `warning` event now reaches a toast (`video_editor_screen.dart`).
- **Unknown effect ids degrade to no effect**, never a crash — the rule unknown transition names already follow. Effect ids are persisted in drafts, so renaming needs a migration.
- **Undo is manual**; a slider drag is one step (`saveStateForUndo` on drag start, a live update per frame).
- Analyzer baseline is exactly **48**. Add none; fix none.
- Verify with `flutter analyze --no-pub`, `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.

## The central design decision: effects are whole-frame, grades are per-lane

Verified in the engines: `applyLaneGrades` calls `renderer.setLaneColorMatrix(lane.index, …)` — a
clip's **colour filter** is applied *per lane, before the blend*, which is what lets two clips
cross-fade between different looks. But an **effect pass runs after compositing**, on the finished
frame, because that is what a blur or a glow means.

So during a transition between two clips with *different* effects there is one frame and two
answers. The options and the ruling:

| Option | Verdict |
| :--- | :--- |
| Run both clips' effects in sequence | **No.** A blur then a glitch is neither clip's look, and the pass count doubles mid-transition. |
| Render each lane into its own target, effect them separately, then blend | Correct in principle, **rejected for now**: it doubles the target memory and every pass, on exactly the low-end hardware transitions already strain. |
| **Use the outgoing clip's effect for the whole window** | **Yes.** |

**The outgoing clip owns the transition window.** That matches the existing clock rule — the
outgoing lane is already transition master (`CLAUDE.md`, transition rendering) — so the effect
follows the same authority the position does. At the window's end the incoming clip's effect takes
over, in the same instant mastership hands over.

This is a **documented compromise, not an oversight**. Write it in the code comment where the
resolution happens, so the next reader knows it was chosen rather than missed.

## What this stage does NOT do

Envelopes (Stage 3), keyframes (Stage 4), effect stacking, and the AI mask input. The debug
`setDebugBlur` hook from Stage 1 is **deleted** by Task 4 — it exists only until the real contract
lands.

---

### Task 1: Device-verify the Stage 1 framework

Stage 1 compiled and shipped but **never executed** — nothing could add a pass. Everything in this
plan builds on it, so it gets verified first, before more is stacked on top.

**Files:** none. This is a verification task.

- [ ] **Step 1: Build and install**

Run: `flutter build apk --debug`

- [ ] **Step 2: Verify the no-passes path is unharmed**

With no debug blur set:
1. A multi-clip project plays and exports as before.
2. Transitions, per-clip filters, photos, overlays and text all unchanged.

**This is the most important check in the task.** Every existing feature goes through `composite`,
and Stage 1 restructured it.

- [ ] **Step 3: Verify the framework actually runs**

Set the debug blur through the channel hook, then:
3. A video clip blurs in the preview, smoothly.
4. The same project exports with the blur **matching the preview's strength**.
5. An overlay or text on a blurred clip stays **sharp** — the chain runs before overlays.
6. A photo clip blurs (image lanes take a different sampler).
7. Blur across a transition blurs the blended result and the transition still plays.

- [ ] **Step 4: If the screen is black, suspect the shader loop first**

No existing shader in this codebase uses a loop. `BlurPass` uses a fixed 16-tap loop indexing a
`uWeights[i]` array, which is spec-legal on ES 2.0 (Appendix A constant-index-expression) but has
no local precedent on a real driver. **If blur renders black, unroll the loop to 16 explicit
statements** before looking anywhere else.

- [ ] **Step 5: Record the result in the ledger and CLAUDE.md**

Note what worked and what did not. If the framework needs a fix, that fix is the next task and the
rest of this plan waits.

---

### Task 2: The effect catalog

**Files:**
- Create: `lib/features/video_editor/logic/effects/effect_catalog.dart`
- Test: `test/features/video_editor/logic/effects/effect_catalog_test.dart`

**Interfaces:**
- Produces:
  - `enum EffectCategory { none, grade, retro, distort, light, motion }`
  - `class VideoEffect { final String id; final String label; final EffectCategory category; final int passCount; final double defaultIntensity; final bool isMultiPass; }`
  - `const List<VideoEffect> kVideoEffects`
  - `VideoEffect? videoEffectById(String? id)`
  - `List<VideoEffect> effectsInCategory(EffectCategory category)`

- [ ] **Step 1: Write the failing tests**

```dart
void main() {
  group('catalog shape', () {
    test('ids are unique', () {
      final ids = kVideoEffects.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('an unknown id resolves to null rather than throwing', () {
      expect(videoEffectById('no_such_effect'), isNull);
      expect(videoEffectById(null), isNull);
    });

    test('every category offers at least one effect', () {
      for (final category in EffectCategory.values) {
        if (category == EffectCategory.none) continue;
        expect(effectsInCategory(category), isNotEmpty, reason: '$category');
      }
    });

    test('intensities are normalised', () {
      for (final effect in kVideoEffects) {
        expect(effect.defaultIntensity, inInclusiveRange(0, 1),
            reason: '${effect.id} must be 0..1, never pixels');
      }
    });

    test('pass counts are sane and match the multi-pass flag', () {
      for (final effect in kVideoEffects) {
        expect(effect.passCount, greaterThanOrEqualTo(1), reason: effect.id);
        expect(effect.passCount, lessThanOrEqualTo(4),
            reason: '${effect.id} exceeds MAX_EFFECT_PASSES');
        expect(effect.isMultiPass, effect.passCount > 1, reason: effect.id);
      }
    });

    test('the catalogue covers both tiers', () {
      expect(kVideoEffects.any((e) => e.isMultiPass), isTrue);
      expect(kVideoEffects.any((e) => !e.isMultiPass), isTrue);
      expect(kVideoEffects.length, greaterThanOrEqualTo(15));
    });
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

- [ ] **Step 3: Implement the catalog with ~15 effects**

Single-pass (one shader each): `vignette`, `grain`, `vhs`, `rgb_split`, `glitch`, `chromatic`,
`scanlines`, `fisheye`, `ripple`, `swirl`, `mirror`, `sharpen`, `duotone`, `light_leak`.
Multi-pass: `blur` (2), `glow` (3: bright-pass, blur, composite).

Label them as a user would name them, not as a shader author would — "Dreamy", not "Gaussian
convolution".

- [ ] **Step 4: Run tests, then the full gates, then commit**

---

### Task 3: The clip model and the timeline contract

**Files:**
- Modify: `lib/features/video_editor/models/video_segment.dart`
- Modify: `lib/features/video_editor/models/editor_timeline.dart`
- Modify: `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart`
- Test: `test/features/video_editor/models/video_segment_effect_test.dart`

**Interfaces:**
- Produces: `VideoSegment.effectId` (`String?`) and `.effectIntensity` (`double`, default from the catalog), both persisted; `EditorTimelineClip.effectId` / `.effectIntensity` serialised into the clip JSON.

- [ ] **Step 1: Write the failing tests**

Cover: both fields round-trip through `toJson`/`fromJson`; a draft written **before** this stage
loads with `effectId == null` and does not throw; `copyWith` can clear the effect (the codebase's
`clearValue` convention); a split copies the effect to both halves; and the composer serialises
both fields into the clip.

`_canMergeForPlayback` must **refuse to merge clips with different effects** — the merged media
item would take the first clip's effect for both. Test that too; it is the same rule per-clip
grades already follow.

- [ ] **Step 2: Implement, run tests, full gates, commit**

---

### Task 4: The Kotlin shader registry

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/effects/EffectShaders.kt`
- Create/modify: one `EffectPass` per effect under `gl/effects/`
- Modify: `NativeTimelineClip.kt`, `TimelinePlaybackEngine.kt`, `VideoExportEngine.kt`, `NativeTimelinePreviewManager.kt`

**Interfaces:**
- Consumes: `EffectPass`, `EffectPassChain`, `TransitionRenderer.setEffectPasses` (Stage 1); the clip JSON's `effectId`/`effectIntensity` (Task 3).
- Produces: `EffectShaders.passesFor(id: String?, intensity: Double): List<EffectPass>` — an unknown id returns an empty list, which renders unprocessed.

- [ ] **Step 1: Port the catalog to a shader registry**

`EffectShaders` mirrors `effect_catalog.dart` id for id. A catalog entry with no shader is a bug
that must show up as "no effect", never a crash.

**Programs are compiled once and cached**, never in the render path — `TransitionShaders`'
`warmUpShaders` is the precedent, and a `glLinkProgram` mid-frame is a visible stall.

- [ ] **Step 2: Resolve the clip's effect per frame, in both engines**

`TimelinePlaybackEngine` resolves the clip from the **timeline clock** (`laneClipFor(lane,
position)`), exactly as `applyLaneGrades` does — `lane.currentClip()` trails the boundary and would
apply the previous clip's effect for a beat at every cut. `VideoExportEngine` resolves it from the
clip it is already drawing.

**During a transition, the outgoing clip's effect wins for the whole window** — see the ruling
above, and comment it where the resolution happens.

Both engines must **change-guard** the call: `setEffectPasses` on every tick with an unchanged list
would rebuild the pass list 60 times a second. The renderer already ignores an unchanged colour
matrix; follow that pattern.

- [ ] **Step 3: Delete the debug hook**

`setDebugBlur` and its Dart counterpart go. They existed only until this contract landed; leaving
them is a second way to set effects that nothing maintains.

- [ ] **Step 4: Compile, then the Dart gates, then commit**

---

### Task 5: The effects panel

**Files:**
- Create: `lib/features/video_editor/widgets/panels/effects_panel.dart`
- Modify: `lib/screens/video_editor_screen.dart` (add the clip-menu tool)
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart` (`setClipEffect`)
- Test: `test/features/video_editor/widgets/effects_panel_test.dart`

- [ ] **Step 1: Add the tool to the clip's contextual menu**

Beside `filters` in the clip menu (`video_editor_screen.dart` ~line 124), since a clip's effect and
its look are siblings. `EditorTool(id: 'effects', label: 'Effects', icon: LucideIcons.sparkles)`.

- [ ] **Step 2: Build the panel**

Categories along the top, a grid of effect tiles, a leading **None** tile, and one **intensity**
slider for the selected effect. Tapping applies immediately with `defaultIntensity` — the casual
path is one tap, and the slider is there only if they want it.

Tiles show the effect's **name and icon**, not a live preview: unlike a text animation tile (which
paints a small widget), an effect tile would need a full GL render per tile. The canvas itself is
the preview — tapping shows the real thing immediately.

- [ ] **Step 3: Wire the notifier**

`setClipEffect(segmentId, effectId, intensity)` with one `saveStateForUndo()`. The slider uses the
drag-start/live-update split so a drag is one undo step.

- [ ] **Step 4: Tests, gates, commit**

Assert: the panel lists `effectsInCategory` (no hardcoded list); tapping writes `effectId` to the
selected segment; the None tile clears it; the slider writes intensity; and the tile for a stored
`effectId` shows as selected.

---

### Task 6: Device verification

- [ ] **Step 1: Build**

- [ ] **Step 2: Verify every effect**

Each of the ~15, applied to a clip: it renders in the preview, and the **export matches**. A shader
that compiles but computes wrongly looks plausible in one and wrong in the other.

- [ ] **Step 3: Verify the cases that historically break**

1. An effect on a clip **either side of a transition** — the outgoing clip's effect holds through
   the window, then the incoming clip's takes over.
2. An effect on a **photo** clip.
3. An **overlay and text** on an effected clip stay sharp.
4. A **per-clip filter and an effect together** — the grade applies per lane before the blend, the
   effect after; both should be visible.
5. A clip with **no effect** — unchanged.
6. **Undo** after applying, and after a slider drag: one step each.
7. A **draft saved before this stage** opens with no effect and no error.

- [ ] **Step 4: Update CLAUDE.md**

Record the catalog, the whole-frame-vs-per-lane distinction and the transition ruling, the
change-guard, and that unknown ids degrade to no effect.

## Stage 2 exit criteria

- [ ] ~15 effects, each verified on device in preview **and** export.
- [ ] The panel reads the catalog — no second list.
- [ ] A clip with no effect is unchanged.
- [ ] Old drafts load cleanly.
- [ ] The debug hook is gone.
- [ ] `flutter test`, `flutter analyze --no-pub` (48), `compileDebugKotlin` all pass.
