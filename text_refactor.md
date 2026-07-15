# Text Overlay System Refactor Plan

This document outlines the current state of our text overlay system, its flaws, and a phased roadmap to rebuild it into a world-class text engine capable of handling advanced typography, dynamic animations, and AI auto-captions.

## 1. What's Missing / Flawed in our Current System

Our current text engine works well for simple text overlays, but it lacks the features expected in a modern video editor. Here are the core issues:

* **No Text Alignment:** All text is hardcoded to `TextAlign.center`. Users cannot left-align or right-align text, which is crucial for paragraphs or subtitles.
* **Rigid Background Plates:** Backgrounds are drawn as hard, sharp 90-degree rectangles (`canvas.drawRect`). We are missing `BorderRadius` for pill-shaped backgrounds and adjustable padding controls.
* **No Manual Text Wrapping:** Users can scale text up or down, but they cannot drag the edges of a text box to force text to wrap onto a new line. The bounding box is automatically constrained to the screen width.
* **No Dynamic Internal Animations:** Because we export text by "baking" it into a single static PNG image, we can only animate the *entire* image (e.g., Slide In, Fade Out). We cannot do internal text animations like typing effects, glowing gradients, or word-by-word karaoke highlights.
* **Missing Z-Index Controls:** Text layers are stacked in the order they are created. Users cannot reorder them ("Send to Back", "Bring to Front").
* **No Background Padding Control:** The padding around the text background is fixed and scales strictly with the text size.

## 2. The "Ash/Blurry Edges" Problem

**The Issue:** When a background color is applied to text, the edges of the background can appear fuzzy or have a grayish/ash-colored halo in the final exported video.

**The Cause:** This is caused by **Alpha Premultiplication** when FFmpeg scales or composites the image over the video. When Flutter generates a transparent PNG, fully transparent pixels are saved as `rgba(0,0,0,0)` (Transparent Black). When FFmpeg interpolates the sharp edge of the background rectangle, it blends the background color with the transparent black pixels, creating a dark halo.

**The Fix:** 
1. Use specific FFmpeg blend flags to handle straight-alpha PNGs.
2. Ensure that Flutter is rendering the background with high-quality anti-aliasing.
3. Potentially add a 1px transparent padding buffer when generating the PNG to give FFmpeg space to interpolate without bleeding into pure black.

## 3. Auto-Captions Architecture (Future)

If we add AI Speech-to-Text to auto-generate captions, the current `TextOverlayModel` will completely break. 

**Current Architecture:** 
`TextOverlayModel` holds a single `String text = "Hello world";` and exports as one static PNG.

**Auto-Caption Architecture:**
1. **The Model:** We will need a new `CaptionOverlayModel` that holds a list of word timings: `[("Hello", 0.0s, 0.5s), ("world", 0.5s, 1.0s)]`.
2. **The Preview (Flutter):** We will replace the standard `Text` widget with `RichText` and `TextSpan`. On every video frame tick, we check the current timestamp against the word timings and highlight the active word.
3. **The Export (FFmpeg):** We cannot export a single static PNG anymore. We will need to generate a "Sprite Sheet" or **multiple sequential PNGs** (one for each word highlight state) and instruct FFmpeg to swap them out at the exact timestamps using a complex `VideoComposition` overlay filter.

---

## 4. Phased Implementation Plan

We cannot build all of this at once. To ensure stability, we will refactor the text engine in three phases.

### Phase 1: Core Style Upgrades (The Low-Hanging Fruit)
This phase focuses on fixing the current UI without rewriting the complex export logic.

- [ ] Add `TextAlign` controls to the `TextStylePanel` (Left, Center, Right, Justify).
- [ ] Add `BorderRadius` to the `TextOverlayModel` to allow smooth, pill-shaped backgrounds.
- [ ] Implement `BorderRadius` in the Preview UI (`text_overlay_layer.dart`).
- [ ] Implement `BorderRadius` in the Export Renderer (`canvas.drawRRect` instead of `canvas.drawRect` in `video_editor_service.dart`).
- [ ] Fix the "Ash Edge" bug by adjusting the PNG export parameters or padding.

### Phase 2: Bounding Boxes & Z-Index
This phase gives the user more control over the physical space of the text.

- [ ] Implement draggable horizontal handles on the text selection box to manually adjust `boxWidth`.
- [ ] Ensure that dragging the horizontal handles wraps the text instead of just scaling it.
- [ ] Add "Bring Forward" / "Send Backward" buttons to the text editor to manage Z-Index/stacking order.
- [ ] Update `VideoEditorService` to respect the Z-Index during `VideoComposition`.

### Phase 3: Auto-Captions & Dynamic Text (The Engine Overhaul)
This phase is the most complex and involves rebuilding how text is exported.

- [ ] Integrate a Speech-to-Text API to generate word-level timings.
- [ ] Create the new `CaptionOverlayModel` to support `List<WordTiming>`.
- [ ] Build a custom `RichText` widget in `TextOverlayLayer` that reacts to the video's current playback position to highlight words.
- [ ] **Rewrite Text Export:** Modify `_createTextImageLayer` to generate multiple sequenced PNGs for a single caption block.
- [ ] Update the `VideoComposition` builder to handle sequenced overlays.
