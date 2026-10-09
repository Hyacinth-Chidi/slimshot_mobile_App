# Roadmap

Current architecture and status live in `CLAUDE.md`. Approaches already tried and rejected live in
`docs/dead-ends.md` — read that before proposing a design.

The engine milestones this file used to track are done: transitions and export run natively,
overlays and text draw in GL, and `media_kit` and `pro_video_editor` are deleted (`CLAUDE.md` has
the account). What follows is the next stretch of work.

---

## Next — closing the gap with CapCut

Agreed 2026-10-09, after reviewing CapCut edits frame by frame: a tutorial for a "car crash
effect" (split, a clip lifted onto the overlay track, a tilted line mask, an AI cutout keyframed
along with the car, a crash sound) with the CapCut tools visible in it, and a cinematic travel edit
(the footage seen only through the digits of "2026" as they roll and then zoom through, dips to
black, speed ramps, three-panel strips). More reference clips are coming; this list is updated as
they are reviewed. The clips live in `samplevideo/` beside the repo, never in it.

**Work in this order**, and finish this list before taking on new reference videos. Sizes: S
small, M medium, L large.

**How every stage is built** (the user's rules, 2026-10-09):

- **Plan before code.** A short design the user approves, then test-first, then a device test
  before merge.
- **Break nothing.** A project that does not use the new feature opens, plays and exports exactly
  as before — drafts byte-identical, engine payloads unchanged — and a test pins it.
- **CapCut-simple UX.** The tool sits where a CapCut user looks for it and works the way CapCut's
  does. Reuse the sheets, panels and gestures the editor already has rather than adding a new kind
  of control. Nothing confusing, nothing that needs explaining.
- **No over-engineering.** Build the smallest version that does what CapCut's does. No options or
  generality for a case nobody has asked for.

### Stage 1 — quick wins

1. **Mask tilt (S).** `ClipMask` gains an angle, so any shape can be rotated — the tutorial tilts
   its line. One model for clips and overlays, so both get it. Rotate in an aspect-true space, as
   `rotateCanvas` does, or the mask shears on a 9:16 canvas. Both mask vec4s are full
   (`shape, cx, cy, feather` / `w, h, inverted, radius`), so the angle needs a new uniform.
   `maskCoverage` in Dart and GLSL change together.
2. **Mirror mask (S).** A band between two parallel lines — CapCut's "Mirror". A new shape
   **appended** to `ClipMaskShape`: the shader reads the shape as a number.
3. **Move clip to overlay (S–M).** One tap on the clip menu lifts a main-track clip onto the first
   free overlay lane at the same timeline time (`lane_layout.dart`), keeping what an overlay can
   carry: trim, speed, volume, opacity, mask, chroma key and the placement keyframes. One undo
   step. Open question for the design: whether the main track closes the gap it leaves.

### Stage 2 — transitions, round two (L)

4. **Port a shortlist from [GL Transitions](https://github.com/gl-transitions/gl-transitions).**
   They plug into our engine directly: their `getFromColor` / `getToColor` / `progress` / `ratio`
   are our `outgoingAt` / `incomingAt` / `uProgress` / `uCanvasAspect`, so each works on photos
   and video and exports identically. 123 of the 125 are MIT and 2 are BSD — keep the authors'
   credit in an open-source licences page. Shortlist:

   | Light | Heavier (the most CapCut-like) |
   | :--- | :--- |
   | DirectionalScaled (×4 directions), DreamyZoom, zoomInOut, Overexposure, GlitchMemories, old_tv_lost_signal, StaticFade, Bounce, Swirl, splitSlideInOut (×2), RotateScaleVanish | CrossZoom (**the zoom blur in the tutorial**), Revolve_Left (×2 directions), tangentMotionBlur, FilmBurn, DefocusBlur, StripDatamoshGlitch, Drop_Zone_Flicker, GlitchDisplace |

   Skipped: what we already have (fade, fade to colour, slide, wipes, simple zoom), slideshow-era
   shapes (heart, stars, blinds, chessboard, bow ties, puzzle), 3D for a later category (cube,
   doorway, page curl, swap), ones needing an image file (luma, displacement), ones too heavy for
   any phone (fragment, powerKaleido), and cannabisleaf.
5. **Our own CapCut signatures**, which the library lacks: **whip pan** (the tutorial's second
   transition), shake, and zoom with overshoot.
6. **Easing on transitions** — slow, very fast through the middle, slow — reusing the keyframe
   easing curves. A large part of the CapCut feel.
7. **Categories in the transition sheet** (Basic, Motion, Glitch, Light, Blur, 3D) with moving
   previews, since 30+ tiles in one grid is a wall. Existing names stay: drafts persist them.
8. **Heavy transitions on every phone.** CrossZoom reads 82 pixels per pixel drawn and FilmBurn
   100, and each read runs our full sampling helper (fit, crop, grade, mask, key). Draw each lane
   into its own texture once per frame so a transition samples plain textures. Export is never
   the limit — it is not realtime. In the preview, probe the device at runtime and fall back to a
   lighter version **and say so**. Never design around one handset.

### Stage 3 — sound effects library (M, server + app)

9. A catalogue on the SlimShot server (categories, preview, file), browsed in the audio sheet,
   downloaded once and cached, inserted at the playhead as an ordinary audio track — the fonts
   model. Every sound licensed for redistribution inside an app (CC0, or a bought pack that says
   so).

### Stage 4 — blend modes: stingers and video inside text (L)

The tutorial's flare-and-handwriting sweep over a cut is a short pre-made video laid over the seam.
The travel edit's opening shows the footage only through the letters of "2026" — in CapCut, white
text on black laid over the clip with a blend mode.

10. **Blend modes on overlays** (Screen, Add, Multiply…) in `OverlayRenderer`'s shader — possible
    now that overlays draw in GL. Screen is what makes footage shot on black usable: black
    vanishes, light remains, no alpha channel needed.
11. **Stinger packs on the server**: short loops, 720p or lower (each one costs a decoder).
12. **Dropping a stinger onto a cut**, centred on the seam. Design question: a kind of transition,
    or an overlay that snaps to the seam.
13. **Video inside text** (M–L). A clip shown only through a text's letters, with black (or the
    project background) around them, and the text keyframed to zoom through a letter into the
    full picture. Design question: a text-shaped mask on the clip (the `ClipMask` route, so every
    transition inherits it) or a text overlay with a blend mode over a black field. The zoom-through
    scales a text far past anything today's captions reach: a text rasterises at most 4096 px wide,
    which goes soft when one digit fills a 1080p frame, so the design must say how the edges stay
    sharp at that scale.

### Stage 5 — text and captions

14. **Emphasised words** (M). Tap a word to make it bigger or coloured — "DAY 6" in the tutorial.
    Carried through the glyph atlas so the export matches.
15. **Roll text animation** (M). Characters roll through other digits or letters before landing —
    "6462" spinning into "2026". Possible by hand today as a run of short texts; as a catalog
    animation the atlas must hold the in-between glyphs too, since it now holds only the final
    ones.

### Stage 6 — the larger editor features

16. **Effects track** (L). Effects as bars on a lane of their own — placed at the playhead, about a
    second long, trimmable, stackable, applying to the main video, one overlay or the whole frame —
    instead of one effect owned by each clip. Today's 39 effects move onto it.
17. **Clip In / Out / Combo animations** (M–L). Presets on the transform and opacity keyframe
    model; their home is the clip menu, with a handler. Include a one-frame white **Flash** in —
    the travel edit's panels arrive with one.
18. **Beat marks** (M–L). Detect beats in a music track, mark them on the timeline, snap cuts and
    effects to them.
19. **Split-screen layouts** (M). Pick two or three panels and drop a clip into each. The travel
    edit's three vertical strips, changing one after another, can be built today from video
    overlays with rectangle masks, but placing each by hand is fiddly. Each panel beyond the main
    clip is an overlay decoder, so the preview's decoder budget applies — a device that cannot
    play them all says so.

---

## After this list — reference videos become features, and templates

Once the stages above are done, each new reference video the user sends is reviewed the same way:
anything it needs that SlimShot lacks is added as a feature, and the edit itself can become a
**template** — the user opens a Templates page, picks one, and drops in their own videos or photos
in place of the original's. Templates need their own design when the time comes (what a
placeholder slot is, how a template's timing fits clips of a different length, where templates
are stored and served); none of it is decided yet.

---

## Parked — AI

Set aside 2026-10-09. These need a vision or audio model, so per the earlier decision each calls an
API rather than shipping a model inside the app:

- **Remove background** — auto cutout plus a brush to fix it (CapCut's Auto removal / Custom
  removal). The tutorial's key step.
- **Camera tracking** — an overlay follows something moving in the shot.
- **Auto reframe**, **Retouch** (face smoothing), **Relight**.
- **Enhance voice**, **Isolate voice**.
- **Video quality** (upscaling).

For background removal the API has to return a **cutout mask per frame**, applied in the shader
the way chroma key is. A generative image or video editor (Grok Imagine, for one) is the wrong
tool: it redraws the picture rather than cutting the original, so the person can change and
flicker between frames, and it bills per image in and out — dollars for a few seconds of video.

---

## Later

- **iOS.** Deferred until Android is stable. Mirror the same Dart timeline contract with
  AVFoundation: `AVPlayer`, `AVMutableComposition`, `AVVideoComposition`, Metal for transitions.
- **AI timeline editing.** AI should emit timeline *operations*, never render black-box video, so
  every AI edit stays undoable and previewable through the same engine.
- **The last FFmpeg in the editor** — the reverse and playback proxies. See "Known broken / not
  yet done" in `CLAUDE.md`.

---

## UX rules to protect

These come from user testing and have each been violated at least once. Treat them as acceptance
criteria, not aspirations.

- No spinner during normal split/trim playback.
- No black flash at clip boundaries.
- **No playhead moving while the video is stalled.** If playback cannot proceed, the playhead stops.
- No success notification before a result is actually usable.
- No audio disappearing silently, and no gap in audio at a transition.
- Applying or retuning a transition must not force unrelated clips to reload.
- No full preview render after an ordinary edit.
- Don't remove unfinished tools — keep them visible and implement them later.

---

## Test matrix

### Must pass

1. Import a video, play to the end, replay.
2. Split into two clips, play across the cut.
3. Split into three, trim the middle clip.
4. Reverse one clip; undo the reverse.
5. Seek while paused; scrub rapidly.
6. Play while a proxy or cache is still generating.

### Transitions

7. Two clips, 0.25s / 0.5s / 1s transitions.
8. Each of the eleven types — confirm direction on wipe and the four smooth variants.
9. Several transitions in one timeline.
10. Seek *into* the middle of a transition, forwards and backwards.
11. Change a transition's type and duration during playback.
12. A transition on a very short clip (duration clamps to 45% of the shorter neighbour).
13. Confirm the exported file matches the preview — timing first, then appearance.

### Boundary

14. Trim very close to a clip edge.
15. Split, then trim both sides.
16. Delete a clip while a cache is generating.
17. Reverse then trim the same clip, and the reverse order.
18. Close the editor while generation is active.

### Device

19. Low-end (the Unisoc target), mid-range, and a high-refresh display.
20. Long and very short videos.
21. Video with no audio; mono AAC; stereo AAC.
22. Mixed resolutions and frame rates, including variable frame rate.

### What to watch in logcat

See the decoder-hygiene table at the end of `docs/dead-ends.md`. Any of those lines appearing *at a
clip boundary* means a flush or codec rebuild is landing where it will be seen.
