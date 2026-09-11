# Roadmap

Current architecture and status live in `CLAUDE.md`. Approaches already tried and rejected live in
`docs/dead-ends.md` — read that before proposing a design.

Order of work is deliberate: **transitions (preview → export) → overlays → everything else.** Do not
start overlay work until transitions are signed off on device.

---

## Now — transitions

Preview is rebuilt on the dual-lane GL engine and is awaiting device sign-off.

Remaining within this milestone:

- **Export parity.** This is the weak half. `exportTrimmedVideo` routes transitions through PVE's
  `ClipTransition`, and `_mapTransitionType` only maps six types — `smoothLeft`, `smoothRight`,
  `smoothUp`, `smoothDown` and `zoomIn` all fall through to `default: dissolve`. So five of eleven
  transitions currently export as a plain crossfade regardless of what the preview showed.

  The FFmpeg `xfade` path already in `video_editor_service.dart` supports all eleven natively and
  shares the catalog's `ffmpegXfadeName`, so routing export through it is a far shorter path to
  parity than waiting for a Media3 Transformer export. The overlap timeline model was chosen to match
  `xfade` semantics exactly, so durations already agree.

- **Audio on export.** Preview now applies an equal-power crossfade across the window. The export
  filters apply `acrossfade`/`afade`, which is close but not identical. Confirm they match before
  calling parity done.

---

## In progress — timeline

Thumbnails are rebuilt: native extraction, per-clip timeline-indexed strips, fixed-width tiles,
visible-window fetching, multi-source cache. See the filmstrip section of `CLAUDE.md`.

Still to do on the timeline, all of which sit on that tile model:

- **Zoom.** `_pixelsPerSecond` is a `static const 50.0` in `ScrollableTimeline`. Make it state,
  drive it from a pinch gesture, and clamp it. `ClipFilmstrip` already recomputes its tile grid from
  `pixelsPerSecond`, so zoom mostly falls out — but the fetch debounce matters during a pinch.
- **Transition markers.** A tappable marker at each overlap that opens the transitions drawer for
  that boundary, replacing the plain black gap line. The overlap region is already known from
  `segmentTimelineStarts` plus `segmentTransitionDurations`.
- **Snapping.** Playhead and clip edges snapping to clip boundaries, transition edges, and other
  clips' edges while dragging.
- **Clip visuals.** Selection state, trim handle affordance, spacing, rounded clip corners.

## In progress — overlays

Moving photo and video overlays onto the GL renderer, so preview and export share one definition.
Text stays in Flutter for now.

**Done:** the timeline contract. `EditorTimelineOverlay` carries each overlay with its geometry
**normalised to canvas fractions**, sorted by lane so lower ones paint first.

**Why normalised — this is the important part.** The editor stores overlay position and size in
*preview-canvas pixels*: an image inside a fixed 200×200 box, a video inside 240×240, centred on the
canvas centre plus a pixel offset, with slide animations travelling a fixed 200px. Those numbers mean
different things on different screens, so the same project renders differently on a phone and a
tablet, and a draft does not survive moving between them. Export hides it today by rescaling
`previewSize → videoSize`. The composer converts to fractions at the contract boundary so the
renderer never sees a device pixel. The editing UI still works in pixels — worth fixing at the source
eventually, but the contract no longer depends on it.

**Remaining:**

- Kotlin `NativeTimelineOverlay` parsing, plus the in/out animation curves ported from
  `image_overlay_layer.dart` so native can evaluate them per frame rather than per Flutter rebuild.
- An overlay draw pass in `TransitionRenderer`: alpha blending, a transform (centre, fit-in-box,
  scale, rotation), and a texture cache keyed by path. Images decode to a `GL_TEXTURE_2D`.
- Video overlays need a decoder each, on top of the two playback lanes. Cap how many decode at once
  and only run those whose window contains the playhead — three concurrent decoders is already
  pushing the low-end target.
- Then delete the Flutter overlay layers and the FFmpeg overlay pass.

Text overlays are the awkward one: rendering them natively means matching Flutter's text layout
exactly, which will not happen by reimplementing it in `Canvas`. The route that guarantees parity is
to rasterise text **in Flutter** (`dart:ui` `Picture.toImage`) and upload the result as a texture, so
the pixels come from the same engine in preview and export.

---

## Then — retire the old stack

**`media_kit` is still load-bearing even in native mode.** Untangle before it can be removed:

- `VideoPreviewCanvas` requires a `VideoController` and gates on `player.state.duration`.
- `ScrollableTimeline` requires `_player!`.
- Video duration, pixel dimensions, and timeline thumbnails all still come from it.

Each of those has a native equivalent (`MediaMetadataRetriever`, the engine's own video-size event,
a native thumbnail extractor). Replace them one at a time, then drop the dependency.

**`pro_video_editor`** goes once export runs on FFmpeg `xfade` and/or Media3 Transformer.

---

## Later

- **Draft cache management.** Proxy files live in `getTemporaryDirectory()` but are
  referenced from draft JSON, so reopening an old draft can point at deleted files. Needs a per-draft
  cache directory, a manifest, a source fingerprint, and a cleanup policy. Validate on draft open.
- **Native export on Media3 Transformer.** `NativeTimelineCompositionBuilder` is the seed. It must
  consume the same `EditorTimeline` the preview does.
- **iOS.** Deferred until Android is stable. Mirror the same Dart timeline contract with
  AVFoundation: `AVPlayer`, `AVMutableComposition`, `AVVideoComposition`, Metal for transitions.
- **AI timeline editing.** AI should emit timeline *operations*, never render black-box video, so
  every AI edit stays undoable and previewable through the same engine.

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
