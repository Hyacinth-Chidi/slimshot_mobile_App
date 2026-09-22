# SlimShot AI â€” Working Notes

A Flutter video editor + media compression app (Android-first). The editor **has migrated** from a
Flutter/`media_kit`/`pro_video_editor` stack onto a native Android **Media3 + OpenGL** engine:
preview, transitions, overlays, text and export all render natively, and both packages are
deleted. The one editor dependency left to remove is FFmpeg, used now only by the two clip
proxies; FFmpeg itself stays in the app for the compression feature.

## Commands

```powershell
flutter run
flutter test
flutter analyze --no-pub
flutter build apk --debug
```

**Flutter 3.47.5 / Dart 3.13.4** (upgraded 2026-09-22 from 3.38.9, three minor versions).
Motivated by the desktop version: 3.47 makes **Impeller the default renderer on macOS, Windows
and Linux**, so starting desktop on an older framework would mean building against a renderer we
would migrate off anyway. Android gains little directly — this app's hot path is Kotlin and GL,
not Flutter's compositor — but the framework-side wins land on the editor UI and timeline.

Three things the upgrade turned up, none of them optional:

- **`lucide_icons` is abandoned and no longer compiles.** Flutter 3.44 marked `IconData` **final**
  and the package declares `class LucideIconData extends IconData`; upstream has shipped nothing
  since 0.257.0. It blocked the upgrade outright — every test failed to *load*. The icons are
  **vendored** into `lib/core/theme/lucide_icons.dart` as plain `IconData` with the font in
  `assets/fonts/lucide.ttf`. The subclass added no behaviour and nothing here ever referenced
  `LucideIconData`, so all 326 call sites across 54 files are untouched; only the import moved.
  `fontPackage` is **null**, because the font is this app's asset now and naming a package Flutter
  cannot find resolves to no glyph.
- **`android.builtInKotlin=false` and `android.newDsl=false`** were written into
  `android/gradle.properties` by Flutter's own migrator. They opt *out* of 3.44's built-in Kotlin
  and the new Gradle DSL, keeping the existing build. A real migration, deliberately deferred —
  not something to delete without doing the work.
- **`unawaited_return_in_try_block`** is a new lint, and it found two genuine faults rather than
  style noise. `image_compression_service` returned a future from inside a `try`, so a file-I/O
  failure escaped the `catch` that promises a null; the rasteriser test returned one before its
  `finally` disposed the image, freeing the pixels out from under the read. Both now `await`.

**Known and accepted:** Impeller on Android has open regressions with `Texture` widgets across
three GPU vendors (Adreno, Mali, PowerVR — the last is what this Infinix has, `IMGGralloc` in
logcat). We already shipped Impeller before this upgrade, and the opt-out
(`io.flutter.embedding.android.EnableImpeller`) is deprecated and being removed, so it is not a
long-term escape. **`Color.value` is deprecated** in favour of `toARGB32()`; ten call sites,
still functional, not yet migrated.

**`SLIMSHOT_NATIVE_PREVIEW` is gone.** The native engine is the only engine, so a plain
`flutter run` is the editor as it ships. The flag existed while `media_kit` was a live fallback;
keeping it after everything moved native would have meant shipping a second, untested preview
path behind a define nobody set.

## Direction

Flutter stays the product shell (UI, tool panels, timeline gestures, undo/redo, drafts). Native
Kotlin owns everything performance-critical (decode, composition, transitions, export).

**`pro_video_editor` and `media_kit` have both been deleted.** PVE's transition support was too
limited next to MediaCodec/Media3 and it could not take photo clips at all; media_kit was the
fallback preview, which became untested code the moment every feature was developed and verified
under the native flag. Removing media_kit also dropped its transitive native libraries
(`media_kit_libs_video`, `volume_controller`, `screen_brightness_android`) from the APK.

Still to remove: **FFmpeg from the editor** — only `createReverseProxy` and
`createClipPlaybackProxy` still use it. FFmpeg stays in the app for the compression feature,
which is its permanent home.

Order of work was **transitions (preview â†’ export) â†’ overlays â†’ text â†’ delete PVE â†’ delete
media_kit**, each signed off on device before the next.

**Read `docs/dead-ends.md` before proposing any transition or preview architecture.** It records
what was actually tried and why it failed â€” several of those approaches look reasonable on paper and
two of them were shipped and reverted. `docs/roadmap.md` has the remaining work, the UX rules, and
the test matrix.

## Architecture

### How the preview reaches Flutter

The preview is a Flutter **`Texture`**, not a PlatformView. The GL renderer draws into a
`SurfaceTexture` from `TextureRegistry`, and Flutter composites it directly.

**Do not go back to `AndroidView`.** That is virtual-display mode: a native `TextureView` renders
into a virtual display and Flutter copies that display into a texture every frame. It cost a full
extra frame copy, churned gralloc buffers per frame (`Gralloc Register`/`Free` pairs in logcat) and
flooded logs with `updateAcquireFence: Did not find frame`. Playback was visibly sluggish. This is
the same texture path `video_player` and `media_kit` use.

The texture is sized to the decoded video via `setDefaultBufferSize`, and the EGL window surface is
**rebuilt** on a size change â€” an EGL surface caches its dimensions, so a size notification alone
keeps rendering at the old size.

### Media assets

A project holds a pool of [MediaAsset]s (`VideoEditorState.assets`) and every clip references one by
`VideoSegment.assetId`. Splitting a video gives two clips over one asset; importing several files
gives several assets. **Nothing may assume a single source file.**

`VideoEditorState.sourceVideo` still exists but is only the *first* asset, kept for the draft cover
and the editor title. Anything that renders, trims or exports a clip must go through
`state.assetFor(segment)` or it will silently use the wrong file.

A `MediaAssetType.image` asset has `durationSeconds == 0` â€” a photo has no source length. Its clip
carries the on-screen duration instead, defaults to `kDefaultPhotoDurationSeconds`, and can be
stretched without bound. Kotlin turns it into a `MediaItem` with `setImageDurationMs` and **no**
`ClippingConfiguration`, so a photo clip costs no video decoder.

**A photo does not reach the video surface.** ExoPlayer decodes it with `ImageRenderer` and hands
out `Bitmap`s through `ExoPlayer.setImageOutput` â€” `setVideoSurface` never sees an image frame.

**`ImageOutput.onDisabled` must not clear the lane's photo.** It reports the image renderer's
lifecycle, not the photo leaving the screen: with photos and video in one playlist ExoPlayer enables
the video renderer â€” and disables the image renderer â€” while a photo period is still current, so
clearing there drops the photo mid-clip and it looks skipped. `applyClipSpeeds` clears the lane from
the timeline's clip list instead. Entry 19 in `docs/dead-ends.md`.

**`ExoPlayer.getCurrentPosition()` does not advance every frame on an image period.** It can hold one
value for most of a second and then jump, most visibly on a photo that precedes a video. The picture
is unaffected â€” a photo is a still â€” but the editor's playhead is driven by the position events, so
it stepped once a second between two clips that ran smoothly. `smoothedPosition` extrapolates the
**reported** playhead between the player's own samples, in timeline seconds (which advance at
wall-clock rate whatever a clip's speed is), gated on `ExoPlayer.isPlaying` so it can never move
while playback is stalled, and held monotonic so a late sample cannot jump it backwards. Everything
the engine *decides* â€” transitions, drift, completion â€” still runs on the raw clock.

**Both `ImageOutput` callbacks run on ExoPlayer's playback thread**, unlike `Player.Listener`, which
is delivered on the application thread. Nothing inside them may touch the player â€” every getter calls
`verifyApplicationThread()` and throws, and the throw surfaces as an `ExoPlaybackException`
("Unexpected runtime error") that kills the lane, so it reads as a playback failure rather than as a
threading mistake. `TransitionRenderer` is safe to call: the bitmap crosses threads through a
`@Volatile` field and is uploaded on the GL thread.
(Transformer makes the same split: images are `INPUT_TYPE_BITMAP`, video is `INPUT_TYPE_SURFACE`.)
Miss this and a photo project *plays* perfectly â€” position advances, media items change, state is
READY â€” against a black canvas.

So a lane holds **either** decoder output (an external OES texture) **or** an uploaded photo (an
ordinary `GL_TEXTURE_2D`). GLSL cannot switch sampler type at runtime, so `TransitionShaders`
generates a variant per pair of source kinds and the program cache keys on it; only the combinations
a timeline uses get compiled. Bitmaps are top-left origin, so an image lane uses a Y-flip matrix
where a video lane uses the `SurfaceTexture` transform â€” which keeps the sampling code identical.

Neighbouring clips only constrain each other's trim range when they share an asset (the split case).
Clamping across assets is meaningless and was a real bug.

**The canvas is a fixed 9:16** (`kDefaultCanvasAspectRatio`) â€” the format short-form video is
published in â€” and an explicit `selectedRatio` from the crop tool overrides it. It is **not** derived
from the imported media.

**`selectedRatio` defaults to `ratio9x16`, not `custom`.** Custom is the freeform-crop path: the
canvas takes the crop rect's shape (`projectAspectRatio`, see the canvas section) and the rect
becomes sampling geometry, so resting on it as the default distorted exports ("thin and stretched")
even when nothing was actually cropped. The crop panel opens with 9:16 active (enum declaration order is panel order, 9:16 first,
Custom last; persistence is by name so reordering was safe), and a draft that stored `custom` with a
full-frame rect â€” the old implicit default â€” reopens as 9:16 via `_ratioFromDraft`; only a real
crop rect keeps a draft on the custom path. `_resolveExportGeometry` now applies zoom/pan under
fixed ratios too, because the zoomed default used to reach legacy export only through the custom
branch.

It used to come from the tallest imported clip. That was wrong in practice: the canvas then changed
shape while assets were being probed and again whenever a clip was added or removed, and every
change resized the preview texture and rebuilt the EGL surface, which the user saw as a flash. A
fixed default also makes a project portable and predictable â€” the same edit renders the same way
regardless of what order the media happened to be imported in. Don't reintroduce a media-derived
canvas; see `docs/dead-ends.md` entry 18.

Every other clip is **fitted** into that canvas, never stretched. The fit is a `vec2` uniform per
lane (`uFitIncoming` / `uFitOutgoing`): the fraction of the canvas the clip occupies once scaled to
contain. `sampleFitted` in the shader header returns black outside that rect, so all eleven
transitions inherit letterboxing for free. `TimelinePlaybackEngine.applyLaneFits` recomputes it each
tick and the renderer ignores an unchanged value.

Importing always goes through `MediaPickerService.pickMedia()` (`pickMultipleMedia`), both to start
a project and to add to one, so permission handling is identical everywhere.

**The preview event stream is shared across service instances** (`_sharedEvents`).
`EventChannel.receiveBroadcastStream()` opens a *new* platform subscription per call while the
platform keeps only one `eventSink`, so two `NativeTimelinePreviewService` instances fight: the
second one's `onListen` replaces the sink and its `onCancel` nulls it, silencing the first â€” which is
still listening and cannot tell. Closing the export screen stopped the editor's playhead this way,
while playback itself carried on perfectly.

`MediaPickerService.enableAndroidPhotoPicker()` runs once in `main()` and **must stay there**. It
turns on the system Photo Picker â€” the gallery sheet that slides up over the app. Without it
`image_picker` falls back to an `ACTION_GET_CONTENT` intent, and a multi-select across mixed photo
*and* video types gets handled by the Documents UI, which throws the user out into the Files app.
Android 13+ uses the Photo Picker by default; 12 and below need this opt-in.

Drafts written before the pool carry a single `sourceVideoPath` and clips with no `assetId`; the
loader synthesises one asset and points every clip at it.

### The timeline contract

`VideoEditorState` â†’ `VideoEditorTimelineComposer` â†’ `EditorTimeline` â†’ JSON â†’ Kotlin.
Everything (preview, export, future AI edits) must consume this one model. Never let a consumer
invent its own interpretation of clips â€” the deleted preview cache did exactly that and it is
entry 17 in `docs/dead-ends.md`.

`EditorTimeline` carries three views, and the distinction matters:

| Field | Meaning |
| :--- | :--- |
| `videoClips` | Edit truth. **Full** source ranges â€” nothing is trimmed for a transition. Clips joined by a transition **overlap** in timeline time, and carry a `laneIndex`. |
| `playbackClips` | The merged single-decoder walk, used only when `transitions` is empty. Adjacent cuts from one file collapse into one media item. |
| `transitions` | Resolved windows (`[start, end]`, type, duration, both clip indices). |

Total duration shortens by the sum of transition durations â€” same as FFmpeg `xfade`. That is what
keeps preview and export agreeing on length.

**Kotlin must never recompute a transition window from clip boundaries**, and must never trim a clip
to make room for a transition. Both clips have to keep decoding through the whole window.

`lib/features/video_editor/logic/timeline/timeline_geometry.dart` holds the same geometry for the
Flutter side â€” `videoTimelineDuration`, `segmentTimelineStarts`, `segmentDisplayDurations`,
`segmentIndexAt`, `timelineTimeToSourceTime`. **Everything that lays out, scrubs, measures or *cuts*
the timeline must go through it.** Summing `segment.duration` is wrong the moment a transition
exists; a test pins the helper and the composer together.

**A timeline instant is not a source instant.** They coincide only for a single untrimmed clip
starting at zero, which is why code that confuses them looks correct in the simplest project and
fails everywhere else. The playhead reports *timeline* seconds; to act on the clip under it, resolve
the clip with `segmentIndexAt` and convert with `VideoSegment.sourceAtOffset` â€” the same mapping
playback and the filmstrip use, so it stays right through trims, speed and reversal. `splitAtPosition`
got this wrong and cut at the wrong point (or refused, "too close to segment edges") on any project
with more than one clip.

`segmentDisplayDurations` is what the timeline *draws*, and it is not the clip's duration. A clip
that transitions out is drawn only up to where the next clip starts, so boxes abut and the seam is
the transition. Drawing full durations makes overlapping clips stack their filmstrips and pushes the
transition marker off the seam by the transition duration â€” a test pins the boxes to tile the
timeline exactly.

### Native preview engine

`android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/`

- `NativeTimelinePreviewManager.kt` â€” MethodChannel/EventChannel bridge
  (`slimshot_ai/native_timeline_preview`). Owns the Flutter texture, renderer and engine.
- `TimelinePlaybackEngine.kt` â€” **all** playback: two lanes, the clock, prerolling, drift
  correction, audio, seeking.
- `NativeTimelineClip.kt` â€” one clip, with `laneIndex` and `sourceAt(timelineSeconds)`.
- `NativeTimelineTransitionIntent.kt` â€” deserialises the `transitions` array. Parsing only.
- `NativeTimelineCompositionBuilder.kt` â€” Media3 `Composition` builder. **Currently unreferenced**;
  kept only as the seed for native export. Sequential only, no transitions.
- `gl/EglCore.kt` â€” EGL/GL helpers.
- `gl/TransitionShaders.kt` â€” one GLSL fragment shader per transition.
- `gl/TransitionRenderer.kt` â€” GL render thread, two external textures, program cache.

### Transition rendering â€” two live streams

A transition is an **overlap between two clips**, not an animation after one ends.

Two `ExoPlayer`s decode into two OES external textures. Through the overlap **both are genuinely
playing**: the outgoing clip runs out its tail on one lane, the incoming clip plays its head on the
other, and the shader composites the two live textures by `progress`. Nothing is captured, frozen,
copied to a bitmap, or paused for the transition's benefit.

- **Clock.** One clock drives everything. The **outgoing** lane stays master for the whole window â€”
  its position is already stable and valid to its own end â€” and the incoming lane is slaved to it.
  Shader progress, the incoming lane's target position and both audio gains all derive from
  `timelinePositionSeconds()`. Mastership hands over at the window's end.
- **Lanes.** Clips alternate lanes only across a transition, so a run of plain cuts stays on one
  lane and keeps gapless playlist behaviour. Within a lane, temporally adjacent clips form a
  *block* played as one playlist; a gap between blocks is crossed by swapping media items during
  the preroll, never in the critical path.
- **Preroll** (`PREROLL_SECONDS`, 0.6s) seeks the incoming lane to its first frame and holds it
  muted, so the window opens on a real decoded picture. Lane 1 is only created when a timeline
  actually has a transition â€” a project without one never holds a second decoder.
- **Drift** above `DRIFT_TOLERANCE_SECONDS` (0.12s) is corrected by seeking; below it is left alone
  deliberately, because a decode flush looks far worse mid-blend than a few ms of skew.
- **Fallback.** If the second lane fails to come up (a device that genuinely cannot run two
  decoders), a `warning` event is emitted and the shader shows one clip â€” a hard cut, not a stall.

Shaders are linked when the timeline arrives (`warmUpShaders`), never in the render path.

### Filmstrip thumbnails

Frames come from `VideoThumbnailProvider.kt` (`MediaMetadataRetriever`, keyframe-accurate via
`OPTION_CLOSEST_SYNC`, newest-request-first on one background thread), through
`VideoThumbnailService` in Dart, which caches by `(path, timeMs)` â€” so a multi-source timeline
shares one cache without collisions.

`ClipFilmstrip` draws **one strip per clip**, and its tiles are **timeline-indexed**: tile `k`
covers a fixed slice of that clip's timeline span, and the frame it shows comes from
`VideoSegment.sourceAtOffset` â€” the same mapping playback uses. Trim, speed, reversal and
transition overlaps therefore stay aligned to the playhead for free. A clip with a prepared proxy
reads from the proxy with proxy-relative times (`isProxySource`), which is what makes a reversed
clip show its actual reversed frames.

Rules that keep it fast:

- Tiles are a **fixed pixel width**, so thumbnail density does not depend on video length.
- Only tiles inside the visible window (plus a margin) are fetched.
- Requested source times are snapped to a 200ms grid, so dragging a trim handle reuses cached
  frames instead of re-decoding the whole strip every frame of the drag.
- Paint from `peek` (synchronous); request only what came back null.

**Do not go back to a single strip of N frames spread across the source duration.** That model is
only correct while timeline position happens to equal source position â€” it broke the moment a
transition overlapped two clips â€” and it stretched one frame across several seconds.

### Canvas, crop, zoom and filters

The **canvas** is the output frame. Its shape is `projectAspectRatio` (9:16 unless the crop tool set
one) and its pixel size `projectCanvasSize`, capped at `kMaxPreviewCanvasPx` on the long side.
Neither depends on the imported media, so importing or removing a clip never resizes the texture.
The native texture is sized to the *canvas*, not to any one clip â€” sizing it to a clip makes every
lane fit wrong the moment another clip has a different shape.

Crop, zoom and pan are three controls that all narrow the same thing, so
`logic/canvas_geometry.dart` collapses them into **one source rect**
(`resolveContentRect`). It travels **per clip** as `videoClips[].contentRect` — a clip's own crop
composed inside the project's — and becomes the `uContentRectIncoming`/`uContentRectOutgoing`
uniforms (the per-clip crop section has the history; `canvas.contentRect` is still written but the
engine no longer reads it). The shader samples through it, so zoom magnifies the picture rather
than the letterbox bars. While the crop tool is open the composer deliberately sends a full-frame
rect, because the preview shows the whole frame with the crop rectangle drawn over it.

**The fit is of the content, not the frame** (`LaneFit.contentAspect`). A lane samples through its
rect, so what reaches the canvas has the frame's shape times the rect's own proportions, and the
letterbox fit has to be computed from *that* — fitting by the frame's shape while sampling through
a differently shaped rect squeezes the picture into a box of the wrong shape. Both engines and the
renderer's photo path (`imageFit`) read the one function. A full-frame or uniformly zoomed rect
gives exactly the old fit, which is how this changed nothing for an uncropped project.

**Under Custom, the canvas takes the crop's shape** (`projectAspectRatio` = 9:16 × width/height of
`projectCropRect`; full while the crop tool is open, so the whole frame shows under the handles).
The preview used to keep the texture at 9:16 and reshape only the Flutter `AspectRatio` box by the
rect — which un-stretched the picture on screen while the export, which has no box to reshape,
kept the stretched texture. One frame shape, read by the texture and the file alike, is what makes
the export match the canvas; the widget's box is now `projectAspectRatio` and nothing else.
`projectCropRect` is the one definition of "what the project shows" for the composer, the canvas
shape and the clip-crop editor.

**The letterbox background** is `canvas.backgroundType`/`backgroundColor` from the background tool,
carried through the timeline contract into the shader (`uBackground`) and `glClearColor`, so bars
are the chosen colour in preview and export alike. **`blur` is the clip blurred behind itself**
(**awaiting device verification**): each frame the renderer draws the lanes on screen
*cover-fitted* — the cover fit derived from the contain fit the engine already pushed
(`BackgroundFit.coverFitFromContain`; the pinch scale cancels out of the ratio), centred, unrotated,
fully present — into a quarter-size target, runs the effect `BlurPass` chain over it twice (four
passes, the cap), and hands the result to `backgroundAt()` in place of a photo with fit (1,1) and
**no v flip** (`uBackgroundImageFlip` is 1 for a bitmap, 0 for a texture the renderer drew).
Preview and export share it through `composite`. The tail past the last clip has nothing to blur
and shows the colour, which stays black for `blur` as the fallback; a device whose GL refuses the
quarter-size buffers falls back to that colour **and says so once** through `onWarning`.

**The picker is `BackgroundSheet`**: a photo tile, then square 64px colour tiles (the crop panel's
tile width; square because a colour needs no label), applied live, one undo step each
(`setBackground` writes type and colour together). The old "Solid Color" switch is gone — black is
the first tile, so there was nothing left to switch; the `black` type survives in the model for
existing drafts and shows as the black tile being current. The sheet stops at
`kEditorSheetPreviewFraction` (45%) of the screen and scrolls inside — a sheet at half the screen
hid the frame the user was choosing for. Filters, Effects, Transitions and the clip animations
share the fraction; the audio and sticker *libraries* keep their own taller height.

**A photo as the background** (`EditorBackgroundType.image`, **awaiting device verification** —
the shader half is GLSL). The photo tile is the grid's **first cell**, colours flowing on in the
same row — alone on a row above them it read as a separate section — and an action where the
colour tiles are values: empty, a dashed frame with an add glyph and "Photo" beneath it *inside*
the tile (a label hanging under would make the first row taller and push the second down);
chosen, the photo itself with the caption along its foot, and it keeps showing while a colour is
in use so one tap brings it back with no second trip to the picker
(`useBackgroundImage`); tapped while in use, it replaces. `importBackgroundImage` copies the picked
file into the project folder as `bg_<draftId>_<ts>` like a cover — the picker's path is a cache the
OS may reclaim, and a fresh name per pick defeats `FileImage`'s path cache — and deletes the
previous copy; the path is persisted in the draft (absent when none) and read back as `black` when
the file is gone. The contract sends `canvas.backgroundImagePath` only while the photo is in use,
so a resting photo never reaches the engine and an older build reads the payload it always did.

In the engine the photo **covers** the canvas (`BackgroundFit.cover`: the visible fraction per axis,
centred — a background with bars would need a background of its own) and is sampled by
`backgroundAt()` in the shader header wherever `incomingAt`/`outgoingAt` used to return the colour,
so every transition inherits it. It samples at `vTexCoord`, the fragment's own canvas position,
not at the uv a transition may have warped, so the photo stays put while clips move over it; and it
flips v, because bitmaps are top-left. The tail past the last clip draws the photo alone through
the passthrough program with the *reciprocal* of the cover fit — a fit above 1 samples a central
sub-rectangle — which lands on exactly the region sampled behind a clip, so the photo cannot jump
at the last cut. It rides texture unit 2 (lanes keep 0 and 1), is decoded to ≤2048px by
`StillImageDecoder` off the GL thread (synchronously for export, so the first frame does not go
out before it is pending) and uploaded at the next draw like a photo lane's bitmap; the renderer
change-guards on the path, because every `setTimeline` re-sends the canvas. A photo that will not
decode falls back to the colour **and warns**, through the same `onWarning` the lane fallback uses.
**Blur is the second tile**, beside Photo — the two "picture" fills before the flat colours — and
sets `EditorBackgroundType.blur`, one undo step; the engine side is in the canvas section above.

**Per-clip canvas transform (pinch to scale, drag to move — CapCut-style).** With a clip selected,
pinching the preview scales it about the contain-fit and a one-finger drag moves it; double-tap
resets. Stored on `VideoSegment.canvasScale/canvasOffsetX/canvasOffsetY` (canvas fractions, so a
draft renders identically on any device), through the clip JSON into `uPan*` + the fit uniforms.
Distinct from crop/zoom: crop/zoom picks what part of the **source** is shown (`uContentRect`);
this places the clip **on the canvas**. The live gesture goes through a lightweight
`setClipTransform` override channel — pushing a recomposed timeline per gesture frame would
re-prepare the players, the same mistake trimming made — and the engine's overrides are cleared by
the next `setTimeline`, which carries the committed values. The gesture is one undo step;
`_canMergeForPlayback` refuses to merge clips with different transforms; split copies the transform
to both halves.

There are **two** colour filters, and the distinction is the whole design:

| | Where it lives | Where it is applied |
| :--- | :--- | :--- |
| **Project look** | `canvas.colorMatrix`, from `state.selectedFilter` | `outputColor`, once, to the finished frame |
| **Clip look** | `videoClips[].colorMatrix`, from `VideoSegment.filterId` | `gradeClip`, per lane, **before** the blend |

The project look must not be applied per clip: that would grade a transition's two lanes separately
and then blend the results, which is a different picture. A clip's own filter must be applied per
lane, before the blend, or two clips carrying different looks could not cross-fade between them.
`gradeClip` runs on sampled texels only, never on the letterbox, or the bars would take the filter's
colour offset and stop being black.

Both use Flutter's 4Ã—5 `ColorFilter.matrix` layout with offsets on a 0â€“255 scale. GLSL ES 2.0 rejects
transposed uniform uploads, so row-major is converted to column-major in `setColorMatrix` /
`setLaneColorMatrix`. `applyLaneGrades` re-pushes each lane's grade every tick, because a lane
auto-advances through its block and would otherwise inherit the previous clip's look; the renderer
ignores an unchanged matrix.

**The two are mutually exclusive per clip.** `VideoEditorState.filterAppliesToAll` decides which the
filter sheet writes to, and switching it moves the look across rather than dropping it â€” so the
picture does not change when the switch is flipped, only what the next edit affects. Leaving both set
would grade those clips twice. On draft load the flag is **derived** (`any(s.filterId != null)`)
rather than stored: a draft holding per-clip grades must not reopen set to "apply to all", because
the next filter picked would wipe them all.

**The filter sheet's preset tiles grade their own pixels** rather than wrapping the frame in
`ColorFiltered`. Under Impeller that widget renders the image ungraded, so every tile showed the same
picture and the user could not tell the presets apart until one was applied â€” while the canvas, which
grades in the GL shader, was correct. The tiles decode one small frame and apply each preset's matrix
directly (the same 0â€“255 arithmetic `ColorFilter.matrix` documents), so a tile shows what the preset
actually does. Only the visible category is graded, once per frame.

`_canMergeForPlayback` refuses to merge two clips graded differently â€” the merged media item would
take the first clip's look for both.

**`VideoPreviewCanvas` must not re-apply any of these when a native surface is present.** It used
to wrap the texture in `Transform.scale`, an `AspectRatio` and a `ColorFiltered`, which double-graded
the image and letterboxed it twice.

### Transition catalog

`lib/features/video_editor/logic/transitions/transition_catalog.dart` is the single source of truth:
11 transitions, their labels, icons, and FFmpeg `xfade` names, plus `resolveTransitionDuration`
(clamps to 45% of the shorter neighbouring clip). The drawer, the composer, the export mapper and the
Kotlin shader registry all key off this. Adding a transition = one entry here + one shader in
`TransitionShaders.kt`.

`EditorTransition.name` is persisted into drafts and sent over the channel â€” renaming needs a
migration. Unknown names (e.g. `circleOpen` from old drafts) degrade to a hard cut, never a crash.

### Conventions

- **State:** Riverpod `StateNotifier` + `.autoDispose`. Hand-written immutable state, no `freezed`.
  `copyWith` takes `Type? value` **and** `bool clearValue = false` for every nullable field.
- **Undo:** manual. Call `notifier.saveStateForUndo()` *before* any structural edit. Transient
  preview edits (`previewVolume`, `previewSpeed`) only snapshot on `commitPreview*()`.
- **Serialisation:** hand-written `toJson`/`fromJson`, defensive on read
  (`(x as num?)?.toDouble() ?? default`).
- Colours from `AppColors`, never hard-coded. Dark theme only. Lucide icons.
- **Motion comes from `AppMotion`** (`core/theme/app_motion.dart`): Material 3 emphasized —
  380ms decelerate in, 260ms accelerate out, leaving always quicker than arriving. Sheets
  (`showEditorSheet`), the bottom-area switcher (`EditorPanelSwitcher`), the `AnimatedSize` around
  it and the timeline's compact resize all read it, because they used to run on three clocks and
  a height that lands before or after its content reads as a stutter. The sheet route fixes its
  own curve, so it takes only the durations. A panel slides in from *fully* below, like a sheet,
  not the old 40% nudge.
- **Sheets open through `showEditorSheet`** (`widgets/panels/editor_sheet.dart`), never
  `showModalBottomSheet` directly — a test scans `lib/` for strays. It paints **no barrier tint**:
  a sheet here is a set of choices *about* the picture (a curve, a filter, a transition), and
  Flutter's default `black54` dimmed the frame exactly while the user compared them. The barrier is
  still there — a tap outside still closes — it just draws nothing. It also carries the two
  settings every sheet shared (`isScrollControlled`, transparent route background).
- `unawaited(...)` for fire-and-forget. `ToastUtils.show(context, msg, isError:)` for user feedback.

## Status

### Done â€” dual-stream transition engine (device-verified)

Root causes fixed, in the order they were found. `docs/dead-ends.md` has the full account of each,
including the ones that were shipped and reverted:

1. **Transition window sat inside the outgoing clip.** It was computed as
   `[clipA.end - D, clipA.end]`, so clip B had not started and there was never a second image to
   blend toward. Windows are now resolved in Dart on the overlap model and consumed verbatim.
2. **`PixelCopy` on the live `SurfaceTexture` froze playback.** It wrapped the live buffer producer
   in a second `Surface` and released it, killing the decoder (`updateAcquireFence: Did not find
   frame`), and paused the player to do it. Gone entirely.
3. **The freeze-frame model was wrong.** A first pass replaced `PixelCopy` with a GPU FBO capture â€”
   no stall, but the outgoing clip was still a still image. Replaced with two real decoders.
4. **Four disagreeing transition lists.** Collapsed into the catalog.
5. **Two clocks wrote the playhead.** The Flutter `Ticker` advanced `currentPlaybackPosition` by
   wall-clock delta while native `position` events wrote the same field. Native is now the sole
   driver; the ticker only handles an audio-only tail past the end of the video.
6. **Duration was summed without overlaps.** Five call sites summed `segment.duration`, so the UI
   thought the timeline was longer than it was. All go through `timeline_geometry.dart` now.
7. **The preview was a virtual-display PlatformView.** `AndroidView` meant every frame was copied
   an extra time; this was the main cause of general sluggishness, unrelated to transitions. Now a
   Flutter `Texture`.
8. **`pauseAtEndOfMediaItems = true` stalled every clip boundary.** It was set on each lane player
   to stop a lane running into its next block â€” but a lane only ever holds its current block, so it
   was both unnecessary and fatal: playback halted at each media item and never resumed.
9. **Drift correction was a seek loop.** While the incoming lane was still buffering its position
   stood still while the expected position advanced, so every 16ms tick issued another seek â€”
   a decoder flush storm (`flushed work; ignored`, `Discard frames from previous generation`, AAC
   buffers returned out of order). Now gated on the lane actually playing, plus a 400ms cooldown.
10. **Volume and speed were re-applied at 60Hz.** Setting an unchanged volume every tick makes
    ExoPlayer rebuild its `AudioTrack`. Both are now change-guarded.
11. **Decoder flushes were landing on the boundary.** Four sources, all removed:
    `loadBlockFor` called `stop()` (releases the codec, so `prepare()` had to build a new one);
    the second lane's codec was first created at preroll, mid-playback (now prewarmed at
    `setTimeline`); preroll re-seeked a lane already parked on the exact frame, flushing for
    nothing on every replay; and drift correction fired on ordinary `play()` start-up latency.
    Symptoms were `flushed work; ignored`, `Discard frames from previous generation`, and new
    `c2.*.avc.decoder#N` instance numbers appearing at each boundary.
12. **`DefaultLoadControl` waited 2.5s before starting playback.** That is the stock
    `bufferForPlayback`, sensible for streaming and pure latency for a local file. Now 200ms.

### Tuning that matters on low-end hardware

`PREROLL_SECONDS` (1.2) must stay comfortably longer than a decoder flush plus first decodes, or
the cost spills into the window. `DRIFT_TOLERANCE_SECONDS` (0.25) and `DRIFT_SEEK_COOLDOWN_MS`
(600) are deliberately loose: the incoming lane always starts a few tens of ms late and that offset
then stays constant, so a steady small skew is invisible while the seek that would "fix" it flushes
the decoder mid-blend and is very visible.

Deleted: `NativeTimelineTransitionOverlayView.kt`, `NativeTimelineTransitionCompositorSettings.kt`,
`gl/TransitionFrameSource.kt`, the A/B even/odd composition builder,
`SLIMSHOT_NATIVE_TRANSITION_COMPOSITOR`, and ~250 lines of the failed FFmpeg region-cache
experiment in `video_editor_screen.dart`.

The `CompositionPlayer` + `StaticOverlaySettings` path was removed deliberately: it can only express
alpha, scale and anchor â€” not wipes, not fades to a colour, nothing shader-shaped. Don't revive it.

Device-verified by the user: transitions play smoothly, no shutter at clip boundaries, playback
starts fast. This part is considered working.

**GLSL is compiled at runtime**, so a shader error surfaces as an `error` event on the channel
rather than a build failure. `flutter analyze` and `compileDebugKotlin` cannot catch it â€” device
behaviour is the only real test of a shader change.

### Also done since

- **Filmstrip rebuilt.** Native `MediaMetadataRetriever` extraction replacing PVE, per-clip
  timeline-indexed strips with fixed-width tiles, visible-window fetching, multi-source cache. See
  the filmstrip section above. Device-verified as fast.
- **Multi-asset projects.** `MediaAsset` pool, `VideoSegment.assetId`, draft migration, per-asset
  trim clamping. See the media-assets section above.
- **Photos as clips.** `setImageDurationMs`, 3s default, freely draggable, `BitmapFactory`
  thumbnails.
- **Mixed shapes.** Canvas = tallest imported clip; everything else letterboxed via the per-lane fit
  uniform.
- **Import.** `MediaPickerService.pickMedia()` (`pickMultipleMedia`) from both the home screen card
  and the in-editor **Add** tool.
- **Trimming fixed, and the preview cache deleted.** Three separate faults made trim handles look
  dead:
  1. `ScrollableTimeline._updateTrim` clamped the drag to `widget.durationSeconds` â€” the *first
     asset's* source length, which is **0** for a photo â€” so every drag on a photo project collapsed
     to an empty range and returned early. The clamp is gone; `VideoEditorNotifier.setTrimRange`
     already clamps per-asset, which is the only place that can do it correctly.
  2. `ToastUtils` called `OverlayEntry.remove()` from an animation callback that can fire twice, and
     can fire after the screen was popped. Both assert. Now guarded by a `removed` flag and
     `entry.mounted`.
  3. The **Transformer preview cache** fired on every edit, failed on any photo
     (`Unsupported track type: 4`), and raised the "smooth preview cache failed" toast the user saw.
     Deleted outright â€” see `docs/dead-ends.md` entry 17. It also silently discarded lanes and
     transitions, so it was actively dangerous, not merely useless.

  Deleted with it: `NativeTimelinePreviewCacheManager.kt`, the `preparePreviewCache` /
  `cancelPreviewCache` channel methods, the `previewCache` timeline key, the `previewCache*` events,
  `NativePreviewCacheResult`, `NativeTransitionPreviewCacheResult`, the screen's cache scheduler and
  its five helpers, and the orphaned FFmpeg ancestors in `video_editor_service.dart`
  (`createTransitionRegionPreviewCache`, `createTimelineTransitionPreviewCache`, their filter
  builders and region helpers â€” ~375 lines with no callers).

- **Three-clip playback faults, from device testing.** All four reports had distinct causes:
  1. **A middle clip was skipped or jumped.** `setTimeline` seeked to `0.0` after rebuilding the
     lanes, so every edit pushed while paused silently moved the engine to the head of the timeline
     while the editor's playhead stayed put. It now restores the position it was at, clamped to the
     new duration.
  2. **A clip could vanish from playback entirely.** `NativeTimelineClip.fromMap` returned `null` for
     any clip with `sourceEnd <= sourceStart`, and `mapNotNull` dropped it â€” the engine then played a
     shorter timeline than the editor was drawing. A degenerate range is now clamped, never dropped.
  3. **The playhead stepped rather than moved.** `POSITION_EVENT_INTERVAL_MS` was 100ms, so the
     editor's playhead ran at 10Hz beside 60Hz video. Now 32ms (~30Hz).
  4. **Scrubbing flashed the preview.** Each gesture frame issued a full seek (a decoder flush) on
     the engine *and* a second one on the still-attached `media_kit` player, and recomposed and
     JSON-encoded the timeline twice. The engine now uses Media3's scrubbing mode, which coalesces
     seeks â€” latest target wins, and the next seek waits for a rendered frame â€” the `media_kit` seek
     is skipped in native mode, and the timeline is not recomposed during a scrub.
- **Canvas is a fixed 9:16.** See the canvas section and `docs/dead-ends.md` entry 18.
- **Split rebuilt.** It was passed the playhead's *timeline* seconds and used them as *source*
  seconds, so it cut at the wrong point on any multi-clip project and threw "too close to segment
  edges" on a trimmed one. It now resolves the clip with `segmentIndexAt` and the cut point with
  `sourceAtOffset`, cuts the clip **under the playhead** rather than the selected one, measures the
  minimum-length guard in timeline seconds, and handles three cases the old code dropped on the
  floor: a reversed clip splits into two reversed halves (the earlier half is the one nearer the
  source *end*), the outgoing transition moves to the right half instead of being invented between
  the new halves, and both halves drop the proxy that was rendered for the old range. The clip seam
  is now drawn legibly â€” the old marker was 2px of pure black on dark footage, so a split looked
  like it had not happened.

## Where we stopped â€” pick up here

### 1. In progress â€” overlays onto the GL renderer

Goal: photo and video overlays render natively so preview and export share one definition.

**Done:** the Dart contract. `EditorTimelineOverlay` + `VideoEditorTimelineComposer._composeOverlays`
serialise each overlay with geometry **normalised to canvas fractions**, sorted by lane.

The editor stores overlay geometry in *preview-canvas pixels* â€” image in a fixed 200Ã—200 box, video
in 240Ã—240, centred on `canvasCentre + position`, slide animations travelling a fixed 200px. Those
are device pixels, so a project renders differently on a phone than a tablet and a draft does not
survive moving between devices. Export hides it today by rescaling `previewSize â†’ videoSize`. The
composer converts at the boundary so the renderer never sees a device pixel. **Do not pass pixels
into GL**, or the renderer inherits the resolution dependence permanently. Fixing it at the source
(the overlay editing UI) is still worth doing later.

**Remaining:**

- Kotlin `NativeTimelineOverlay` parsing, plus the in/out animation curves ported from
  `image_overlay_layer.dart` so native evaluates them per frame rather than per Flutter rebuild.
- An overlay draw pass in `TransitionRenderer`: alpha blending, transform (centre, fit-in-box,
  scale, rotation), texture cache keyed by path. Images decode to `GL_TEXTURE_2D`.
- Video overlays need a decoder each, on top of the two playback lanes. Cap concurrency and only
  decode overlays whose window contains the playhead â€” three at once already pushes the low-end
  target.
- Then delete the Flutter overlay layers and the FFmpeg overlay pass.

**Text overlays are deliberately not in this batch.** Reimplementing Flutter's text layout in
Android `Canvas` will not match â€” font metrics, stroke and shadow all drift. The route that
guarantees parity is rasterising text **in Flutter** (`dart:ui` `Picture.toImage`) and uploading the
result as a texture, so the pixels come from the same engine in preview and export.

### 2. Done â€” native export, replacing `pro_video_editor`

Agreed direction: **export is the preview engine rendering to an encoder surface.** Point
`TransitionRenderer`'s EGL window surface at a `MediaCodec` encoder input Surface instead of the
Flutter texture, drive the clock faster than realtime, and the output is pixel-identical to the
preview because it is the same code path. Hardware encode, so fast on low-end hardware.

**Do not route export through FFmpeg `xfade`.** An earlier note in this file recommended it; that
was wrong and has been removed. PVE encodes on hardware while the FFmpeg path uses `libx264`
software encoding, so it would make every export markedly slower on exactly the target hardware â€”
and `xfade`'s transitions are a different implementation from the app's own shaders, so it would not
give parity either.

No transition needs dropping for this: the encoder only ever sees finished RGB frames, so all eleven
shaders survive. That is the opposite of the PVE path, where five silently become a dissolve.

Pieces: `MediaCodec` encoder + `MediaMuxer`; an audio path (decode/mix/encode, reusing the
equal-power crossfade rule); a non-realtime clock; progress events back to Dart.

**ExoPlayer cannot be driven faster than realtime**, so export does not reuse `TimelinePlaybackEngine`.
It needs its own per-clip `MediaCodec` decode loop â€” decode until a lane has the frame for output time
`t`, composite, stamp, swap â€” which is the standard decode-edit-encode pattern. What it *does* reuse is
the compositing: the same `TransitionShaders` programs and the same uniforms, or the exported frame is
a second implementation that will drift from the preview.

**Media3 Transformer is not the export engine, and `SurfaceAssetLoader` does not rescue it.**
`SurfaceAssetLoader` (1.5.0+) looked like the way to keep our compositor *and* Google's pipeline â€”
render our composite into a Surface Transformer encodes. Reading its source rules it out: it declares
a **single video track** (`onTrackCount(1)`) and only ever signals `signalEndOfVideoInput()`, so it
cannot carry audio. Getting audio in would need a multi-sequence `Composition` pairing a surface-fed
sequence of `C.TIME_UNSET` duration with an audio sequence, through a delegating
`AssetLoaderFactory` (the factory is global to the Transformer), on `@UnstableApi`, with no precedent
to copy. Too much unverified surface under the app's most important operation.

The usual argument for Transformer â€” encoder capability negotiation and fallback â€” is also weaker
here than it looks: **we never encode arbitrary media, only our own canvas** (fixed ratio, â‰¤1280 long
side, even dimensions). That is the safest configuration a hardware AVC encoder can be given; there
is nothing to fall back from. Fallback machinery earns its keep when re-encoding whatever the user
imported at whatever size it happens to be, which is not what export does.

What we *do* take from Media3 is `media3-muxer` â€” the standalone `Mp4Muxer`, no Transformer
involved. `media3-ui`, `media3-effect` and `media3-transformer` are gone from the build; nothing
referenced them once the Transformer route was ruled out, and `NativeTimelineCompositionBuilder.kt`
(the "seed for native export") went with them, since it was written for a composition model that
cannot draw our transitions.

**Done so far** (`android/app/src/main/kotlin/com/techfamz/slimshotai/export/`):

- `EglCore` gained `createWindowSurface(Surface)` and `setPresentationTime` â€” the encoder takes its
  timestamps from the surface, so without the latter every frame would carry the wall-clock time it
  happened to be rendered at, and a faster-than-realtime export would have a meaningless duration.
- `VideoFrameEncoder.kt` â€” hardware H.264 encoder owning the input `Surface` the GL context draws
  into, with `drainTo`.
- `ExportMuxer.kt` â€” Media3 `Mp4Muxer`, guarded so nothing is written until every track has been
  added. The video and audio encoders publish their formats at different moments; unguarded that
  throws, or drops the samples produced before the second track appeared, so a file exports missing
  its first second of audio. Samples arriving early are **held and flushed**, not dropped. Media3's
  muxer takes its own `androidx.media3.muxer.BufferInfo` and `androidx.media3.common.Format`, so the
  platform `MediaCodec.BufferInfo`/`MediaFormat` are converted at this boundary and nowhere else.
- `ExportCapabilities.kt` â€” what the device's codecs will actually agree to. `alignedEncoderSize`
  rounds the canvas **down** to the encoder's alignment (never up: growing the frame would letterbox
  differently than the preview). `canDecode` checks a clip's codec exists before export starts, so an
  HEVC/VP9/AV1 file this device cannot open is named rather than exported as a black stretch.

**Capability rule â€” this is a design constraint, not a detail.** `minSdk` is 24, so the app spans a
decade of hardware. **Never decide the pipeline's shape from one device.** Query every capability at
runtime, and where a device refuses, **degrade loudly**: fall back and tell the user. An export that
silently drops a transition breaks "no success notification before a result is actually usable" â€” the
file differs from the preview with nothing explaining why.

The fallback already has a precedent to match: when the preview engine's second lane will not come
up it emits `"Transition lane unavailable on this device"` and shows a hard cut. Export must behave
the same way, so preview and export still agree when a device forces a compromise.

`ExportCapabilities.probe()` is a **diagnostic**, not a gate â€” it reports what a given device does,
for logs and bug reports. Both the two-decoder path and the fallback get built regardless of what any
one phone reports. Filter logcat on `SlimshotExport`.

- `ExportClipDecoder.kt` â€” one clip, decoded into a lane's surface and stepped by the export clock.
  `advanceTo(targetUs)` decodes forward and renders **only** the frame that is due; earlier frames are
  decoded and dropped, which is the decode-forward half of an exact seek (`SEEK_TO_PREVIOUS_SYNC`
  then walk). A trim starting mid-GOP is the normal case, so landing on the nearest sync sample
  instead would start clips on the wrong frame. Step count per output frame is bounded so a malformed
  file cannot hang the export.

**Compositing is shared, not duplicated.** `TransitionRenderer.renderFrame` was split into
`updateLaneTextures()` + `composite(w, h)`, and export calls the same `composite`. Preview draws it to
Flutter's texture, export to the encoder's input surface â€” one implementation of what a frame looks
like, which is the whole reason an exported frame matches the previewed one. `beginExport` /
`drawExportFrame` / `endExport` swap the target; `callOnGlThread` exists because the export loop has
to run on the renderer's thread, where the EGL context lives. A non-null `exportSurface` suppresses
ordinary preview drawing, or a preview frame would take the context out from under the export.

- `VideoExportEngine.kt` â€” the non-realtime clock. For each output frame it resolves which clips are
  live, positions their decoders, sets the same per-frame lane state the preview engine sets each
  tick (fit, grade, transition progress), calls `drawExportFrame` and drains the encoder.
  **Playback must release the lane surfaces first** (`detachSurfacesForExport`): a `Surface` has one
  producer, and the export decoders write into the very same lanes ExoPlayer fills â€” which is what
  makes an exported frame identical to a previewed one.
- Channel: `exportVideo` / `cancelExport`, with `exportProgress` and `exportWarning` events. Dart
  side is `NativeTimelinePreviewService.exportVideo` returning `NativeExportResult`.

`NativeTimelineClips.fromTimeline` and `LaneFit.of` were extracted so playback and export share the
clip list and the letterbox formula rather than each having its own. Copying either would be the
easiest way to make an export differ from the preview.

- `PcmAudioSource.kt` â€” one file's audio as stereo float PCM at the export rate. Speed **and**
  sample-rate conversion both go through Media3's `SonicAudioProcessor`, the same processor ExoPlayer
  uses for playback speed. That is a parity requirement, not a convenience: Sonic preserves pitch,
  so a sped-up clip sounds in the file as it did in the preview. Resampling by reading faster would
  shift the pitch and the two would not match. A file with no audio track is normal, not an error.
- `AudioExportMixer.kt` â€” mixes over the whole timeline in blocks, so overlapping sources simply sum
  (which is what a transition and a background track both need). Gains are the preview's:
  `masterVolume * clip.volume`, with an **equal-power** `cos`/`sin` crossfade across a transition.
  Linear would sum to ~70% power mid-blend, audible as a dip at every transition.

**Audio is encoded before video.** The muxer holds samples until every track is added, and holding
video would mean buffering hundreds of megabytes where audio is a couple. Running the audio codecs to
completion first also releases them before the video decoders and encoder are created, keeping the
peak number of live codec instances down. `AudioExportMixer.prepare()` has to run before the muxer is
built, because the muxer must be told how many tracks to wait for and promising an audio track that
never arrives would leave it waiting forever, producing no file at all.

`EditorTimeline.isMuted` was added to the timeline contract â€” project mute previously existed only on
overlays, so a muted project would have exported with its sound back.

**Export was routed by capability while native could not draw everything** — overlays, then text —
so projects carrying what it could not render kept going through PVE. That routing is **gone**:
native draws all of it, `needsLegacyExport` is deleted, and **there is one export path**. The
staged approach was deliberate: switching wholesale would have silently dropped overlays from
people's exports, and holding the switch until everything landed would have left the pipeline
untested while more was built on it.

The one project native export refuses is a **reversed clip whose proxy is not prepared** — no
decoder plays backwards. With no legacy fallback left, `_exportVideo` says so and stops rather
than exporting the clip forwards.

`ExportVideoScreen` takes `nativeExportState`; non-null picks the native path. Progress comes from
`exportProgress` events and an `exportWarning` surfaces as a toast, so a file that legitimately
differs from the preview never passes as a clean success.

**Device-verified working:** filters, transitions, duration, audio (including the equal-power
crossfade), and progress. Audio and video each drive their share of the progress bar
(`AUDIO_PROGRESS_SHARE`) because the audio pass runs to completion first and the bar otherwise sat at
zero long enough to read as a freeze.

### Export — fixes applied, awaiting a device run

All three compile and pass the suite; none has been confirmed on hardware yet.

**1. A photo project exported one still for the whole duration.** `prepareLane` recorded the clip id
and nothing else, on the assumption the still was already on the lane from the preview engine's
`ImageOutput`. It is not: export runs with playback paused and the lane surfaces detached, so
whatever bitmap happened to be there when export began stayed for every frame. `loadStill` now
decodes through the shared `StillImageDecoder` — the same one the filmstrip uses, so a photo is
decoded and oriented identically in both — and calls `renderer.setLaneImage`.

**2. A two-clip project exported the second clip frozen on one frame.** `ExportClipDecoder.advanceTo`
had no "the frame on the lane is still the right one" check, so every call dequeued a fresh output
buffer and the decoder consumed exactly **one source frame per output frame** whatever the timestamps
said. Source and export rates then had to match exactly or the clip drifted: 24fps footage exported
at 30 ran a quarter fast, hit its last frame a quarter of the way through, and a spent decoder
returned false forever. 60fps footage would instead play at half speed. Guarded now with
`if (lastRenderedUs >= 0L && lastRenderedUs >= targetUs) return false`.

There is a second half to this. `releaseOutputBuffer(index, true)` only **queues** a frame — it
reaches the lane's `SurfaceTexture` on the producer's thread, and the flag the renderer gates its
texture update on is delivered to the GL thread's looper, which the export loop occupies. So export
waits on a frame **sequence** (`awaitLaneFrame`) rather than an async flag that cannot arrive.

**3. Export was capped at 720x1280.** It took its dimensions from the preview canvas, which is
clamped by `kMaxPreviewCanvasPx` so that a 4K clip is not previewed at 4K — a sound preview
optimisation that an export must not inherit. The export now sizes itself from `targetShortSidePx`,
which the existing SD/HD/2K selector already produces (default 1080).

**`targetShortSidePx` is the short side, not the height.** A 9:16 project at 1080 exports
1080x1920 and a 16:9 one exports 1920x1080 — which is what "1080p" means in either orientation.
Treating it as height would give a portrait project 608x1080. The lane textures are never
size-clamped (only the Flutter output texture is), so rendering the composite at a higher resolution
samples full source detail rather than upscaling the preview.

`ExportCapabilities.alignedEncoderSize` clamps to what the device's encoder accepts, and it must
clamp **aspect-preserving**. Encoder ranges are per-axis (commonly widths ≤1920, heights ≤1080), and
clamping each axis independently turned a portrait 1080x1920 request into a 1080x1080 square — the
shader then letterboxed clips against the 9:16 it was told about inside a square viewport, so every
clip shrank and photos visibly shrank at export. When the request does not fit, the whole frame is
scaled down uniformly. Belt and braces, the engine computes lane fits against
`encodeWidth/encodeHeight` (`renderAspect`), never against the requested canvas aspect, so even a
forced shape change letterboxes correctly. A real reduction — not alignment rounding — raises an
`exportWarning` naming both sizes, so a smaller file than the user chose is never silent.

**Image and video overlays now render natively in export** (untested on device):

- `NativeTimelineOverlay.kt` parses the composer's `overlays` array and evaluates the in/out
  animations per frame (`stateAt`) — a 1:1 port of the arithmetic in `image_overlay_layer.dart`, on
  the export clock, so a fade or slide lands identically however fast the export runs. If the
  Flutter layer's curves change, this must change with them.
- `gl/OverlayRenderer.kt` paints overlays **after** `composite`, outside the project colour grade —
  in the preview they are Flutter widgets stacked over the graded texture, so grading them in export
  would recolour them. Corners are computed on the CPU with rotation done in an aspect-true space
  (rotating in normalised coords on a non-square canvas shears). Bitmaps upload premultiplied — that
  is how Android stores them — so the blend is `ONE / ONE_MINUS_SRC_ALPHA` and opacity multiplies the
  whole texel, which also fades opaque video correctly. Two programs: `sampler2D` for stills,
  `samplerExternalOES` (+ `SurfaceTexture` matrix) for video.
- Each video overlay gets its own `ExportClipDecoder` into its own OES texture, frame-availability on
  the shared `frameThread` looper (the GL thread is blocked by the export loop — same reason the clip
  lanes do this). Decoders are released the moment the playhead leaves the overlay's window, and
  capped at `MAX_OVERLAY_DECODERS` (2, on top of the two clip lanes); an overlay past the cap is
  skipped **with a warning**, never silently.
- A video overlay's sound goes to `AudioExportMixer` as one more windowed source, the same shape as
  an imported music track.
- Overlay draws are export-only: in the preview the same overlays are live Flutter widgets, so
  drawing them in the GL pass as well would show everything twice.

**Text now exports natively** (`TextOverlayRasterizer`, **device-verified** — a photos + text
project with a tail exports correctly). Each text overlay is
rasterised by Flutter's own text engine — `TextPainter` into a `PictureRecorder` — written to a
temp PNG and appended to the composed timeline as an ordinary image overlay
(`compose(extraOverlays:)`), on `laneIndex + 1000` so it stacks above other overlays like the
preview does. Animation names map to what the preview **actually plays**: flutter_animate's stock
0.5s (the stored durations are ignored by the layer), slides travel the raster's own box (not the
image overlays' 200px), and the bare slide names have no out-variant in the layer so they export
as no out-animation.

**The text box has one definition: `logic/text_overlay_geometry.dart`.** `TextOverlayLayout.measure`
is what the preview layer lays its widget out from *and* what the rasteriser paints from — font
size, line height, outer padding, the background insets, the wrap width, the styles, and
`TextScaler.noScaling` (a phone set to "large text" must not grow the preview while the file
stays put). The layer and the rasteriser used to each carry their own copies of those constants
"mirroring each other", which is a drift waiting to happen; now neither has its own idea of a box.
`boxWidth` is the **outer** box width in reference px, applied *tight* (the text aligns inside
it), so a widened box centres and aligns identically on canvas and in the file — the old layer
widened the widget with `minWidth` but positioned it from an unwidened measurement, so a widened
box was already off-centre in the preview, and its handle seeded from the outer width then
applied `boxWidth - 32`, shrinking the box the moment it was touched.

**Text exported squashed** ("shrunk and expanded" — one-liners lost most of their height, tall
blocks most of their width; awaiting device re-verification). `OverlayRenderer.writeCorners`
contain-fits content inside a box it assumes is a **pixel square** — the image overlays' 200×200
contract — deriving the fit from the content's aspect. Text sent its raster's own rectangle as the
box, so the aspect was applied twice. `textOverlayFitBox` now sends the smallest square that
contains the raster and the fit lands on its exact size; a test pins the arithmetic against the
renderer's. **Anything else that adds a non-square overlay must do the same**, or change the
Kotlin contract — not both.

**Raster density folds in the user's pinch scale** (`effectiveRasterScale`: export density ×
`overlay.scale`, floored at 1×, capped so the PNG stays under 4096px). A text scaled 3× was
rasterised at canvas density and upscaled 3× in GL, which is exactly what made exported text look
soft next to the preview; now it is drawn at its final pixel size.

**Text exports as a glyph atlas** (Stage 1 of per-character animation; **awaiting device
verification**). `TextOverlayRasterizer.rasterizeAtlas` draws each inked character into its own
cell of one sprite sheet, and the timeline carries a `text` overlay kind holding a per-glyph
table. `OverlayRenderer.Draw` gained an exact-rect placement mode (`srcRect` + `boxRect`): a
glyph's cell already has the right shape, so contain-fitting it the way an image overlay is
fitted would letterbox a letter. Nothing animates yet — the stage's gate is that text exports
*identically* to the flat raster, which is what proves the atlas reassembles correctly before
animation is built on it.

Each cell draws the **whole text run** translated and clipped to one glyph, never characters
painted individually — kerning and ligatures mean the width of "AV" is not the width of "A"
plus "V", so per-character painting would drift from the flat raster.

**A glyph carries three rects, and conflating any two of them is a real bug that was made
once.** The first design stored a glyph's *padded* rect as both its clip and its placement.
Padding exists so a shadow or stroke is not clipped — but padded rects of neighbouring glyphs
**overlap in box space**, so reassembling them with ordinary source-over blending composites
the shared ink twice. Measured against the flat raster: a 20px shadow gained 7.4% ink area and
2396 pixels moved by more than 32/255 alpha. It looked plausible and every well-formedness test
passed; it was simply heavier than the preview, worst where glyphs are tightly spaced.

| Rect | Space | Meaning |
| :--- | :--- | :--- |
| `atlasRect` | atlas fractions | The whole padded cell. What gets **sampled**. |
| `boxRect` | text-box fractions | Where the glyph is **placed**. These tile the box and never overlap. |
| `srcRect` | fractions **of the cell** | Which sub-rectangle of the cell maps to `boxRect`. Bleed sits outside it. |

The renderer draws the full cell positioned so `srcRect` lands on `boxRect`
(`fullCellW = boxW / srcW`, `cellLeft = boxLeft - srcLeft * fullCellW`), so bleed extends past
the placement rect without any ink being drawn twice. `glyphsForAtlas` converts at the Dart
boundary with **three different denominators** — and `srcRect` is *already* a cell fraction, so
it is passed through undivided; dividing it yields values that still look plausible while
silently mis-sampling every glyph.

A residual remains and is **accepted, not a bug to chase**: adjacent glyphs' padded cells can
still overlap on canvas, so faint *bleed* re-composites even though *ink* does not. It is
measured at 100% outside `boxRect`, and the text sheet can only ever emit
`shadowBlurRadius: 8.0`. The reassembly tests gate ink hard (`60 × glyphCount` pixels, max
delta 80 — a real double-composite saturates near 255) and halo softly with per-case measured
numbers. Masking a cell to its own ink cannot work (nothing attributes rasterised pixels to a
glyph) and a max/coverage blend would break alpha for every overlay; neither is worth retrying.

**Two cases deliberately keep the flat raster**: text whose atlas exceeds the 4096px texture
limit even at floor density, and text with a **background box** (the glyph pass draws letters
only, so a background would vanish — it becomes its own quad in a later stage). Both are silent
*by design here* because the output is identical either way. **The moment animation lands, a
fallback means "no per-character animation" and must warn.** A rejected atlas still wrote its
PNG, so it is registered for deletion or an unusable atlas leaks a file per export.

`TEXT_ATLAS_MAX_PX` (4096) is separate from `OVERLAY_IMAGE_MAX_PX` (1024) on purpose: the 1024
cap is generous for a photo in a small overlay box, but decoding an atlas at 1024 would
downscale it and make exported text *blurrier* than the flat raster it replaced.

**Tests that measure text must use `kTestFontFamily`** (`test/support/test_fonts.dart`).
`GoogleFonts.getFont` throws from an async continuation nothing awaits when a font is neither
cached nor fetchable, and `flutter_test` charges that error to whichever test is running —
including ones that already passed. It cannot be caught at the call site or through
`FlutterError.onError`, so the fix is a bundled family, not a try/catch. Production
`font_utils.dart` is deliberately unchanged.

**Text animates per character** (Stage 2; **awaiting device verification**). Every animation —
typing, wave, bounce, the legacy fades and slides — is defined once in
`logic/text_animation_catalog.dart` as a **pure function** `stateAt(p, i, n)` returning a
`TextGlyphState` (opacity, offsetX/Y, scale, rotation, fillProgress). Three consumers read it:
the preview painter, the Kotlin port `TextAnimationCurves.kt` that the export uses, and later
the animation tab's preview tiles. Nothing else may describe what an animation does.

**`test/fixtures/text_animation_fixture.json` pins Dart and Kotlin together.** It is sampled
curve values both sides assert against (`dart run tool/generate_animation_fixture.dart`
regenerates it, and the copy under `android/app/src/test/resources/` must be regenerated with
it). A deliberate curve change means regenerating **and** re-running the Kotlin test; otherwise
a drifted port fails the build instead of silently shipping a file that differs from the
preview. Note what it does **not** do: it is generated from the same code it pins, so it
catches *divergence tomorrow*, never a wrong curve today. A green fixture test is not "the
animations are right".

**The Kotlin `_hashUnit` port must use `Long` + `ushr`.** `shake_loop`/`wiggle_loop` derive
jitter from a hash of the glyph index — deterministic on purpose, because `Random()` would
differ between preview and export. A literal `Int` + `>>` translation of that hash diverges on
**1425 of 1600** samples (the multipliers exceed `Int.MAX_VALUE`, and `>>` sign-propagates
where a logical shift is needed); `Long` + `ushr` gives zero divergence. This was caught by
simulating the port during review, before it was written — exactly what the fixture exists for.

**Legacy animation ids resolve by SLOT, not by id.** Drafts store `fade`, `scale` and bare
slide names, and the old `flutter_animate` layer read the same string differently per field:
`'fade'` meant fadeIn in `inAnimation` and fadeOut in `outAnimation`. So `resolveTextAnimation(id,
slot)` consults per-slot tables. Two rules that look like oversights and are not: bare in-only
ids (`slide_up`, `zoom_in`, `zoom_out`) resolve to **nothing** in the out slot, because the old
layer had no arm for them and resolving them would add an animation the user never had; and the
legacy slides and zooms carry **no opacity ramp**, because the old arms were pure
`scaleXY`/`slideX/Y` with no `fadeIn()`. New animations may fade; legacy ones must not. Both
are bug-for-bug fidelity to what saved projects already look like.

**In the preview painter, the clip must travel with the glyph transform.** Apply the transform
first, then `clipRect` — clipping in the resting position while the letter moves through it
means a slide (1.5 glyph heights) leaves its own clip and **draws nothing at all**; `zoom_out`
showed a letter's middle, `bounce_in` was cut off at its overshoot. GL has no such trap because
the cell *is* the quad, which is why `writeCorners` never had this bug and the Dart painter did.
A painter test pins it — verified by reintroducing the bug and watching two tests fail.

`textGlyphBleedPadding` is one definition the painter and the rasteriser both call: the preview
clips the rect the export samples, so two copies of that arithmetic drift into a silent
preview/export mismatch.

**Per-glyph transforms apply about the glyph's own centre, before the overlay's.** Scale and
rotation happen in glyph space, then the displacement moves that centre, then the overlay's own
scale/rotation apply about the overlay centre. Reversed, a bouncing letter swings around the
whole caption instead of hopping where it sits.

**Speed is a multiplier, not a duration.** Each animation declares a *natural* duration that may
depend on content length (typing is `0.04s × chars`, clamped 0.4–2.5s; a fade is a flat 0.5s),
and the slider scales it 0.5×–3×. `animationInDuration`/`animationOutDuration` were repurposed
to hold that multiplier, so drafts carry `animationSchema`: 0 (pre-Stage-2, any stored duration
reads as speed 1.0) or 1 (the value is a speed). The old range 0.1–2.0s and the speed range
0.5–3.0 overlap, so guessing from the value alone is not possible — the marker is what makes
the migration safe. When `in + out` exceed the overlay's span both are **compressed
proportionally**, never dropped: a dropped animation is a silent preview/export mismatch, a
fast one is self-explanatory.

**`colour_fill` and `colour_cycle_loop` exist but are not selectable** (`isSelectable: false`).
Their curves resolve and time correctly but nothing draws `fillProgress` yet, so offering them
would show an animation that does nothing *and* raise a fallback warning about it. They become
selectable when the colour-fill draw pass lands. **Blur and Neon Flicker are absent entirely** —
both need multi-pass rendering (render to texture, blur each axis, composite) and there is no
FBO framework; they belong to the effects pipeline, with the background `blur` option that
falls back to black for the same reason.

**The animation tab reads the catalog** (`text_animation_panel.dart`, **awaiting device
verification**). Three categories — In / Out / Loop — each listing
`selectableTextAnimations(category)` with a leading None tile. There is no hardcoded list: the
old `_animationsList` of seven names is deleted, so a new catalog entry reaches the UI with no
edit, and a panel test counts the grid's `itemCount` against the catalog so one cannot silently
miss the tab. Selection highlights through `textAnimationSlotValue`, which returns the
**resolved** id — a draft storing `'fade'` highlights "Fade out" in the Out tab and "Fade in" in
the In tab.

**A tile is the canvas painter, not a picture of it.** `TextAnimationTile` builds a synthetic
overlay (the user's styling, their text cut to 8 **grapheme clusters** — `substring` would split
an emoji), measures it with `TextOverlayLayout.measure`, and sweeps `positionSeconds` through
`TextOverlayPainter`. A tile that drew its own approximation would promise an animation the
export does not deliver, which is the failure the three-consumer architecture exists to prevent;
the tile tests pull the real painter out of the widget tree and fail without it. The animation
must be placed in the slot its `category` names, or `resolveTextAnimation` refuses the
cross-slot id and the tile shows a still frame.

**One clock drives every tile.** A repeating `AnimationController` on the panel, passed to each
visible tile as its `clock`; only the active category is built, so switching tabs does not leave
twenty animations running. A `Ticker` per tile would mean twenty tickers.

**The slider is Speed, not seconds.** It writes the multiplier the model has held since Stage 2
(`animationInDuration`/`animationOutDuration`, and `loopSpeed` for the Loop tab), labelled `1.4×`.
`saveStateForUndo()` fires on drag start and `updateTextOverlayLive` per change, so a drag is one
undo step.

**Only a per-glyph animation triggers the fallback warning.** Reported from a device: text with a
background box warned that its animation could not export character by character, while the
export was identical to the preview. It was identical — the animation was a fade, which is
`isPerGlyph: false`, so the flat path animates the whole quad and draws the same picture. The
gate requires `isSelectable` **and** `isPerGlyph`: only typing, wave, bounce and the like
genuinely collapse into a whole-block effect.

**Both flat-raster fallbacks now warn.** In Stage 1 they were silent because output was
identical either way; that stopped being true the moment animation landed, since a fallback now
means "this text does not animate per character". Text over the 4096px atlas limit and text with
a background box each raise an `exportWarning` naming the overlay.

If the layout, the layer's drawing or the animation curves change, the rasteriser must change
with them. `needsLegacyExport` is deleted and **every project routes to
native export** (except reversed clips without proxies, which fail `_canUseNativeTimelinePreview`
and are refused with a toast). This also fixed **photos + text failing outright**: text forced
the PVE route and PVE cannot take photo clips at all, so that combination could not export.

**Deleted with PVE** (device-verified first): the `pro_video_editor` dependency,
`exportTrimmedVideo` (~330 lines) and its animation/size helpers, `ffmpeg_overlay_builder.dart`,
`ExportVideoScreen`'s legacy branch and 15 of its 19 parameters, `exportPayloadProvider` (replaced
by `exportCanvasSizeProvider` — the canvas size is all native export needs, since it composes the
timeline from state), `prepareAndExportVideo`, and `_resolveExportGeometry` with its crop/zoom
helpers. `_isNearlyFullFrame` survives: draft migration uses it to tell a real crop from the old
implicit default. `VideoEditorService` is now **only** the two clip proxies.

**Multi-clip export: one clip's video never decoded** (**device-verified fixed** — three trimmed
clips export correctly; which clip lost had varied run to run, trimmed or not — its audio played,
its video never appeared, and the previous clip's last frame stayed on screen). Root cause: **`ExportClipDecoder.open()` flushed right after
`start()`** — open, then `seekTo` (which flushes). The MediaCodec docs are explicit that a flush
too soon after `start()` — before the first output — can lose the codec-specific data, and our
CSD arrives via `configure`, so it was never resubmittable; a decoder without SPS/PPS silently
eats the whole file producing nothing: no error, no failed open, no diagnostic. It is a race
(whether the codec consumed its config before the flush), which is why the victim moved between
runs. **`open(startUs)` now seeks the extractor before the codec ever starts — a fresh codec has
nothing to flush.** `seekTo` (with its flush) is mid-stream only, where outputs have already been
produced. The video-overlay decoder had the identical pattern and got the identical fix — this
likely also explains any frozen video overlay in past exports.

Defenses retained around it, each **toasting through `exportWarning`** so the device names the
failing mechanism without a logcat: a decoder that still produces nothing gets **one full reopen**
(`LaneState.recoveryStage`, keyed per clip so a hopeless clip cannot loop the export into
re-reading its file), then a nearest-earlier-frame rescue (covers a trim past the video track's
last sample — containers routinely outlive their video track); a decoder whose `open()` genuinely
fails retries with 20ms wall-clock backoff, gets the lane **surface rebuilt** after every 10
failures (`recreateLaneSurfaceForExport` — stale async surface disconnects are ExoPlayer-
workaround territory), and on final give-up the lane is invalidated (background, never the
previous clip's stale frame) with a toast naming the file.

Earlier, related: at a
same-lane clip switch the new decoder's `open()` can fail transiently — the surface the previous
codec just vacated reconnects only after `MediaCodec.release()`'s async disconnect completes — and
`lane.failed` was sticky, so one clip exhausting its 30 retries silently killed **every later
clip** on the lane while the renderer kept compositing the stale last frame (a shorter trimmed
clip burned fewer than 30 and only itself vanished: "the middle clip was jumped"). Failure is now
scoped per clip (`failed` resets on clip change; the attempt counter keys on
`attemptsClipId` because the retry path clears `clipId` on purpose), and failed opens back off
`OPEN_RETRY_BACKOFF_MS` (20ms) of wall time — export runs faster than realtime, so bare retries
all landed inside the same few milliseconds, before the disconnect had settled. The engine also
logs `export duration: clips end Xs, timeline says Ys -> rendering Zs` at start, so a duration
dispute between Dart and Kotlin shows up in one `SlimshotExport` line.

### Batch from device testing (fixes applied, awaiting device run)

1. **Canvas flashed on every edit.** Two causes. Overlays sat in playbackSignature although the
   preview engine never draws them (preview overlays are Flutter widgets), so every overlay edit
   pushed a whole timeline; removed from the signature. And every push rebuilt the lanes - a
   decoder re-prepare, visible as a background flash. setTimeline now has a **soft path**
   (isSamePlaybackStructure): when only per-clip properties changed (transform commit, filter,
   volume), the engine adopts the new clip list and lets the change-guarded per-tick setters apply
   it, touching no player. Only edits that change *what plays* rebuild.
2. **Overlays/audio were capped at the first asset's length.** Six clamp sites all used
   durationSeconds. Removed: overlays and audio now extend freely past the video's end
   (_kUnboundedMs), the project runs longer over the background, and totalEditedDurationProvider +
   ScrollableTimeline._totalEditedDuration count overlay ends - the latter was also still
   *summing* segment durations, the overlap bug alive in one last place.
3. **Video overlays frozen in native preview.** VideoOverlayLayer synced its players from the
   media_kit player's position stream - paused and motionless in native mode. Now driven by
   currentPlaybackPosition/isPlaying from state, which whichever engine is playing keeps current.
   Export-side second-clip freeze with an overlay: codec slots are scarce; expired overlay
   decoders are now released at the **top** of each frame (releaseExpired) before lanes open
   anything, and a failed lane open **retries** (MAX_DECODER_OPEN_ATTEMPTS) instead of failing
   the lane forever.
4. **Photos shook at boundaries.** The fit came from lane.currentClip(), which lags the bitmap:
   ExoPlayer can deliver the next photo before currentMediaItemIndex moves, so the new photo wore
   the previous clip's fit for a beat. First fix: the fit derived from the delivered bitmap's own
   pixels (an engine-side Lane.imageAspect) - the pixels are the authority, not clip metadata.
   **Superseded by item 10**: that still pushed the fit on the main-thread tick while the GL draw
   raced ahead of it, so a smaller flash survived; the fit is now derived inside the renderer at
   draw time.
5. **Playhead no longer snaps to 0 at the end.** It parks at the end; play from there restarts.
   completed hands over to the ticker when audio/overlays outlast the video, so the tail plays
   over the background instead of stopping dead at the last video frame.
6. **Lane order flipped.** The filmstrip sits directly under the ruler; overlay/audio lanes stack
   *below* it (lane 0 nearest), so additions stop pushing the video track around.
7. **Two follow-up faults from the first device run of this batch.** The soft update replaced
   `clips` but not the lanes' *blocks* — and every per-tick reader (fits, grades, volumes) goes
   through `lane.currentClip()`, which reads the blocks — so a committed pinch snapped back to the
   old objects' scale. The soft path now remaps each block's clips to the new instances by id. And
   the engine kept emitting its parked end position at ~30Hz after `completed`, dragging the
   playhead back to the video end while the ticker walked the tail; `sendPositionEventIfDue` now
   stops with the engine, and the screen ignores engine positions while `_isDrivingTail`. The
   "exported without sound" toast is log-only for projects with nothing audible — a photos-only
   export is legitimately silent.
8. **Photos flashed between two sizes in the exported file** (second device run; awaiting
   re-verification). The engine's ticker never stops — `pause()` does not touch it — so through the
   whole export the paused engine kept pushing `applyLaneFits`/`applyLaneGrades`/`driveTransitions`
   for the clip under the *paused playhead* into the same renderer lanes the export engine was
   setting per output frame for *its* clock. Two unsynchronized writers; each encoded frame took
   whichever fit landed last. Invisible until two clips carried different fits — pinch-zoomed
   photos made the disagreement maximal. Same fight also hit per-clip grades and could clear the
   export's transition draw mid-blend. Fix: `exportOwnsRenderer` — set in
   `detachSurfacesForExport`, cleared in `reattachSurfacesAfterExport`, and `tick()` returns while
   it holds (the runnable keeps rescheduling, so the ticker resumes by itself). **The renderer's
   lane state has exactly one writer at a time**; anything new that writes fits/grades/transition
   state must respect the export hold.
9. **Export cut off where the video ended, chopping a longer audio track** (awaiting device run).
   The preview already plays the tail — the ticker walks the playhead past the last clip over the
   background — but `VideoExportEngine` took its duration from `clips.maxOf { timelineEnd }`, video
   only. Now the composer's `durationSeconds` is the true project end (`_projectEndSeconds`: video,
   audio tracks, and every overlay type — a new test pins the overlay case), the manager passes it
   through as `Request.totalDurationSeconds`, and the engine runs to
   `max(videoEnd, totalDurationSeconds)`. Frames past the video end draw **no lane**
   (`setActiveLane(NO_ACTIVE_LANE)` = -1; composite then paints background + live overlays only),
   and the clip decoders are released at the tail's first frame so their codec slots are free for
   overlay decoders. The audio mixer already took the full duration, so the tail carries the music.
   The preview's tail background was also changed from forced black to the **project background**
   (`video_preview_canvas.dart`), so tail frames look the same on canvas and in the file.
10. **Photos still flashed at plain cuts in the preview** (awaiting device run). Item 4's fix moved
    the aspect to the delivered bitmap but still pushed the *fit* from the main-thread tick — and
    `setLaneImage` triggers a GL draw immediately, so the new bitmap was composited with the old
    clip's fit for at least one frame (up to `TICK_INTERVAL_MS` + scheduling) at every cut where
    the aspects differ, then snapped right. **A photo's contain fit is now derived inside the
    renderer at draw time** from the uploaded bitmap's own dimensions (`Lane.imageWidth/Height`,
    recorded in `uploadPendingImage` on the GL thread) against the viewport actually being drawn
    (`viewportAspect`, set at the top of `composite` — canvas texture in preview, encoder surface
    in export, so both letterbox identically). Engine and export push only the clip's pinch
    scale/pan for image lanes via `setLaneImageTransform`; `setLaneFit` remains the video-lane
    path. The engine-side and export-side `imageAspect` bookkeeping is deleted.
    **Follow-up in the same batch:** per-clip *transform* and *grade* used to resolve through
    `lane.currentClip()` = `player.currentMediaItemIndex`, which trails the boundary (and trails
    hard mid-seek), so adjacent clips pinched or graded differently wore the neighbour's values
    for a beat at every cut. `applyLaneFits`/`applyLaneGrades` now resolve the lane's clip from
    the **timeline clock** (`laneClipFor(lane, position)`: containing clip, else the upcoming one
    so a prerolled lane wears its own state before the first blended frame, else the last past
    one) — the timeline is the authority on what is on screen, dead-ends entry 19.
    `applyClipSpeeds`/`applyAudio` deliberately stay on the player index: speed and volume must
    follow what the *player* is doing. Residual skew is now ≤ one 16ms tick; fully pairing
    metadata with the bitmap delivery would need mapping `presentationTimeUs` to a clip, which is
    unverified API territory and not worth the risk.

### Per-clip effects — the multi-pass framework and 39 effects

**Awaiting device verification** beyond the four already checked (`fisheye` perfect, `vignette`
working after a reshape, `glow` and `blur` fixed but unseen). Spec:
`docs/superpowers/specs/2026-09-12-clip-effects-design.md`.

A clip carries **one** effect (`VideoSegment.effectId` + `effectIntensity`), chosen from the
**clip's contextual menu** beside Filters, travelling the same route a per-clip filter does:
`VideoSegment` → composer → clip JSON → `NativeTimelineClip` → `EffectShaders` → the pass chain.
`logic/effects/effect_catalog.dart` is the single source of truth and the panel reads it — there
is no second list, and a test counts the grid's `itemCount` against the catalog so a new entry
cannot silently miss the UI.

**The renderer was single-pass, and that is why blur never existed.** `composite()` bound
framebuffer 0 and drew straight to the output, so any effect needing the frame *back* — blur,
glow, bloom — was impossible; this is also why the background tool's `blur` option falls back to
black. `gl/RenderTarget.kt` and `gl/EffectPassChain.kt` add render-to-texture and a ping-pong
chain (`MAX_EFFECT_PASSES` 4, two targets allocated per size change and reused). **With no
passes the frame takes exactly the old path** — the diff that introduced this removed two lines
and both reappear in the no-passes branch.

**The pass budget is per *frame*, and a frame draws one clip.** `applyClipEffect` resolves a
single clip from the timeline position — the outgoing one inside a transition window, the master
lane's otherwise — and applies only that clip's effect. So a project of any length with a
different effect on every clip costs nothing extra: clip 4's blur is never drawn while clip 1 is
on screen, and even a transition draws **one** effect because the outgoing clip owns the window.
The budget binds only when a *single* clip stacks several effects, which is what makes stacking
the feature that has to reckon with it.

`MAX_EFFECT_PASSES` is a **correctness bound, not a performance one** — enough for a separable
blur plus a composite, and a hard stop on a future catalog entry quietly asking for twelve.
Whether a given device sustains four is a different question, and the answer is the standing rule:
**probe at runtime and degrade loudly**, never assume from one handset. 36 of the 39 effects are
single-pass, so the cap is reached by stacking blur-class effects, not ordinary ones.

**The chain runs inside `composite`, before overlays.** That is what keeps text or a sticker on a
blurred clip **sharp**: effects treat the clip picture, overlays sit above it. Do not move the
chain out or the overlay draw in.

**A grade is per-lane, an effect is whole-frame, and that asymmetry decides transitions.**
`applyLaneGrades` sets a colour matrix per lane *before* the blend, so two clips can cross-fade
between different looks. An effect pass runs *after* compositing, on the finished frame — so a
transition between two differently-effected clips has one frame and two answers. **The outgoing
clip's effect owns the whole window**, matching the existing rule that the outgoing lane is
transition master. Rendering each lane into its own target would be more correct and doubles both
targets and passes on exactly the hardware transitions already strain. Documented at the
resolution site in both engines, because it reads as an oversight otherwise.

**`uProgress` is the clip's own 0..1 position, from the timeline clock.** Effects began with no
notion of time, which made every *intro* effect impossible — a cinema zoom or a shutter reveal is
nothing but a function of time. It is resolved through `NativeTimelineClip.effectProgressAt` in
both engines, never a frame counter or `System.nanoTime`: export runs faster than realtime, so
anything self-timed renders differently in the file than on the canvas. `VideoEffect.introSeconds`
makes an effect *timed* — progress runs over that opening window and then sits at 1 — while a
static look gets whole-clip progress and ignores it. A zero-length window returns 1.0, not a
division by zero, or a `fade_in` would park on black.

**Intensity and progress are `@Volatile` uniforms uploaded per draw, never constructor
arguments.** Baking intensity into a pass meant `passesFor` rebuilt and re-linked the programs on
every change, so dragging the slider would have linked a program per frame. `IntensityControlled`
and `ProgressControlled` are the interfaces; a pass that forgets one ships a slider that silently
does nothing. `ClipEffectController` rebuilds on **id** change only.

**`callOnGlThread` runs inline when already on the GL thread.** Export froze at ~15% with no
error: `runVideo` already runs inside `callOnGlThread`, and per output frame it resolved the
clip's effect, which hopped to the GL thread *again* — posting a block behind the call waiting
for it. The thread blocked on itself at the first frame whose clip carried an effect. A deadlock
is not a failure anything can report, which is why it presented as a frozen progress bar.

**Two device-found shader lessons worth not repeating:**

- **A vignette must not correct for aspect.** Correcting put the farthest points on the long
  *edges*, so on a 9:16 clip the darkening read as a band across the top. A lens darkens toward
  its own corners: plain UV distance normalised to the half-diagonal gives corner 1.0 and edge
  midpoint 0.707 on any canvas shape.
- **A bloom must be blurred at reduced resolution.** Glow was invisible because the halo was ~8px
  at 1080p. The fix is a half-res bloom — the same 16 taps reaching twice as far — **not** a
  raised radius cap, which trades invisibility for visible banding.

**Randomness in a shader must be a deterministic hash**, of UV and of `uProgress` where it should
move. Never `Random()`, never a frame counter. And **`mediump` overflows around n≈515** in
`fract(sin(n*127.1)*…)`: hash seeds must be folded to 0..1 per term rather than summed and
wrapped at the end, or grain bands flatly on some GPUs and not others.

**`BlurPass` holds the only loop in the codebase** — 16 taps indexing `uWeights[i]`. Spec-legal on
ES 2.0 (Appendix A constant-index-expression) but with no driver precedent here, so it is
**unverified on hardware**. Every other shader deliberately avoids loops. If `blur` renders
unchanged footage on a device, that loop is the first suspect and the fallback is unrolling it.

### Animatable parameters — envelopes and keyframes

**Awaiting device verification.** An effect's intensity is an `AnimatableDouble`
(`logic/animation/animatable_double.dart`): a base value, an optional named **envelope**, an
optional **keyframe** list, and one `resolveAt(progress)` that answers what the value is now.
A Kotlin port (`nativepreview/AnimatableDouble.kt`) is pinned to the Dart by
`test/fixtures/animatable_fixture.json`, the same mechanism the text animation curves use — and
with the same caveat, that it catches *divergence tomorrow*, never a wrong curve today.

**The model is general, and that was deliberate.** `AnimatableDouble` knows nothing about
effects; effects merely happen to be its first consumer. Keyframes are a **timeline** feature —
transform (Ken Burns), opacity and volume will all want them — and building them inside the
effects system would have meant keyframes that work in exactly one place plus a draft migration
when the second consumer arrived.

**Resolution order is keyframes, else envelope, else the flat base value**, and it is not
negotiable. One keyframe means the user has taken manual control and the envelope steps aside
*entirely* — no blending, no mode to enter, no state where both are half-applied.

**Every envelope lands on 1.0 at `p == 1`**, pinned by a table-wide test that iterates
`kEnvelopeNames`, so an envelope added later inherits the rule rather than needing someone to
remember it. An effect caught mid-transition on a clip's final frame pops exactly on the cut,
where the eye already is; resting at full strength makes the last frame identical to the clip
with no envelope, so the handover is continuous by construction.

**A flat parameter serialises as the bare number it replaced** (`toJson` returns `baseValue` when
`!isAnimated`), which is how introducing this changed nothing for the 37 effects carrying no
envelope, and how drafts written before it still load. `fromJson` takes `dynamic` for the same
reason. Only `blur` (`ramp_out`) and `glow` (`throb`) carry a default envelope; static grades
declare none, because a pulsing vignette is a gimmick, and timed intros declare none because they
already animate through `uProgress` and an envelope on top would fight it.

**Keyframe positions are clip-relative `0..1`**, so a trimmed or sped-up clip keeps its keyframes
where they look right and a draft renders identically on any device.

**Adding a keyframe must never change the picture.** It takes the parameter's value *at that
moment* (`resolveAt(progress)`), so placing one is purely additive. Tested at several positions
and with existing keyframes present, because it is the property a future refactor would silently
break.

### Keyframes — a diamond is an instant of a clip

**Awaiting device verification.** Spec: `docs/superpowers/specs/2026-09-15-clip-keyframes-design.md`.

A clip carries seven keyframable properties, all `AnimatableDouble`: `canvasScale`,
`canvasOffsetX`, `canvasOffsetY`, `canvasRotation`, `volume`, `effectIntensity` and `opacity`. **`speed` cannot join them, and
the reason is structural**: every other property is read *at* a progress, while speed decides what
progress means — `duration` is `(sourceEnd - sourceStart) / speed` and `clipProgressAt` divides by
that duration, so a keyframed speed makes progress a function of itself and every diamond slides
while the curve is edited. A speed ramp needs source-time to be the integral of the speed curve:
its own model, its own Kotlin port, its own UI. That is why CapCut ships speed as a separate curve
tool, not as a keyframable parameter. **A diamond at progress `p`
means every one of them carries a keyframe at `p`** — that is what makes one mark on the
filmstrip an honest picture of the clip's state, and what lets a single button serve every
property with no picker. `logic/animation/clip_keyframes.dart` holds the pure functions
(`ClipProperty`, `captureKeyframe`, `removeKeyframe`, `setKeyframeEasing`, `keyframeProgresses`);
they take a segment and return a segment, knowing nothing about the playhead or Riverpod.

**One rule decides whether an edit is a base value or a keyframe**, and it is the reason no
control has a keyframe UI of its own. `VideoEditorNotifier._writeClipValue`:

- **No diamonds on the clip** → write the base value. Byte-identical to what each control did
  before keyframes existed, which is the path every project takes until someone places one.
- **Diamonds, playhead on one** → write that keyframe, leaving the base alone.
- **Diamonds, playhead between them** → place a diamond first (capturing every *other* property
  at that instant so nothing else moves), then write into it.

The pinch gesture, the volume slider and the effect intensity slider all call `setClipProperty`
and inherit keyframing without knowing the feature exists. **Anything new that edits a clip
property must go through it**, or it will be the one control that cannot be keyframed — which is
exactly how the rejected design ended up able to animate a single number.

**The selection is the playhead.** Nothing stores which diamond is selected: it is the one the
playhead is standing on (`playheadKeyframeProgress`). That is what keeps the plus/minus flip, the
easing sheet and the filmstrip agreeing about what "here" means without a third piece of state to
fall out of step. Tapping a diamond seeks onto it, which is what makes tap-then-minus remove it.

**`selectedClipProgress` is null, never clamped, while the playhead is on another clip.** A clip
stays selected as the playhead moves onto its neighbour, and clamping resolved that as progress 0
or 1 — so a plus tapped there pinned a diamond at the edge of a clip the user was not looking at,
and the curve icon lit for a segment the playhead was nowhere near. With null the toggle dims
(`canToggleKeyframe`, the same disabled-not-hidden rule as the curve), `clipEditValue` shows the
base, and a write goes to the base. The clip's own edges count as on it: a split parks the
playhead exactly on the seam, which is the right half's first instant. The pinch anchors to
`clipEditValue` for the same reason — anchor and write must name the same target.

**A diamond moves by long-press-drag** (`moveKeyframe`, `moveKeyframeLive`). Tap seeks, and a
plain drag anywhere on the filmstrip scrubs or reorders, so moving is the gesture those leave free
— the same one that picks up a clip. The move is of the *instant*: every property's keyframe at it
travels together, keeping its value and curve, or the one mark would stop being an honest picture
of the clip. The playhead rides along so the diamond stays the selected one and the canvas shows the
instant being placed; one snapshot at pick-up covers the drag. **A diamond stops short of a
neighbour rather than merging into it**: `moveKeyframe` returns the segment unchanged when another
diamond sits at the destination, and the widget keeps dragging from where the diamond really is.

**`kKeyframeHitSeconds` (0.05s) is seconds, not progress.** The same progress tolerance is a
different number of frames on a 1s clip and a 30s one, so a fixed progress window would make
diamonds unhittable on long clips and impossible to step off on short ones.

**Progress is whole-clip for every property** (`clipProgressAt`), including `effectIntensity`,
which previously measured against the effect's intro window. The shader's `uProgress` keeps that
window — it is the *effect's* clock, a different quantity that happens to share a range — but a
diamond is an instant of the **clip**, and resolving one against the intro window would put it
somewhere the timeline never drew it.

**A control shows what its write will target** (`clipEditValue`). With no diamonds an edit writes
the base, so the base is shown; with diamonds it writes the keyframe at the playhead, so the value
*there* is shown. This is not cosmetic, and getting it wrong was a device-reported bug: a volume
slider parked at the base's 1.0 on a clip whose keyframes had taken it to 0.2 offers **no way to
drag up** — the thumb sits at the top while the audio is quiet. An envelope is not a keyframe
here: it shapes the base and the write still targets the base, so the base is what to show.

**Easing is four families, one shown at a time**: Default (sine), Quadratic, Cubic, Bounce, each
offering None / Ease in / Ease out / Ease, with a ✓ that dismisses. Sixteen cells at once is a
wall, and the families are alternatives rather than a list to read through. **The sheet is styled
from the effects sheet, not from Material** — same background, corner radius and grab handle, the
same *pill* row for the families (not a `TabBar`, whose underline and ripple are a different
visual language), and the same `primaryStart` border over `highlight` fill for a selected cell.
The first version used a white highlight and a Material tab bar; every choice was defensible on
its own and the result read as a different app. One `_kEdge` (16) aligns the family row, the cell
row and the ✓, and each cell carries half of `_kCellGap` per side so the outer margin matches the
gaps between cells rather than crowding the edges. The sheet opens on the family
the current curve belongs to, and every tap applies **live** — a sheet that held the choice until
confirmed would make the user commit to a curve they have not seen move. Every group's None is
`linear`, drawn as a crossed circle rather than a straight line: a diagonal in a graph box reads
as *linear*, a curve among curves, rather than as the absence of one. `hold` is deliberately
absent from the sheet but kept in the enum for drafts and step effects. The other cells plot their
curve from `applyKeyframeEasing` itself over a dashed grid, because "Quadratic ease out" and
"Cubic ease out" are indistinguishable as words and obvious as shapes.

**The curve control edits a SEGMENT, and never places a diamond.** This is the distinction from
the plus button, and blurring it was the second device-reported bug — tapping the curve icon
between diamonds silently added one. A curve shapes travel that already exists;
`keyframeCurveTarget` resolves which segment, and it is null in three real "nothing to shape"
cases: fewer than two diamonds (one point is a value held, with no travel), before the first, and
after the last. On the **last** diamond it falls back to the segment arriving at it — nothing
follows, and an icon going inert the moment a user taps the final diamond reads as broken.
Anywhere else the diamond's own flag controls the segment leaving it, which is what gets edited.

**The curve icon is disabled, not hidden**, when `canEditKeyframeCurve` is false. A control that
vanishes and reappears is harder to find than one that dims, and dimming teaches what it wants:
place a second diamond and it lights up.

**The cells give the graph the leftover height rather than demanding a square.** Three rounds of
computing "square + label" arithmetic all overflowed by a different number, because the label's
line height follows the text scale and a `TabBarView` refuses intrinsic measurement (it is a
viewport). `Expanded` on the graph makes the cell shrink instead of striping at any size.

**`ease` no longer exists as an enum value and resolves on read to `cubicInOut`** — the curve it
always was. The enum name is persisted into drafts and crosses the channel, so this is a
migration, and an exact one. **A fresh keyframe is `linear`**, so the sheet's highlighted cell
tells the truth about a diamond nobody has shaped; an unreadable name degrades to `linear` too,
because guessing a curve would move the value along a path nobody chose.

**Every curve lands on exactly 0 and 1 at the ends and stays inside that range**, bounce
included. A keyframe pair means "this value here, that value there"; overshooting would send a
parameter past the maximum its own slider offers, which a clamped consumer silently flattens into
a plateau. `test/fixtures/animatable_fixture.json` pins all fourteen curves against the Kotlin
port at fourteen sample points, including the bounce family's segment boundaries where the curve
touches exactly 1.0 and an off-by-one `<` versus `<=` shows up.

**Splitting a keyframed clip rescales into each half's own 0..1**, after pinning a keyframe at
the cut on the original so both halves read the same value at the seam. Copying the lists
verbatim would leave the left half's later keyframes past its own end, where the value holds and
the move silently freezes.

Three engine-side subtleties worth not rediscovering:

- **The volume slider is audible while dragged** through `setClipVolume`, an override the engine
  applies in `applyAudio` in place of the clip's keyframed gain until the next `setTimeline`
  clears it — the same shape as `setClipTransform`, for the same reason (a recomposed timeline per
  slider frame would re-prepare the players). **✕ has to lift it explicitly** (`clearClipVolume`):
  a discard pushes no timeline, so without that the engine kept the dragged level until the next
  edit happened to push one. ✓ lifts it too, ahead of the push that carries the committed value.
- **`Lane.applyVolume` change-guards on `VOLUME_EPSILON`, and that guard is what makes a
  keyframed fade safe.** Setting an unchanged volume every tick makes ExoPlayer rebuild its
  `AudioTrack` — fault 10 in this engine's history.
- **`AudioExportMixer` must not skip a clip keyframed up from silence.** Its silent-clip check
  reads `baseValue`, which for a fade-in from zero *is* zero; it now asks `isAnimated` first, or
  the clip exports mute.
- **The clamps live on the resolved value, not the parse.** `canvasScaleAt` and `volumeAt` clamp,
  because a keyframe moves the value after `fromWire` has run — the same move the effect
  intensity clamp already made.

**Keyframes are the clip's, not the effect's.** Changing an effect drops the *intensity's*
keyframes (that parameter belongs to the effect) and leaves transform and volume keyframes
standing.

**Opacity is the seventh keyframable property** (`VideoSegment.opacity`, `ClipProperty.opacity`,
**awaiting device verification**). **It is a mix toward the letterbox fill, never alpha**: the clip
pass has no GL blending, `glClear` uses an opaque background, and the sampling helpers already
return `backgroundAt()` for letterbox pixels rather than transparency — so an alpha would be a
value nothing reads, and enabling blending would change how all eleven transitions composite. The
helpers end with `mix(backgroundAt(), graded, uOpacity*)`, which every transition inherits because
all of them sample through those two functions. It sits **after `gradeClip`** (fading a graded
clip is fading what the user sees; fading first would push a filter's colour offset onto a
vanishing clip) and **before the effect chain** (a blurred clip at 50% is a blurred clip,
half-present). Resolved per tick by both engines through `opacityAt`, clamped where resolved
because a keyframe can overshoot; per-lane, change-guarded. The Opacity tool sits beside Volume on
the clip menu — a fade of the picture next to a fade of the sound — and writes through
`setClipProperty`, so a fade in is two diamonds. The overlay opacity path is untouched. Fading to
the project background rather than to black was the open question; the background it is, since
that is what the bars already show and a fade that revealed a different colour would read as a
flash.

### Mask — a window over the picture

**Awaiting device verification** (the coverage half is GLSL). `VideoSegment.mask` (`logic/mask/clip_mask.dart`)
is a shape — rectangle, circle (an ellipse of the window's size) or linear (keeps the left of the
centre, fades to the right) — with a centre, a size, a feather and an invert, **authored in
fractions of the clip's fitted frame** like the crop rect, so it travels with the clip's placement
and a draft renders identically anywhere. In the shader `maskCoverage` multiplies the clip's opacity
in the sampling helpers: outside the window is the letterbox fill exactly as a letterbox pixel is,
so every transition inherits the mask. It reads the fitted coordinate **before the mirror** — the
window is over the picture as displayed, and flipping the clip must not move it. `maskCoverage` in
Dart is the shader's twin, pinned by tests; if one changes the other must. The two vec4s
`(shape, centerX, centerY, feather)` / `(width, height, inverted, 0)` are encoded once on each side
(`maskUniforms`, `NativeTimelineClip.maskUniforms`) in a fixed order and tested to match.

**An overlay can be masked too, with the same model** (**awaiting device
verification**). `ImageOverlayModel.mask` and `VideoOverlayModel.mask` are the same `ClipMask`, so a
circle means one thing everywhere and there is one coverage function keeping preview and export
agreeing. **Authored in the overlay's own box**, not in canvas fractions: an overlay is placed and
scaled independently, so a mask measured against the canvas would slide off the picture the moment
the overlay moved. The panel serves whichever of the three is selected
(`VideoEditorNotifier.maskOnSelection` / `setMaskOnSelection`, a clip winning when several somehow
are), so there is no second mask editor to drift from the first.

**The two renderers reach the shape differently, and that is the one gap.** Export computes the
coverage in `OverlayRenderer`'s fragment shader, reading the quad's own 0..1 — which *is* the
overlay's box — and multiplying it into the premultiplied texel beside `uAlpha`. The preview
cannot: overlays there are plain Flutter widgets with no shader of their own, so
`OverlayMaskClip` clips them to the same shape instead. A clip is a **hard edge** where the shader
ramps over the feather, so a soft-edged mask looks very slightly crisper on the canvas than in the
file. That is the right way round — nothing appears in the export that the preview did not show —
and it closes entirely when overlay playback moves into the engine.

**A chroma key on an overlay is built now** — see the native-preview overlays section. It was
blocked for exactly the reason stated here: a key is a per-pixel colour decision the widget layer
could not make, so the export would have dropped the green while the preview still showed it.
Overlays being drawn in GL removed the blocker, and the key is the same `ChromaKey` model with the
same shader functions.

**`roundedRectangle` is the fourth shape**, appended to the enum on purpose: both sides read the
shape as a **number** (the shader tests `a.x < 1.5`), so inserting a value would have turned every
saved circle into something else. A test pins each index. It is a rounded-box distance field —
push the box in by the radius, measure to that smaller box, subtract the radius back — identical
to the plain rectangle along the straight edges and an arc at the corners, with the radius clamped
to the box so a large value degrades to a stadium rather than folding inside out. The radius rides
the **last uniform slot**, which was reserved and unused until this shape, and stays 0 for every
other shape — exactly what they have always sent. It is the shape a picture-in-picture actually
wants: a plain rectangle reads as a screenshot pasted on, and a circle crops the corners off a
16:9 inset.

**Mask is an in-place panel, not a sheet**: the window is placed on the canvas — drag to move,
pinch to resize, with the outline and a grab point drawn by `_MaskOutlinePainter` — and a sheet
would cover the surface being edited. The panel holds only what the canvas cannot: shape, feather,
invert. While the tool is open the composer shows the clip **unplaced but cropped**: scale, pan,
rotation and mirror suspended so the canvas maps a drag through the fit alone, the clip's own crop
kept because the window is over the picture as it will play — the crop tool's rule, one step
gentler (`unplaced` vs `plain`). It joins `kCanvasEditingTools`. Switching shape keeps the window
where it was. Plain values, not animatable yet: a moving mask is four coupled numbers with a design
of its own.

### Replace clip — swap the file, keep the edit

`replaceClipAsset` puts a picked file under the selected clip. Everything the user did to the clip
is about the *slot* on the timeline, not the file — speed, placement and its keyframes (clip-relative,
so they still mean the same instants), crop, mirror, opacity, adjustments, filter, effect,
transition — and survives. The trim survives where it fits: a shorter file pulls the end in and
slides the start back to keep as much of the clip's length as the file allows; a photo has no
source length and is given the clip's on-screen length at 1×. **What cannot survive is what
belonged to the old file**: the proxy rendered from it, and a reversal that depended on that
proxy. One undo step; the file joins the asset pool once, and the old asset stays for anything else
using it. The screen takes the first pick from the same picker Add uses and re-syncs the preview.

### Apply to all — a copy, not a mode

Transform, the clip crop and Effects each carry an `ApplyToAllButton`: one tap copies the selected
clip's placement (scale, position, rotation with their keyframes, and the mirror), its crop rect, or
its effect and intensity onto every other clip, as one undo step, and says how many it reached.
**Deliberately not the `ApplyToAllToggle` Filters and Transitions use.** Those edits are single
choices that can sensibly write everywhere live; a placement is a ruler drag, and a live all-clips
mode would write a keyframe into every clip at the same *relative* instant on every frame of the
drag — which nobody means. Set one clip up, then copy it. All three go through
`_copyToOtherClips`, which snapshots once and does nothing — no snapshot either — with nothing
selected or nothing else to write, because an undo entry that undoes nothing is a lie. Disabled and
dimmed, not hidden, in a one-clip project.

### Freeze frame — a still cut in where the playhead is

`freezeFrameAtPlayhead` is built from parts that already existed: the frame under the playhead is
decoded by the filmstrip's extractor (`frameAtSize`) at the clip's **source** time there
(`sourceAtOffset`, so a trimmed, sped or reversed clip freezes the frame that was on screen),
written into the project folder like a cover (`freeze_<draftId>_<ts>.jpg`, decoded at most 1920
on the long side — no export renders a still larger), added as an image asset, and inserted as a
`kDefaultPhotoDurationSeconds` photo clip. **The still wears the clip's state at that instant as
flat values**: a keyframed zoom mid-flight freezes at the size it had, with no keyframes, because a
still has no travel; filter, effect, crop, flip and adjustments copy across. Where the playhead is
at least `kMinClipDurationSeconds` from both ends the clip is cut and the still goes between the
halves — **one undo step** for cut and insert; nearer an end it goes before or after, uncut, rather
than forcing a sliver the blade would refuse. A photo throws ("already a still"), as does a frame
the extractor cannot read, with the message the user sees — the blade's own pattern.

**The cut is a helper now** (`_cutSegments`): pure, returning the new list and where the right half
landed. `splitAtPosition` and the freeze both build on it, so a cut is one piece of arithmetic
however it is reached. Anything else that cuts a clip should go through it rather than re-derive
the source split and the keyframe rescale.

### Adjust — brightness, contrast, saturation, temperature

**Rides the grade pipeline that already exists; no shader changed.** `logic/color/color_adjustments.dart`
turns the four parameters (each -1..1) into one 4×5 matrix in Flutter's `ColorFilter.matrix` layout
— the shape a filter preset already is — and `composeColorMatrices(outer, inner)` multiplies two
of them (inner first). A clip's adjustments compose **after its filter** into `VideoSegment.colorMatrix`,
which is now what the clip sends as its `colorMatrix` (the old `filterMatrix` getter survives for
the filter sheet's tiles); the project's compose after the project filter into the canvas look
(`_projectColorMatrix`). Both land in the `gradeClip` / `outputColor` the engine already applies.
Applied to a pixel in the order contrast, saturation, temperature, brightness — a convention, held
in one place. Full desaturation collapses to Rec. 709 luma; contrast pivots about mid grey.

**The two levels coexist**, unlike filters. A filter applied at both levels grades twice by mistake,
which is what `filterAppliesToAll`'s exclusivity prevents; an adjustment at both is the user's
intent — a warm project with one clip pulled cooler. The sheet (`panels/adjust_sheet.dart`) has
four pills and one `ValueRuler`, opens on the selected clip and offers the same `ApplyToAllToggle`
Filters uses to switch to the project; from the root menu there is no clip and no toggle. **The
ruler shows the level it writes.** Drags write live with one undo snapshot per drag; the readout
tap resets to 0. Persisted per clip (omitted while untouched) and on the draft (`adjustments`).

**`ValueRuler` anchors its drag on pointer-down** (`DragStartBehavior.down`). Alone, a horizontal
recogniser is accepted on its first move; inside a scrolling sheet it competes with the vertical
recogniser and, with the default behaviour, the touch slop spent winning the arena was dropped from
the drag — the Adjust sheet's first test got exactly half its travel. Same rule as the trim handles.

### Transform — a tool with a sheet, and a clip that can rotate

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-09-16-transform-sheet-and-per-clip-crop.md`.

**Transform's children are root tools and Transform is a tool of its own.** Crop, Zoom and
Background moved out of the submenu onto the root toolbar; the dead `rotate` tool — a menu entry
with no handler — was deleted. Transform opens a sheet (`panels/transform_sheet.dart`) with three
tabs, Scale / Rotate / Position, each a `ValueRuler`. It is on the root menu **and** the clip menu:
the root menu is hidden while a clip is selected, and a tool reachable only by deselecting the
clip you want to transform is not reachable. From the root menu nothing is selected, so
`selectSegmentAtPlayhead` picks the clip under the playhead, resolved through `segmentIndexAt` —
and **`_showTransformSheet` puts that selection back when the sheet closes.** The toolbar is
chosen by `currentMenuId`, which stays on root, so leaving the borrowed selection showed root
tools beside a selected clip and its keyframe controls: a half state the user never entered. It
`await`s the sheet for the same reason `_showTransitionsDrawer` does — every way of closing — and
a selection the user made themselves stays.

**The ruler is per pixel, not per widget width** (`panels/value_ruler.dart`). A slider spreads its
range across whatever width it gets, so precision depends on the phone; a ruler moves a fixed
amount per pixel and reaches a large range by dragging more than once. Right raises the value —
the user's specification — and the ticks travel *with* the finger; they carry no labels, so there
is nothing for that to contradict. Anchor-based like every drag here. **Its change guard compares
against the value it last reported, never `widget.value`**: the parent may not have rebuilt
between frames, and guarding on the given value swallowed the report that brought a value back to
its start, leaving the caller holding a stale extreme. The anchor test caught it.

**The sheet has no keyframe control and needs none.** Every ruler writes through
`updateClipCanvasTransform` — the edit rule — and shows `clipEditValue`, so on a keyframed clip a
drag keyframes itself and the ruler reads the value at the playhead. One property moves per drag
and the other three are handed back as *shown*, so on a keyframed clip they write their own
resolved value to the same diamond, a no-op. The engine hears every frame through the
`setClipTransform` override channel exactly as the pinch does, and the screen catches up once on
release. Tapping a readout resets that value through `setClipProperty`, undoably.

**`beginClipCanvasTransform` pauses playback first.** A ruler drag or a pinch writes at the
playhead every frame, so on a keyframed clip a moving playhead turned one drag into a trail of
diamonds. The sheet and the pinch share the one entry point, so both inherit the pause.

**Rotation is the sixth keyframable property, and it did not exist before.** `canvasRotation` is
an `AnimatableDouble` in **degrees** (what the ruler shows, what a draft should read as); the
engine converts to radians once, at the uniform. Unrotated clips serialise a bare `0.0`.
`normaliseDegrees` folds any angle into (-180, 180] so a clip dragged round twice reads as its
actual orientation and equal angles compare equal for the merge rule.

**The shader rotates in an aspect-true space, or it shears.** The canvas is 9:16, so a unit of u
is not a unit of v; rotating raw uv squashes the picture into a rhombus at 45°. `rotateCanvas`
scales x by `uCanvasAspect` first, rotates, scales back — the identical trap
`OverlayRenderer.writeCorners` documents for overlays. **Order: remove the pan, rotate, un-fit** —
sampling undoes the transform in reverse of how the clip was built. Rotating before removing the
pan spins the clip about the *canvas* centre rather than its own, and a clip dragged to a corner
orbits instead of turning. The sign is the inverse of the intuitive one because it is the sampled
point being turned, not the clip.

**Flip is two booleans, not a rotation** (`flipHorizontal`/`flipVertical`, **awaiting device
verification**). Turning a picture 180° puts it upside down *and* back to front; a mirror does
only the second, which is what selfie footage wants. The shader applies the mask to the *fitted*
coordinate — after placement, before the content rect — `fitted = mix(fitted, 1.0 - fitted,
uFlip*)`, so the picture mirrors inside its own frame and the frame stays where it sits.
`NativeTimelineClip.flipMask()` encodes the flags once for both engines. Written to the wire and
the draft only when set; suspended in the clip-crop plain view like scale and pan (a mirrored
picture would put the handles on the wrong side); refused by the merge rule; copied by split;
cleared by the transform reset. Two toggles on the Transform sheet's Rotate tab, where a user
looks for them. Deliberately not animatable: half a mirror is not a picture.

**The split's right half is built by hand, so every clip-owned field has to be named there.** A
rotated clip lost its angle on the right of a cut until `canvasRotation` was added to that
constructor; a test now checks the split carries both rotation and crop to both halves. Anything
new on `VideoSegment` has to be added to that constructor, or a split silently drops it.

### Per-clip crop — the sampling rect became per lane

**Awaiting device verification**, and this one changes the sampling path for every clip while
meaning to change nothing, so an existing project's crop, zoom and pan — on video *and* photos, in
preview *and* export — is the first thing to check.

**`contentRect` is per clip now.** It was one rect on `EditorTimelineCanvas`, bound once in
`bindCanvas` and sampled by every lane through a single `uContentRect` — so a transition had one
rect and two clips, which is what made a per-clip crop impossible. Each `EditorTimelineVideoClip`
carries its own, the shader has `uContentRectIncoming`/`uContentRectOutgoing`, the renderer holds
it on the `Lane` beside fit and pan, and both engines push it per lane (`setLaneContentRect`). The
canvas field survives for the Flutter side; the engine no longer reads it. **Export used to inherit
whatever rect the preview engine had last left on the renderer** — right by accident, because a
`setTimeline` always preceded an export; it now sets the clip's rect per frame, which is correct
and no longer accidental.

**A clip's crop composes *inside* the project's** (`composeCropRects`): cropping a clip to its
middle half means the middle half of what the project already shows. Then the same
`resolveContentRect` applies zoom and pan — one geometry definition, as `canvas_geometry.dart`
requires. **Freehand only, no ratio**: a per-clip ratio would fight the project canvas every clip
is fitted into. **A plain `Rect`, deliberately not animatable**: an animated crop is a pan-and-scan
with its own design, and four coupled numbers rather than one parameter.

**The first device build stretched every cropped clip.** The lane was still fitted by
`sourceAspect`, the whole frame's shape, while it sampled through a smaller rect of a different
shape. `LaneFit.contentAspect` (canvas section) is the fix, in both engines and the renderer's
photo fit; `LaneFitTest` pins it. The same arithmetic is why a custom *project* crop exported
stretched — the preview had hidden it by reshaping the Flutter box — and why the canvas now takes
the crop's shape instead.

**While the clip-crop tool is open *on a clip*, that clip shows plain**: the project's crop and
nothing else — not its own crop, no zoom, no scale, no pan, no rotation (the composer passes
identity parameters for it). Only that clip; the rest of the project must not change shape while
one is edited. Plain is what makes the handles honest: a clip's rect is a fraction of the clip's
*picture*, which sits contain-fitted inside the canvas with bars around it, and the canvas draws
the handles over that fitted rect (`_cropFrame`, via `fittedFrameRect` — the Dart half of
`LaneFit.of`) and measures drags in fractions of it. Spread over the whole box, as the project
crop's handles are, they agreed with the source only for a clip that happened to fill the canvas;
on a letterboxed clip a rectangle drawn over the bars cropped a region the user never pointed at.
With the clip plain, the fit is the only transform between the handles and the source, so the
mapping is exact; with scale and pan in play most of a 3× clip would be off-canvas where no handle
can reach. The project crop keeps whole-box handles: it applies to every clip at once, and clips
of different shapes have no single picture to map through.

**One editor, two targets.** The canvas's crop handles and painter serve both the project crop and
a clip's; `_cropTarget` decides which rect is read and written from `activeToolId` (`crop` versus
`clip_crop`), so there is no second editor to drift from the first. The clip tool is on the clip
menu with the same label as the root menu's Crop and a different id — to the user it is the same
verb applied to a smaller thing. Both now take **one undo snapshot per drag**, at pan start; the
project crop had none before.

**`clampNormalizedRect` threw on a rect pushed wholly past an edge.** `right.clamp(left + min,
1.0)` with `left == 1.0` gives a lower bound above its upper bound, which Dart rejects with
`Invalid argument(s): 1.0001` — inside compose, which takes the whole timeline down. Found by the
`composeCropRects` junk-input test; the near edge now stops one minimum extent short of the far
side. A hand-edited draft could have hit this before any of this work existed.

**The rejected design is entry 23 in `docs/dead-ends.md`** — a keyframe row under the clip, opened
from a button on the effects sheet. Read it before proposing anywhere else for a keyframe control.

**The crop was upside down, and the UI was never the problem** (**awaiting device verification**).
Device-reported: "if I crop from the top it crops from the bottom, if I crop from the bottom it
crops from the top" — on the project crop *and* the per-clip crop, which is what says it is one
shared cause rather than two.

Everything on the Dart side is **y-DOWN**, consistently: `Rect.top` is the distance from the top
edge, `_handleCropPanStart` hit-tests in screen pixels, `_handleCropPanUpdate` moves `top` by a
positive `dy`, `composeCropRects` and `resolveContentRect` keep `top` as `top`, and the painter
draws `frame.top + top * frame.height`. Every one of those agrees with the others, which is
exactly why the handles *looked* right while the picture disagreed — there was nothing to find in
the crop editor.

The shader samples in a **y-UP** space: texcoord (0,0) is the bottom-left vertex. `TransitionShaders`
already documents this for the pan, which is negated "at the one place the two frames meet", with
the warning that skipping it makes a downward drag move the clip up — "which shipped once". The
content rect crosses the same boundary and was never converted, so `top` became `bottom` in the
sample.

**`NativeTimelineClip.toSamplingRect` converts once, at the parse boundary**, and the location is
the point: `TimelinePlaybackEngine` and `VideoExportEngine` both push the parsed array straight to
`setLaneContentRect`, so one conversion fixes preview and export together and leaves a single
definition. In the shader it would be two copies; in Dart it would put a GL detail into the
contract. It is its own inverse, so nothing accumulates, and it touches **only y** — `LaneFit.contentAspect`
reads width and height alone, so letterbox fitting is unaffected and an uncropped project is
byte-identical.

**The conversion clamps, and a test found why.** `1f - top - height` is not exact in float32: a
crop flush to the bottom (top 0.8, height 0.2) lands at **-1.49e-08** rather than 0. Invisible as
a number and harmless under `GL_CLAMP_TO_EDGE`, but it is a *texture coordinate* — under a repeat
wrap a negative y samples the opposite edge of the picture.

### 3. Then â€” timeline UX

Zoom (`_pixelsPerSecond` is a `static const 50.0`; `ClipFilmstrip` already recomputes its grid from
it), snapping, clip visuals. All sit on the tile model. Reorder and the cut seam are done.

#### Trim handles

A handle inside a horizontally scrolling timeline competes with the scroll view for the same gesture,
and the arena does not resolve until the finger has travelled `kTouchSlop` (~18px). At 50px/second
that is a third of a second of trim swallowed before anything moves â€” the handle appears not to pick
up when touched, then jumps. `_ImmediateHorizontalDragRecognizer` claims the pointer on **down** and
uses `DragStartBehavior.down`, so the grab is immediate and no travel is lost.

Handles track an **anchor**, not a running sum of deltas: `anchorValue + (fingerX - anchorX)`. A
per-frame delta that gets dropped â€” the range hit its minimum, or `setTrimRange` clamped it against
the asset â€” is lost for good, and the handle stays offset from the finger by the overshoot. The
minimum-length clamp is applied in `_dragTrimHandle` rather than left for `_updateTrim` to reject,
so the handle rests exactly on the limit.

**Lane drags follow the finger**: the four clip movers (audio, text, image, video overlay)
computed `lanesMoved` with a negation left over from the old upward-growing lane layout, so after
the lane-order flip every vertical drag landed on the opposite side. Lanes stack downward (lane 0
nearest the filmstrip): drag down = higher lane index, no negation. The main clip track is
untouched — its reorder is horizontal-only by design.

**The timeline area has a floor as well as a cap** (`timelineTrackHeight`, 190–250): the canvas
is `Expanded`, so any pixel the timeline does not claim the canvas absorbs — a simple project
used to collapse the track area and balloon the canvas. CapCut-style: keep a workable track area,
size the canvas from what is left. **While a tool panel is open the floor is released**
(`ScrollableTimeline.compact`): the panel is taller than the toolbar it replaces, and that
difference used to come out of the canvas while the track area kept its idle slack — the picture
shrank and the timeline was shoved up by the panel's full height. Now the slack goes first and the
canvas only pays if there are no empty rows to give; real rows are never taken. The container is an
`AnimatedContainer` so the release moves with the panel's `AnimatedSize` instead of snapping ahead
of it.

**A tool panel takes the height its content needs**, floored at the toolbar's `_kToolbarHeight`
so opening a tool can never drop the timeline. It was a fixed 160 (200 for Background) with the
body in an `Expanded`, and the crop panel read as a box holding one row of chips with a gap under
it. Every panel body therefore lays out under an **unbounded height**: a horizontal list or an
`Expanded` inside one throws the moment the fixed box is gone, which is why `CropPanel` carries its
own row height and `BackgroundPanel` bounds its swatch area. `tool_panel_sizing_test.dart` pumps
each such body unbounded; a new panel with a list in it must be added there.

**The transition marker is its own widget** (`timeline/transition_marker.dart`), drawn over the
filmstrip on each seam. Three faults were fixed together after a device report. Its tap set
`currentMenuId: 'transition'` — whose tool list is **deliberately empty**, because the drawer
replaces it — while `onTransitionTapped` was declared, called, and **never wired by the screen**, so
a tap surfaced an empty submenu and no way to choose anything. The timeline now selects the seam and
the screen owns the modal, which is the right split: a widget deep in the timeline should not reach
for a sheet. **Both openers go through `_showTransitionsDrawer`, which `await`s the sheet and then
calls `deselectAll()`** — entering the transition menu is a mode, and something has to leave it.
Without that, dismissing the sheet left the empty submenu on screen, which was the same bug from
the other end. The `await` is what covers *every* way a sheet closes — the scrim and the system Back
gesture as well as a button — where an `onTap` on the drawer's own control would only catch one; the
drawer never pops itself, so those are the only paths. Only the selection and the menu are
transient, never the edit. Its colours were hard-coded Slate (`0xFF1E293B`/`0xFF0F172A`) beside the app's Zinc
surfaces — the grey-blue that read as another app — and are now all from `AppColors`. **The applied
state is carried by the fill, not by a ring**: an earlier pass changed only the border and the ink,
and 1.5px of tint is the first thing to vanish against a busy frame, so "has a transition" and
"empty" looked alike exactly where it mattered. The accent fill is `Color.alphaBlend(highlight,
surface)` rather than `highlight` raw, because `highlight` is 15% alpha — right over a panel, washed
out over bright footage. The glyph is `arrowLeftRight`, not `sparkles`: sparkles is the language of
*effects*, something applied to a picture, where a transition is two clips meeting. An empty seam
shows a `plus` — it is an invitation, not a state.

**Lane identity gutter** (`_buildLaneGutter`): the run-in before 00:00 carries a 2px vertical
line marking the timeline's start and, left of it, one icon per kind of thing each lane holds
(music/type/image/video — a mixed lane shows several), so thin lanes can be told apart at a
glance, CapCut-style. It is part of the scrolling content on purpose — visible exactly when the
start is — and wrapped in `IgnorePointer` so it can never eat a gesture. The audio clip's fill
also stopped changing on selection (it swapped to opaque purpleAccent, which read as a second
purple washing over the waveform); selection is the border's job on every clip type.

**Project cover** (`_coverTileBody` + `CoverPickerSheet`): a small card on the video track's
run-in before 00:00 — the chosen cover (or the edit's first frame) under a scrim with a pencil;
the one deliberately rounded element on the timeline, which is what makes it read as a card, not
a clip. **It lives in the timeline's outer stack, tracked over both scroll offsets — never in
the content stack**: it sits before 00:00, outside the content's bounds, and Flutter paints such
overflow (`Clip.none`) but `RenderBox.hitTest` still gates on `size.contains`, so an in-content
card rendered perfectly while every tap fell through to nothing. Anything interactive in the
run-in must take the overlay route. Tapping opens a sheet with a scrubbable strip of frames
resolved through the **same
(path, time) mapping the filmstrip uses** (`sourceAtOffset`, proxy read from its own zero), so a
trimmed/sped/reversed clip offers exactly the frames it plays, plus a gallery import. The chosen
frame is fetched via `VideoThumbnailService.frameAtSize` — a fresh, uncached decode, because the
strip cache keys by `(path, timeMs)` only and sizes share a key; going through it would return a
160px tile as the cover or poison the strip with a full-size image. `setCoverImage` writes a
**timestamped** `cover_<draftId>_<ts>.jpg` (`FileImage` caches by path, so overwriting one file
would show the stale cover), deletes the previous cover file, and saves the draft.

**The text editor sheet is the one text-styling surface** (`text_editor_dialog.dart`). Four
labeled tabs — Keyboard / Style / Font / Animation — at a fixed panel height so switching tabs
never resizes the sheet. Style opens with one-tap **presets** (bundles of colour/stroke/
background/shadow; fonts deliberately excluded — a preset overwriting the chosen typeface would
feel destructive), then alignment, colour targets and sliders. The header has an explicit ✓
Done; duplicate/delete belong to the timeline, not the sheet. **Text is created empty** and
`showTextEditor` deletes the overlay if it is still empty when the sheet closes — no
"Double Tap to Edit" ghosts in an export. The in-screen text panels (`text_panels.dart`,
activeToolIds style/font/animation) were unreachable dead code — nothing ever set those tool ids
— and were deleted; do not grow a second styling surface, it will drift from the sheet. The Text
tool has **no submenu on purpose**: it would hold one item today, a tap tax on the most common
action — add the submenu when templates/captions give it a second real entry.

**The text selection frame is CapCut's** (`text_overlay_layer.dart`, awaiting device run): a solid
white rectangle through the box's transformed corners, × delete top-left, pencil top-right,
duplicate bottom-left, a **rotate + scale** handle bottom-right (finger distance from the centre
sets the scale, its angle sets the rotation — one gesture, no modes), and width pills on both
edges (the far edge stays put: the centre shifts by half the applied change along the box's own
x-axis). Right angles snap within 3°. The body itself moves on one finger, pinches and two-finger
rotates. **First tap selects; a tap on the selected text opens the editor** — opening on every tap
made text impossible to move, because the sheet is modal and takes the canvas away. Handles live
in **canvas space**, positioned from the body's rotated corners, so they keep one screen size at
any text scale. Two rules that shaped the structure:

- **Every `RenderBox` gates hit-testing on its own size**, so a `Transform.scale`d child cannot
  be touched outside its parent's unscaled rect — the old layer's text stopped responding once it
  was scaled up. The body is laid out in a square that holds the box at any scale and rotation
  (`max(scaled diagonal, unscaled width, unscaled height)`), and the `GestureDetector` sits
  innermost on the real box, so exactly the visible text catches a finger. Do not put the
  detector outside the transforms.
- **A drag is one undo step.** The handles and the body call `saveStateForUndo()` once on
  gesture start and `updateTextOverlayLive` (no snapshot) per pointer move; going through
  `updateTextOverlay` pushed an entry per frame, so "undo" walked a drag back a pixel at a time.
  All drags are anchor-based (start value + total displacement), never accumulated deltas.

**Every lane's trim handles (audio, text, image, video overlay) go through `_laneTrimHandle`**,
which wraps the same immediate recognizer and adds a held highlight â€” they used plain
`GestureDetector`s before, so their drags lost `kTouchSlop` to the scroll arena and gave no
feedback when caught. Grips are the same bar on both ends (a chevron implied a direction the drag
does not have), `_kMinTrimDuration` is the one minimum for every trimmable thing (the video
clips' `kMinClipDurationSeconds`, replacing a stray 100ms rule on overlays), and **timeline
chrome is square**: no radius on handles, clip bodies, the transition marker, the carried-drag
preview or the canvas â€” the only rounding left is the playhead's 2px glow line and the waveform
bars' 1px softening, which are lines, not boxes.

#### Snapping

**A scrub release within `kSnapTolerancePx` (8px) of a clip seam glides onto it** — on release,
not during the drag. The playhead is fixed and the content scrolls under it, so snapping the
*reported* position mid-drag would put the marker a few pixels off the seam it claimed; sticking the
scroll itself mid-drag fights the finger. A 120ms `animateTo` after the finger lifts feels magnetic
without either, and it scrolls through the same notifications a finger does, so the engine follows
it the same way. Seams come from `clipBoundaryTimes` — the starts with transition overlaps applied,
plus the end — so the playhead parks where the cut is drawn. **A trim handle snaps to the playhead**
when the playhead is inside the clip being trimmed: trimming to the frame you are looking at is the
common intent and was otherwise a frame or two off every time. The tolerance is pixels converted to
source seconds through the clip's speed, so the pull feels the same on a sped clip; the haptic
fires once on arrival (`_trimSnapped`), not on every frame held there. `snapToNearest` is
unit-agnostic so the two feel identical.

#### Reordering clips

Drag-and-drop lives in `ScrollableTimeline`. The shape of it:

- **`_clipLayouts()` is the single source of clip positions.** Every clip-track widget â€” filmstrip,
  selection border, seam, transition marker â€” positions itself from that one list, so a reorder
  preview cannot leave them disagreeing about where a clip is. Without it the pieces of a clip drift
  apart mid-drag.
- **Long press to pick up.** A plain horizontal drag is already a scrub anywhere on the timeline and
  a trim on a handle, so reorder needs a gesture neither can claim. Audio clips already use this.
- **Widths are captured at pickup** (`_reorderWidthsPx`). Display durations tile the timeline
  exactly, so laying them out cumulatively reproduces the layout the user grabbed; re-resolving
  transition overlaps for a hypothetical order every frame would be expensive and jumpy. The real
  geometry is recomputed on drop.
- **The carried clip follows the finger with no animation** â€” easing there reads as lag â€” while the
  others move under `AnimatedPositioned`. The slot it would drop into is drawn in place.
- **The target is chosen by the carried clip's centre**, not the finger, so grabbing a long clip by
  its edge does not throw it a slot early.
- **Auto-scroll** pulls the timeline when a clip is held near the viewport edge, and adds the scroll
  delta to the grab point â€” the finger has not moved but the content under it has. While reordering,
  `_onScrollNotification` and `_syncScrollToTimelinePosition` both bail out, or the drag and the
  playhead fight over the scroll position.
- `reorderSegment(from, to)` takes the destination in the **final** list, not an insertion index into
  the pre-removal list. It also drops the transition off whatever ends up last â€” a transition there
  would be a window with no incoming clip.

### Known broken / not yet done

- **The preview's sound is assembled from three implementations, and the export uses none of
  the first two.** Clip sound comes from ExoPlayer, imported music from `just_audio` in Flutter
  (`audio_player_manager.dart`, re-seeked only when "massively out of sync"), and the file from
  `AudioExportMixer`. That is why preview audio can only ever *approximate* the export: a speed
  curve steps where the export glides, and music sync is loose. **The assessed way out is the
  preview playing the export's own mix**: `AudioExportMixer` already builds the mix block by block
  (`mixSource` into a 1024-frame buffer) and only its last step is export-specific — handing the
  block to an encoder rather than to the speaker. With ExoPlayer decoding video only, its clock
  also stops following an audio buffer, so a rate change lands immediately and a curved clip's
  picture can follow the curve exactly instead of in steps. **Not started, and not a small job**:
  it moves the engine's master clock onto the audio output, in the most device-verified part of
  the app, and everything uncertain about it (underruns, Bluetooth latency, audio focus, pause and
  scrub behaviour) only shows on hardware — it needs its own spec and device sessions. Replacing
  ExoPlayer for *video* as well (the full CapCut architecture) is a further stage with the most
  risk and the least audible gain; do the audio stage first and only then decide.
- **The two clip proxies are the editor's last FFmpeg users.** `createReverseProxy` and
  `createClipPlaybackProxy` render with `libx264` software encoding — slow on exactly the target
  hardware. Replace with `ExportClipDecoder` + `VideoFrameEncoder` (hardware, already built for
  export): decode GOPs forward, emit frames backward. Then the editor imports nothing from
  `ffmpeg_kit`, and FFmpeg belongs only to the compression feature.
- **Speed change shifts pitch, in export and now in the preview too.** Sonic was removed from
  export after it silently killed all export audio (dead-ends entry 22); the linear resampler that
  replaced it does rate conversion and speed with no dependency that can throw, at the cost of
  pitch on a sped-up clip. The preview used to preserve pitch, so the two differed; it now sends
  pitch equal to speed (`PlaybackRate`), so they agree. A natural-pitch speed-up needs a
  time-stretcher in the **export**, at which point keeping pitch becomes a per-clip choice and
  `FLAT_SPEED_SHIFTS_PITCH` goes.

### Overlays are drawn natively in the preview too

**Awaiting device verification.** Spec:
`docs/superpowers/specs/2026-09-17-native-preview-overlays-design.md`. Photo and video overlays
used to be drawn **twice, by two implementations** — `OverlayRenderer` in the export, two Flutter
widget layers in the preview — and that split was the direct cause of every overlay limitation:
an approximate feather, no chroma key, no blend modes, and ~90 lines of drift correction that
existed only because `video_player`'s clock is polled about twice a second.

The native half was never the missing piece. `OverlayRenderer` already lived on the preview
renderer, and the manager already parsed overlays on every `setTimeline`; the only thing out of
the preview's reach was `VideoExportEngine.OverlayPass`, a **private inner class**. It was lifted
verbatim into `gl/OverlayDrawBuilder.kt` (464 lines moved, the header and the engine-internal
references the only changes) and both engines now call it, so there is one definition of which
overlays are live and how they animate.

**Overlays travel on their own channel**, `setOverlays`, never in `setTimeline`: a timeline push
replaces every lane's media items and re-prepares the players, which is a decoder rebuild and a
visible flash for an edit that changes nothing about what plays. It is light enough to send per
frame of a drag, which is also why an overlay moved under the finger moves on the canvas —
`_syncNativePreviewTimeline` deliberately bails out during a gesture, and `_syncNativeOverlays`
does not.

**`OverlayClock.needsRedraw` is what keeps this off the GPU.** The engine ticks ~60 times a second
and almost none of those ticks can change an overlay, so a redraw is owed only where the drawn
result differs: an overlay appearing or disappearing, or being inside an animation window. A test
caught that the step landing exactly *on* rest was skipped — the window's far edge is a boundary
like any other, and without crossing it an overlay parks one frame short of full opacity.

**`OverlayClock.override` is the tail.** Past the last video frame the engine's clock parks and
Flutter's ticker owns the playhead, so the screen sends that position for overlays alone — and the
engine honours it **only beyond its own duration**. Inside the video, two clocks writing one
playhead is dead-ends entry 12.

**The draws are built inside the draw, on the GL thread — the way export builds them.**
Device-found, and the first version got both halves wrong: it built them in the engine's ticker,
on the **main** thread, and only when the playhead crossed an overlay boundary. The builder
uploads textures and creates decode targets, which need a GL context the main thread does not
have; and a still that had not decoded yet answered `Pending` **once**, after which nothing ever
asked again — the decode finished, requested a redraw, and the redraw repainted the same empty
list. Every overlay showed its handles and no picture. Now `TransitionRenderer` owns the builder
and calls it in `renderFrame`, so a redraw of *any* cause re-asks it and a still or a video frame
that lands late simply appears on the next draw. The engine supplies only the list and the clock.

**Three things a realtime clock needs that an export's does not** (`realtime` on the builder,
`OverlayClock.shouldSeek`). The export's clock only ever walks forward, so `ExportClipDecoder`
never seeks during a run and "expired" means past the overlay's end. A preview playhead stands
still, jumps and runs backwards: a decoder left behind by a backward scrub would show a later
frame for ever, so it seeks — but only on a real jump, never on ordinary playback, because a seek
flushes the codec (dead-ends entry 11) and never before the decoder's first output, because a
flush that early is what lost the codec's config data in the export's one-clip-never-decoded bug.
A decoder is also freed when the playhead is *before* its overlay, not only after, since a codec
instance held for a picture nobody can see is one the clip lanes may need. And a **video** overlay
asks for a redraw on every clock step, animation or not — over a photo clip nothing else asks for
a draw, so its footage would otherwise freeze.

**A frame that lands after the draw that asked for it** (`OverlayRenderer.onVideoFrameQueued`).
The export waits for the frame; a realtime draw must never block on a decoder, so the preview does
not — which means the frame arrives too late for the draw that requested it, and without something
asking for another draw a paused overlay stays invisible until the playhead moves.

**Stills load off the GL thread in the preview** (`StillSource`), where the export decodes inline.
A decode inside a realtime draw is a visible hitch, so a just-added overlay is missing for a frame
or two and the decode's completion asks for the redraw that shows it. `Pending` and `Failed` are
separate answers because only one of them is worth telling the user about.

**Two things that were quietly broken, fixed here.** `NativeTimelineOverlay.speed` was carried by
the model, settable in the tool, and honoured by **nothing** — the plugin ignored it and
`sourceAt` walked the source at 1×, so a slowed overlay played at normal speed on the canvas *and*
in the file. It is now in `sourceAt`, which both engines resolve through. And **a video overlay's
sound was never mixed into the export**: clip audio and imported music were, its was not, so an
overlay you could hear on the canvas was silent in the file. `AudioExportMixer` now takes it as
one more windowed source, at its own speed so the sound runs with the picture.

**What the Flutter layers are now**: the box the user grabs. The selection frame, corner dots,
rotate/scale handle and action bar, laid out from the same geometry the composer sends the engine
so the handles and the picture agree. Gone with the drawing: one `video_player` controller per
overlay — a decoder and a texture each, **with no cap at all**, where the engine enforces
`OverlayDrawBuilder.MAX_OVERLAY_DECODERS` and warns — and the whole drift apparatus.
`video_player` stays a dependency; three other screens use it.

**Four faults from the second device run, all four confirmed in code before anything was changed**
(fixes **awaiting device verification**; the export was right throughout, which is what pointed at
the realtime half):

- **A video overlay showed a frozen frame from 0:00, before its own start, and never moved.**
  The tail's clock override was written while the tail played and *nothing cleared it*, so after
  one playback through a tail the overlays' clock stayed pinned past the end while the real
  playhead was back inside the video. `OverlayClock.override` now also takes the engine's
  position and is honoured **only while the engine is itself parked at its end** — a stale value
  is made harmless rather than relying on every path remembering to clear it.
- **Nothing showed in the tail.** Two halves. `VideoPreviewCanvas` dropped the texture in the
  tail and drew the background itself — right when overlays were Flutter widgets above it, wrong
  the moment they moved into the texture. The texture now stays, and the engine draws the tail the
  way the export does: `setActiveLane(NO_ACTIVE_LANE)`, so composite paints the background and the
  live overlays and no stale last frame.
- **The main clip played slowly with a video overlay on screen, and drags crawled.** The overlay's
  `ExportClipDecoder` was stepped inside the draw, on the GL thread, as the export does — where a
  single step can block for the 10ms dequeue timeout many times over, on the one thread that also
  presents the clip lanes. `RealtimeOverlayDecoder` moves it to a thread of its own: the draw says
  which frame it wants (`request`, latest wins) and never waits; the frame lands on the overlay's
  `SurfaceTexture` and its arrival asks for the redraw. The codec is opened there too.
  **The builder is kept across edits** (`updateOverlays`): the list changes on every frame of a
  drag, and rebuilding the builder reopened every video overlay's codec each time.
- **The dashed frame did not fit the picture.** It was the fixed 200/240 square the content is
  fitted *into*; `OverlayContentBox` sizes it from the content's own aspect
  (`fittedOverlayBox`, the Dart twin of the fit `OverlayRenderer.writeCorners` applies).

**A drag is one undo step, and costs one composition** — the same report's "the dotted container
moves faster than the picture". Every frame of a move went through `updateImageOverlay` /
`updateVideoOverlay`, which snapshot the whole editor state for undo: sixty snapshots a second,
and an Undo that walked the drag back a pixel at a time. The layers now snapshot once at gesture
start and write through `updateImageOverlayLive` / `updateVideoOverlayLive` — the rule the text
layer already had. `_syncNativeOverlays` composed and JSON-encoded the overlay list **twice** per
push, and — because it runs on every state change — once per *position event* during playback to
learn nothing had changed; it now identity-checks the two overlay lists and the canvas size
(immutable state keeps an untouched list's identity through `copyWith`) and builds the payload
once (`overlayPayload` / `sendOverlayPayload`).

**The frame steps aside while the body is moved** (`_movingId`). What is left after all of the
above is inherent to split rendering: the frame is a Flutter widget drawn this frame, the picture
crosses the channel, is drawn on the GL thread and composited a frame or two later. Two drawings
that cannot agree should not both be on screen, so the frame, handles and action bar hide for the
gesture and return on release. Corner-handle drags keep their chrome — the handle is what is
held. The full fix is drawing the frame in GL with the picture; not worth it until something else
needs it.

**An overlay's sound is the engine's too** (`OverlayAudioPlayers`, `OverlayAudioSync`,
**awaiting device verification**). Device-reported, and mine: the deleted `video_player`
controller had been the overlay's picture *and* its sound, and `OverlayDrawBuilder` replaced only
the picture — the canvas went silent while the export, which mixes overlays itself, stayed right.
One `ExoPlayer` per audible overlay near the playhead, **video track disabled**
(`setTrackTypeDisabled(C.TRACK_TYPE_VIDEO)`). That disabling is the reason this is not another
`just_audio` player beside the imported music: `just_audio` cannot turn a video track off, and
ExoPlayer keeps a video decoder on a placeholder surface when nothing shows it — a hidden
hardware codec per overlay, on top of the two clip lanes and the picture decoders, which is what
a low-end device runs out of first. Slaved to `overlayClockNow`, the instant the picture is drawn
at, so sound and picture cannot part; speed goes through `PlaybackRate.pitchFor`, the rule that
makes the preview sound like the export's resampler.

**"Advancing" is asked honestly, and it is two questions.** Inside the video it is the master
lane *genuinely* playing (`ExoPlayer.isPlaying`), so an overlay cannot be heard over a stalled or
still-buffering picture — the "no playhead moving while the video is stalled" rule, applied to
sound. In the tail the engine is parked and Flutter's ticker owns the playhead, so there it is
whether tail positions are still arriving (`OverlayAudioSync.tailIsAdvancing`): the messages
*are* the evidence of motion, so backgrounding or anything else that stops them stops the sound,
with no second message needed to say so. Scrubbing is never advancing.

`OverlayAudioSync` holds the decisions as pure functions because the players only run on a
device. Its rules are the lanes' own, restated: seek only on a real jump and only while the
player is actually playing (a buffering player's position stands still while the target advances
— the seek loop of fault 9), never re-seek a player already parked on the instant it is starting
from, and change-guard volume and rate (fault 10). Past `MAX_PLAYERS` (4) or on a file whose
sound will not decode, the overlay is silent **and the user is told** through the same `warning`
event the lane fallback uses. Export mixes every overlay regardless, so the cap costs nothing in
the file.

**The overlay audio crackled, and both causes were in that first version**
(**awaiting device verification**).

- **Drift correction was seeking, and every audio seek is a click.** The overlay player and the
  clip lane are two independent ExoPlayers with no shared clock, so they genuinely drift apart
  over a long overlay. I gave the overlay the lanes' own 0.25s tolerance and 600ms cooldown —
  but a video reseek costs a dropped frame nobody notices mid-blend, where an audio seek flushes
  the codec and is *heard*, so the setting that is right for a lane is a crackle every 0.6s here.
  Ordinary drift is now lived with (a few tenths of a second of skew against the picture is
  invisible) and only a jump too large to be drift — `JUMP_SECONDS` 0.5, a scrub, a loop round —
  earns the flush, at most every 2s.
- **Gain was switched, not ramped.** Every start, stop and seek took the player from silence to
  full between two buffers, which is a step discontinuity: a click. `OverlayAudioSync.rampedGain`
  spreads a change over `RAMP_TICKS` (5 × 16ms ≈ 80ms) — too short to read as a fade — and
  **every audible edge now sits behind it**: a seek is taken at silence (`mayStop`) and a stop
  waits for the ramp, so the one unavoidable flush is inaudible. The ramp reaches its target
  *exactly*, with a float slack, because a gain that settles at 3e-8 is silent to the ear and
  non-zero to `mayStop`, which would then refuse to stop or seek for ever — a real bug the test
  caught on the way down. `pauseAll` stays abrupt on purpose: it answers an explicit pause, and
  stopping 80ms late would leave sound running past the button.

**An overlay can be keyed on colour** (**awaiting device verification** — the keying half is
GLSL). `ImageOverlayModel.chromaKey` / `VideoOverlayModel.chromaKey` are the clip's own
`ChromaKey`, and `chromaCoverage`/`despill` are copied verbatim into `OverlayRenderer`'s
fragment shader from `TransitionShaders` — so a green screen keys identically on a clip and on
an overlay, against the one Dart twin. **If one changes they all must.** This is the feature
CLAUDE.md recorded as "deliberately not built yet, for the same reason inverted": a key is a
per-pixel colour decision a Flutter widget cannot make, so the export would have dropped the
green while the preview still showed it. Drawing overlays in GL is what made it a shader line.

**The key reads unpremultiplied colour, and this is the one thing the clip path did not have to
think about.** A bitmap arrives from Android premultiplied, so a half-transparent green texel is
*stored* darker than the green it represents; keying that directly compares the wrong colour and
drops the wrong pixels. The shader divides the alpha out, keys, despills, and multiplies it back
— and skips a fully transparent texel, which has no colour to key and would be a divide by zero.
`enabled` at 0 is the whole early-out, so an unkeyed overlay costs one compare, and an unkeyed
overlay writes no `chromaKey` at all, which is the payload every older build has always read.

**The Chroma tool is on both overlay menus and the sheet serves the selection**
(`chromaKeyOnSelection` / `setChromaKeyOnSelection`, a clip winning when several somehow are), so
there is one chroma editor rather than a second to drift from the first. `_showChromaKeySheet`
borrows a clip **only when nothing at all is selected** — it used to test `selectedSegmentId`
alone, which with an overlay selected would have keyed the clip under the playhead instead of the
overlay the user opened the tool on.

**The realtime decoder killed the app, and it was a teardown race** (**awaiting device
verification**). Device-reported as "crashes on Android 12, mostly when working with video
overlays", first blamed on memory. The logcat named it exactly:

```
FATAL EXCEPTION: slimshot-overlay-decode
java.lang.IllegalStateException
  at android.media.MediaCodec.releaseOutputBuffer(Native Method)
  at ExportClipDecoder.advanceTo, at RealtimeOverlayDecoder.pump
```

preceded by `BufferQueue has been abandoned` and `Codec reported err 0xe`. **The surface was freed
while the codec was still decoding into it.** An uncaught exception on a `HandlerThread` kills the
process, which is why it read as a random crash after minutes rather than as a decoder fault.

The teardown *looked* ordered — decoder, then lane — but `release()` posted the codec release
**behind an in-flight `pump()`**, waited 400ms, and returned regardless; the GL thread then freed
the surface under a live codec. Two further faults made the window wide: `released` was read
**once** at the top of `pump()`, so a walk after a seek (up to the step cap at a 10ms dequeue
timeout each) carried on for seconds after teardown was asked for, and a turn that ran the whole
walk never let the handler see the release message at all.

**Waiting harder is not the fix**, and this is the part worth not re-deriving: teardown is
requested from the GL thread, so blocking it trades a crash for a visible freeze.
`gl/OverlayDecoderTeardown.kt` sequences the two threads instead — the decode thread frees the
codec and *then* hands the surface release back through `onCodecReleased`, so the order is correct
by construction and nobody waits. `giveUp()` is the backstop for a wedged codec: the surface is
freed anyway, because a stranded lane leaks a texture and the overlay could never reopen. All
three release sites go through one `releaseRealtimeDecoder`; a fourth spelling of this ordering is
how the bug would return.

**A dead codec is now an outcome, not an exception.** `ExportClipDecoder.failed` — every
`MediaCodec` call is illegal once the codec has reported an error, and the log also carries
`keep callback message for reclaim`, the system's resource manager **taking a codec away from us**
under pressure. That is not ours to prevent, so it must be survivable: `advanceTo` catches
`IllegalStateException`, marks the decoder failed and returns false, and the overlay stops **with
a toast** through the same `onOverlayFailed` the lane fallback uses. The export path could assume a
healthy codec because it owns the lifecycle; a preview decoder cannot.

**The measured reason it happens at all — and the caps are wrong** (not yet changed). On the
Infinix (Unisoc, Android 12), `adb shell dumpsys media.player` reports for `c2.unisoc.avc.decoder`:

| | |
| :--- | :--- |
| `size-range` | `64x64-1920x3840` — **this device cannot decode 4K at all** |
| `max-concurrent-instances` | 10 |
| `blocks-per-second-range` | `1-864000` |
| `measured-frame-rate-1920x1080` | 42–54, for **one** instance |

Two things that follow, both correcting assumptions in this file. **Instances are not the scarce
resource** — the device allows 10 and `MAX_OVERLAY_DECODERS` is 2. **Throughput is**: 864000
blocks/sec ÷ 8160 blocks per 1080p frame ≈ **105 fps of 1080p across every decoder combined**. Two
clip lanes at 30fps spend 60 of that; each 1080p overlay spends 30. Two lanes plus two overlays is
120 — over budget, which is what invites the reclaim. **And decoding smaller is not available**:
`KEY_MAX_WIDTH`/`KEY_MAX_HEIGHT` are adaptive-playback buffer hints, not output scaling, so
MediaCodec offers no portable way to decode a stream below its native size.

`maxSupportedInstances` is read **only** inside `ExportCapabilities.probe()`, which merely logs,
while the numbers that govern behaviour are hardcoded in two unrelated files
(`OverlayDrawBuilder.MAX_OVERLAY_DECODERS`, `OverlayAudioPlayers.MAX_PLAYERS`) and compared
against nothing. For the one resource that is genuinely scarce the app neither probes nor degrades
— the standing rule unfollowed. A budget derived from `blocks-per-second` is the next piece of
work, deliberately **not** bundled with this crash fix: shipping both together would leave no way
to tell which half was wrong.

**What it unlocks**: an overlay chroma key and blend modes, each now a shader line rather than an
impossibility, and an exact feather instead of a hard-edged clip.

### Draft files — a draft owns its folder

A draft is JSON in preferences that *points at* files, and until now those files were scattered
and orphaned: proxies went to `getTemporaryDirectory()`, which `FileUtils.cleanupStartup` sweeps
by prefix at every launch — so a draft reopened after a restart pointed its reversed clips at
nothing — and `DraftService.deleteDraft` deleted only the thumbnail, leaving the proxies, cover,
frozen frames and background photo behind for good.

`lib/core/services/draft_files.dart` is the one place that knows where a draft's files live.
Proxies render into `drafts/<id>/proxies/` under the documents directory (both proxy methods on
`VideoEditorService` take an `outputDir`; the notifier passes the draft's — a project with no
draft yet still falls back to temp). `DraftFiles.deleteAll(id)` removes that folder **and** the
root-level files named for the draft (`cover_<id>_*`, `freeze_<id>_*`, `bg_<id>_*`), and is called
from `deleteDraft` and `clearAll`. It matches on `<kind>_<id>_` so a look-alike id (`d1` versus
`d10`) cannot take another draft's files — a test pins that.

**A reopened draft heals itself and says so once.** `loadDraft` drops any `overrideVideoPath`
whose file is gone (`_healMissingProxies`): the clip is fine — it plays from its source — and a
reversed clip **keeps its reversal**, losing only the dead file. The screen toasts one notice
(`takeLoadNotice`, consumed on read) and the reversed clips' proxies are rendered again in the
background (`_renderReverseProxy`, the second half of `toggleReverse` on its own). Until that
render lands the clip plays forward, and export still refuses a reversed clip without a proxy by
name, which is the honest state. `rerenderMissingProxies: false` exists only so tests, which have
no FFmpeg, can exercise the heal.

### Speed curves — source time as an integral

**Device-verified by the user:** the export is right, the preview's picture follows the curve, and
after the pitch fix below the preview's sound matches the export's with the glitches gone. **Not
yet checked on a device:** splitting a curved clip, and a curve on a reversed clip. A clip's speed
can ramp:
`VideoSegment.speedCurve` (`logic/speed/speed_curve.dart`) is speed as a function of **where in
the footage** the clip is, and the flat `speed` and a curve are **exclusive** — setting a curve
resets `speed` to 1, and committing the Speed slider clears the curve.

**This is why speed was never a keyframable property.** Every other one is read *at* a progress,
while speed decides what progress *means*: `duration` divides by it and `clipProgressAt` divides
by `duration`, so a keyframed speed makes progress a function of itself. A ramp needs source time
to be the **integral** of the speed curve, which is its own model — the same reason CapCut ships
speed as a separate curve tool.

The curve is parametrised over the **source**, not the timeline, so a point placed on a moment of
the footage stays on that moment however the curve around it is reshaped. Speed interpolates
linearly between points, which keeps both directions closed-form per segment: reaching source
fraction `x` takes `∫ dx/v(x)` of timeline — a **logarithm** where the speed ramps, a division
where it is flat (`timeToSource`, and `durationFactor` for the whole clip) — and the frame due at a
timeline instant is that integral's **inverse**, an exponential (`sourceAtTime`). Everything that
asks "how long" or "which frame" goes through the segment: `duration`, `sourceAtOffset`,
`speedAtOffset`, and `timelineTimeToSourceTime`, which now delegates to `sourceAtOffset` rather
than carrying a second copy of the mapping.

**The Kotlin port is pinned by `test/fixtures/speed_curve_fixture.json`** (regenerate with
`dart run tool/generate_speed_curve_fixture.dart`, then re-run **both** sides), the same mechanism
and the same caveat as the animation fixtures: it catches divergence tomorrow, never a wrong curve
today. What pins the arithmetic *today* is `speed_curve_test.dart`, which checks `timeToSource`
against a **numeric trapezoid integral** of `1/v` on every preset — a sign slip in the logarithm
cannot pass as "roughly right".

**The engine steps the player's rate along a ratio ladder** (`PlaybackRate.quantise`, rungs 3%
apart, 1.0 exactly on a rung), while the exact integral still decides where the clip *is*
(`sourceOffsetAt`). Still a step rather than the exact value, because handing ExoPlayer new
`PlaybackParameters` sixty times a second is the audio-pipeline churn of fault 10. **A ratio, not
a fixed amount**: the first version stepped by 0.05, which is 2.5% at 2x and 12.5% at 0.4x — over
a semitone per step, in exactly the slow-motion range a ramp lives in. The master clock inverts
with `timelineOffsetForSource`, since a curved clip's player position no longer divides by a
scalar.

**In the preview, pitch follows speed** (`PlaybackRate.pitchFor`, device-reported). The export's
audio path is a resampler, so a ramp is *heard* in the file: the sound drops through the slow
section and rises through the fast one. The preview sent ExoPlayer a bare speed, which leaves
pitch at 1 and makes Media3's Sonic **time-stretch** — a different sound, and one that restarts
its stretcher on every rate step, audible as small glitches several times a second. The user's
words: the export sounds right and the preview does not. With pitch equal to speed, Sonic's
`processStreamInput` computes `speed / pitch == 1`, skips `changeSpeed` and runs only
`adjustRate` — a plain resample, the export's own operation (checked in Media3's source, not
assumed). `FLAT_SPEED_SHIFTS_PITCH` applies the same rule to flat-speed clips, so one statement
holds everywhere: **the preview sounds like the export.** What remains is that the preview steps
where the export glides sample by sample; closing that fully means the preview no longer playing
audio through ExoPlayer.

**Export audio follows the curve in source time.** `PcmAudioSource` takes an optional
`speedAtSource` and recomputes its resample `step` per output frame from the source seconds it has
consumed, so the sound tracks the same clock the video decoder is stepped by — a fixed step would
slide against the picture through the ramp. (The pitch caveat above is unchanged: the linear
resampler shifts pitch where the preview's Sonic does not.)

**A curved clip never merges with its neighbour** (`_canMergeForPlayback` refuses on either side
carrying a curve): a merged media item has a different source range, and the curve would land on
other frames. **A split cuts the curve** (`SpeedCurve.splitAt`): each half is rescaled into its own
0..1 and both read the original's speed at the seam, so the halves add up to the whole length and
play through the cut unchanged.

**The sheet is presets first, the graph second** (`panels/speed_curve_sheet.dart`). Seven named
curves plus Normal, each tile drawing its own shape — "Montage" and "Bullet" are words for
pictures. A tap is the whole interaction for most users; dragging any point makes the curve the
clip's own (`presetId` goes null, so nothing is highlighted, which is the truth about what it is).
**Only the speed moves**: dragging a point sideways would slide the moment being shaped out from
under the finger. Speed maps to height **logarithmically**, because linearly 1× would sit at a
tenth of a 0.1×–10× graph. A drag is one undo step (`beginClipSpeedCurve` snapshots and pauses —
reshaping the curve changes the clip's length under a running playhead — then
`setClipSpeedCurveLive` writes per frame).

**The graph claims the pointer on pointer-down** (`_ImmediateVerticalDragRecognizer`). It sits
inside the sheet's `SingleChildScrollView`, and against a *vertical* competitor the scroll view
simply wins the arena — the graph was undraggable in the sheet while working perfectly in
isolation. Third occurrence of this fault, after the trim handles and the `ValueRuler`.

### Chroma key — a coverage keyed on colour

**Awaiting device verification** (the keying half is GLSL). `VideoSegment.chromaKey`
(`logic/chroma/chroma_key.dart`) drops a colour so the project background shows through: a key
colour, a `similarity` window, a `smoothness` edge and a `spill` strength, off on every clip until
someone turns it on.

**It is the mask's sibling, and that decides where it lives.** A mask is a coverage keyed on
*where* a pixel is; a key is a coverage keyed on *what colour* it is. Both multiply into the same
`mix(backgroundAt(), graded, …)` at the end of `incomingAt`/`outgoingAt` — the only place in the
pipeline where a clip pixel can be replaced by what is behind it, since the clip pass has no GL
blending and `glClear` uses an opaque background, so an alpha would be a value nothing reads.
Every transition inherits the key for free, and a keyed clip fading is a keyed clip, fading.

**It cannot be an effect pass**, and this was checked before anything was written. The effect chain
runs on `scene.textureId` — the finished composited frame, one texture in and one target out — by
which point the clip's green has already been drawn over the background and there is nothing behind
it to reveal.

**The key reads the source texel, before `gradeClip`.** A green screen is a property of the
footage; keying after a grade would change which pixels drop every time the user moved a colour
slider. Despill runs on the source too, so the grade then treats the de-fringed picture exactly as
it treats an unkeyed one.

**Keyed on hue direction, with saturation as a second term — both halves measured.**

- Plain RGB distance fails the basic case: a green screen is never evenly lit, and a 45% green sits
  0.46 from a full green in raw Cb/Cr, as far as a sensible similarity window reaches, so the
  shadowed corners of the screen survive the key. Normalising the chroma vector to a **direction**
  fixes it — a shadowed green and a lit green now key identically, which a test pins.
- But hue alone is **binary along the desaturation axis**: a full walk from green to grey gave 0.0
  then 1.0 with no value between, so the soft edge where a hair or a motion-blurred arm lives
  collapsed to a hard cut and `smoothness` did nothing at all. Weakly saturated pixels are
  therefore pulled toward "keep" in proportion to how grey they are, which is what gives that edge
  its ramp. A test walks the axis and fails if the gradient disappears again.

Greys and near-blacks are never keyed — they have no hue to compare, and a shadow on set is not the
screen. `similarity` at zero still takes the key's own hue (the saturation term carries it) and
only widens into the neighbouring hues as it rises, which is what the slider is for.

`chromaCoverage` and `despill` in Dart are the twins of the shader's, and exist because GLSL only
runs on a device: **if one changes the other must.** The two vec4s are
`(r, g, b, similarity)` / `(smoothness, spill, enabled, 0)`, encoded once on each side
(`ChromaKey.uniforms`, `NativeTimelineClip.parseChroma`) and tested to match. `enabled` at 0 is the
whole early-out, so an unkeyed clip costs the shader one compare.

**Two differently keyed clips never merge** into one media item, and a split carries the key to
both halves. The sheet is a toggle, four screen colours and three rulers behind pills, with the
tuning hidden until the key is on; **turning it off keeps the tuning**, so comparing keyed against
unkeyed is not destructive.

### Decisions already made â€” don't re-litigate

| Question | Decision |
| :--- | :--- |
| Canvas for mixed shapes | **Fixed 9:16**, overridable from the crop tool; every clip letterboxes into it. Reverses the earlier "tallest imported clip" rule â€” deriving it from media made the canvas resize mid-session, which flashed. |
| Photo duration | 3s default, either edge draggable, no upper bound. |
| Import entry points | Both â€” multi-pick to start *and* an in-editor Add button, sharing one picker. |
| Audio across a transition | Equal-power (`cos`/`sin`) crossfade. Reverses an older "no crossfade" rule; the hard requirement is that audio never gaps. |
| Export engine | Native (preview engine â†’ encoder), not FFmpeg, not PVE. |
| Filter scope | Both: a project look **and** per-clip looks, switched by one "apply to all" toggle and kept mutually exclusive so nothing grades twice. |
| Transition scope | Same toggle in the transition sheet; "all" writes every seam except the last. |
| Transition frame source | Two live decoders. Freeze-frame was built, reviewed and rejected. |
| Panels vs sheets | **A tool that edits on the canvas or the timeline is an in-place panel; a set of choices about the picture is a sheet.** Crop, clip crop, Trim, Zoom and Speed stay panels — a sheet is modal and would cover the very surface they edit (handles on the canvas, handles and the stretching clip on the timeline). Curve, Transform, Filters, Effects, Transitions and **Background** are sheets. Volume could go either way and stays a panel; the two kinds share `AppMotion` and the same look. |
| Dismissing a panel | **Back and a tap on empty canvas space close an open panel, keeping its edits** — modal semantics, as a sheet's dismissal keeps its live edits; ✕ stays the explicit discard. Exception: a canvas-editing tool (`kCanvasEditingTools`: crop, clip crop, zoom) ignores the canvas tap, because touching the canvas is how it is used. Back closes any tool. Only with no tool open does Back leave the editor. `logic/tool_dismissal.dart`. |

Fuller detail, ordering, and the test matrix are in `docs/roadmap.md`. Approaches already tried and
rejected are in `docs/dead-ends.md` â€” read it before proposing an architecture.

## Rules to protect

From user testing. Each of these has been violated at least once â€” treat them as acceptance
criteria, not aspirations.

- No spinner during normal split/trim playback.
- No black flash at clip boundaries.
- **No playhead moving while the video is stalled.**
- No success notification before a result is actually usable.
- No audio disappearing silently, and no gap in audio at a transition.
- Applying or retuning a transition must not force unrelated clips to reload.
- Don't remove unfinished tools â€” keep them visible and implement later.
