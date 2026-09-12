# Multi-pass Effect Framework (Effects Stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The renderer can render to a texture and chain shader passes, proven end to end by a real gaussian blur that looks identical in preview and export.

**Architecture:** `composite()` currently binds framebuffer 0 and draws the finished frame straight to the target. This stage lets it draw into an offscreen texture instead, run N effect passes ping-ponging between two targets, and blit the result. One effect (gaussian blur, two passes) proves the chain. Nothing else changes: with no effect the frame takes the existing path untouched.

**Tech Stack:** Kotlin, OpenGL ES 2.0, Flutter/Dart.

**Spec:** `docs/superpowers/specs/2026-09-12-clip-effects-design.md`

**Depends on:** the native export engine and `TransitionRenderer`, both device-verified.

## Global Constraints

- **minSdk 24, GLES 2.0 only.** No GLES 3 features — no `textureGrad`, no MRT, no `in/out` qualifiers. `EglCore` requests `EGL_CONTEXT_CLIENT_VERSION, 2` and that does not change here.
- **Probe at runtime, degrade loudly.** A device that cannot allocate the FBO targets must fall back to the unprocessed frame **and say so** via `exportWarning`, never silently drop the effect. `ExportCapabilities` is the precedent.
- **`composite` is shared by preview and export.** Both must take the identical path or the two diverge — the failure this codebase has hit repeatedly.
- **The renderer's lane state has exactly one writer at a time.** `exportOwnsRenderer` holds while exporting and the preview ticker returns early; anything new that writes renderer state must respect that hold.
- **No device pixels in the timeline contract.** Effect parameters are normalised or in canvas fractions.
- **GLSL compiles at runtime** — no build step catches a shader error. It surfaces as an `error` event. Device behaviour is the only real test.
- Verify with `flutter analyze --no-pub`, `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.

## Where the chain goes, and why

Verified by reading the renderer:

- `renderFrame()` → `updateLaneTextures()` → `composite(surfaceWidth, surfaceHeight)` → `swapBuffers`.
- `drawExportFrame()` → `updateLaneTextures()` → `composite(exportWidth, exportHeight)` → `overlays.draw(...)` → `swapBuffers`.
- `composite()` begins with `glBindFramebuffer(GL_FRAMEBUFFER, 0)` and `glViewport(...)`, then clears to the background and draws the lanes.

So the effect chain belongs **inside `composite`, before overlays are drawn**. Effects treat the
*clip picture*; overlays (images, video, text) sit above it and must not be recoloured or blurred
— exactly the rule that already puts `overlays.draw` outside the project grade.

## What this stage does NOT do

No effect catalog, no per-clip effect model, no UI, no timeline contract changes, and no second
effect. Blur is here as **proof the framework works**, reachable only through a debug hook, not
as a user-facing feature. Stage 2 builds the contract and the library on top.

---

### Task 1: An offscreen render target

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/RenderTarget.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/EglCore.kt`

**Interfaces:**
- Consumes: `GlUtil.createTexture2D(width, height)` and `GlUtil.checkGlError` (existing, in `EglCore.kt`).
- Produces:
  - `internal class RenderTarget` with `val textureId: Int`, `val width: Int`, `val height: Int`, `fun bind()`, `fun release()`.
  - `internal fun createRenderTarget(width: Int, height: Int): RenderTarget?` — null when the framebuffer is incomplete, never a throw.

- [ ] **Step 1: Write the class**

A colour-only FBO: one `GL_TEXTURE_2D` colour attachment, no depth, no stencil (nothing here is
3D). After attaching, **check `glCheckFramebufferStatus`** and return null on anything but
`GL_FRAMEBUFFER_COMPLETE` — a device that refuses the allocation must be detectable, not
discovered as a black frame.

`bind()` binds the framebuffer **and** sets the viewport to the target's own size. Those two
always go together, and splitting them is how a pass ends up rendering a corner of its target.

Filtering is `GL_LINEAR` with `GL_CLAMP_TO_EDGE` — a blur samples outside the frame at the
edges, and `GL_REPEAT` would wrap the opposite edge into the sample, smearing the left edge into
the right.

- [ ] **Step 2: Compile**

Run: `.\android\gradlew.bat -p android compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/RenderTarget.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/EglCore.kt
git commit -m "feat(gl): an offscreen colour render target

Checks framebuffer completeness and returns null rather than throwing,
so a device that refuses the allocation is detectable instead of
showing a black frame. CLAMP_TO_EDGE because a blur samples past the
frame's edge and REPEAT would wrap the opposite side into it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The pass chain

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/EffectPassChain.kt`

**Interfaces:**
- Consumes: `RenderTarget`, `createRenderTarget` (Task 1); `GlUtil.createProgram` (existing).
- Produces:
  - `internal interface EffectPass { val id: String; fun render(sourceTextureId: Int, target: RenderTarget?, viewportWidth: Int, viewportHeight: Int, passIndex: Int) }`
  - `internal class EffectPassChain(private val onWarning: (String) -> Unit)` with:
    - `fun resize(width: Int, height: Int): Boolean` — allocates/reallocates the two ping-pong targets; false if the device refused.
    - `fun run(sceneTextureId: Int, passes: List<EffectPass>, viewportWidth: Int, viewportHeight: Int): Int` — returns the texture id holding the result, or `sceneTextureId` unchanged when there are no passes or the chain is unavailable.
    - `fun release()`

- [ ] **Step 1: Write the chain**

Rules the implementation must follow:

- **Two targets, reused.** Allocate once per size change and ping-pong between them. Allocating
  per frame at export resolution is exactly the kind of per-frame allocation that makes a
  low-end device stutter, and two 1080×1920 RGBA targets are ~16MB — real, but bounded.
- **An odd pass count must not require a copy.** Return whichever texture the last pass wrote
  and let the caller sample it; do not blit "back" to a canonical target.
- **The final pass draws to the real target when the caller asks.** `run` writing to an FBO and
  the caller then blitting costs a full extra frame copy. Give `render` a nullable `target`:
  null means the currently-bound framebuffer, which is how the last pass reaches the screen or
  the encoder directly.
- **Cap the chain length** (`MAX_EFFECT_PASSES`, 4 is enough for blur-plus-composite and stops a
  future catalog entry from asking for twelve). Past the cap, run the first N and **warn**.
- **A failed `resize` disables the chain**: `run` returns the scene texture untouched, and the
  frame renders unprocessed. Warn once per session, not per frame — a per-frame toast is worse
  than the missing effect.

- [ ] **Step 2: Compile**

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/EffectPassChain.kt
git commit -m "feat(gl): a ping-pong effect pass chain

Two targets allocated per size change, not per frame. The last pass can
draw to the currently-bound framebuffer so reaching the screen costs no
extra copy, and an odd pass count needs no blit back. A device that
refuses the targets disables the chain and renders unprocessed, warning
once rather than every frame.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Composite through the chain

**Files:**
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/TransitionRenderer.kt`

**Interfaces:**
- Consumes: `EffectPassChain` (Task 2).
- Produces: `TransitionRenderer.setEffectPasses(passes: List<EffectPass>)` and an internal `sceneTarget` used only when passes are present.

- [ ] **Step 1: Split `composite` into scene and present**

Today `composite(viewportWidth, viewportHeight)` binds framebuffer 0, clears, and draws the
lanes. Restructure so that:

- **With no passes**, it does exactly what it does now — framebuffer 0, one draw, byte for byte
  the same path. This is the case every existing project takes, and it must not change.
- **With passes**, the lane draw goes into a scene `RenderTarget` at the viewport's size, the
  chain runs, and the final pass draws to framebuffer 0.

`viewportAspect` is set at the top of `composite` and read by the image-lane fit at draw time, so
it must reflect the **output** viewport in both branches — the scene target is the same size, so
the value does not change, but the assignment must not move inside a branch where one path skips
it.

- [ ] **Step 2: Keep the export path identical**

`drawExportFrame` calls `composite(exportWidth, exportHeight)` and then draws overlays. The chain
runs **inside** composite, so overlays still land on the finished, effected frame — which is
what keeps an overlay from being blurred along with the clip it sits on.

- [ ] **Step 3: Resize with the surface**

The scene target and the chain's targets must be reallocated when the output size changes
(`surfaceWidth/Height` for preview, `exportWidth/Height` for export). Allocating on every
`composite` call would be a per-frame allocation; allocating never means a resized preview
renders into a stale-size target. Reallocate when the requested size differs from the allocated
one.

- [ ] **Step 4: Compile**

Run: `.\android\gradlew.bat -p android compileDebugKotlin`

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/TransitionRenderer.kt
git commit -m "feat(gl): composite through the effect chain when passes are present

With no passes the frame takes the existing path unchanged, which is
every project today. With passes the lane draw goes to a scene texture,
the chain runs, and the last pass reaches the real target directly.

The chain runs inside composite, so overlays still land on the finished
frame rather than being blurred along with the clip beneath them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Gaussian blur, and the debug hook that proves it

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/effects/BlurPass.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelinePreviewManager.kt`
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart`

**Interfaces:**
- Consumes: `EffectPass` (Task 2), `TransitionRenderer.setEffectPasses` (Task 3).
- Produces: `BlurPass(radiusFraction: Double)` implementing a separable two-pass gaussian; a `setDebugBlur(radius)` channel method reaching `setEffectPasses`.

- [ ] **Step 1: Write the blur**

Separable: a horizontal pass then a vertical one. **Not** a single pass sampling an N×N grid —
that is O(N²) texture reads where separable is O(2N), and on the low-end target the difference is
the whole frame budget.

GLES 2.0 constraints that bite here:
- **Loop bounds must be compile-time constant.** A `for (int i = 0; i < uRadius; i++)` is illegal
  on ES 2.0. Use a fixed loop count and weight taps to zero beyond the requested radius, or
  compile a variant per radius bucket.
- **`uStep` is `1.0 / textureSize`**, passed in, because ES 2.0 has no `textureSize()`.
- Sample offsets must be in **texel** units of the target being sampled, which is the scene
  target's size, not the canvas's.

Blur radius arrives as a **fraction of the frame's short side**, so the same value blurs
identically at preview resolution and at 1080p export. A radius in pixels would blur the preview
far more than the file — precisely the class of preview/export mismatch this codebase keeps
hitting.

- [ ] **Step 2: Add the debug hook**

A `setDebugBlur` method on the channel, wired to `setEffectPasses`. This is **not** a feature and
must not reach the UI: it exists so this stage is verifiable on device before any effect model
exists. Say so in a comment, and note that Stage 2 replaces it with the real per-clip contract.

- [ ] **Step 3: Compile, then the Dart gates**

Run: `.\android\gradlew.bat -p android compileDebugKotlin`, then `flutter analyze --no-pub` and
`flutter test`.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/ lib/features/video_editor/services/native_timeline_preview_service.dart
git commit -m "feat(gl): a separable gaussian blur, behind a debug hook

Two passes rather than an NxN grid: O(2N) texture reads against O(N^2),
which on the low-end target is the difference between a frame budget
and a slideshow. The radius is a fraction of the short side, so the
same value blurs identically in the preview and at export resolution.

The debug hook is not a feature and does not reach the UI; it exists so
the framework is device-verifiable before the effect model exists.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Device verification

This stage's gate is that **blur works and preview matches export**, and that everything without
an effect is untouched.

- [ ] **Step 1: Build**

Run: `flutter build apk --debug`

- [ ] **Step 2: Verify, with the debug hook on**

1. A video clip blurs in the preview, smoothly, at a usable frame rate.
2. The same project exports, and the exported blur **matches the preview** — same strength, same
   softness. A radius in pixels rather than a fraction shows up here as a much stronger blur in
   the file.
3. An **overlay or text on a blurred clip stays sharp** — the chain runs before overlays, so
   anything above the clip must be unaffected.
4. Blur across a **transition** blurs the blended result, and the transition still plays.
5. A **photo clip** blurs as well as a video clip (image lanes take a different sampler).

- [ ] **Step 3: Verify nothing else changed, with the hook off**

6. A plain project plays and exports exactly as before — this is the no-passes path.
7. Filters, transitions and overlays all behave as they did.

- [ ] **Step 4: Watch for the degrade path**

If the device refuses the targets, the frame must render **unprocessed with a warning**, not
black and not crashed. Worth forcing once (temporarily request an absurd target size) to confirm
the fallback actually fires, since it is the path least likely to be exercised naturally.

- [ ] **Step 5: Update CLAUDE.md**

Record the chain, where it sits relative to overlays, the fraction-not-pixels rule, and the
GLES 2.0 constraints that shaped the blur.

## Stage 1 exit criteria

- [ ] Blur renders in preview and matches in export.
- [ ] Overlays and text on a blurred clip stay sharp.
- [ ] A project with no effect is unchanged in both preview and export.
- [ ] A refused allocation degrades loudly, not to black.
- [ ] `compileDebugKotlin`, `flutter test` and `flutter analyze --no-pub` (48) all pass.
