# Dead Ends — approaches that failed, and must not be revived

This is a record of things that were genuinely tried in this codebase and did not work. Each entry
says what was tried, what broke, and why the current design is different.

**Read this before proposing a transition or preview architecture.** Several of these look
reasonable on paper, and two of them were shipped and reverted. The current architecture is
described in `CLAUDE.md` — this file only explains what is *not* on the table.

Platform throughout: Android, Media3/ExoPlayer, OpenGL ES 2.0. Test hardware that exposed most of
these is a Unisoc chipset — low-end, and unforgiving about decoder churn.

---

## 1. `pro_video_editor` transitions for preview

**Tried:** using PVE's `ClipTransition` as the transition engine.

**Why it failed:** PVE exposes a small fixed set of transition types with no shader control. It
cannot express wipes, directional soft wipes, or fades to a colour. It is also a rendering library,
not a preview engine — every tweak means a re-render.

**Status:** **PVE has been deleted from the project entirely.** It outlived preview only on the
export path, which is now native (`export/VideoExportEngine.kt`); the dependency,
`exportTrimmedVideo` and the FFmpeg overlay pass are gone. It must not come back for anything.

---

## 2. Per-transition rendered MP4 "region caches"

**Tried:** rendering each transition to a short MP4 with FFmpeg `xfade` and splicing those clips
into the playback playlist between the source clips.

**Why it failed:** playback had to switch decoder and audio state at exactly the boundary that must
stay smooth. Result was audio cracking and video stalls at every transition. It also meant every
transition tweak triggered a re-render, and changing one boundary could invalidate others.

**Status:** deleted. ~250 lines removed from `video_editor_screen.dart` plus the FFmpeg helpers.
Transitions are now a shader uniform — applying or retuning one costs nothing.

---

## 3. Media3 `CompositionPlayer` + `StaticOverlaySettings`

**Tried:** a two-track `Composition` (even clips on sequence A, odd on sequence B) with a custom
`VideoCompositorSettings` driving `StaticOverlaySettings` per input, behind the
`SLIMSHOT_NATIVE_TRANSITION_COMPOSITOR` flag.

**Why it failed:** `StaticOverlaySettings` can only express alpha, scale, and anchor. That is not
enough for the transition set:

- no wipe — there is no clip region or mask,
- `fadeToBlack` had to alpha *both* tracks toward transparent, which reveals the compositor's clear
  colour rather than fading through black,
- slide and push relied on `setBackgroundFrameAnchor`, whose semantics do not match the intended
  motion.

Media3 additionally documents crossfading between sequences as unsupported.

**Status:** deleted, along with the flag and `NativeTimelineTransitionCompositorSettings.kt`.
`NativeTimelineCompositionBuilder` survives **only** as the seed for native export — it has no
transition support and should not grow any. Its other consumer, the Transformer preview cache, is
gone; see entry 17.

---

## 4. `PixelCopy` snapshot of the live `SurfaceTexture`

**Tried:** at the start of a transition, pause the player, wrap the `TextureView`'s live
`SurfaceTexture` in a new `Surface`, `PixelCopy` it into a bitmap, and animate that bitmap.

**Why it failed:** wrapping the live buffer producer in a second `Surface` and releasing it destroys
ExoPlayer's producer. Logcat fills with `updateAcquireFence: Did not find frame` and the decoder
stops delivering frames — playback freezes permanently, not just for the transition. It also
allocated a full-frame `ARGB_8888` bitmap on the main thread and paused the player to do it.

**Status:** deleted entirely. Nothing may create a `Surface` from a `SurfaceTexture` that a decoder
is actively writing into.

---

## 5. GPU freeze-frame as the outgoing image

**Tried:** replacing `PixelCopy` with an FBO blit — copying the current external texture into a 2D
texture on the GPU, then holding it for the length of the transition. No readback, no bitmap, no
pause.

**Why it failed:** technically clean, but the outgoing clip is a *still image* through the whole
blend. On slide/push/fade it is nearly invisible; on a dissolve over moving footage it reads as a
stutter. A transition is a composition of two **advancing** streams, and anything less is visible.

**Status:** rejected on review. The `TransitionFrameSource` / `FrozenFrameSource` abstraction that
supported it has been deleted — do not reintroduce a pluggable "outgoing image" seam, because the
only correct source is a second live decoder.

---

## 6. Deriving the transition window from clip boundaries in Kotlin

**Tried:** computing the window as `[clipA.timelineEnd - D, clipA.timelineEnd]` on the native side.

**Why it failed:** that window sits entirely *inside* clip A. Clip B has not started, so there is
never a second image to blend toward. Every transition was structurally a no-op followed by a hard
cut. This bug hid underneath the `PixelCopy` freeze and survived the first fix.

**Status:** windows are resolved once in Dart, on the overlap model, and consumed verbatim. Kotlin
must never recompute one.

---

## 7. Truncating the outgoing clip so one decoder could walk the timeline

**Tried:** shortening clip A by the transition duration so the playback clips never overlapped, letting
a single decoder play them back to back while the renderer covered the seam.

**Why it failed:** it throws away clip A's tail — both video *and audio*. That is what produced the
audio gap at every transition. It also made the single-decoder model structurally unable to ever show
two moving streams.

**Status:** clips keep their full source ranges. They overlap in timeline time and are assigned to
different lanes.

---

## 8. Dual decoders on two `TextureView`s (the *original* attempt)

**Tried:** two `ExoPlayer`s rendering to two `TextureView`s, blended with view alpha and matrix
transforms.

**Why it failed:** decoder buffer pool exhaustion on Unisoc/MediaTek/low-end Exynos
(`Client returned a buffer it does not own`), heavy jank, and the second `TextureView` staying black.

**Important nuance — do not over-learn from this.** The failure was the *two-TextureView, view-level
compositing* design and its surface lifecycle, **not** two concurrent hardware decoders. Two decoders
feeding two OES textures into a single GL surface works on the same hardware, and is what the engine
does today. If you read this entry as "dual decoding is impossible on Android", you will revert the
architecture for the wrong reason.

---

## 9. `AndroidView` (virtual display) for the preview surface

**Tried:** exposing the preview as a Flutter `PlatformView` via `AndroidView`, with a `TextureView`
inside it.

**Why it failed:** `AndroidView` is virtual-display mode. The native view renders into a virtual
display, and Flutter then copies that display into its own texture *every frame*. Symptoms:
`Gralloc Register`/`Gralloc Free` pairs for the same buffer repeating per frame, continuous
`updateAcquireFence: Did not find frame`, and visibly sluggish playback that had nothing to do with
transitions.

**Status:** the preview is a Flutter `Texture` fed from `TextureRegistry`, which is what
`video_player` and `media_kit` do. The `PlatformView` and its factory are deleted. Do not go back.

---

## 10. `pauseAtEndOfMediaItems = true` on lane players

**Tried:** setting it so a lane could not auto-advance past its current block.

**Why it failed:** it pauses at *every* media item, and nothing resumed playback — so playback
stalled at each clip boundary. It was also unnecessary: a lane's playlist only ever contains its
current block, so it cannot run past it.

---

## 11. Unconditional drift correction

**Tried:** every tick, compare the slaved lane's position to the master clock and seek if it differs
by more than a small tolerance.

**Why it failed:** while the slaved lane is still buffering its position stands still while the
expected position keeps advancing, so drift only grows and every 16ms tick issues another seek. That
is a decoder flush storm — `flushed work; ignored`, `Discard frames from previous generation`, and
AAC buffers returned out of order.

Correcting ordinary `play()` start-up latency is also wrong: the offset is *constant* once both lanes
run, so a steady ~100ms skew is invisible across a half-second blend, while the seek that "fixes" it
flushes the decoder mid-blend and is very visible.

**Status:** correction only while the lane is genuinely playing and ready, tolerance 0.25s, hard
cooldown 600ms, and the cooldown is stamped when the lane starts so short transitions complete with
no correction at all.

---

## 12. Two clocks writing the playhead

**Tried:** a Flutter `Ticker` advancing `currentPlaybackPosition` by wall-clock delta while native
`position` events wrote the same field.

**Why it failed:** they fight. When a decoder stalls the ticker keeps advancing the playhead, so the
UI claims playback is progressing while the picture is frozen — which the UX rules explicitly forbid.

**Status:** native is the sole driver during native playback. The ticker only covers an audio-only
tail past the end of the video, where there is no native clock left.

---

## 13. Summing `segment.duration` for timeline length

**Tried:** computing total duration and clip positions by folding clip durations.

**Why it failed:** correct only until a transition exists. Transitions overlap their clips, so the
timeline is shorter than the sum by the total transition duration. Five call sites disagreed with the
composer, so the playhead drifted against the clips.

**Status:** everything goes through `lib/features/video_editor/logic/timeline/timeline_geometry.dart`,
with a test pinning it to the composer.

---

## 14. Stock `DefaultLoadControl` for local files

**Tried:** default ExoPlayer buffering.

**Why it failed:** the default `bufferForPlaybackMs` is 2500 — it waits for 2.5 seconds of buffered
media before starting. Sensible for streaming, pure startup latency for a local file, and felt as
"slow for the first few seconds".

**Status:** 200ms `bufferForPlayback` on lane players.

---

## 15. One global filmstrip spread across the source duration

**Tried:** generating `clamp(duration/2, 5, 30)` frames evenly across the whole source, laying them
in a `Row` of `Expanded` across the full strip width, then rendering that same strip inside each
clip shifted by `-sourceStart * pixelsPerSecond` and scaled by `1/speed`.

**Why it failed:** the strip was indexed by *source* time while the clips are positioned by
*timeline* time. Those agree only until something makes them diverge — and a transition does exactly
that, because the overlap pulls every later clip earlier while the picture inside it stays put. The
reported symptom was "thumbnails stop respecting the playhead after adding a transition." Reversed
clips were ignored entirely, and speed was handled by a `Transform.scale` composed in the wrong order.

Density was broken by the same root cause: a 3-minute video got 30 tiles across 9000px, so one
thumbnail was 300px wide, covered six seconds, and could be three seconds away from what the playhead
pointed at.

**Status:** replaced by per-clip, timeline-indexed `ClipFilmstrip` with fixed-width tiles. See the
filmstrip section of `CLAUDE.md`.

---

## 16. `pro_video_editor` for filmstrip thumbnails

**Tried:** `ProVideoEditor.getThumbnails` with a batch of timestamps.

**Why it failed:** one blocking batch up front, no cache, no visible-window awareness, and it kept a
PVE dependency we are trying to remove. It also forced the fixed-frame-count model above, because
asking for a batch means deciding the count in advance.

**Status:** native `MediaMetadataRetriever` with `OPTION_CLOSEST_SYNC`. Frame-exact seeking is the
wrong trade for a filmstrip — it decodes from the previous keyframe every time and is visually
indistinguishable at 50px.

---

## 17. Flattening the timeline into one MP4 as a "smooth preview cache"

**Tried:** `NativeTimelinePreviewCacheManager` — a Media3 `Transformer` pass that rendered the whole
edit to a single temp MP4, which the preview then played back as one media item. It came from the
single-decoder era, when playing several clips in sequence genuinely stuttered. A debounced
scheduler in `video_editor_screen.dart` re-ran it after every edit.

**Why it failed:**

- **It fought the engine it was supposed to help.** `parsePreviewCacheClip` replaced the composed
  timeline with one flattened clip, discarding `laneIndex` and every entry in `transitions`. Had it
  ever succeeded on a timeline with a transition, the dual-lane engine would have had nothing to
  blend.
- **It could not encode photos.** Transformer rejects `TRACK_TYPE_IMAGE` in that configuration —
  `W/ExoPlayerAssetLoader: Unsupported track type: 4` — so on any project containing a photo it
  failed, surfacing to the user as a "smooth preview cache failed" toast on **every edit**,
  including every frame of a trim drag.
- **It re-encoded the whole timeline after every edit** to buy something the two-lane engine already
  does live.

**Status:** deleted — the manager, the `preparePreviewCache`/`cancelPreviewCache` channel methods,
the `previewCache` timeline key and its parser, the `previewCache*` events, and the scheduler and
its five helpers in the screen. The service-side FFmpeg ancestors of the same idea
(`createTransitionRegionPreviewCache`, `createTimelineTransitionPreviewCache` and their filter
builders, ~375 lines) had already lost their callers and went with it.

**Do not reintroduce a flattened-render preview.** The dual-lane engine plays trims directly as
clipping configurations; a trim is a property change on a media item, not a reason to re-encode.

---

## 18. Deriving the canvas shape from the imported media

**Tried:** `VideoEditorState.canvasAsset` picked the **tallest** imported asset and the project
canvas took its aspect ratio and height. The reasoning was sound on paper — fitting a landscape clip
into a portrait frame only costs bars, while the reverse crops the subject.

**Why it failed:** the canvas is an *input* to the preview texture's size, so making it a function of
the asset pool made the texture resize at times the user never asked for anything to resize:

- asset dimensions are probed asynchronously, so `height` is 0 and then isn't — the canvas changed
  shape a moment after import,
- adding, removing or replacing any clip could change which asset was tallest,
- and each change resized the `SurfaceTexture` and **rebuilt the EGL window surface**, which is
  visible as a flash.

It also made a project non-portable: the same three files imported in a different order, or a draft
reopened after a clip was deleted, rendered to a different frame.

**Status:** replaced by a fixed `kDefaultCanvasAspectRatio` of 9:16, overridable from the crop tool —
the one place a canvas change is expected and understood. A test pins that adding clips never changes
`projectCanvasSize`.

**The general lesson:** anything the GL surface is sized from must be stable for the life of a
session unless the user explicitly changes it. Derived-from-content sizing and a cached EGL surface
do not mix.

---

## 19. Letting `ImageOutput.onDisabled` decide when a photo leaves the screen

**Tried:** the lane's photo was cleared from `ImageOutput.onDisabled`, the natural-looking pair to
`onImageAvailable`.

**Why it failed:** `onDisabled` reports the *image renderer's* lifecycle, which is not the same event
as the photo leaving the screen. In a playlist that mixes photos and video, ExoPlayer brings the
video renderer up while a photo period is still current — in a photo/photo/video timeline the
`c2.*.avc.decoder` is created a beat *before* the transition into the second photo — and disables the
image renderer at that point. The photo was therefore dropped with seconds still to run, so a photo
between other clips looked skipped: the position advanced and the media item changed correctly, but
nothing new was ever drawn.

Two things made it hard to see: the engine's own clock log was completely correct (`item=1` held the
right range), and the symptom only appears when photos and video share a timeline — photos alone
never enable a video renderer.

**Status:** `onDisabled` no longer clears anything. `applyClipSpeeds` clears the lane from the
timeline's clip list, which is the only source that actually knows whether the clip on screen is a
photo. `onImageAvailable` and `onDisabled` both log under `SlimshotEngine` when `VERBOSE`.

**The general lesson:** the timeline is the authority on what should be on screen. A player callback
tells you what the *player* is doing, and the two diverge exactly when the player is preparing
something ahead of time.

---

## 20. `ColorFiltered` for the filter sheet's preset tiles

**Tried:** each preset tile was the preview frame wrapped in
`ColorFiltered(colorFilter: ColorFilter.matrix(preset.matrix), child: Image.memory(...))`.

**Why it failed:** under Impeller — which is the default renderer on the target device — the image
renders **ungraded**. Every tile in the sheet showed the identical raw frame, so a user could not
tell NEON from DUAL from anything else without applying it and looking at the canvas. The filters
themselves were fine: the canvas grades in the GL shader, and that was correct throughout, which is
exactly what made the report confusing ("they apply but the preview doesn't show it").

**Status:** the tiles grade their own pixels. One small frame is decoded (`instantiateImageCodec`
with `targetWidth: 160`), each preset's 4×5 matrix is applied to the raw RGBA on the 0–255 scale
`ColorFilter.matrix` documents, and the result becomes a `ui.Image` shown with `RawImage`. Only the
visible category is graded, once per frame, and the images are disposed with the sheet.

**The general lesson:** when a look is correct in one place and wrong in another, compare the two
render paths before suspecting the data. Here the data — the same matrix — was right in both.

---

## 22. `SonicAudioProcessor` in the export audio path at all

**Tried:** after entry 21 narrowed it to "only when Sonic has work to do", the processor was still
built whenever a clip's sample rate differed from the export's — which is almost always, because
phone video is 48kHz and the export was 44.1kHz.

**Why it failed:** it threw `IllegalStateException` during `open()`, which the source caught and
treated as "this clip has no audio". Every clip was dropped and the file exported silent. The whole
chain downstream — decode, mix, encode, mux — was correct and never ran.

**Status:** removed. Rate conversion and speed are the same operation — both change how fast the
source is consumed per output frame — so one linear resampler covers both, with no dependency that
can throw. At the common case (source at the output rate, speed 1.0) the step is exactly 1.0 and
samples pass through untouched.

**Cost, accepted knowingly:** a speed-changed clip now shifts pitch in the export where the preview
preserves it. Worth closing later; not worth silence now.

**The general lesson:** a `catch` that maps *any* failure onto "this input has no audio" will hide
the actual fault indefinitely. Three rounds were spent downstream of a component that never ran.

---

## 21. Routing export audio through `SonicAudioProcessor` unconditionally

**Tried:** every audio source was fed through Media3's `SonicAudioProcessor`, which handles both
playback speed and sample-rate conversion — and, importantly, preserves pitch, so a sped-up clip
sounds the same exported as it did in the preview.

**Why it failed:** an `AudioProcessor` with nothing to do reports itself **inactive**, and an inactive
one silently discards whatever is queued into it and returns an empty buffer from `getOutput()`. The
ordinary clip — speed 1.0, already at the output sample rate — makes Sonic inactive, so the common
case threw every sample away and exported a silent file. Video, transitions, filters and duration
were all correct, which is what made it look like an audio-specific bug rather than a bypass mistake.

**Status:** `isActive` is checked after `configure`, and Sonic is used only when it has work to do.
Otherwise the decoder's PCM goes straight to the mixer, which is what it already wanted.

**The general lesson:** an inactive `AudioProcessor` is a no-op that *consumes*, not a pass-through.
Anything built on the `AudioProcessor` interface has to branch on `isActive()`.

---

## 23. A keyframe row under the clip, opened from the effects sheet

**Built, device-reviewed, rejected outright, deleted.** The first keyframe UI put a "Keyframe"
button on the effects panel; tapping it opened a 26px row under the selected clip holding
diamonds for that clip's **effect intensity**, and the panel's intensity slider grew a second
subject so it could edit whichever diamond was selected.

**Why it was wrong, and it is a design fault rather than an implementation one.**
`AnimatableDouble` was written general on purpose — its own header says keyframes are a *timeline*
feature that the transform, opacity and volume will all want. The UI then contradicted that: it
was reachable only from one tool panel, drew a row that existed only while an effect was applied,
and could animate exactly one number. A user wanting a Ken Burns move had no way in at all. The
plan that specified it said "a Keyframe control on the effects panel"; the implementer built what
was written.

Three structural symptoms, each of which looked like a local problem:

- **A row implies one lane per animated property**, so it could never grow to five properties
  without becoming five rows — and it claimed 26px of timeline height whenever it opened, pushing
  every lane down.
- **A stored selection** (`keyframeEditorSegmentId` + `selectedKeyframeProgress`) had to be
  cleared at five separate moments — deselecting a clip, selecting another, clearing the effect,
  changing the effect, closing the row — because three widgets with no common ancestor all acted
  on it. Every one of those clears was a bug waiting to be forgotten.
- **A slider with two subjects and a label saying which** is a symptom, not a fix. The label
  existed because the control could not otherwise be understood.

**What replaced it:** a diamond is an instant of a *clip*, pinning every animatable property at
once; the control lives in the playback bar beside the transport, where anything acting on the
whole clip belongs; and one rule in the notifier decides whether an edit writes a base value or a
keyframe, so every existing slider and gesture keyframes itself without a control of its own. The
selection is simply the playhead, so there is no stored state to clear.

**The rule this produces: a keyframe control belongs to the clip, never to a tool panel.** If a
feature wants keyframes, it does not grow a keyframe UI — it routes its writes through
`setClipProperty` and gets them.

---

## Decoder hygiene — the general lesson

Most of the remaining stutter in this app has come from **decoder flushes and codec re-creation
landing on a clip boundary**. When chasing a stutter, look for these in logcat:

| Log line | Means |
| :--- | :--- |
| `flushed work; ignored` | a seek flushed the decoder |
| `Discard frames from previous generation` | same, frames after a flush |
| `Client returned a buffer it does not own` | buffers returned across a flush |
| a new `c2.*.decoder#N` number | the codec was released and rebuilt |
| `Gralloc Register`/`Free` pairs per frame | a per-frame buffer copy somewhere |
| `updateAcquireFence: Did not find frame` | a surface/producer lifecycle problem |

Rules that follow from this:

- Never `stop()` a player just to change its media — `stop()` releases the codec.
- Never seek a player that is already at the target position.
- Create codecs at timeline-load time, not mid-playback.
- Never set an unchanged `volume` or `playbackParameters` on a tick — ExoPlayer rebuilds its
  `AudioTrack`.
- Prefer a constant small skew over a seek.
