# SlimShot AI â€” Working Notes

A Flutter video editor + media compression app (Android-first). The editor **has migrated** from a
Flutter/`media_kit`/`pro_video_editor` stack onto a native Android **Media3 + OpenGL** engine:
preview, transitions, overlays, text and export all render natively, and both packages are
deleted. The one editor dependency left to remove is FFmpeg, used now only by the two clip
proxies; FFmpeg itself stays in the app for the compression feature.

## Commands

```powershell
flutter run --dart-define-from-file=env/env.json
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
  cannot find resolves to no glyph. **Its ISC notice is the app's to carry now**: the package
  listed it on the licences page itself, and once vendored nothing did — found by a font licence
  audit (2026-10-28) and registered in `core/legal/third_party_licences.dart` (`kLucidePackage`),
  pinned by `third_party_licences_test.dart`.
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
41 transitions, their labels, icons, categories and FFmpeg `xfade` names (now a record only —
export is native), plus `resolveTransitionDuration`
(clamps to 45% of the shorter neighbouring clip). The drawer, the composer, the export mapper and the
Kotlin shader registry all key off this. Adding a transition = one entry here + one body in
`LayeredTransitions.kt` (the eleven earliest live in `TransitionShaders.kt`).

`EditorTransition.name` is persisted into drafts and sent over the channel â€” renaming needs a
migration. Unknown names (e.g. `circleOpen` from old drafts) degrade to a hard cut, never a crash.
**`test/fixtures/transition_names.json`** is the one list both sides test against
(`transition_names_fixture_test.dart`, `TransitionNamesFixtureTest`), so a name the sheet offers and
the engine lacks fails a test instead of shipping as a hard cut.

**Layered transitions** (Stage 2 part 1; spec `docs/superpowers/specs/2026-10-10-transitions-engine-layers-design.md`;
**device-verified** — preview, export, masks over a background photo, the earlier transitions
unchanged). The GL Transitions ports read each clip many times per pixel
(CrossZoom ~80, FilmBurn ~100), and through `incomingAt`/`outgoingAt` — fit, crop, grade, mask
and key on *every* read — they would crawl on the low-end target. So a layered transition
(`TransitionShaders.isLayered`) draws each lane **once per frame into a layer**
(`layerFragment`: the finished picture premultiplied by its coverage, transparent where no clip is)
and reads only the two layers through the library's own API (`getFromColor`, `getToColor`,
`progress`, `ratio`), then lays the result over `backgroundAt()` at the fragment's own position.
For any blend linear in its inputs that is exactly today's `mix(bg, picture, coverage)`, so masks,
keys, opacity and a background photo behave as they always have, and the background stays put while
the clips move. **A port must carry alpha through**: the original's forced `a = 1.0` would paint
black where the background should show. **The eleven earlier transitions keep their own path,
byte for byte** — `TransitionShadersGoldenTest` hashes every source they compile; the header's
`backgroundAt` and `outputColor` were moved into shared constants and the hash proves the header
assembles to the same text. Layers are frame-sized `RenderTarget`s, allocated on the first layered
frame, released with the effect targets and when a timeline has no layered transition; a device that
refuses them plays a dissolve **and says so once**. The blurred background's cover picture draws a
layered transition as a dissolve — the blur hides the difference. **`TransitionQualityGovernor`**
(preview only): when the median of 12 layered frames, swap included, is over 45ms, heavy
transitions drop to their light version (Zoom Blur: 12 steps instead of 40) for the session —
**logged, not toasted** (the user's call: the export always draws the full version, so a lighter
preview is nothing to interrupt anyone with; a refused-buffers dissolve still toasts, because the
file itself differs). **Device-verified on the Infinix**, which trips the check: its preview plays
the light Zoom Blur. **Zoom Blur** (`zoomBlur`, CrossZoom, MIT,
rectalogic) is the first, and the first transition with a shader loop — the only other is
`BlurPass`; if Zoom Blur shows a plain dissolve-like picture on a device, the loop is the first
suspect.

**Sixteen more layered transitions and a sheet that plays them** (Stage 2 part 2a; spec
`docs/superpowers/specs/2026-10-10-transitions-sheet-and-ports-design.md`; **device-verified
2026-10-10** — the sixteen transitions on the canvas and in the file, the moving tiles and
tap-to-play). The bodies live in `gl/LayeredTransitions.kt`, each with its
author, licence and what was changed: Slide & Scale ×4 (DirectionalScaled), Split In/Out
(splitSlideIn/OutHorizontal), Bounce, Swirl, Spin Away (RotateScaleVanish), Zoom In-Out, Dreamy
Zoom, Motion Blur (tangentMotionBlur), Defocus (DefocusBlur) from gl-transitions.com (MIT), and
three of ours — **Whip Pan, Shake, Zoom Bounce**. The port rules: the library's uniforms become
constants (a uniform nothing binds reads as zero on a device — a test rejects any stray one), loops
count in `int`, randomness is interleaved gradient noise rather than the `sin`-`fract` hash that
overflows `mediump`, and alpha is carried through. Only Zoom Blur, Motion Blur and Whip Pan have a
light version (`hasLightVersion`); they are the step-heavy ones. Every shader was compiled with
`glslangValidator` (`#version 100`) before shipping — not a device, but it catches what the
runtime compiler would refuse.

**The sheet is category pills over tiles that play the real transition** (`TransitionsDrawer`).
`TransitionCategory` (Basic, Motion, Blur, Light, Glitch, 3D) is on each catalog entry;
`offeredTransitionCategories` hides an empty one, and the sheet opens on the seam's own
transition's category. A tile is **the engine's drawing**: `TransitionRenderer.renderTransitionPreview`
runs the transition's own program — a layered one with the samples as its layers, an earlier one
with them as two photo lanes — between two pictures drawn in code (`TransitionPreviewSamples`,
stored upside down so GL's bottom-up rows come out upright), reads 16 frames back as JPEGs, and
the tile loops them on one clock (rest, transition, rest — `previewFrameAt`), held while the grid
scrolls. `TransitionPreviewFrames` asks for them **one at a time** — the renderer's thread is the
live preview's — keeps them for the session, and remembers a failure so the tile keeps its icon.
Skipped while an export holds the renderer. **Four tiles to a row** (`kTransitionGrid`, not the
text grids' three): under the pills, duration and Apply to all, a 45% sheet leaves the grid about
180px on a phone. **A tap applies the transition and plays it on the canvas** —
`_playTransitionOnCanvas` pauses (which is what lets the new transition reach the engine), parks
the playhead 0.6s before the window (`transitionWindowFor`), plays, and pauses 0.4s after it; any
pause in between cancels the stop, so it never stops a playback the user started. None plays
nothing.

**Light, Glitch and 3D — thirteen more** (Stage 2 part 2b; spec
`docs/superpowers/specs/2026-10-10-transitions-part2b-design.md`; **device-verified
2026-10-10**, Film Burn after the per-vertex fix). Overexpose, Film Burn, Flash (ours); RGB Split, Lost Signal, Static,
Datamosh, Displace, Flicker; Revolve L/R and Cube L/R. **Every sin-fract hash became
`slimHash`**, which folds its inputs to 0..1 before combining so it cannot overflow `mediump`
(Drop_Zone_Flicker's `p * 443.9` did), and the hashing ports ask for `highp` behind
`#ifdef GL_FRAGMENT_PRECISION_HIGH`; a test fails on any `43758` in a layered source. **Light is
light on the lens, damage is to the picture**: leaks, flashes, sparks and strobes wash the whole
frame, bars included, as Fade White does; scanlines, noise and exposure pulses are scaled by the
picture's coverage. Right is Left mirrored, one line apart (the Cube mirrors its geometry, never
the pictures on its faces). Light versions: Film Burn and both Revolves.
**Film Burn places its blotches in a vertex shader of its own** (`Body.vertex`,
`layeredVertexFor`; device-reported: perfect in the export, jumpy and barely visible in the
preview). Each of its thirteen blotch centres is two noise lookups — sixteen hashes and fourteen
`pow`s — with the same answer for every pixel of a frame; per pixel that was over two hundred
hashes, which the export waited out and the preview could not. Worked out at the quad's four
corners and handed down as seven varying rows (of the eight GLES2 guarantees), it is the same
arithmetic at no cost. `uProgress` is declared `mediump` there because the fragment declares it
so — a shared uniform of two precisions does not link, which glslang's link check confirms.
Its light version had also dropped to 5 blotches, so the speed check switching mid-transition
made 8 vanish at once; it now keeps all 13 and differs only in blur taps. **Every other
transition still links the shared vertex shader**, and a test pins it. **The six pills share
the row** rather than scroll it — at natural width they ran past a phone's edge, hiding 3D —
each label scaled down where large text would not fit.

**Easing on transitions** (Stage 2 part 3; spec `docs/superpowers/specs/2026-10-10-transitions-easing-design.md`;
**device-verified 2026-10-11**). A curve button beside the duration opens the keyframes' own
easing sheet; each choice applies and plays on the canvas. **The picture only**:
`NativeTimelineTransitionIntent.pictureProgressAt` is the window's progress through the curve,
read by the shader in both engines, while the sound's equal-power crossfade keeps `progressAt` —
an eased crossfade would surge, and a bounce would swing the sound back. Per seam on
`VideoSegment.transitionEasing`, **null for a straight line, linear never stored**, so a seam
without a curve writes nothing new to the draft or the engine. **Clearing a transition clears its
easing inside `copyWith`**, which is what covers None, reorder, a split's left half and the last
seam without each site remembering; a split's right half carries it. An easing-only edit takes the
engine's soft path (`sameWindows` sets easing aside). The tiles stay linear.

**Open-source licences** (`core/legal/third_party_licences.dart`): the GL Transitions MIT notice
and every ported author are registered in `main()`, and Settings → LEGAL opens Flutter's
`LicensePage` on the root navigator. **A new port adds its author to `kGlTransitionsAuthors`** —
the credit beside the shader in `LayeredTransitions.kt` does not ship in the APK.

### Conventions

- **State:** Riverpod `StateNotifier` + `.autoDispose`. Hand-written immutable state, no `freezed`.
  `copyWith` takes `Type? value` **and** `bool clearValue = false` for every nullable field.
- **Undo:** manual. Call `notifier.saveStateForUndo()` *before* any structural edit. Transient
  preview edits (`previewVolume`, `previewSpeed`) only snapshot on `commitPreview*()`.
- **Serialisation:** hand-written `toJson`/`fromJson`, defensive on read
  (`(x as num?)?.toDouble() ?? default`).
- Colours from `AppColors`, never hard-coded. Dark theme only. Lucide icons.
  **`panel_theme_test.dart` enforces this across `widgets/panels/`**, because
  the rule held in the newer sheets and had never reached the five older
  drawers — 40 sites on `Colors.white`/`white54`. Not pedantry:
  `textPrimary` is Zinc 50 and `textSecondary` Zinc 400, a different hue *and*
  weight from pure white and 54% white, so the two generations of sheet read
  differently side by side. Titles diverged with them, 13px against 14px.
  What the test deliberately allows, because both generations already agree
  and the theme has no token for them: `white24` for a grab handle, `white12`
  for an inactive slider track, `white10` for a divider, and pure white for a
  glyph sitting *on* the purple accent, where the contrast is the point.
  **A selected tile is `primaryStart` over `border`** — the Background,
  Effects and easing grids' pattern; the crop panel's white ring was the last
  surface saying "selected" in a second language.
- **Motion comes from `AppMotion`** (`core/theme/app_motion.dart`): Material 3 emphasized —
  380ms decelerate in, 260ms accelerate out, leaving always quicker than arriving. Sheets
  (`showEditorSheet`), the bottom-area switcher (`EditorPanelSwitcher`), the `AnimatedSize` around
  it and the timeline's compact resize all read it, because they used to run on three clocks and
  a height that lands before or after its content reads as a stutter. The sheet route fixes its
  own curve, so it takes only the durations. A panel slides in from *fully* below, like a sheet,
  not the old 40% nudge.
- **A sheet does not repeat the name of the tool that opened it.** Tapping
  "Transform" and being told "Transform" is a line of chrome describing what the
  user just did. The five drawers have shipped titleless and nobody has missed
  one; the space goes to the controls. What stays is a title that is *not* an
  echo — the cover picker opens from an unlabelled card, and the speed curve's
  header keeps the clip's resulting **duration**, the one number the graph does
  not show.
- **White on purple, never dark.** `primaryStart` is the chosen-state fill
  everywhere (background tiles, effect grid, easing cells, the apply-to-all
  check) and the glyph on it is white. The theme guard exempts exactly that
  case.
- **`ApplyToAllToggle` is a label and a check, not a Material `Switch`.** The
  switch plus two stacked lines cost ~70px at the top of a sheet capped at 45%
  of the screen, for a control glanced at once. It is **"Apply to all" and the
  check, nothing else** — the explanatory second line went too, because a
  checkbox does not need prose to say whether it is ticked and the sheet read
  "Apply to all clips · One look over the whole video", one fact twice. The
  **whole row** is the tap target rather than a 20px box at its end. `ApplyToAllButton` is left alone: it is a
  copy *action*, already compact, and correctly reads as a button. Its one
  variant is the `label`: on a caption the text editor says **"Apply to all
  captions"**, because there "all" is not the clips.
- **The Transform sheet's mirrors live in its header**, not under the Rotate
  ruler. Each tab is one continuous value set by dragging; a mirror is an
  instant on/off that applies to the whole placement. Under a tab they were
  invisible from the other two — a user had to already know they were there.
  Icon-only with a tooltip, since a flip glyph beside the words "Flip H" says
  it twice.
- **Sheets open through `showEditorSheet`** (`widgets/panels/editor_sheet.dart`), never
  `showModalBottomSheet` directly — a test scans `lib/` for strays. It paints **no barrier tint**:
  a sheet here is a set of choices *about* the picture (a curve, a filter, a transition), and
  Flutter's default `black54` dimmed the frame exactly while the user compared them. The barrier is
  still there — a tap outside still closes — it just draws nothing. It also carries the two
  settings every sheet shared (`isScrollControlled`, transparent route background).
- `unawaited(...)` for fire-and-forget. `ToastUtils.show(context, msg, isError:)` for user feedback.
- **A toast is a compact pill at the top of the screen, never a banner**
  (`core/utils/toast_utils.dart`, **awaiting device verification**).
  Device-reported: the old full-width `AwesomeSnackbarContent` card was
  pinned flush to the top, so deleting a draft raised a "Success!" banner
  over the drafts screen's own action buttons and the user waited ~4s for
  their UI back. **The pill sits at the screen title's row, Apple-notification
  style — the user's position, twice corrected** (a first pass centred it on
  screen; a second floated it below the app bar, which read as "inside the
  screen"). What fixes the covering is compactness and tap-through, not
  distance: it drops in 8px below the safe area and slides down/up with a
  fade on `AppMotion`'s curves. **It is the island** (the owner's pick of four, 2026-10-24,
  **awaiting device verification**): a black pill (`background`) with a faint white edge that
  drops in and grows from 85%, like the iPhone's Dynamic Island, the severity a solid disc of
  `success`/`warning`/`error` with a white glyph (check, triangle, cross), the words in the
  interface face — before, a grey pill whose only colour was a 16px icon. Rules a test pins
  (`toast_utils_test.dart`): compact (sized to its text), top-centred, **no
  title** — "Success!" above "Draft deleted" is the echo rule, severity is
  the icon and its `AppColors.error/warning/success` colour — tap to
  dismiss (through the same smooth exit), one at a time (a new toast
  replaces the current, never stacks), and taps outside the pill pass
  through, because `Align` hit-tests only its child. **The pill drives its
  own lifecycle**: an `AnimationController` for enter/exit and one hold
  `Timer` cancelled in `dispose` — deliberately not `flutter_animate`,
  whose `Animate` starts through `Future.delayed`, a timer nothing can
  cancel, which trips flutter_test's "Timer is still pending" invariant in
  every test that shows a toast. `awesome_snackbar_content` is gone from
  the build. **A toast test pumps one frame before asserting**
  (`settleToast`): the enter starts at value 0 on the entry's first frame,
  and a slide moves hit geometry with it (`SlideTransition` transforms hit
  tests), so a single long pump meets the pill mid-flight off its layout
  position.

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
still overlap on canvas, so an antialiased *ink edge* inside the overlap re-composites. The
**shadow no longer does**: each cell casts only its own glyph's shadow, built from the glyph's
tile before rasterising (see the text-shadow section), so a shadow is drawn once however cells
overlap. Until that landed every cell carried the whole run's shadow cropped to the cell, and
the overlap drew it twice — darker, stepped at each cell edge, and (once the shadow stopped
being cut off) 1682 halo pixels off the flat raster at blur 8. The reassembly tests gate ink
hard (`60 × glyphCount` pixels, max delta 80 — a real double-composite saturates near 255) and
halo with per-case measured numbers (every shadow case 60; measured 16 at the default, 0 soft
and 7 hard at the far corners of the controls, 0 at the widest blur). Masking a
cell's *rasterised pixels* to its own glyph still cannot work (nothing attributes a pixel to a
glyph) and a max/coverage blend would break alpha for every overlay; the per-glyph shadow works
because it is built from geometry, not attributed afterwards.

**A letter drawn on its own draws only itself, and every shadow goes under every letter**
(`caption_cross_line_test.dart`, `text_shadow_order_test.dart`, **awaiting device
verification**). Device-reported on a two-line caption: a sweep left white holes in words already
spoken, and Pop dragged a scaled ghost of line 1 across it. A cell draws the whole run clipped to
itself, and its padding — sized for the outline and shadow — reaches the other line at caption
size, so a line-2 cell repainted line-1 letters in line 2's colour and motion. Invisible while
every letter looked alike; wrong the moment a highlight made them differ. Two rules now:

- **Ink within its region** (`glyphInkRegions`): a letter's outline and fill are bounded halfway
  to its neighbour on the line and halfway to the next line, plus a pixel of overlap so touching
  letters cannot seam; the padding is kept only at the text's outer edges. Halfway into a space
  means two words never share pixels. The canvas painter and the atlas both draw within it.
- **Shadows first.** Drawn letter by letter with each shadow beside its own ink, line 2's shadow
  landed on line 1's letters — up to 60/255 of grey on white, on every highlighted caption and
  every exported multi-line text with a shadow (the alpha-only reassembly tests could not see it:
  a shadow over an opaque letter changes its colour, not its alpha). The canvas paints in two
  passes (`paintTextOverlayInk`'s `shadow` / `ink`); the atlas gives each shadowed letter a
  **shadow cell** of its own (`RasterizedGlyph.shadowAtlasRect`, `shadowAtlas*` on the wire,
  omitted for a text without a shadow) and `TextQuads.shadows` draws them all before
  `TextQuads.glyphs` — placed by the same `forEachPlaced`, so a shadow can only sit under its own
  letter, one per letter however a sweep splits it.

With nothing lit, letter by letter now draws the letters identical to the whole text; what remains
is the halo residual below.

**A text's shadow has one painter: `paintTextOverlayInk`** (`text_overlay_geometry.dart`,
`text_shadow_test.dart`, **awaiting device verification**). Device-reported as "the shadow is
only on the left". Rendered and measured in tests, three faults, each fixed:

- **The export cut the shadow off.** The flat raster was exactly the text box (8px outer
  padding) and atlas cells were padded by 1.5 × the blur radius (12px), while the shadow reaches
  ~19px down and right (offset + 3σ of the blur) and ~11px up and left. The file kept the soft
  left and top and lost the rest in a straight line — alpha 66 on the raster's last column, 51 on
  its last row. `TextOverlayLayout.shadowReachFor` is the reach; `textGlyphBleedPadding` pads
  cells by it, and the flat raster grows an **even** margin (`RasterizedTextOverlay.rasterPxSize`)
  so its centre stays the box's. The export places the flat raster by that size and keeps
  `canvasPxSize` — the text box — for the slide travel, which is the widget's own size. **No Kotlin
  changed**: sizes already cross the channel as numbers.
- **An outlined text had two shadows**, one per text style, and the fill's was painted over the
  outline beneath it.
- **A `Shadow`'s blur ignores the canvas scale.** The export draws at 2–3× the canvas's
  density; measured, a shadow faded over 12 box px at 1× and 6.7 at 3× — twice as sharp in the
  file as on the screen.

So **no text style carries a shadow any more**. `paintTextOverlayInk` casts it once — the
silhouette (outline included) in the shadow colour through a `saveLayer` with an image-filter
blur of the same sigma a `Shadow` uses, which *does* scale with the canvas — then paints outline
and fill over it. The canvas (still and animated), the flat raster and the atlas all call it.
With `shadowFrom` it casts from one glyph's tile only: that is how each atlas cell and each
animated letter carries its own letter's shadow, drawn once, travelling with the letter.

**The shadow is the user's: colour, opacity, blur, distance, angle** (`text_shadow_settings_test.dart`,
`text_editor_shadow_test.dart`, **awaiting device verification**). Only the colour used to be
adjustable. `TextOverlayModel` gained `shadowOpacity` (0–1, multiplying the colour's alpha —
`TextOverlayLayout.shadowColorFor`), `shadowDistance` (reference px) and `shadowAngle` (degrees,
**the direction the shadow falls, clockwise from pointing right**: 90 is straight down),
beside the existing `shadowBlurRadius`. The old fixed shadow — blur 8, offset (blur/2, blur/2),
opaque — is exactly the defaults (`kTextShadowDefault*`, distance 4√2 at 45°), so:

- **A draft saved before the controls opens pixel-identical.** No `shadowDistance` key means
  legacy: with a shadow, the geometry is re-derived from the stored blur by the old rule; without
  one, the stored blur 0 was part of "no shadow" and becomes the default, or a shadow chosen
  later would sit hidden exactly under the letters.
- **The tuning survives the colour being cleared**, so choosing a colour again brings the shadow
  back as it was. A shadow is drawn when it has a colour, some opacity, and a blur *or* a
  distance (`hasShadow`) — blur 0 with a distance is the hard shadow.
- **Blur and distance stop at 20** (`kTextShadowMaxBlur`/`kTextShadowMaxDistance`) because the
  export's raster margin and atlas cells are sized from the shadow's reach, and the reassembly
  tests measure the atlas up to exactly those values. Clamped on read, angle folded into [0, 360).
- **The per-glyph shadow is cast through an unantialiased tile clip** (`doAntiAlias: false`): an
  antialiased clip split each boundary pixel between two cells and source-over put them back
  short of whole — a hairline seam through a hard shadow at every letter (198 px off the flat
  raster at the far hard corner; 7 without).
- Anything that copies a text's style field by field must copy all five — the animation tile
  did, and `shouldRepaint` compares them.

**One case keeps the flat raster**: text whose atlas exceeds the 4096px texture limit even at
floor density. Text with a **background box** used to be the second — the glyph pass drew
letters only, so the box would have vanished — until the box became a cell of its own (the
word-highlight section). A fallback means "no per-character animation, no word highlight" and
**warns** when it costs one of them. A rejected atlas still wrote its PNG, so it is registered
for deletion or an unusable atlas leaks a file per export.

`TEXT_ATLAS_MAX_PX` (4096) is separate from `OVERLAY_IMAGE_MAX_PX` (1024) on purpose: the 1024
cap is generous for a photo in a small overlay box, but decoding an atlas at 1024 would
downscale it and make exported text *blurrier* than the flat raster it replaced.

**Tests that measure text must use `kTestFontFamily`** (`test/support/test_fonts.dart`) —
Montserrat Bold, bundled, so text lays out against a real face's metrics. A server font draws in
the System face until it is downloaded, which no test does, so a test naming one would measure
the fallback.

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
cross-slot id and the tile shows a still frame. The painting shell — clock sweep, measure, fit,
clip, chrome — is `TextPreviewTile`, shared with the template tiles; the animation tile only
builds its synthetic overlay and span.

**A tile fits the whole look and fills itself with it** (`text_preview_fit_test.dart`). It
used to fit the text *box* and scale only down, so a shadow or an outline — which reach past
the box — was cut at the tile's edge, exactly where a glow or a far drop shadow lives, and a
short word sat small in an empty tile. The fitted extent is the box grown by
`textGlyphBleedPadding` (the reach the export pads by, so the tile holds what the file does),
scaled to meet a `kTextPreviewMargin` both up and down, capped at `kTextPreviewMaxUpscale`
(1.5×) so "Hi" does not become two giant glyphs. The `ClipRect` is now only for animation,
which moves letters past the resting look.

**Every grid of preview tiles is `kTextPreviewGrid`**: three to a row, a little wider than tall.
The animation tab ran four to a row in taller tiles beside a Templates tab of three — the same
kind of tile, sized differently from one tab to the next — and tests pin both grids to the one
constant.

**One clock drives every tile.** A repeating `AnimationController` on the panel, passed to each
visible tile as its `clock`; only the active category is built, so switching tabs does not leave
twenty animations running. A `Ticker` per tile would mean twenty tickers.

**The clock holds still while its grid scrolls** (`holdPreviewClockWhileScrolling`, both the
templates grid and the animation tab; **awaiting device verification**). Device-reported: the
templates sheet scrolled rough and felt hard to move. Measured before changing anything: every
tile redoes its text layout and casts its shadow into an offscreen layer per letter on each tick
— ~12ms of UI work a frame for the catalog on a desktop CPU (0.2ms for a plain text), several
times that on the phone, plus ~50 offscreen layers — and that took the frames the scroll needed.
Held on scroll start and resumed on scroll end, a tile is a picture the scroll only moves. **A
grid replaced mid-scroll never reports the scroll's end**, so the animation tab, whose grid is
keyed by category, restarts the clock on a category switch or every tile would stay frozen. The
templates grid also took the platform's clamping physics where its neighbours bounce; it bounces
now.

**The slider is Speed, not seconds.** It writes the multiplier the model has held since Stage 2
(`animationInDuration`/`animationOutDuration`, and `loopSpeed` for the Loop tab), labelled `1.4×`.
`saveStateForUndo()` fires on drag start and `updateTextOverlayLive` per change, so a drag is one
undo step.

**Only what the flat raster genuinely loses triggers the fallback warning**
(`textFallbackWarning`). Reported from a device: a boxed text warned that its animation could not
export character by character, while the export was identical to the preview — the animation
was a fade, `isPerGlyph: false`, which the flat path animates as a whole quad. The gate requires
`isSelectable` **and** `isPerGlyph`, or a caption's word highlight; anything else draws the same
picture either way and stays silent. Since boxed text takes the atlas, the one fallback left is
text over the 4096px limit.

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
   **And a rebuild no longer flashes either** (`LanePicture`, `LanePictureTest`, **awaiting
   device verification**). Device-reported on the speed curve presets: a curve changes the
   clip's length, so it rebuilds, and `loadBlockFor` invalidated the lane on screen the moment
   its items were replaced — background until the re-prepared decoder delivered. The lane the
   user is looking at now keeps its picture through a rebuild that leaves it on screen
   (`rebuildShownLane`, set only for `setTimeline`'s own loads), so the frame holds until the
   one at the new position lands, as on a seek. Every other load still drops it: a lane
   prepared off screen holds another clip's last frame, which a transition would blend in.
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

### Effects track — bars on the lanes, over the main video

**Awaiting device verification.** Spec: `docs/superpowers/specs/2026-10-20-effects-track-design.md`,
plan beside it in `plans/`. Roadmap item 16, its first part: a bar applies to the **main video**
(the clips and the background, under every overlay, text and emoji, which stay sharp on top).
Whole frame and one overlay are next; Whole frame waits on the preview drawing text in the engine,
since Flutter paints text above the engine's picture where no effect can reach it.

An effect is something that happens *at a moment of the video*, not a property of whichever clip
is there. A clip-owned effect could not span a cut, could not stack, could not start mid-clip, and
through a transition showed only the outgoing clip's. So an effect is a **bar on the shared
lanes** (`EffectBarModel`: effect id, start, end, lane, intensity), beside text, photos, video
overlays and audio. `laneSpansOf` includes bars, so moving, trimming, snapping, copying, deleting
and closing empty lanes are the lane rules already there (`lane_layout.dart`), each gesture one
undo step through `beginTimelineGesture` / `endTimelineGesture`.

- **Effects is on the main menu** (id `effects`, after Overlay) and opens the effects sheet.
  **The sheet acts on the selected bar**: with none, a tap adds one; with one, a tap changes its
  effect — so browsing while the sheet is open does not litter the timeline, and closing before a
  tap adds nothing. No None tile (Delete removes a bar, Undo backs out an add), no title, no
  Apply to all. A tap on the effect the bar already wears takes no undo step. A new or changed
  effect starts at the catalog's `defaultIntensity` and `defaultEnvelope`, and a change drops the
  intensity's keyframes — that curve belonged to the old effect.
- **A new bar** (`newEffectBarSpan`) lands at the playhead, `kDefaultEffectBarSeconds` (3) long,
  on the first free lane there, and **fits inside the project**: near the end it ends at the end,
  starting earlier only to keep `kMinClipDurationSeconds`. Adding one never makes the project
  longer.
- **A selected bar's menu is Edit · Copy · Delete** (`_effectBarMenu`, registered as
  `effect_bar`). Copy goes straight after the original on its lane where there is room, else to
  the nearest free lane below — the audio rule: an effect continuing.
- **Selection is exclusive**: selecting a bar clears every other selection, every other select
  clears the bar's; playing does not.
- **Drawn in `AppColors.effectTrack`** (Blue 500 — photo bars were already teal), with the
  effect's icon and name, the sparkles glyph in the lane gutter, and its intensity diamonds under
  its handles. Hidden in recording mode with every other lane.

**Bars live in timeline time.** Trimming, moving or deleting a clip does not move a bar —
CapCut's behaviour, and the reason a bar can span a cut. **They count toward the project's end**
like every lane item, through `projectEndSeconds` (`logic/timeline/project_end.dart`), the one
function the composer, `totalEditedDurationProvider` and `ScrollableTimeline._totalEditedDuration`
all read — so a bar past the last clip extends the project over the background instead of being
drawn where taps do not land.

**One keyframable property, intensity**, with the clips' and overlays' diamonds, plus button,
easing sheet and edit rule — `keyframe_core.dart` through a one-parameter adapter; the selected
bar is the third kind of keyframe target (`keyframeEffectBar`) beside a clip and an overlay.
**Progress is the bar's own 0..1**, so trimming a bar stretches its curve — the overlay rule. The
slider shows the value its write lands on (`effectBarEditIntensity`, `clipEditValue`'s rule), and
a drag pauses and is one undo step (`beginEffectBarIntensityEdit`).

**Which bars draw at an instant is one rule, written twice and pinned once**: `effectBarsDrawnAt`
(`logic/effects/effect_stack.dart`) and Kotlin's `EffectStack.drawnAt`, pinned by
`test/fixtures/effect_stack_fixture.json` — regenerate with `UPDATE_EFFECT_FIXTURE=1 flutter test
test/features/video_editor/logic/effects/effect_stack_fixture_test.dart`, which writes the copy
under `android/app/src/test/resources/` too, then re-run the Kotlin suite. The usual caveat: it
catches divergence tomorrow, never a wrong rule today.

- A bar draws on `start <= t < end`, **half-open**, so two bars meeting at a seam never both draw
  there.
- **In lane order**, the bar nearest the clips first, each later one over the result.
- **Within `kMaxEffectPasses` (4), whole bars only.** Each costs its catalog `passCount` — blur
  and blur_in 2, glow 4 (`EffectShaders.glowPasses` builds four; the catalog had said 3),
  everything else 1, with `EffectPassCosts.kt` holding Kotlin's copy. A bar that does not fit is
  skipped **whole** — a blur is never cut in half — and the walk goes on, so a later bar that fits
  still draws. An effect id the catalog does not know draws nothing and costs nothing.
- **Intensity resolves at whole-bar progress** (the diamonds' clock), clamped 0..1. **The
  shader's progress runs over `introSeconds` from the bar's start** for a timed effect and rests
  at 1; across the whole bar otherwise. That ended a latent mismatch: Dart placed a clip's
  intensity diamonds on whole-clip progress while Kotlin resolved them on the intro window, so a
  keyframed intro drew a different strength from the one the slider showed.

**A skipped bar is said once, by name** (`newlySkippedEffectBar`, `effectSkippedMessage` —
"Dreamy is skipped: too many effects at once"). The drawn set changes only at bar edges, so the
check runs once between each pair of edges, before and after an edit, and only a bar skipped now
that was not before is named: a bar already skipped is not announced again on every later edit,
and a list arriving into an empty one — a draft opening — says nothing, since one bar alone always
fits. It is a toast although preview and file agree, because a bar on the timeline drawn nowhere
reads as an effect that does not work.

**Through a transition a bar applies to the blended frame**; the old "outgoing clip's effect owns
the window" rule is gone, with nothing to replace it. **In the tail** it applies to what Main video
is there: the background.

**The engine** (`NativeTimelineEffect`, `EffectStack`, `gl/effects/EffectStackController.kt`):

- **Bars travel on their own channel, `setEffects`** — the `setOverlays` pattern — sent from every
  place overlays are sent: draft load, import, Add, Replace, and the state listener, which runs
  mid-drag, so a bar dragged, trimmed or retuned moves on the canvas under the finger.
  `EffectBarsSync` answers a position event by the list's identity and an equal rebuilt list by
  its payload text, so playback composes nothing. The export reads the bars from the timeline
  (`EditorTimeline.effects`, which carries `introSeconds` from the catalog and leaves out an id the
  catalog does not know).
- **No program is linked in the render path.** `EffectStackController.setBars` builds — in one GL
  hop, when the list arrives — as many instances of each effect's passes as the most bars of that
  effect ever drawn at once (`EffectStack.peakInstances`), and frees what the new list no longer
  needs. `apply` only chooses among built passes and pushes intensity and progress as uniforms,
  so crossing a bar's edge costs a list swap. Uniforms are pushed before the pass list; when only
  uniforms moved, `redrawEffects` asks for the frame.
- **The preview draws at `overlayClockNow`**, the instant the overlays are drawn at, so a bar in
  the tail follows the tail's playhead. `applyEffects` runs after `applyOverlays`, in the tick and
  on a tail clock update.
- **One writer at a time.** While an export holds the renderer, `setEffects` only records the list
  — a GL hop then would block the main thread until the export ended — and
  `reattachSurfacesAfterExport` builds, re-asserts and draws it. The export calls `setBars`
  **before its first frame**, `apply` on every frame including the tail, and `clear` + `release`
  in `finally`. That first `setBars` has no JVM test (the export engine needs GL); it was found
  missing by reading the diff, and an export with no effects in it is the symptom if it goes.
  **A fresh controller's first `apply` always hands its list over, empty included**: the export's
  controller is a second one on the preview's renderer, which may still hold the preview's passes
  — a bar under the paused playhead — and "nothing changed" from its own empty start left them
  there, so every exported frame before the first bar wore that effect.
- `composite` is unchanged: lanes and background into the scene, the stack's passes over it, then
  overlays.

**Old projects are converted on load** (`migrateClipEffects`, before `normalizeLanes`). Each
clip's effect becomes a bar `effect_<clipId>` covering exactly where it showed — from the end of
its incoming transition window (the outgoing clip owned the window), or the clip's start, to the
clip's end — with the same effect, base value and envelope, and its keyframes re-placed on the
same timeline instants: rescaled to bar progress, any before the bar's start dropped, one pinned
at the start carrying the value there, **linear**, since the rest of an eased segment is not the
same easing shape. **One accepted difference**: a timed effect on a clip entered through a
transition used to join its intro part-way; its bar plays the intro whole from the window's end.
A clip carries no effect any more — not on the model, in the draft or on the wire — and the draft
is saved in the new form, `effectBars` omitted when empty.

**What went with the clip's effect**: the clip menu's Effects, `setClipEffect`,
`applyEffectToAllClips` and the sheet's Apply to all, `ClipProperty.effectIntensity` (clips keep
six keyframable properties), the effect checks in `_canMergeForPlayback`, the effect in
`clipToOverlayLosses`, freeze frame's effect copy, `ClipEffectController`, `applyClipEffect` and
the export's per-frame effect clip.

**Device checks** (GLSL and timing only run there): a bar starts and stops on the right frame in
the preview and in the export; two stacked bars; a bar across a transition; an intro plays from
the bar's start; playback crossing a bar's edge does not hitch; an old project with effects looks
the same; a bar in the tail; a bar dragged or trimmed updates the canvas live; a glow stacked on a
blur toasts once.

### Effect tile previews — each tile plays its effect

**Awaiting device verification.** Spec:
`docs/superpowers/specs/2026-10-21-effect-tile-previews-design.md`, plan beside it in `plans/`.
Twenty of the 39 effects are intros or reveals whose whole point is motion, and a tap adds a bar
at the paused playhead — the canvas shows only the effect's first instant, black for a fade-in. So
each tile plays **a new bar's opening on the sample picture** — **a city at dusk**
(`gl/EffectPreviewSample.kt`), not the transition tiles' sunset, which the user found showed the
effects poorly: an effect is judged by what it does *to* a picture, so the scene carries what every
kind needs — highlights (moon, stars, lit windows), edges (the skyline), a full tonal range,
saturated colour (two neon signs) and a regular grid (the windows) that a distortion visibly bends.
Designed by rendering a pure-Python port of the scene and the Sparkle maths first and looking at
the result; drawn in code, upside down like the transitions' samples,
drawn by the engine's own shaders: 0.4 s plain, then the bar's first 1.6 s **in real time** at
15 fps, on one shared clock that holds while the grid scrolls. The sample bar is pinned equal to
what `addEffectBar` + `composeEffects` produce for every catalog effect
(`effectPreviewSampleBar`), so a tile cannot promise a look a tap does not give.

- **One image per effect, never a frame list.** An atlas of 25 cells
  (`effect_preview_layout.dart`: 160×144 on 16-px JPEG block boundaries, 5×5, inset a pixel so
  filtering cannot bleed a neighbour) is drawn once per session and decoded by the tile into a
  `ui.Image` **it owns** — deliberately not `Image.memory`, whose decoded frames pile into
  Flutter's shared `ImageCache` (up to 100 MB, evicted on its own schedule; the transition tiles
  still do this, below). `EffectPreviewPainter` paints one cell per tick of the sheet's frame
  index (`super(repaint:)`), not per vsync.
- **Bounded memory.** The grid keeps no tiles off screen (`cacheExtent: 0`), so decoded pictures
  are only what is visible (~2.3 MB each, ≈28 MB worst case, zero when the sheet closes); every
  async step in `EffectPreviewStage` checks a generation bumped on dispose and on a change of
  effect, and **a decode that lands stale disposes the image it got** — tests pin it with
  `debugDisposed`. The encoded JPEGs (`EffectPreviewAtlases`, a non-autoDispose provider) are the
  session's and are dropped on `didHaveMemoryPressure`.
- **No wedged queue, no work for nobody.** The cache draws one effect at a time; a tile's ask is
  a ticket withdrawn on dispose, so closing the sheet or flicking through a category drops asks
  that have not started; a drawing that does not answer in 10 s counts as busy. **Failed is
  remembered, busy is not**: the engine answers bytes, null (this phone cannot draw it — the tile
  keeps its icon for the session) or `error("busy")` (no renderer, an export, the editor closing —
  retried on the next ask). A drawing future is re-wrapped to the result type before `.timeout`,
  because a renderer answering `Future<Never>` made the fallback a type error that let the error
  escape.
- **The GL side never stalls the canvas.** `TransitionRenderer.renderEffectPreview` runs
  `EffectPreviewJob`: at most 4 cells per GL turn, each slice posted behind the live preview's
  queue, re-checking the host (released / exporting) and making the context current again (an
  export may have run between slices). Everything it draws with is its own — the sample texture,
  the atlas target, a private `EffectPassChain`, its own pass instances — so the live effect
  stack's passes are untouched; JPEG encoding runs on a single encoder thread, never the GL one.
  **Answered exactly once on every path** — `release()` abandons live jobs, since `quitSafely`
  drops what they would post and an unanswered call leaves Dart's queue waiting forever.
- **The tabs run lasting looks first, then the timed ones** (`kEffectPanelCategories`, the
  user's call): **Retro leads by name**, so a fuller shelf (Light, since the drawn pack) cannot
  push it down; the other lasting shelves follow fullest first, and Intro and Reveal
  — whose effects play a fixed 0.5–1.2 s opening and then rest, however long the bar — come last.
  Fullest first within each group because the sheet opens on the first tab and two or three tiles
  read as "this is all there is". Worked out from the catalog (a shelf is timed when its effects
  carry `introSeconds`), so a new entry reorders the tabs with no edit to the panel. **Whether the
  timed effects belong under Effects at all is open**: they behave as clip In animations
  (roadmap item 17) or as stretchable "Intro" bars — talked through with the user, left as they
  are for now.
- **The stage falls back to the icon** while an effect has no atlas or could not be drawn; cached
  bytes decoding show the empty stage, so a scroll back never flickers icon-to-picture. The clock
  is made in the panel's `initState`, not `late final` — nothing reads the controller until a
  scroll notification, and a lazily made clock never starts (caught by the frame-index test).

**Device checks**: every category's tiles play and look right (the effect, not a dissolve-ish
blur); the canvas does not stutter while tiles draw during playback; the profiler's memory stays
within ~28 MB of decoded tiles while browsing every category and falls when the sheet closes;
atlas JPEGs measure ≤ 150 KB (tune `PREVIEW_JPEG_QUALITY` if over); an export run after browsing
is unaffected, and tiles asked during an export keep icons and fill in afterwards.

### Tile drawings kept on the phone — the icon is seen once

**Awaiting device verification** (2026-10-28; the owner's call: keep the icons, see them once).
The Transitions and Effects tiles' drawings — a transition's 16 frames, an effect's atlas — were
held for the session only, so every launch drew them again and every first open of a sheet showed
the tiles turning from icon to picture one by one. **`TilePreviewStore`**
(`logic/tile_preview_store.dart`) keeps each drawing on the phone the moment the engine draws it,
in `<app support>/tile_previews/<build>/<kind>/<name>.bin` beside the font previews (and, like
them, left alone by Clear Cache), so a later launch reads it back instead of asking the engine.

- **One build's drawings are never another's.** The folder is named for the build — Android's
  version code **and install time** (`AppBuildChannel.kt`, `slimshot_ai/app_build`,
  `appBuildStamp`), so a debug rebuild with a changed shader counts as a new build even with the
  version code unchanged — plus `kTilePreviewFormat` (frame count and size, the atlas layout), so a
  Dart-only change to those names a new folder too. Every other build's folder is cleared when this
  one is found: a phone keeps one build's worth — roughly 10–15 MB once every tile has been drawn. No build known (a test, a
  failed lookup) means nothing kept or served.
- **Nothing waits on it.** `has` answers at once and is false until `prepare` has read the folder,
  so a tile asked for before then is simply drawn, as it always was — in widget tests, where an
  unanswered platform call never completes, that is every tile. The editor screen calls `prepare`
  in `initState`, long before either sheet can open. A kept drawing is read back **straight away,
  never queued behind a drawing** (reading a file takes nothing from the GL thread).
- **Written whole or not at all** (`.part`, then renamed; a leftover `.part` is cleared). A
  transition's frames are one file, each frame's length then the frame (`packTransitionFrames`);
  an atlas must read back as a whole JPEG. One that does not is forgotten and drawn again.
  **A failure or a busy engine is never kept**, so the next launch tries again.
- **The tiles** (`_TransitionTileState`, `EffectPreviewStage`): the icon stands in only while the
  engine draws — the first time, since the drawing is then kept — or where it could not, and the
  picture fades in over it (`kTilePictureFadeIn`, 150ms, the icon held through the decode so the
  two cross-fade). A drawing held in memory or read back from the phone shows the bare stage and
  simply appears. None keeps its crossed circle. Tests use `MemoryTileStore`
  (`test/support/`), since a real file never finishes reading under the test clock.

### Effects — the multi-pass framework and 47 effects

**Awaiting device verification** beyond the four already checked (`fisheye` perfect, `vignette`
working after a reshape, `glow` fixed but unseen; `sharpen`, `blur` and `chromatic` reworked
after device reports that they barely showed, below). Spec:
`docs/superpowers/specs/2026-09-12-clip-effects-design.md`.

Effects were built per clip — one per clip, from the clip's menu — and live on the timeline as
bars since the effects track (the section above), which owns where an effect applies and when.
This section is the drawing underneath, unchanged by the move: bar → `EditorTimeline.effects` →
`NativeTimelineEffect` → `EffectShaders` → the pass chain. `logic/effects/effect_catalog.dart`
is the single source of truth and the panel reads it — there is no second list, and a test counts
the grid's `itemCount` against the catalog so a new entry cannot silently miss the UI.

**The renderer was single-pass, and that is why blur never existed.** `composite()` bound
framebuffer 0 and drew straight to the output, so any effect needing the frame *back* — blur,
glow, bloom — was impossible; this is also why the background tool's `blur` option falls back to
black. `gl/RenderTarget.kt` and `gl/EffectPassChain.kt` add render-to-texture and a ping-pong
chain (`MAX_EFFECT_PASSES` 4, two targets allocated per size change and reused). **With no
passes the frame takes exactly the old path** — the diff that introduced this removed two lines
and both reappear in the no-passes branch.

**The pass budget is per *frame*.** Only the bars under the playhead draw, so a project of any
length with an effect every few seconds costs nothing extra: a blur at 0:40 is never drawn at
0:05. The budget binds only where bars **stack**, and the effects track's rule spends it — whole
bars in lane order, a bar that does not fit skipped and named.

`MAX_EFFECT_PASSES` is a **correctness bound, not a performance one** — enough for a separable
blur plus a composite, and a hard stop on a future catalog entry quietly asking for twelve.
Whether a given device sustains four is a different question, and the answer is the standing rule:
**probe at runtime and degrade loudly**, never assume from one handset. 44 of the 47 effects are
single-pass, so the cap is reached by stacking blur-class effects, not ordinary ones.

**The chain runs inside `composite`, before overlays.** That is what keeps text or a sticker on a
blurred clip **sharp**: effects treat the clip picture, overlays sit above it. Do not move the
chain out or the overlay draw in.

**A grade is per-lane, an effect is whole-frame.** `applyLaneGrades` sets a colour matrix per
lane *before* the blend, so two clips can cross-fade between different looks. An effect pass runs
*after* compositing, on the finished frame — which used to force a rule, the outgoing clip's
effect owning a transition's window, since a frame between two differently-effected clips had two
answers. A bar is not a clip's, so it simply applies to the blended frame and the rule is gone.

**`uProgress` is the bar's own 0..1 position, from the timeline clock.** Effects began with no
notion of time, which made every *intro* effect impossible — a cinema zoom or a shutter reveal is
nothing but a function of time. It is resolved through `EffectStack.shaderProgress` in both
engines, never a frame counter or `System.nanoTime`: export runs faster than realtime, so
anything self-timed renders differently in the file than on the canvas. `VideoEffect.introSeconds`
makes an effect *timed* — progress runs over that opening window from the bar's start and then
sits at 1 — while a static look gets whole-bar progress and ignores it. A zero-length window
returns 1.0, not a division by zero, or a `fade_in` would park on black.

**The drawn pack — Thunder, Rain, Snow, Embers (a new Nature tab), Light Rays, Lens Flare,
Sparkle, Neon (Light)** — is CapCut's most used looks of the kind a shader alone can draw
(`gl/effects/DrawnPack.kt`, **awaiting device verification**; the user asked for "the ones you
can"): no footage, nothing downloaded, nothing tracked, so no app size and the file matches the
canvas by construction. **They keep time in seconds** — `uSeconds`, the bar's own
`barSeconds` (`EffectStack`, Dart's `ActiveEffectBar`, pinned by the stack fixture), uploaded
through `TimeControlled` — because the bar's 0..1 would make rain on a ten-second bar fall at a
third of the speed it falls on three. Timeline seconds, never wall clock. The pack's rules:
intensity 0 is the untouched picture; `highp` where the GPU has it (seconds outgrow `mediump`
within a minute); a sine-free hash (`packHash`, Hoskins' "Hash without Sine"); no reversed
`smoothstep` edges; sizes in frame units. **Every shader was compiled and linked against the shared
vertex shader with `glslangValidator` (Khronos 16.6.0, `#version 100`)** —
`DrawnPackShadersTest` writes each to `<java.io.tmpdir>/slimshot-shader-dump/`; not a device, but it is
what the runtime compiler would refuse. The thunder strikes once per 1.6s window, early in it, so
a short bar and the sheet's tile both see a bolt. **Sparkle was all but invisible at first**
(device-reported via the tiles: a glint's core was under a pixel in a tile, and its twinkle was dark
most of the time); it is now large four-point glints with diagonal rays and a glow, two layers of
cells at 4.5 and 8.5 to the frame's height, each glint faded out before its cell's edge so no
boundary cuts one, and it **starts at 95%** (the user's call). **Still to come, needing more than a shader**:
real-footage effects from the server (blended video loops) and face-tracked effects (on-device
landmarks, analysed once per clip) — talked through with the user, not started.

**Intensity and progress are `@Volatile` uniforms uploaded per draw, never constructor
arguments.** Baking intensity into a pass meant `passesFor` rebuilt and re-linked the programs on
every change, so dragging the slider would have linked a program per frame. `IntensityControlled`
and `ProgressControlled` are the interfaces; a pass that forgets one ships a slider that silently
does nothing. `EffectStackController` builds when the bars arrive, never when one starts.

**`callOnGlThread` runs inline when already on the GL thread.** Export froze at ~15% with no
error: `runVideo` already runs inside `callOnGlThread`, and per output frame it resolved the
frame's effect, which hopped to the GL thread *again* — posting a block behind the call waiting
for it. The thread blocked on itself at the first frame whose clip carried an effect. A deadlock
is not a failure anything can report, which is why it presented as a frozen progress bar.

**Device-found shader lessons worth not repeating:**

- **A vignette must not correct for aspect.** Correcting put the farthest points on the long
  *edges*, so on a 9:16 clip the darkening read as a band across the top. A lens darkens toward
  its own corners: plain UV distance normalised to the half-diagonal gives corner 1.0 and edge
  midpoint 0.707 on any canvas shape.
- **A reduced copy buys sampling density, not reach.** Glow was invisible because the halo was
  ~8px at 1080p, and its fix blurs a half-res copy believing the same 16 taps then reach twice
  as far. They do not: `BlurPass`'s radius is a fraction of the viewport it is *handed*, and the
  half-size draw is handed the half-size viewport, so it blurs the same share of the picture.
  What the copy buys is room — a radius past the full-res cap (0.014 of the short side) that
  the taps still cover without banding — and the cap has to be raised to use it, as Soft Blur
  now does (`BlurPass.chain(maxRadiusFraction:)`). **Glow's halo is therefore still ~15px at
  1080**, its comments to the contrary; found while fixing Soft Blur, not changed, since the
  device has not judged it yet.
- **Strength is measured in the frame, never in texels** (`EffectStrengthTest`,
  **awaiting device verification**). Sharpen was a one-texel laplacian and showed nothing even
  at 100%: the preview's texture is drawn on screen smaller than it is, and shrinking averages
  a one-texel halo away. It is now an eight-tap ring `SharpenPass.SAMPLE_RADIUS` (0.0035) of the
  short side out — ~2.5 texels on the preview, ~4px at 1080, never under one texel — on
  brightness only, past a noise floor, with the lift capped (`HALO_LIMIT`), which is what lets
  the amount reach 3× where the old kernel had to stop at 0.9. Default 0.5.
- **A fringe grows with the distance, not with its cube.** Fringe moved red out and blue in by
  `r²` along a direction that itself grew with `r` — cubic — so the middle of the frame moved a
  third of a pixel at 100% and only the top and bottom edges showed anything. It is now what a
  lens's lateral colour is, a magnification difference about the centre
  (`ChromaticPass.MAX_SPREAD` 0.03 × intensity × distance): ~4px halfway to a 1080 frame's side
  at the new 0.5 default, ~16px at a corner. A uniform scale needs no aspect correction.
- **A wide blur is drawn into a reduced copy chosen per frame** (`StandaloneBlurPass`). Soft
  Blur stopped at the full-res cap, ~15px at 1080 — barely soft on a phone — and its `ramp_out`
  envelope held the middle of every bar at the radius floor. It now reaches 4× the cap (a sigma
  of ~2% of the frame) at intensity 1, with no envelope. `downscaleFor` picks the least power of
  two (≤ 8) that brings the radius in pixels inside the 16 taps, so a light blur draws at full
  resolution exactly as before and a copy is used only where the gaussian hides it (≥ 2.5
  reduced texels of sigma). Copies are kept per scale and dropped on a size change; a refused
  copy falls back to the full-res blur. Blur In is unchanged.
- **The shared hash returned nothing on the device** (`EffectHashShadersTest`, **awaiting
  device verification**). `hash11` was `fract(sin(x) * 43758.5)` at `mediump`, and a 16-bit
  float stores a number near 43758 to the nearest 32 — the fraction is always zero. The
  argument had been guarded against overflow everywhere; the multiplier never was. On the
  Infinix's PowerVR, which takes `mediump` literally, **Glitch never tore even at 100%,
  Handheld and Super Shake sat at one fixed offset, Film Grain was a flat darkening, VHS's line
  jitter froze, Grid Reveal arrived as a plain fade and Steady In did not shake** — the first
  three device-reported, the rest found from the same cause. The hash now runs in `highp`
  behind `#ifdef GL_FRAGMENT_PRECISION_HIGH`, with a small multiplier a 16-bit float can still
  take the fraction of where the GPU has no high precision.
- **Randomness the same for every pixel of a frame is planned on the CPU**, not hashed in the
  shader: exact on every GPU, and testable. **Glitch** (`GlitchPlan`): stepped 12 times a
  second, in bursts — 0.5s windows that strike or stay clean, nearly all striking at 100%, the
  first always (so a bar, and its tile, opens on a glitch), never more than three clean in a
  row — up to four torn blocks (wrapping), channel splits, now and then a band's channels
  swapped, sent as `uBlock0..3`/`uGlitch`. **Handheld and Super Shake** (`CameraShake`): the
  pose is smooth value noise in the bar's own **seconds** — a hand's sway under 2Hz with an
  8.5Hz tremor and under two degrees of turn; a shake's 5–11Hz jolts, three and a half degrees
  and a punch in — sent as `uPose`; Super Shake also blurs along the path each point travelled
  over a 1/60s exposure (`uPosePrev`, five taps). They had drawn a fresh hashed offset per frame
  — white noise, a vibration rather than a camera, even where the hash worked — at a rate per
  bar, so a longer bar shook slower. A fixed zoom per intensity and canvas shape
  (`CameraShake.coverFor`) keeps every pose's edges off screen; a test sweeps the corners
  through every frame. `CameraShake.sampleOf` is the shader's `shakeUv`, step for step — if
  one changes the other must.

**Randomness in a shader must be a deterministic hash**, of UV and of `uProgress` where it should
move. Never `Random()`, never a frame counter. And **`mediump` overflows around n≈515** in
`fract(sin(n*127.1)*…)`: hash seeds must be folded to 0..1 per term rather than summed and
wrapped at the end, or grain bands flatly on some GPUs and not others. **The `* 43758.5` is
the other half**: at `mediump` it leaves no fraction at all, so a sin-fract hash runs in
`highp` where the GPU has it (`EffectShaderLib`'s `hash11`), and randomness shared by a whole
frame belongs on the CPU (`PlanHash`), as above.

**`BlurPass` holds the only loop in the codebase** — 16 taps indexing `uWeights[i]`. Spec-legal on
ES 2.0 (Appendix A constant-index-expression) but with no driver precedent here, so it is
**unverified on hardware**. Every other shader deliberately avoids loops. If `blur` renders
unchanged footage on a device, that loop is the first suspect and the fallback is unrolling it.

### Animatable parameters — envelopes and keyframes

**Awaiting device verification.** An effect bar's intensity is an `AnimatableDouble`
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
reason. Only `glow` (`throb`) carries a default envelope — Soft Blur's `ramp_out` went once
effects became bars, since on a bar stretched over a moment it left the middle unblurred, and
a bar saved with it keeps it; static grades
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

A clip carries six keyframable properties, all `AnimatableDouble`: `canvasScale`,
`canvasOffsetX`, `canvasOffsetY`, `canvasRotation`, `volume` and `opacity` (a seventh,
`effectIntensity`, went to the effect bars with the effect itself). **`speed` cannot join them, and
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
they take a segment and return a segment, knowing nothing about the playhead or Riverpod. Since
overlay keyframes they are thin adapters over **`keyframe_core.dart`**, which owns what a diamond
does for clips and overlays alike — see the overlay keyframes section below.

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

**Progress is whole-clip for every property** (`clipProgressAt`). The same rule holds on an
effect bar, whose diamonds run on whole-bar progress while the shader's `uProgress` keeps the
intro window — that is the *effect's* clock, a different quantity that happens to share a range,
and resolving a diamond against it would put it somewhere the timeline never drew it.

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

**Opacity is the sixth keyframable property** (`VideoSegment.opacity`, `ClipProperty.opacity`,
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
`setClipProperty`, so a fade in is two diamonds. Overlay opacity goes through the same rule since
overlay keyframes (next section) — a text's included. Fading to
the project background rather than to black was the open question; the background it is, since
that is what the bars already show and a fade that revealed a different colour would read as a
flash.

### Overlay keyframes — the same diamonds on text, photos and video

**Awaiting device verification.** Spec: `docs/superpowers/specs/2026-09-25-overlay-keyframes-design.md`,
plan beside it in `plans/`. A text, photo or video overlay keyframes **position (x, y), scale,
rotation and opacity** with the clip's diamonds, plus button, easing sheet and edit rule. Text
colour is deliberately not in this batch: it needs its own export colour pass.

**One core, two adapters.** `logic/animation/keyframe_core.dart` is what a diamond *does* —
capture, remove, move, ease, the edit rule, split — over a `KeyframeParams<P>` map, for any set of
named `AnimatableDouble`s. Every function returns **the same map instance** when it changes
nothing, which is how callers tell a refused edit from a done one. `clip_keyframes.dart` and
`overlay_keyframes.dart` only say which parameters an item has. A fix to what a diamond does is
therefore one fix: **capturing on an existing diamond keeps it, curve and all** — a split that
landed exactly on an eased diamond (a tapped diamond parks the playhead there) used to straighten
the curve leaving it, on clips too.

**The tracks ride beside the plain fields.** `position`, `scale`, `rotation` and `opacity` stay
exactly what they were — the **base values** every existing reader uses — and
`OverlayKeyframes` sits next to them; `OverlayMotion` is the two as one value (`motion` /
`withMotion` on each model). An overlay with no diamonds writes no `keyframes` key and sends the
engine **byte-identical** JSON — a golden captured before the change pins it. Text gained
`opacity` with this, and now sends its own where a constant 1.0 used to go.

**`shownAt(seconds)` is what the canvas draws and what a gesture anchors on, and is never written
back into state.** Progress is overlay-relative (`overlayProgressAt`, 0 for a zero span), so
trimming an overlay stretches its motion with it — the clip rule.

**The keyframe target** (`VideoEditorState.keyframeOverlay`): the selected overlay, unless a clip
is selected — a clip wins, as for the mask. `hasKeyframeTarget`, `keyframeTargetProgress` (null
off the span, never clamped) and `keyframeDiamonds` feed the playback bar and the timeline;
`playheadKeyframeProgress`, `keyframeCurveTargetProgress` and `keyframeCurve` dispatch. Every
notifier command dispatches through `_editSelectedOverlayKeyframes`, which reports "handled" even
when nothing changed, so a command meant for an overlay can never fall through onto a clip.
**A command that changes nothing takes no undo step** — a second plus from a double tap landing
before the button flips to minus, a minus off every diamond, a plus off the target — on clips as
well.

**Live edits** go through `setOverlayMotionLive`, which folds every given property through the
edit rule on **one** params map — between diamonds the first write places the diamond and the
rest find it. Three guards, each for a real failure: `id` drops a write whose gesture's overlay is
no longer selected (a second finger can select another overlay mid-drag, and the first gesture's
stale callback may fire once more); a value that is not finite is skipped (`jsonEncode` refuses
NaN, so one bad frame in a keyframe would fail every later draft save); opacity is held to 0..1.

**`beginLiveEdit` pauses, then takes the one snapshot a gesture shares** (`beginOverlayEdit` is
it, guarded on an overlay being selected). Clearing `isPlaying` is enough because the screen drops
engine position events and the tail ticker stands still while it is false, so every frame of the
gesture resolves the same instant. Without the pause, a drag at a moving playhead leaves a trail
of diamonds — which is why the clip Opacity slider, the Effects intensity slider and a diamond's
long-press drag now start with it too; they had the same flaw before overlays had keyframes.

**On the canvas** every layer draws `shownAt(playhead)`, and every gesture anchors on
`overlayEditValue` — the value its write will land on — never on the stored base, which a
keyframed overlay is not at. A one-finger move writes position only: writing back its unchanged
scale and rotation snapped a near-straight overlay to the axis. A text fades as one piece through
an `Opacity`, added only below 1. The text width pills write `boxWidth` directly; the centre shift
they cause is a position and goes through the rule.

**A scaled-up photo or video can be touched where it is drawn.** The detector used to wrap the
transforms and so kept the unscaled box — past about 1.4× the corner handles could not be grabbed
at all (probe-confirmed; the text layer had the same fault). The transforms now sit in a square
that holds the scaled box at any rotation, with the detector inside them on the real box.

**On the wire** `EditorTimelineOverlay.centerX/centerY/scale/rotation/opacity` are
`AnimatableDouble`s. The centre's pixels-to-fractions conversion is affine, so `mapAnimatable`
applies it once to the base and to every keyframe value — resolving the mapped track equals
mapping the resolved value. A text's centre goes through `textOverlayWirePlacement`, the layer's
own per-axis clamp one keyframe value at a time — exact wherever the values sit inside the canvas,
which is everywhere a drag can put them. **A text rasterises at its peak keyframed scale**
(`textOverlayPeakScale`), or a keyframed zoom would end on an upscaled, soft raster — the
pinch-scale fault again.

**In Kotlin** `NativeTimelineOverlay` reads the five through `AnimatableDouble.fromWire`;
`restingStateAt(t)` resolves them at the overlay's progress, and `stateAt(t)` applies the in/out
presets on top — a fade multiplies a keyframed opacity, a slide adds to a keyframed centre. The
clamps moved to the resolved values. `OverlayDrawBuilder.draw` reads centre and rotation from the
frame state and never from the overlay, whose fields are tracks. `OverlayClock.needsRedraw` gains
one case: a keyframed overlay redraws on every clock step inside its span.
**`test/fixtures/overlay_motion_fixture.json` pins the two sides** — three keyframed overlays as
the composer sends them, resolved at seven progresses; regenerate with `UPDATE_OVERLAY_FIXTURE=1
flutter test test/features/video_editor/logic/timeline/overlay_motion_fixture_test.dart`, then
re-run the Kotlin suite. The usual caveat: it catches divergence tomorrow, not a wrong curve
today.

**On the timeline** the selected overlay's diamonds sit on its own bar, in the bar's box and under
its trim handles (a clip's order), hidden while the bar is carried. A split video overlay pins a
diamond at the cut and rescales each half; a duplicate is nudged 20px along its **whole** path —
nudging only the base put a keyframed copy exactly on top of the original.

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
(`maskUniforms`, `NativeTimelineClip.parseMask`) in a fixed order and tested to match.

**The mask was drawn upside down, and the code said so before a device did**
(`MaskOrientationTest`, **awaiting device verification**). The wire is y-down like every canvas
coordinate; the clip shader reads the mask against `fitted`, which is y-up, and nothing converted
it — so a window dragged toward the top of the picture was drawn toward the bottom. The crop's
bug again, one uniform over. Video overlays had it too (their quad samples bottom-up); photo
overlays did not (top-down). The conversion is `NativeTimelineClip.toSamplingMask` — only the
vertical centre moves, its own inverse, no mask passed through untouched — applied where the
sampling space is known: `NativeTimelineClip.maskUniforms()` for every clip lane, and
`OverlayRenderer.Draw.samplingMask()` for a draw from a video. `parseMask` stays the wire's
reading, the twin of Dart's.

**A window can be tilted** (`ClipMask.angle`, `clip_mask_tilt_test.dart`, `MaskTiltTest`,
**awaiting device verification** — the turn is GLSL). Degrees, **clockwise** (the way the fingers
turn and every rotation in the editor reads), folded into (-180, 180] and written to the draft and
the wire **only when not zero**, so an untwisted mask is byte-identical. A two-finger twist on the
canvas turns it (`maskAfterGesture` — anchor-based, the pan and pinch exactly what they were),
snapping within 3° of a right angle like the text frame (`snapMaskAngle`), with the angle shown in a
pill at the top of the picture while twisting, as CapCut does. **The turn is rigid on the picture**:
it happens with x scaled to the height's units, or a pixel-round window would come out a tilted
ellipse on a 9:16 frame — a test turns one at four angles and requires the coverage unchanged, and
fails when the turn is made on raw fractions. The shader takes the tilt as a third vec4 `(cos,
sin, 0, 0)` and the frame's pixel aspect beside it: for a clip `uCanvasAspect * fit.x / fit.y`, for
an overlay its content aspect (`Draw.maskAspect`). An untilted window skips the turn in the shader
(`cos == 1`) and in the Dart twin, so it runs exactly the arithmetic it always did. A y-up space
turns the other way: `toSamplingMask` negates the sine along with turning the centre over.

**An overlay can be masked too, with the same model** (**awaiting device
verification**). `ImageOverlayModel.mask` and `VideoOverlayModel.mask` are the same `ClipMask`, so a
circle means one thing everywhere and there is one coverage function keeping preview and export
agreeing. **Authored in the overlay's own box**, not in canvas fractions: an overlay is placed and
scaled independently, so a mask measured against the canvas would slide off the picture the moment
the overlay moved. The panel serves whichever of the three is selected
(`VideoEditorNotifier.maskOnSelection` / `setMaskOnSelection`, a clip winning when several somehow
are), so there is no second mask editor to drift from the first.

**One renderer reaches the shape, in preview and export alike.** `OverlayRenderer`'s fragment
shader computes the coverage from the quad's own 0..1 — which *is* the overlay's box — and
multiplies it into the premultiplied texel beside `uAlpha`. The preview used to clip overlay
widgets to the shape with a hard edge (`OverlayMaskClip`) while the file feathered; overlays have
drawn in GL since the native-preview overlays work, and the widget is deleted.

**An overlay's window is placed on the canvas, like a clip's** (`overlay_mask_handles_test.dart`,
**awaiting device verification**). Until Stage 1 nothing on the canvas answered for an overlay's
mask — only a clip's window took a drag — so an overlay's window sat at its default in the middle
of the picture while the panel said "drag on the canvas to move the window". The car-crash edit
masks an overlay with a tilted line, so it needed the same handles. **The editor lives in each
overlay layer**, which already lays the box out exactly where the engine draws the picture —
keyframes, in/out animation and rotation included — and its detector sits inside the overlay's
transforms, so a gesture's *local* focal point is already in the box's own axes: a drag across a
turned overlay moves the window along the overlay's x and y with no rotation arithmetic
(`OverlayMaskGesture`, shared by the photo and video layers; a test fails when it reads screen
coordinates instead). The outline is the clip's own `MaskOutlinePainter`, drawn inside the box with
the line widths and the angle readout counter-scaled and turned upright; the gesture maths is the
clip's own `maskAfterGesture`. While the tool is open on a masked overlay, the outline replaces the
overlay's frame and handles, so a mask edit cannot grab the overlay; an overlay with no window yet
still moves, as a clip does. One undo step per gesture.

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

**`mirror` is the fifth shape**, CapCut's band between two parallel lines (`clip_mask_mirror_test.dart`,
**awaiting device verification** — the band is GLSL). Appended for the same reason, index 5: it
keeps what lies within half the window's **height** of the centre line, edge to edge — the width
plays no part — horizontal until it is tilted, feathered on both edges. The radius slot stays 0
for it (`parseMask` now reads the radius for the rounded rectangle alone, matching Dart). **The
panel orders its own chips** (`_kShapeOrder`): the enum is the wire's and append-only, so Mirror
sits beside Linear, the two line shapes together as CapCut groups them, without renumbering any
saved shape. The pinch sets the band's thickness; the outline draws its two edges and their soft
edges, cut to the picture.

**Mask is an in-place panel, not a sheet**: the window is placed on the canvas — drag to move,
pinch to resize, twist to tilt, with the outline and a grab point drawn by `_MaskOutlinePainter` —
and a sheet
would cover the surface being edited. The panel holds only what the canvas cannot: shape, feather,
invert. While the tool is open the composer shows the clip **unplaced but cropped**: scale, pan,
rotation and mirror suspended so the canvas maps a drag through the fit alone, the clip's own crop
kept because the window is over the picture as it will play — the crop tool's rule, one step
gentler (`unplaced` vs `plain`). A tap on the picture keeps it open. Switching shape keeps the window
where it was. Plain values, not animatable yet: a moving mask is four coupled numbers with a design
of its own.

**The Mask panel has no ✕ / title / ✓ bar, and its shapes are tiles** (`toolPanelHasHeader`,
`kHeaderlessTools`; `mask_panel_test.dart`, `tool_dismissal_test.dart`; **awaiting device
verification**; the user's call, after CapCut). Every Mask change applies as it is made and its ✕
had nothing to put back, so the bar was two buttons that both just closed the panel; it closes
with Back and with anything that leaves the selection, and a tap on the picture still keeps it
open. **Only Mask**: on Volume and Opacity ✕ is the only way to throw a drag away. In the bar's
place, one row of tiles — each shape drawn as what it does (`_MaskShapeGlyph`), its name small
under it — sized so all six fit across a 360dp phone (44–56px, scrolling only on a narrower one),
styled as the crop panel's ratio tiles.

**A Circle is round on the picture** (`maskWithShape`, `roundMaskWindow`,
`clip_mask_circle_test.dart`). Device-reported as an oval: a window is fractions of the picture's
width and height, so the default 60% of each is two different lengths on any picture that is not
square, and a pinch — scaling both alike — kept it stretched. Choosing Circle now sizes the window
round in pixels, its diameter the window's shorter side on screen, about the same centre; the
other shapes still keep the window exactly. The picture's shape is the one the canvas fits: a
clip's from `VideoEditorState.maskPictureAspect` (now also what `_maskFrame` reads, one
definition), an overlay's from `OverlayContentBox.cachedAspect`. A circle saved before this stays
as it was until Circle is chosen again.

### Replace clip — swap the file, keep the edit

`replaceClipAsset` puts a picked file under the selected clip. Everything the user did to the clip
is about the *slot* on the timeline, not the file — speed, placement and its keyframes (clip-relative,
so they still mean the same instants), crop, mirror, opacity, adjustments, filter, transition —
and survives. (An effect is a bar on the timeline, not the clip's, so it stays where it was.) The trim survives where it fits: a shorter file pulls the end in and
slides the start back to keep as much of the clip's length as the file allows; a photo has no
source length and is given the clip's on-screen length at 1×. **What cannot survive is what
belonged to the old file**: the proxy rendered from it, and a reversal that depended on that
proxy. One undo step; the file joins the asset pool once, and the old asset stays for anything else
using it. The screen takes the first pick from the same picker Add uses and re-syncs the preview.

### Move to overlay — a clip lifts onto the overlay track

**Awaiting device verification.** CapCut's "Overlay" on a clip, the car-crash edit's first step:
**Overlay** on the clip menu (beside Replace; id `to_overlay`) moves the selected clip to the first
free overlay lane **at the same time**, **drawn exactly where it was**, and the main track closes
the gap — the tutorial's own behaviour, checked frame by frame. One undo step; the new overlay is
selected on its own menu. A photo becomes a photo overlay, a video a video overlay.

**It lands where the clip was** (`logic/clip_to_overlay.dart`, `clip_to_overlay_test.dart`). A
clip is its picture contain-fitted into the canvas, scaled, moved and turned; an overlay is the
same picture contain-fitted into its own square box (`kImageOverlayBoxPx` 200 /
`kVideoOverlayBoxPx` 240, preview-canvas pixels — now **one definition** in `overlay_box_fit.dart`,
read by the layers, the composer and this), scaled, moved and turned. So the overlay's scale is the
clip's times the ratio of the two fits, its position the clip's canvas-fraction offset in pixels,
its turn the clip's degrees in radians. Each is a fixed change of units, applied through
`mapAnimatable` to the base and every keyframe alike, so a keyframed move keeps moving, easing
included; keyframe progress is clip-relative and the overlay's is overlay-relative over the same
span. A test fails when the fit ratio is dropped.

**What cannot come along is named first** (`clipToOverlayLosses`): filter, Adjust, crop,
flip, speed curve, reverse, volume keyframes — what a clip carries and an overlay cannot hold yet.
**Only when there is any**, one dialog says so in a line ("Filter and speed curve won't carry
over.", `confirmMoveToOverlay`) with Cancel and Move; a clip that loses nothing just moves. Trim,
flat speed, volume, opacity, placement and its keyframes, mask and chroma key carry. Its
transitions go as a deleted clip's do, which has never asked. Under a speed curve the overlay
plays its source at 1x.

**The last clip stays** — moving it would empty the main track, which Delete never does — and the
tool is **dimmed, not hidden**, for it: `EditorToolTile.enabled` and `isToolbarToolEnabled` are the
toolbar's way to say "waiting" beside `isToolbarToolVisible`'s "not here". A dimmed tile ignores
the tap.

**Known:** the project's own crop and zoom (the root Crop and Zoom tools) frame every clip and
no overlay, so a clip moved out of a project-cropped or zoomed canvas shows its full frame —
placed at the size its full frame had, since the overlay has no crop to keep. Re-cropping a
moved clip is the user's call; carrying a project crop onto one overlay would make it the only
overlay the project crop reaches.

### Auto captions — generating a set (Stage 1)

**Device-verified by the user**: a set generates, the default look is right, and after the WAV
and lead fixes the words land on time. Spec: `docs/superpowers/specs/2026-09-29-auto-captions-design.md`,
Stage 1 plan beside it in `plans/`. Stage 2 (editing) and Stage 3 (word highlight) are the next
sections, then Stage 4 (caption styles). Sign-in and credits have exactly one hook:
`CaptionAccess.ensureAllowed`, called before the options sheet opens — see "Accounts and credits".

**A caption is an ordinary text overlay**, for the emoji reason: a dedicated caption kind would
be a second implementation of the text pipeline. `TextOverlayModel` gains `captionSetId` (a
string, not a flag — a translated second set is the obvious next feature) and `captionWords`:
each word's **UTF-16** range in the text, the unit `TextGlyphBox.charIndex` already counts in,
and its times **relative to the caption's start**, so dragging a caption bar moves its words.
Both keys are omitted on ordinary text, so a draft without captions is byte-identical.
`VideoEditorState.captionSettings` remembers how the set was made (source, language, length) and
is what the sheet reopens on; persisted on the draft, omitted when null. A word whose offsets are
out of reach of a hand-edited text is clamped or dropped on read, never thrown on, and **a
language the sheet does not list reads as Auto detect** (`isCaptionLanguage`) — the sheet labels
a language from its list, so an unknown code from a later build's draft left Auto captions unable
to open for that project.

**The audio is the export's own mix, which is why word times need no conversion.**
`renderCaptionAudio` runs `AudioExportMixer` under `MixConfig.CAPTIONS` — mono 16 kHz **PCM in
a WAV** (`writeWavTo`, `WavWriter`), from timeline 0 at timeline rate — so the server's "seconds from the start of the file"
*are* timeline seconds, through trims, flat speed, speed curves and crossfades. `MixConfig` is
the mixer's rate, layout and gain rule as a value; `MixConfig.EXPORT` is exactly what the export
had. Captions mix at **unity gain**: volume, its keyframes and the project mute are ignored (a
muted clip's words were still spoken), the transition crossfade is kept because it is timing, not
level. **Reversed clips are skipped inside the mixer**, not filtered from its clip list —
`crossfadeGain` finds a transition's clips by *index*, so a filtered list would fade the wrong
ones. The source choice (`CaptionSource`: Video sound = clips + video overlays, Audio tracks,
All) travels as `include`; the pass runs to the end of the last included sound, and a selection
with nothing audible answers `hasSound: false` before anything is uploaded.

**Captions showed a little after their words** (device-reported, about 50ms; fix **awaiting
device verification**). Two causes, both addressed. **The audio was AAC**: an AAC encoder opens
every stream with a run of priming samples — tens of milliseconds at 16 kHz — and nothing in
the file told the transcriber to skip them, so every word was heard that much late. The caption
audio is now uncompressed, where the first sample of the file is the first instant of the
timeline; it costs about 2 MB a minute on upload (`uploadTimeout` is 5 minutes for it), and the
export's AAC path is untouched — both outputs share one mixing loop (`mixBlocks`). **And a
caption that starts on its word reads as late**: `kCaptionLeadSeconds` (0.06) shows each caption
that long before its first word, covering the frame or two the preview spends getting it to the
screen. Only the caption's *appearance* leads — word times are measured from the caption's start
and have the lead added back, so Stage 3's highlight stays on the spoken word. The previous
caption makes way for the next one's lead.

**`SlimshotApi` (`core/services/`) is the app's one server client** — captions are the first
server feature of several. The address comes only from the `SLIMSHOT_API_URL` define, kept with
the Google client ID in **`env/env.json`** (not committed; `env/env.example.json` shows the keys;
production is `https://slimshot-server.techfamz.com`) and passed with
`--dart-define-from-file=env/env.json`;
**without it the tool is not shown** (`isToolbarToolVisible`'s `hasCaptionServer`), which is the
"not offered before it works" rule as code. Its requests come in three kinds — signed in,
sign-in and public — described in "Accounts and credits". **Debug builds allow cleartext** for the LAN test
server (`android/app/src/debug/AndroidManifest.xml`); release does not, so the deployed server
must be HTTPS.

**The upload key is kept until the server is known to hold a failed job for it**
(`CaptionPipeline`; the rule since stage 2 of credits). A key names one upload: once the server
holds a job for it the same key answers with that job, a failed one included, so only a retry
after a `failed` job (`CaptionJobFailed`) takes a fresh key. Every other failure keeps it — a lost
response, a poll that stopped answering, a proxy page, a failure before the upload — because a
retry under a new key would become a second job and, since stage 2, a **second charge**; under
the held key the server answers with its job, never saw the key, or refuses it with
`IDEMPOTENCY_KEY_REUSED` (one fresh key, nothing charged). It was briefly "reuse only after a
network loss", and the stage 2 review found three double-charge paths in that. `CaptionService` polls at the server's
`pollAfterMs` and gives up after 10 minutes. **A dropped poll is ridden out**
(`maxPollFailures`, 3 in a row): one lost request on a mobile connection says nothing about a
job the server is still working on, and giving up on it means rendering and uploading it again
under a new key. Every failure is one line from `captionErrorMessage`, no title.

**Spacing is rebuilt from the transcript** (`rebuildTranscriptSpacing`): the server drops the
provider's spacing tokens, and joining words with a space would put spaces through Chinese and
Japanese. Each word is found, in order, in the transcript `text`; what lies between two words is
the separator.

**Grouping** (`groupCaptionWords`): a caption breaks after sentence-ending punctuation, before a
word following a pause of `kCaptionPauseBreakSeconds` (0.6), and at the length limit — Word 1;
Phrase 3 words or 20 characters; Line 7 or 32, characters being grapheme clusters. A word longer
than the limit stands alone; a token with no letter or digit never starts a caption of its own.
A caption holds `kCaptionHoldSeconds` (0.4) past its last word, never past the next caption's
start — which is also why there is no separate minimum length: a caption is shorter than the
hold only where the next one leaves no room to extend it. **The hold never runs past the end of
the sound** (`endLimitSeconds`, the rendered audio's length): speech that reaches the end of the
video is the ordinary case, text overlays count toward the project's end, and a hold beyond it
made the project — and the exported file — up to 0.4s longer, a tail of bare background. A word
that itself outlasts the limit is kept whole. **Captions never overlap, whatever
order the provider's times arrive in** — each starts no earlier than the previous one ends — so
a set always fits one lane.

**The first default look** — now the **Classic** style (`kCaptionClassicLook`); since the
device look at Stage 4 a project's first set wears **Bubble** (the caption styles section):
**Montserrat Bold**, white, a black outline and a soft shadow, no fades (a
half-second fade is most of a one-second caption's life). Device-reported: the first version
wore the Subtitle template — Inter at regular weight, scale 0.9 — and read as thin and small.
The font is **bundled** (`assets/fonts/Montserrat-Bold.ttf`, its own family in
`kBundledFontNames`, since the model has no weight field): a caption has to look the same
offline and on a phone whose system face is not what a download would have been. **The size is
a fraction of the frame**, not a fixed scale — a text's size used to be stored in the pixels of
the canvas it was made on, which is whatever the phone left room for, so one scale was large on
one phone and small on the next. It was first a scale computed from the canvas width; since the
text Size work it is a **Size** (`kCaptionTextSize`, 100: letters a tenth of the frame) at scale
1 — see "Text Size" below. **The wrap width is `kCaptionWidthFraction`** (0.86 of the canvas),
the same for every caption so they all wrap alike, and a bigger Size re-wraps inside it. That
reverses the plan's "`boxWidth` unset" ruling, and is why a boxed caption's background hugs its
words rather than the box (Stage 4). The centre sits at `kCaptionPlacement` — a little over three quarters
down, clear of the bottom fifth where the apps that play short-form video put their own caption
and buttons. Since Stage 4 new plain text starts in Montserrat Bold too (`newText`).

**Placement** (`placeCaptions`): on the first lane free across the whole set, one undo step.
**A new set replaces the old** — removed *before* the lane is chosen, so the new set
takes the lane it freed — after "Replace captions?"; plain text is untouched. The gutter marks a
caption lane with `subtitles` (`laneGutterIcons`). The progress sheet is **modal on purpose**:
the audio is a snapshot of the timeline, and a clip moved while the server listens would
misplace every later word; any way it closes before the words land cancels the run.

**Three export faults fixed on the way, all of which a caption set would have hit first:**

- **A video overlay's sound was mixed twice.** Since the mixer learned to take overlays at their
  own speed, `startExport` *also* kept listing each video overlay as a 1× audio track — double
  volume at normal speed, two voices out of step at any other. `TimelineAudioTracks` is now the
  one reader of a timeline's tracks, and it reads imported tracks only.
- **Still textures were never freed during an export** — `imageTextures` emptied only on full
  release, so a hundred captions meant a hundred text atlases on the GPU at once.
  `ExpiredStills` frees a still once every overlay using its path has ended. Only the export's
  builder does it, since a preview playhead scrubs back — but **the cache itself is shared with
  the preview**, so what it frees may be a texture the preview uploaded. That costs nothing new:
  `endExport` has always dropped every overlay texture (`overlays.releaseAll()`) and re-adopted
  the preview's list, which reloads what it needs.
- **Export did not wait for fonts** — fixed then by waiting on Google Fonts' downloads behind a
  bounded wrapper, and **gone since**: fonts come from the server and are used only once on the
  phone, so there is nothing to wait for (the fonts section).

### Auto captions — editing a set (Stage 2)

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-09-30-auto-captions-stage2.md`.

**One rule runs through all of it: a word stays on the instant it was spoken.** Word times are
stored relative to their caption's start, so anything that moves that start — a trim, a split, a
merge — moves them back by as much (`logic/captions/caption_edits.dart`, pure functions over
captions that know nothing of the playhead or of undo).

**Retiming lives in the notifier, not in any one editor.** Every text write goes through
`_setText`, and a caption whose text changed is retimed there (`retimeCaptionWords`) — so the
caption list, the text editor and anything added later fix words the same way, and there is no
editor that can forget to. Old and new words are aligned by longest common subsequence with case
and punctuation set aside (`hello` and `Hello,` are one word); **a matched word keeps its times
exactly**; a run of new words shares the room between its matched neighbours, by length; with
nothing matched — a rewrite — they share the whole caption. Words are whitespace-separated,
except that each character of a script written without spaces (Han, kana; not Hangul, which
spaces its words) is a word of its own with its punctuation attached, which is how a provider
returns those languages.

**A caption set moves as one** (`_moveCaptionSet`, `followCaptionMotion`). Moving, pinching or
turning one caption on the canvas gives every other caption of its set the same change — a
caption that sits somewhere else each second reads as a fault. The edited caption goes through
the edit rule like any text; the others take the *delta* between what it showed before and
after, on their base values **and every keyframe value**, so a keyframed caption keeps its
motion and takes the move. Only `setOverlayMotionLive` does this — a keyframe command (placing
or removing a diamond) is about one caption's path and leaves the set alone. No snapshot of its
own: the gesture took one, so one Undo puts the whole set back. **Box width is the set's too**
(`_setText`) — it is what makes captions wrap alike. Ordinary text still moves alone.

**The caption list** (`CaptionBatchSheet`) opens from **Captions** on a selected caption's menu —
shown only for a caption (`isToolbarToolVisible`'s `hasCaptionSelected`). Each row is the
caption's start (`1:04.2`; a tap seeks there and selects it), its text, and Split / Merge with
next / Delete. The header holds Length — which **re-cuts** the whole set, hand fixes included,
keeping the look and place of its first caption — and Delete all. It is a list to read and type
into, not a choice about the picture, so it takes the audio library's 0.7 height and rides above
the keyboard; rows are a fixed height so the list can open on the caption it was opened from
without laying out the ones before it. **Typing is one undo step per caption, taken on the first
change, not on focus**: a field only looked at leaves nothing to undo. The fields follow the
project through `ref.listen`, not in `build` — setting a controller's text during a build
notifies its listeners mid-build. A caption left with no words is removed when the list closes.

**Split, merge, delete all and re-cut are each one undo step — and none where there is nothing
to do**: a split at either end of the text, a merge on the last caption. Split cuts at the word
boundary nearest the cursor, and the right half leads its first word like any caption. **The
timeline Split tool stays off for text**; splitting a caption is a list action.

**Found by the stage's review, each fixed with a test that failed first:**

- **A copy of a caption is ordinary text** (`duplicateTextOverlay` clears the caption). Left in
  the set, the copy fed its words into a re-cut a second time ("hello world hello world") and
  was laid on its original's lane, since the set is placed as one.
- **✕ on Opacity put back only the selected caption** while the drag had changed the whole set.
  `openRevertibleTool` records the rest of a caption's set and `discardActiveTool` restores it.
- **A trim dragged past a word and back left the word at the edge.** Each frame trimmed the
  frame before it, and a word the edge has passed is held at the edge. The trim now works from
  the caption **as the gesture found it** (`_gestureBase`).
- **A word respelled keeps its times** — an unmatched run that replaces as many old words takes
  theirs, one for one; it is the same moment of speech. Sharing the gap between the neighbours
  started a respelled first word at 0, inside the lead. New words are never placed past the
  caption's end.
- **What the server would refuse is not sent** (`maxUploadBytes`, 50 MB — about 26 minutes of
  uncompressed audio), and the file is streamed rather than read into memory.
- **Re-cutting to the length it already has does nothing**: it would take an undo step, issue
  new ids and throw away every split and merge made by hand, to arrive where it started.
- **Split with the cursor at either end of the text cuts in the middle** — the end is where the
  cursor sits after typing, and a button that did nothing there read as broken.

**Known:** a caption can end a few tens of milliseconds before its last word does (the next
caption's lead takes that room) — Stage 3's highlight clamps word times to the caption's span,
so this costs nothing there. An Undo can bring back a caption that was emptied and then removed when
the list closed; opening and closing the list removes it again.

**The cause of the late captions is a theory, not a measurement.** AAC priming is the right
direction and the right size, but the lead was added in the same change and would hide 50ms by
itself, so a device run cannot say which of the two did it. The way to know is a click at a known
instant sent as AAC and as WAV; if WAV is not measurably earlier, its larger upload buys nothing
and the AAC path should come back.

### Auto captions — the word being spoken lights up (Stage 3)

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-10-02-auto-captions-stage3.md`.
A caption set lights its words six ways — **Colour**, **Pop**, **Pill**, **Karaoke**,
**Reveal**, **Focus** — chosen in the Auto captions sheet's Highlight row with one colour from
`kCaptionHighlightColors`, the fill for Colour, Pop and Karaoke and the box for Pill.

**One catalog, three consumers.** `logic/captions/caption_highlight_catalog.dart` is a pure
function, `wordHighlightStateAt(style, t, words, index, span)` → `WordHighlightState`
(`highlighted`, `fill`, `scale`, `opacity`, `pill`), in plain Dart with no `dart:ui` so the
fixture tool can run it. The canvas painter, the Kotlin port `CaptionHighlightCurves.kt` and
Stage 4's preset tiles read it; nothing else may describe a highlight.
`test/fixtures/caption_highlight_fixture.json` pins the port (`dart run
tool/generate_caption_highlight_fixture.dart`, copy under `android/app/src/test/resources/`) —
with the usual caveat: divergence tomorrow, never a wrong curve today.

The rules it holds, each a decision:

- **A word is active from its start until the next word starts**, the last until the caption
  ends, so nothing drops out in the gap between two words. Word times are clamped to the
  caption's span — a caption can end a little before its last word (the next caption's lead).
- **Colour switches at the boundary, never blended.** A glyph half in each look would cast its
  shadow twice. Only scale, pill and opacity ramp (`kHighlightRampSeconds`, 0.08s).
- **Pop swells the word, not each letter**: every glyph scales in place and moves away from the
  word's centre by as much, so the word grows as one piece. **It settles onto a hold, never back
  to rest** (peak 120%, hold 110% over 0.25s, one sine over two floors): settling fully to 1.0
  was a seven-frame twitch at the preview's ~30Hz, after which Pop was plain Colour — the first
  device look called it out. **And a lit fill must read as lit**: Neon shipped lighting its word
  in exactly its glow's blue — edges melted into the halo, and at 0.45 luminance the "lit" word
  was the darkest thing on the line; it lights in a brighter cyan now, and the catalog test pins
  both rules (never the glow's own colour; fill-lighting colours above 0.55 luminance — pills are
  exempt, a box behind white text may be dark).
- **The highlight composes with the text's own animations**: opacities and scales multiply.

**Where a glyph's word comes from: `CaptionHighlightLayout`** (`caption_highlight_layout.dart`).
Built from the glyph boxes `layoutTextGlyphs` already measures, it maps each glyph to its word by
`charIndex` against the words' UTF-16 ranges (a glyph between words is -1 and draws in the base
look), unions each word's ink box, and knows which words are right-to-left. The painter and the
rasteriser both build it, so a word's box, its pill and the line a karaoke sweep crosses are one
rect in the preview and in the file.

**On the canvas** `TextOverlayPainter` takes its per-glyph path for any highlighted caption, and
repaints on every playhead move while it has one. Pills paint first and do not travel with a
letter's animation, like the box; a lit glyph is the overlay painted with the highlight colour as
its fill, outline and shadow unchanged. **Karaoke is two complementary clips** across the glyph
at the sweep — lit behind, plain ahead — so the glyph's shadow is still cast once; a
right-to-left word sweeps from the right.

**In the export the atlas holds what the highlight needs**: each glyph a second time in the
highlight colour (a cell the same size, so `srcRect` serves both), a pill cell per word (pill
style only), and the background box as a cell of its own. `EditorTimelineGlyph` gains
`litAtlas*` and `word`, the overlay `highlight` and `backgroundAtlas*` — **written only when
present**, so ordinary text sends byte-identical JSON. `gl/TextQuads.kt` is the export's half, pure
Kotlin and JVM-tested (`TextQuadsTest`) against the painter's own cases: background, then pills,
then glyphs, each glyph sampling its lit or base cell, a popped word moved about its centre, and
**karaoke cut into two quads at the sweep**, each sampling the matching slice of its own cell. A
cut glyph's scale is pre-applied about the whole cell so the halves stay together; a *rotation*
cannot be pre-applied to an axis-aligned rect, so the halves turn about their own centres — a
seam that opens only while a rotating per-glyph animation and a sweep cross the same letter.
`OverlayDrawBuilder.textDraws` maps the quads onto `Draw`s and nothing more.

**A highlighted caption repaints only when a word changes look** (`_wordStatesDiffer`, from the
stage review). Every repaint casts a blurred shadow per letter, and `shouldRepaint` used to say
yes at every position event for as long as the caption was on screen — a large share of each
frame on a low-end phone for a picture that had not changed. It now compares each word's
`WordHighlightState` at the two instants, from the word times alone with no layout: Colour,
Pill, Reveal and Focus repaint at word boundaries and through their ramps, Karaoke and Pop while
they move.

**Atlas cells keep a 2px gutter** (`kAtlasCellGapPx`). The GPU samples a cell's edge between two
texels; flush cells were harmless while every cell was a glyph with a transparent margin, but a
pill or box is solid to its edge and would draw a faint line of its colour along its neighbour.

**The background box is a quad of its own**, drawn behind the glyphs with the overlay's
whole-block state — exactly how the preview already drew it, one rect that does not move with the
letters. So boxed text takes the atlas path: it animates per character and highlights, the
boxed-text fallback and its warning are gone, and so is the template rule they forced.

**Choosing one** (the Highlight row of **Caption style**, on a selected caption's menu — see
the caption styles section; colours shown only for a style that lights in one,
`captionHighlightUsesColor`): **each choice reaches the whole set at once** through
`setCaptionHighlight`, every caption and the settings together, one undo step per choice and none
when nothing changes. A new set is generated in the style `captionStyleForNewSet` decides
(`CaptionSettings.highlight` → `buildCaptionOverlays`). Re-cutting keeps it; **a copy of a caption sheds it**, since
`copyWith(clearCaption: true)` makes ordinary text, and a highlight marks a caption's words.

**Known, from the stage review, deferred:** Focus dims every word and Reveal shows a bare box
for the 60ms lead before a caption's first word (both sides agree; "before the first word
nothing is active"). A boxed text too large for the atlas falls back to the flat raster
silently, where a whole-block fade fades the box with the letters while the preview leaves the
box at rest — a narrower form of a divergence that predates the stage. `CaptionHighlightLayout.of`
guards a word's end against the text but not a reversed or negative range (unreachable from a
draft, whose reader clamps). A pill cell is clipped to its cell in the rasteriser, cutting the
antialiased half pixel the canvas keeps. `setCaptionHighlight` takes an undo step when only
the settings, not the captions, differ.

### Auto captions — caption styles (Stage 4)

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-10-03-auto-captions-stage4.md`.
A set's whole look — face, colours, outline or box, shadow, motion and word highlight — is one
tap in **Caption style**, on a selected caption's menu, and a look edit on one caption reaches
the set.

**The look is chosen on the captions, not in the sheet that makes them** (from the first device
look). The Auto captions sheet asks only what generating needs — Source, Language, Length — and
a set is styled afterwards, where it can be judged against the footage. A selected caption's
menu reads **Edit · Caption style · Captions · Templates · Style · Font · Animation** (then
Opacity, Copy, Delete); Caption style and Captions show only for a caption
(`isToolbarToolVisible`), so plain text's menu is what it always was. `editor_menu_test.dart`
pins the order and the handler.

**A text's look has one definition: `TextLook`** (`logic/text_look.dart`): face, fill, outline,
box colour/radius/padding, the five shadow fields, alignment, the three animations and their
speeds. `TextLook.of`, `applyTo`, and `sameLookAs` — equality at any pace, which is what "is this
text wearing that look" has always meant. Templates restyle and recognise themselves through it
(`TextTemplate.look`; their tests passed unchanged through the refactor), and so do caption
presets and apply-to-all. **`text_look_test.dart` holds every serialised field of a text to one
side or the other**: a field added to the model and its JSON fails until it is classified, and
a look field must then be carried by `TextLook`, or a template or preset would leave it behind.

**A preset is a look plus a highlight — no place and no size** (`kCaptionPresets`,
`logic/captions/caption_preset_catalog.dart`). A style that moved the set would undo the user's
own placement every time they tried one, and a caption's size is its Size
(`kCaptionTextSize` until the user changes it). Nine: **Bubble — the default, `kDefaultCaptionPreset`**, white
type over a soft shadow with a purple pill behind the spoken word, chosen on the device because it
shows the highlight off from the first moment, and the grid's first tile so "the first one" and
"what I got" agree — then Classic (`kCaptionClassicLook`, the look the first device run approved),
Karaoke, Pop, Boxed, Impact, Neon, Reveal, Focus. No in or out animations: the highlight is a caption's motion. The catalog
test pins fonts bundled or in `kServerTemplateFontNames`, animations selectable, shadows inside the Style tab's ranges,
**a highlight never the text's own colour** (a word lit the colour it already wears does not
light, and a pill the colour of its letters swallows them), and no two presets alike.

**Caption style** (`CaptionStyleSheet`, `widgets/panels/caption_style_sheet.dart`) is the
styles grid on top — a style is a whole look, highlight included, so it is picked first — and
the Highlight row with its colours under it, to tune it. No title, by the echo rule. It opens on
the selected caption's look and highlight, and **every tap restyles the whole set at once**
(`restyleCaptions` for a style, `setCaptionHighlight` for a highlight): every caption's look and
highlight and the settings' highlight, words, timing, place, size and motion untouched, one undo
step per tap and none when nothing changes. A single caption is still the text editor's, with
"Apply to all captions" off. The sheet takes `presets` as a parameter because a test cannot load
the downloaded faces; `CaptionSheetFrame` and `SheetSectionLabel` keep it and the Auto captions
sheet one family.

**The grid is the canvas painter** (`CaptionPresetTile` over `TextPreviewTile`, in
`kTextPreviewGrid`): a caption wearing the preset, its sample words timed across the loop
(`kCaptionPresetWordSeconds`) so the highlight plays. The sheet owns one clock for every tile and
holds it while it scrolls; the grid is not a scrollable of its own. **The current style is found,
not remembered** — the preset whose look and highlight the caption wears — so a hand edit marks
none.

**What a new set wears** (`captionStyleForNewSet`): a project's first set, the default style;
**a regeneration, the current set's style**, read from its **earliest** caption before the old set
is replaced — regenerating for a better transcript must not undo the styling, hand tuning
included, and splits and merges reorder the list while time does not move.

**Apply to all captions** (`VideoEditorState.captionLookToAll`, on by default, not persisted).
`_setText` — the one place a text is written — passes a caption's `TextLook` to every caption of
its set when the look changed, beside the box width the set already shared, inside the edit's own
undo step. Words and moves are never broadcast by it (a set already moves as one through
`_moveCaptionSet`). The text editor shows the switch on a caption only, and not on the Keyboard
tab, where the words are each caption's own. **A template chosen on a caption keeps the
caption's size**: a template's size would make it larger or smaller than its neighbours.
**Undo and redo carry the switch across rather than restoring it** (from the stage review): it is
a way of editing, not an edit, and an Undo that silently turned it back on let the next colour
change restyle a set the user had said to leave alone.

**A boxed caption's background hugs its words** (`TextOverlayLayout.backgroundRect`). A caption
carries its set's wrap width, one the user never chose, so the Boxed style drew a band most of the
canvas wide behind one word. It wraps the longest line, placed by the lines' alignment; the box
the user grabs keeps the set's width, so the width handles behave as before. One layout feeds the
painter and both export rasters. Plain text with a width of its own keeps its banner.

**New plain text starts in Montserrat Bold** (`newText`, `kNewTextFontFamily`), the spec's
bundled default. Only text from the Text tool: a template keeps its own face, an emoji is still
made in Roboto (harmless — the platform's emoji face draws it either way), and the model's default
and a draft that names no face stay Roboto, so every saved project opens as it was.

**Known, from the stage review, deferred:** `backgroundAlign` reads `'start'`/`'end'` while
`textAlignFor` does not, so a hand-edited draft with either centres its words in a box hugging
one edge — the editor offers neither value. The sheet marks a style current by `sameLookAs`
(speeds ignored) while `restyleCaptions` returns early only on full equality, so a current tile
could still take an undo step if a preset ever carried an animation (none does). **Reveal carries
no outline** — white type over a soft shadow alone; a device call on bright footage. (Bubble has
none either, and was judged readable on the device.)

### Text Size — the letters, not the scale

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-10-03-text-size.md`. A text
has a **Size**: a ruler in the text editor's Size tab (between Font and Animation), also on the
text's menu as a door into it. Agreed with the user after looking at how CapCut does it: **two
controls, never folded into one.** Size is the letters — a style; scale is the whole text as an
object — the pinch, the corner handle, and what keyframes animate.

**`TextOverlayModel.fontSize` is frame-relative**: the letters' em size in thousandths of the
frame's **short side**, so Size 100 is letters a tenth of the frame, the same on any phone
(short side, so a landscape project is not sized by its long one). **Null is the old meaning**
— 32 reference pixels, how every text was sized — so every saved project opens byte-identical;
`textSizeOf` gives such a text the Size its letters already have, and the ruler starts from
there, so moving it changes nothing until the finger moves. Range `kMinTextSize`–`kMaxTextSize`
(20–300), clamped on read. **Not part of `TextLook`** — a template or caption style restyles
without resizing — and not keyframable.

**The layout has two scales, and `renderScale` is gone from it so every caller had to choose.**
`canvasScale` is geometry: where the box sits and how wide it may wrap. `inkScale`
(`textInkScale`) is what the text draws — letters, outline, shadow, background padding and
radius, the box's own padding — the canvas scale times the Size. **Their difference is the
feature**: bigger letters in the same width re-wrap instead of running off the frame, and a
look keeps its proportions at any Size. The painter, both rasters, the glyph layout and the
preview tiles draw with `inkScale`; the canvas layer's moves and width handles keep
`canvasScale`. A pixel test pins that the exported letters grow with the Size — the box alone
comes from the layout and would agree even if the raster drew at the wrong scale. **Anything new
that draws a text must take `inkScale`, and anything that places one `canvasScale`.** Flutter's
blur sigma for a radius adds half a pixel, so a shadow's *radius* keeps proportion, not its
sigma.

**Defaults**: new plain text and template text start at `kDefaultTextSize` (120 — about what the
old 32 px letters are on a phone's canvas, so a new text looks as it did there and now the same
everywhere); a template's own `scale` sits on top. Captions are built at `kCaptionTextSize` (100)
**at scale 1**, so the ruler shows their real size and pinch starts from 100%. On a caption a Size
change reaches the set with "Apply to all captions" on (`_setText`, beside the look and the box
width); a regeneration keeps the set's Size (`captionStyleForNewSet`). **A caption set saved
before Sizes is converted on load** (`migrateLegacyCaptionSize`): the scale folded into the Size
and the wrap width multiplied back — the same letters, insets and line breaks at scale 1 (line
heights agree to within the text engine's per-line rounding) — and left alone where that cannot
be exact: a keyframed zoom, no reference canvas, a Size outside the ruler. Plain text is never
migrated; it simply reads its Size.

**The ruler**: half a step a pixel, snapping at the text's default (a caption's for a caption,
a text's for a text), the number tapped puts that default back, one undo step per drag.

**Known, from the review, deferred:** tapping the number at the default, or touching the ruler
without moving, takes an undo step that undoes nothing — the editor's sliders share the pattern.
Insets grow with the Size while the box's minimum width (`kMinTextBoxWidth`) does not, so at a
large Size with a background the width handle can ask for a box narrower than the insets; the
box stops shrinking and the far edge drifts toward the finger (preview and file still agree). A
legacy caption whose scale is keyframed is not migrated, so a Size broadcast from a converted
sibling leaves it larger at rest — dividing its scale keyframes by the old scale would convert it
exactly. A new emoji is still made without a Size (it draws as it always has). `copyWith` has no
`clearFontSize`; nothing clears a Size, and `_applyEdits` relies on null meaning "keep".

### Fonts from the server — one grid, a tap to download

**Awaiting device verification.** Spec: `docs/superpowers/specs/2026-10-22-server-fonts-design.md`,
plan beside it in `plans/`. Server contract: `slimshot_server/docs/app-catalog-api.md` §8.
**`google_fonts` is gone**, and with it every runtime download from Google: a guard test
(`test/no_google_fonts_test.dart`) fails on any import under `lib/` or the package in `pubspec.yaml`.

- **The Font tab is one grid** (`FontGridView`, `fonts/font_grid.dart`): System (Roboto), the three
  bundled fonts (`kBundledFontNames`: Montserrat Bold, Bebas Neue, Poppins), then **every
  published font** in the owner's order (`GET /fonts`, no category). **No categories at all** —
  the owner's call, after trying Trending and More fonts and finding a font filed nowhere simply
  missing from the app: publish a font and it is listed, a new one at the top until moved, the
  order set on the dashboard's Order tab. No tabs, no Downloaded tab, no delete. A server tile is the server's preview image (480×160, `FontPreviewCache` under
  `<app support>/font_previews/`), with an arrow until the font is on the phone and a ring while it
  downloads; one tap downloads and applies. **The last tap wins**: a font that lands after another
  was chosen, or after the sheet closed, applies nothing. Search runs on the phone, over label and
  name, ignoring case, spaces, dashes and underscores. A server font named like a local one, or
  listed twice, shows once, first place.
- **A font's name is what a text stores** (`fontNameFor`): the family for a Regular face,
  `<family> <style>` otherwise ("Lato Bold"). The server keeps (family, style) unique
  case-insensitively, so the name identifies the face, it is the name the engine registers, and
  **the draft format is unchanged**.
- **Files**: `<documents>/font_library/<id>-v<version>.<ext>`, written as `.part` and renamed when
  whole, indexed by `library.json` (through a temp file) — not temp, which the OS sweeps, and not
  a draft's folder, since one font serves every draft. The list is saved
  (`<app support>/font_catalog.json`) and shown at once, and **asked for again on every opening**
  of the tab and on pull-to-refresh — device-reported: a list kept for five minutes hid a font
  just published, which reads as the font not being there; the server's cache is cleared by any
  dashboard change and the limit is 120 reads a minute, so a read an opening costs nothing. A 429
  keeps what is shown and asks nothing until `retryAfterSeconds` passes, and
  with no `SLIMSHOT_API_URL` the grid is the local fonts alone (`fontServerConfiguredProvider`).
  Offline the grid and every downloaded font work. A newer `version` of a font on the phone
  downloads quietly when the list arrives (`updateOutdated`), used from the next start.
- **Registration** (`FontRegistry`): `ui.loadFontFromList` under the font's name, once a session —
  the engine cannot replace a family it holds, which is why an update waits for a restart. A file
  the engine refuses leaves its texts in System and never throws. **A text drawn before its font
  landed redraws when it lands**: `FontRegistry.instance.changes` notifies, `TextOverlayLayer` and
  `TextPreviewTile` lay their text out again, and `TextOverlayPainter` repaints through its
  `repaint` listenable — needed beside the rebuild, because a new painter over an unchanged
  overlay and box answers `shouldRepaint` false and would keep the fallback glyphs.
- **Making a name drawable** (`FontService.ensureAvailable` → `FontAvailability`): registered
  already; else on the phone; else found by name in the saved list; else
  `GET /fonts/by-family/:name`, **accepted only when the face it answers has that very name** —
  the lookup returns a family's Regular face, and "Lato Bold" is not "Lato". Every download asks
  for a fresh address (good for ten minutes, never stored); calls for one name share one download.
- **A project's fonts** (`fonts/project_fonts.dart`): opening a draft registers the fonts already
  on the phone before the first frame; every other text font is fetched in the background, once a
  session per name (`fontsToFetch`), from a listener on the text list alone — its identity
  survives a position event, so playback asks nothing. A font that cannot be had is said once a
  session (`kFontUnavailableMessage`); its texts draw in System, on the canvas and in the file.
- **Templates and caption styles keep their faces**: the bundled three plus
  `kServerTemplateFontNames` — Abril Fatface, Inter, Montserrat, Nunito, Oswald, Permanent Marker,
  Playfair Display, Press Start 2P, Righteous, Sacramento — prefetched when the templates sheet,
  the editor's Templates tab or Caption style opens, so the tiles show their real looks. The
  catalog tests pin every face to those names: **a template naming any other would draw in System
  for good.**
- **The export no longer waits for fonts** (the owner's point: a font is used only once it is on
  the phone). It registers the project's fonts that are on the phone — local, milliseconds —
  before it rasterises, so a text whose font is there can never export in the fallback, and one
  whose font is not draws System on the canvas and in the file alike. `export_fonts.dart` is gone.
- **The interface font is bundled**: Plus Jakarta Sans as static files at 400–800
  (`kInterfaceFontFamily`). The eight decorative fonts (personal-use or all-rights-reserved
  notices), an unused demo face and two `.zip`s that were saved HTML pages are deleted; the
  bundled fonts' SIL OFL notices are registered in `third_party_licences.dart`. Latin script only.
- **The owner's to-do on the server**: upload the ten template and caption fonts above as
  Regular faces. Only free (OFL) or licensed fonts go up.

### Apply to all — a copy, not a mode

Transform and the clip crop each carry an `ApplyToAllButton`: one tap copies the selected clip's
placement (scale, position, rotation with their keyframes, and the mirror) or its crop rect onto
every other clip, as one undo step, and says how many it reached. (Effects had one too, until an
effect became a bar: a bar already spans as many clips as it is long.)
**Deliberately not the `ApplyToAllToggle` Filters and Transitions use.** Those edits are single
choices that can sensibly write everywhere live; a placement is a ruler drag, and a live all-clips
mode would write a keyframe into every clip at the same *relative* instant on every frame of the
drag — which nobody means. Set one clip up, then copy it. Both go through
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
still has no travel; filter, crop, flip and adjustments copy across, and an effect bar over the
instant goes on applying where it is. Where the playhead is
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

**Speed and Zoom are rulers; Volume and Opacity are sliders**, and the split is the
ruler's own argument applied honestly. Sensitivity per pixel matters where the range is
wide or a tenth of a step is visible: speed spans `SpeedCurve.kMinSpeed`–`kMaxSpeed`
(0.1×–10×) and zoom 1×–5×. **The Speed slider capped at 2×**, so 4× was unreachable from
the Speed tool at all while the model, the engine and the speed *curve* all supported it —
a slider spanning 0.1–10 would have put 1× a tenth of the way along and made every
ordinary value a pixel-hunt. Volume and Opacity keep sliders: 0–100% on a track is the
universal idiom and a second gesture buys nothing. Both rulers snap to their default (1×),
because that is a value people return to *exactly*.

**The zoom row overflowed by 78px at 360dp** — the hint and the Reset chip side by side,
a yellow-black stripe on a narrow phone. Caught by adding both panels to
`tool_panel_sizing_test.dart`, which pumps a body unbounded; the hint is `Flexible` and
ellipsises, the chip keeps its size. **A new panel with a ruler or a row in it must be
added there.** Reset also stopped being `Colors.deepOrange` — a hue found nowhere else in
the editor's chrome, warning about an action that merely returns to the default.

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

**The clip turned the wrong way, and the code said so before a device did** (**awaiting device
verification**). The model's angle is clockwise, but `rotateCanvas` turned the sampled point by
`-radians` in a space that runs **y-up** — clockwise there — so a clip the ruler called 30°
clockwise was drawn 30° anticlockwise, in preview and export alike. The comment beside it reasoned
in a y-down picture: the slip the pan, the crop and the mask each made once. Now `+radians`. It
surfaced because Move to overlay has to keep a turned clip's angle, and overlays turn clockwise.
No test can see it — GLSL runs only on a device — so the device run is the check: a clip at +30°
leans its top to the right.

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

Zoom and snapping are done (below); clip visuals — speed, mute and duration badges — remain.
Reorder and the cut seam are done.

#### Zoom — pinch the timeline

**Device-verified 2026-10-19.** Two fingers on the track zoom it **about the playhead**: the
instant under the playhead when the pinch begins stays under it (`_pinchAnchorSeconds`), from
`kMaxPixelsPerSecond` (600, ~20px a frame at 30fps) out to where the whole project fills
`kZoomOutFitFraction` (80%) of the screen — never closer than `kDefaultPixelsPerSecond` (50), the
scale it had before; not saved with the draft (`logic/timeline/timeline_zoom.dart`).
`_pixelsPerSecond` became a field and everything on the track is placed through it, so lanes,
handles, diamonds, markers, the filmstrip (fixed-width tiles, so more frames rather than stretched
ones) and the ruler all follow.

**It opens zoomed out** (`_fitScaleOnOpen`, `timeline_opening_zoom_test.dart`, **awaiting device
verification**; the user's call): at that furthest zoom out, so a long project opens with all of it
in view and a pinch spreads it out, while a short one opens at 50 as before. It opened at 50
whatever the length — a minute of video was eight screens to scroll through before anyone pinched
it smaller. **Fitted once**, the first time the project has a length; a scale refitted to every
edit would change under the finger as a trim changed the length. The opening frame fetch covers
the half screen right of the playhead at that scale (`_visibleEndSeconds` before layout) —
fitted, that is far more than the 12 s it assumed, and nothing rebuilds the track after its first
layout to ask again, so the rest of the strip stayed blank until touched.

- **A `Listener`, not a recogniser**: it sees every finger without entering the arena, so a
  one-finger scrub, trim or carry is exactly what it was; the pinch begins at the second finger,
  and not while something is being moved or trimmed (`_isHandlingItem`).
- **Both scroll views hold still while pinching** (`NeverScrollableScrollPhysics`), or the first
  finger's scroll fights the zoom's own placement; the scrub it may have started is ended, never
  glided onto a seam.
- **The offset is corrected, not jumped** (`ScrollPosition.correctPixels`): a jump sends scroll
  notifications, which the timeline reads as a scrub — the playhead would move and playback pause
  for a zoom. A test pins the anchor and fails without the correction.
- **The ruler's step comes from the zoom** (`rulerTickInterval`: the finest of 0.1s … 1h with labels
  `kRulerMinLabelSpacingPx` apart), not from the project's length, and it paints only a screen
  either side of what is visible — zoomed in, a long project's whole ruler is thousands of labels.

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

**The lanes have two rules: nothing overlaps on a lane, and no lane is left empty**
(`logic/timeline/lane_layout.dart`, `lane_layout_test.dart`, `timeline_lanes_test.dart`,
**awaiting device verification**). Text, photos, video overlays and audio share one set of lanes,
so the rules are pure functions over `LaneSpan`s (id, lane, timeline range) and know nothing about
what an item is; the notifier reads the four lists into spans and writes the answers back.
Device-reported: a duplicate landed exactly on top of its original, and nothing could be dragged
onto a new lane below the last. Reading the code found the rest:

- **Duplicates** kept the original's lane and times. A text, photo or video copy now takes the
  nearest lane at or below the original that is free at that time (`firstFreeLane`); an audio copy
  goes straight after the original on its lane when free (`duplicateAudioTrack`, moved out of the
  screen).
- **A move** (`moveLaneItem`, `resolveMove`) takes the target lane if free; onto an item it
  overlaps on another lane the two **trade lanes** — lane is paint order, so that is the layer
  reorder — but only when everything displaced fits where the mover came from; otherwise the
  nearest free lane below. Sliding onto a neighbour on one's own lane steps down a lane. The
  target is clamped to `maxMoveLane`: one below the last lane anything *else* is on. With company
  on the last lane an item may open one new lane; alone there it may not go further, because the
  lane it left would be empty. The widget used to clamp to the current last lane, so no new lane
  could ever be made. A swept test drops every item at every time on every lane and asserts no
  overlap.
- **A trim** (`trimLaneItem`, `trimAudioTrackLive`, `clampTrim`) stops each edge at its lane
  neighbour. **A video overlay's left edge now cuts into its footage**: it moved only
  `timelineStart`, so trimming the head left the footage starting at its first frame, just later.
  `sourceStart` follows by `Δt × speed`, and neither edge may run past the footage
  (`sourceEnd` is the file's end or Split's cut; a right trim never changes it).
- **Empty lanes close** (`compactLanes`) when a gesture ends and on every overlay/audio delete,
  keeping relative order. **A draft saved before the rules held opens repaired**
  (`normalizeLanes` in `loadDraft`): overlaps separated in paint order, so of two stacked items
  the later, which painted on top, still does.

**A timeline gesture is one undo step, and the snapshot comes first.** Every frame of a lane move
or trim went through `updateTextOverlay` and its siblings, which snapshot per call, so Undo walked
a drag back a frame at a time; and `onDragEnd` was wired to `saveStateForUndo`, a snapshot of the
*finished* state — the first Undo did nothing, and a **clip trim could not be undone at all**
(`setTrimRange` never snapshots; its only entry was taken after it). Photo and video drags and
every overlay trim handle never called `onDragEnd`. Now `onDragStart` → `beginTimelineGesture`
(one snapshot) and `onDragEnd` → `endTimelineGesture` (close emptied lanes, and withdraw the
snapshot — restoring the redo stack — when nothing changed) bracket all twelve gestures, and a
test counts them. The live writes take no snapshot. `update*Overlay` lost its `newLaneIndex`
parameter and `_swapToLane`/`_findAvailableLane` are gone; **anything new that moves an item
between lanes goes through `lane_layout.dart`**.

Smaller faults fixed with it: the audio drag was still capped at `durationSeconds` — the first
asset's length, the last of the clamp sites the tail work removed; overlay trim handles enforced
the minimum only once a handle crossed the other edge, so a text could be trimmed to a few
milliseconds; audio trims used their own 0.5s minimum instead of `kMinClipDurationSeconds`; photo
and video duplicates left a clip selected beside the copy.

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
feel destructive), then alignment, colour targets and sliders — a target's sliders appear once
it has a colour: Thickness under Outline, Radius and Padding under Background, and **Opacity,
Blur, Distance and Angle under Shadow**. **Every slider in the tab is one undo step per drag**
(`_buildSliderRow` snapshots on drag start and writes live): they used to go through
`_updateOverlay` per frame, which snapshots per call — measured, an outline drag undid to 5.875
instead of 5. **A preset is a complete look**: applying one resets the shadow's tuning to the
defaults along with its colour. The header has an explicit ✓
Done; duplicate/delete belong to the timeline, not the sheet. **Text is created empty** and
`showTextEditor` deletes the overlay if it is still empty when the sheet closes — no
"Double Tap to Edit" ghosts in an export. The in-screen text panels (`text_panels.dart`,
activeToolIds style/font/animation) were unreachable dead code — nothing ever set those tool ids
— and were deleted; do not grow a second styling surface, it will drift from the sheet.

**The Text tool opens a submenu: Add text and Templates** (`_textMenu`, **awaiting device
verification**). It went straight to typing while Add text was all it held, because a one-item
submenu is a tap tax on the most common action; Templates is the second real entry that pays
for the tap. Both go through **`_addText`**, so a new text is made one way — at the playhead,
three seconds, **empty**, the editor opened on the keyboard. Its Templates (`add_template`) is
**choose, then type**; the other way round is the selected text's own Templates (below). The two
ids differ on purpose — `text_templates` is the sheet-tab door — so neither handler can catch
the other's tap. **Auto captions** is the third entry, shown only in a build that carries a
server address — it is not offered before it works (see the auto captions section). **It is on
the main menu too, right after Text** (device-reported: under Text alone it was hard to find —
captions are something people open the editor for, not a kind of text they think to look
under). The same id in both menus, so one handler and one visibility rule serve both doors;
`editor_menu_test.dart` pins both places.

**A template is a complete starting look, and it makes an EMPTY text**
(`logic/text_template_catalog.dart`, `panels/text_templates_sheet.dart`). Not a preset: the
editor's presets restyle an existing text and deliberately leave its font alone, where a template
is where a text *begins* — font, colours, stroke or box, alignment, size, place on the canvas and
in/out/loop animations, chosen as one look. `TextTemplate.sampleText` is **only the tile's**; the
inserted text is empty, so the rule that an empty text is deleted when the editor closes still
keeps placeholder words out of every export — a template inserting its sample would be exactly
the ghost that rule exists to prevent. `placement` is a fraction of the canvas from its centre,
converted at insert through the canvas size, so a template lands in the same place on any
device. The catalog test pins what a template could otherwise break silently: every font is bundled
or in `kServerTemplateFontNames` (any other draws in System for good); every animation resolves in its own
slot and is selectable; placement stays on the canvas and scale inside the pinch range; and a
template's shadow is inside the Style tab's own ranges and survives a draft unchanged.
Mutation-checked: an unknown font fails its test. (A rule that a boxed template use only
whole-block animations was retired with the boxed-text fallback — a box is a quad of its own
now and animates beside its letters.)

**Twelve templates, built from everything text can do** (**awaiting device verification** — most
real faces come from the server, which tests do not reach). A **glow** is a shadow at distance 0 with a
wide blur in the text's own hue (Neon, Glow, Typewriter); a **retro** or **comic** drop is a hard
shadow, blur 0, pushed clear of the letters; captions and banners ride a box. Each template sets
the whole shadow — colour, opacity, blur, distance, angle — not just a colour. **Type, then
choose**: `TextTemplate.restyle(text)` puts a template on a text that already has words, keeping
its words, timing, place, rotation, box width and lane and replacing **every** look field —
including the ones the template leaves empty, so changing from Comic to Caption leaves no outline
behind (a test runs every pair both ways) — with animations back at natural speed and the
template's size. `apply` is `restyle` on an empty text, so the two ways in cannot drift.
`isAppliedTo` says whether a text is wearing a template — the look only, not size (a pinch after
choosing is placement) — and a test pins that each template recognises its own look and no
other, which also means no two templates are the same look under different names.

**A preview tile sits on a stage and never wraps.** `AppColors.previewStage` (zinc 600) is the
tile's inner screen: on the tile's own near-black surface a subtitle's outline and a comic's drop
vanished, and a test pins the stage's contrast against black (>2.5) and white (>4.5).
`kTextPreviewCanvas` is 640 wide because text wraps at the canvas width less a margin, and at 240
that broke HEADLINE and BREAKING in two and wrapped Press Start 2P almost always; at 640 a sample,
or the eight graphemes of the user's text a tile shows, sits on one line.

**A template tile is the painter too.** `TextTemplateTile` builds its overlay with
`TextTemplate.apply` itself — the call that makes the real text — given the sample words, and
plays entrance, hold (at least one loop cycle) and exit in one loop. It and `TextAnimationTile`
are thin wrappers over **`TextPreviewTile`**, the shared shell (clock sweep, measure, fit, clip,
selection chrome), extracted so the two cannot drift; the animation tile's 26 existing tests pass
unchanged through the extraction. The sheet stops at `kEditorSheetPreviewFraction`, has no title,
and drives every tile from one 2.4s clock — longer than the animation tab's 1.8s because a
template tile plays three motions per loop. **Its tests must never `pumpAndSettle`**: the tiles
play forever by design, so it times out after ten simulated minutes; they pump past the sheet's
motion instead (`settleSheet`).

**Type, then choose: the text editor's Templates tab** (`text_editor_templates_test.dart`,
**awaiting device verification**). Right after Keyboard, and reached from the selected text's
menu (Edit, **Templates**, Style, Font, Animation). Every template is previewed **in the text's
own words** (`textPreviewWords` — the same eight-grapheme rule the animation tiles use, falling
back to each template's sample while there are none); a tap puts it on through
`TextTemplate.restyle`, one undo step, words and place kept; another tap swaps it, as often as
the user likes. The tile of the template the text is wearing is highlighted, found by
`isAppliedTo` rather than remembered, so it is right on reopening and goes dark the moment a hand
edit changes the look. **A chosen template must go back through `_loadLook`**: the sheet rewrites
the whole text from its own copies of every look field on each keystroke, so without it the next
letter typed put the old look back — the test for it fails when `_loadLook` is removed. Both ways
in show one grid (`TextTemplateGrid`, with its own clock); the sheet and the tab differ only in
the words they give it and what a tap does.

**A selected text has a menu of its own** (`_textOverlayMenu`, **awaiting device
verification**). Selecting a text used to show the **root** menu — tools for making a project,
none for the text — and its whole editor hid behind a tap on the already-selected text; image
overlays, video overlays, clips and audio each had a menu. The menu follows the selection through
every door: `selectTextOverlay`, `addTextOverlay` (the Text tool *and* the emoji picker),
and `duplicateTextOverlay` open it, and **`deleteTextOverlay` leaves it
itself** — the canvas frame's ✕ calls delete and nothing else, so a caller-side deselect would
strand the menu with nothing selected. `addTextOverlay` now also clears any other selection,
like `addImageOverlay`, or the delete handler (which checks text first) could act on a thing the
toolbar was not about. **Edit, Templates, Style, Font and Animation are doors into the one
sheet**, not surfaces of their own: `kTextMenuSheetTools` maps each id to the tab it opens, and a test pins
the map to the menu declaration and to every tab. The ids carry a `text_` prefix because
`animation` already opens the photo and video overlays' `AnimationDrawer`.

**A text cannot be split** — built, then removed at the user's call: a text is retimed by its
trim handles, and a second copy of the words is what Copy is for. `editor_menu_test.dart` pins
the menu entry and the handler both gone.

**The Split tool is offered by the rule it cuts with, for everything that splits**
(`isSplitToolEnabledProvider`, `split_gate_test.dart`). The gate used to carry a rule of its own
and was wrong twice — both demonstrated with a probe before anything changed. It knew only clips,
requiring `isClipSelected`, which selecting a video overlay clears: **the
video-overlay menu's Split had never shown.** And for clips it compared the playhead's
**timeline** seconds against the selected clip's **source** range — the confusion the
timeline-contract section warns about — so a later clip from another file hid its Split mid-clip
(clip b at 5–13s over its own 0–8s, playhead 9.0), and near a seam it offered a cut the blade
refused. Now a video overlay asks `_overlaySplitPoint` (each half at least
`kMinClipDurationSeconds`, the cut on a whole millisecond, the precision a draft stores), and clips ask **`_clipCutPoint`,
the one clip-cut rule** — `_cutSegments` throws where it refuses and the freeze sits its still
beside the clip where it refuses, so the blade, the freeze and the button cannot disagree. The
sweeps compare gate against action at both edges of every clip and overlay.

**Unhiding the video overlay's Split exposed two faults in `splitVideoOverlay`**, fixed with it:
both halves kept both animations (now the entrance stays left and the exit right — copied
verbatim, the overlay would exit before the cut and enter again after it), and the source was
cut at the bare timeline offset, ignoring `speed` — the engine plays an overlay at
`sourceStart + offset × speed` (`NativeTimelineOverlay.sourceAt`), so at 2× the right half started
early in the footage. The cut now mirrors that mapping, clamp included, so every instant shows the
frame it showed before the split.

**A declared tool reaches the user unless `isToolbarToolVisible` says otherwise**
(`logic/toolbar_visibility.dart`, **awaiting device verification**). Device-reported: the video
overlay's Volume never showed. It was declared, and the menu tests — which read declarations —
were green, because the filter hiding it lived inline in the screen where no test looked: Volume
and Speed were hidden in any project with several clips and none selected, and selecting an
overlay deselects the clip. The same filter hid the video overlay's **Animation** outright, a rule
from before the engine drew overlays (`AnimationDrawer`, `setOverlayAnimation` and the composer all
carry a video overlay's animations). The filter is a pure function now, and
`toolbar_visibility_test.dart` reads every overlay menu's declared ids and requires each shown for
its own selection. **A new rule that withholds a tool goes there**, never back into the screen.

**✕ on Volume or Opacity discards, whatever the target** (`openRevertibleTool` /
`discardActiveTool`, `tool_discard_test.dart`, **awaiting device verification**). Only a clip's
Volume held its drag as a preview; a video overlay's volume, any overlay's opacity and a clip's
opacity write the model as the slider moves — the engine hears them through it — so ✕ closed
the panel and kept the change. The two tools now open with a record of the selected clip or
overlay and the undo depth; ✕ puts **that one object** back by id (not a state snapshot, which
would also move the playhead to where the drag began) and drops the undo entries the drag
pushed, keeping older ones. ✓, Back and a canvas tap keep the edit as before. Any plain
`setActiveTool` drops the record, because a tool can close without ✓ or ✕ and a stale record
would let the next ✕ restore an old overlay. Imported music's own player is reset to the
track's volume on ✕ — nothing else re-syncs it. An overlay's Opacity drag is also **one undo
step** now; it snapshotted per frame. **A new slider panel that writes live must open through
`openRevertibleTool`**, or its ✕ keeps.

**An emoji is a text overlay, and that is the whole feature** (`logic/emoji_catalog.dart`,
`panels/stickers_drawer.dart`, **device-verified**). An emoji is a *character*: it
renders through the platform's own colour emoji face, which is why one typed from the system
keyboard already exported correctly before any of this existed — device-confirmed by the user.
So the picker inserts a `TextOverlayModel` whose text is the emoji, and it inherits the glyph
atlas, per-character animation, mask, chroma key, keyframes and export parity already verified.
**Do not add an emoji overlay kind**, and do not bundle an emoji font: a dedicated kind would be
a second implementation of the text pipeline, and a bundled face would add megabytes plus a
second look that drifts from what the user's keyboard produces. `_addEmojiOverlay` deliberately
does **not** open the text editor — the user has already chosen what they wanted, and a keyboard
over the canvas is a second decision nobody asked for; tapping the overlay opens it as usual.
`kEmojiOverlayScale` (2.5) is only a starting value, because an emoji at caption size reads as
punctuation rather than as a sticker; nothing downstream knows an emoji from a word.

**Every catalog entry must be one grapheme cluster**, pinned by `emoji_catalog_test.dart` across
all ~590. A flag is two regional indicators and a skin tone is a base plus a modifier: a
two-cluster entry would insert as two glyphs and animate as two characters, and a half-cluster
renders as a hollow box — in the export as well as the preview. Entries are kept to Emoji 12
(2019) and older for the same reason: a codepoint newer than the device's font is a box.
`text_overlay_emoji_test.dart` pins the rasteriser half (clusters stay whole, cells are well
formed, emoji paint ink). It deliberately does **not** assert colour — `flutter_test` has no
colour emoji face behind its bundled test font, so such a test would pin the harness rather
than the product; colour is a device fact.

**The picker stops at `kEditorSheetPreviewFraction` (45%), not at the audio library's 0.7.**
Choosing an emoji is a choice *for a frame* — the user is looking at where it will land — so the
device-reported rule that a tall sheet hides the very frame being chosen for applies here as it
does to Filters or Background. A grid pays nothing for the cap because it scrolls, where the
audio library is a list to read down; at 45% several rows still show with the canvas in view.

**The drawer had GIF and Sticker tabs and a search field, and all three were a mockup** — three
hardcoded labels over a spinner that never resolved, with no callback, no selection and no
insert. They are removed rather than left visible, which is the same call as the root menu's
Effects entry: the rule protects *unfinished* tools, not ones promising content that has no
provider behind it. GIFs need an animated source, and that means a video overlay (a GIF through
the image path is `BitmapFactory`, one frozen frame) plus an API serving MP4 — a separate piece
of work, not a wiring job.

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

**One rule for everything on the lanes** (`logic/timeline/timeline_snapping.dart`, **device-verified
2026-10-19**). Moving a text, photo, video overlay or audio track, and trimming either
edge of one, pulls onto the nearest of: 0:00, the playhead, every cut between clips, and the start
and end of every other item on any lane (`timelineSnapTargets`). A move snaps whichever of its two
edges is nearer a target (`snapMovingSpan`). The reach is `kSnapTolerancePx` converted through the
current zoom (`snapToleranceSeconds`), so it feels the same at every scale. A guide line runs
through the filmstrip and every lane where it landed, with one haptic tick on arrival. **The
targets are taken once, when the gesture starts** (`_snapTargetsFor`): a move previews its own
start on the playhead, so a live playhead target would chase the item and snap it to itself.
Snapping comes first and the lane rules (`lane_layout.dart`) still have the last word. The text
mover's old pull to whole seconds is gone — an arbitrary point. A main-track clip's **end** trim
also meets the lane items' edges (`_snapTrimEndToItems`; not under a speed curve or a reversal,
where source and timeline are not a straight line); its start trim keeps the playhead alone, since
trimming the start shifts every later clip.

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

#### Timing — what the playhead points at, and when

**Awaiting device verification.** From a check of everything that has to agree on an instant —
the picture, the playhead, the filmstrip, the bars, the music, the text. Five faults, each pinned
by a test:

- **The playhead line was 4.25 px late** (85 ms at the default zoom): the column holding the line
  and its triangle was placed by the line's width but centred the line on the triangle's. The
  column is centred on the playback instant now (`timeline_playhead_alignment_test.dart`).
- **A filmstrip tile showed a frame from before itself**: its left edge rounded *down* to the
  200 ms grid — for a clip's first tile after a split, a frame from across the cut — and the
  extractor then moved to the nearest keyframe, which can lie across the cut too. A tile shows its
  own middle, rounded to the nearest step and held inside the clip; a clip's first and last tiles
  ask for the exact frame (`OPTION_CLOSEST`, cached apart under `exact`), the rest the nearest
  keyframe for speed (`clip_filmstrip_timing_test.dart`).
- **Imported music started late.** `play()` went out with its seek in flight. It plays once the
  seek has landed, re-aimed by a short second seek where the playhead moved on meanwhile — before
  the start only (`MusicPlayer`, `audio_player_sync_test.dart`). **While it plays, drift is lived
  with**: only a jump of `kMusicJumpSeconds` (0.5) is corrected, with one seek, at most every 2 s.
  Device-reported: a first version corrected from 0.1 s, and music, extracted sound and sound
  effects crackled — the music player always sits a steady tenth or so behind the engine (the time
  its sound takes to start), so it seeked every 1.5 s, and every seek of a playing track is a
  click. The overlay sound's lesson, below, unapplied; a test now plays ten seconds of steady lag
  and requires no seek.
- **The playhead moved only when a report landed** — about 30 times a second, a step every other
  frame, ~20 px at the closest zoom — and **text appeared, left and animated on those reports**,
  behind the picture. `PlayheadDisplayClock` (`logic/timeline/`) draws the playhead between the
  engine's reports, every frame, from the screen's ticker into `_drawnPlayhead`; the timeline
  scrolls to it (`ScrollableTimeline.playhead`) and text is drawn at it
  (`TextOverlayLayer.playhead`). **It writes nothing** — the reports stay the playhead state's only
  writer, dead-ends entry 12. It moves only while the engine says its picture is moving
  (`advancing` on the position event, the very test the engine's own smoothing makes), at most
  `kPlayheadMaxExtrapolationSeconds` (0.1) past the last report, and never back for a report that
  lands late. Given it, the timeline follows it alone: the reports, arriving behind it, would pull
  the track back a little thirty times a second (`timeline_drawn_playhead_test.dart`, checked by
  putting the old sync back).
- **A pause lands on the frame the engine stopped on.** The `paused` event carries the engine's
  position and the playhead takes it, unless something moved the playhead since (`_pauseFrom`) —
  without the move the drawn playhead, a little ahead, would jump back on every pause. Putting the
  playhead there does not seek the engine onto the frame it already shows (`_engineParkedAt`).

**Not fixed, and only a device can measure it:** the picture and the sound leave the phone through
pipelines of different latency (display versus audio output, Bluetooth the worst), which nothing
in the app sees. The drawn playhead also trails the engine by the platform channel's own delay, a
few milliseconds.

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
- **The transition tiles have the two weaknesses the effect tiles were built without.** Each
  frame goes through `Image.memory`, so decoded frames pile into Flutter's shared `ImageCache`
  (~88 MB browsing every category), and a `renderTransitionPreview` whose renderer is released
  mid-call leaves the channel unanswered — `TransitionPreviewFrames`' one-at-a-time queue then
  waits forever. Moving them onto the effect tiles' atlas, job and cache fixes both.
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
one more windowed source, at its own speed so the sound runs with the picture. **That fix left
it mixed twice** — the export kept its older 1× track entry for the same overlay beside the new
source — until `TimelineAudioTracks` (auto captions section).

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

**The measured reason it happens at all — and the caps were wrong.** On the
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

**The preview's overlay cap is now a budget, not a constant** (`nativepreview/DecoderBudget.kt`,
**awaiting device verification**; shipped separately from the crash fix on purpose, so a
regression in either half names itself). The cap used to be `MAX_OVERLAY_DECODERS = 2`, read by
nothing that knew the device — the one genuinely scarce resource the app neither probed nor
degraded on. `DeviceDecoderFacts.avc` reads the AVC decoder **once**: `maxSupportedInstances` and
`VideoCapabilities.getSupportedFrameRatesFor(1920, 1080).upper`, which is the platform's own
`blocks-per-second ÷ macroblocks` — the portable route to throughput, and it **throws** for a
size the codec cannot open, which is how "no 4K" shows up without parsing `dumpsys`. It logs one
`decoder facts:` line under `SlimshotExport` with both numbers, the size range and the caps they
yield, so the next device report arrives with measurements instead of guesses.

`DecoderBudget.previewOverlayCapacity(device, lanes)` costs every stream — a clip lane or an
overlay — as a **reference 1080p30** and takes the tighter of throughput and instances, floored
at 1 (zero would silently remove video overlays as a feature) and capped at `PREVIEW_CEILING` 6
(a memory bound: each decoder holds five to eight 1080p output buffers). **No headroom is held
back**, on evidence: the Infinix plays one lane plus two overlays — 90 of its ~105 — for minutes,
and a 15% margin would have cut that to one. So it yields the same **2** that always shipped
there with no transition, and **1** through a transition, where the second lane spends the
throughput the second overlay wanted. A device that will not describe itself gets `LEGACY_CAP` 2.
The lane count is why it is recomputed on every `setTimeline` (`applyDecoderBudget`), pushed
through `TransitionRenderer.setPreviewOverlayDecoderCap` and applied to the builder's
`maxVideoDecoders` on every draw. **It bounds opening, never evicts**: a decoder already live
when a transition drops the cap plays on until its overlay expires, because a picture vanishing
mid-frame for no visible reason is worse than one frame over budget. Per-stream accounting (a
720p overlay costs less than it is charged here) and eviction are the expensive half and are
deliberately not built. **The export keeps the constant 2** — it is not realtime, so a decoder
over the throughput line only slows the run. `OverlayAudioPlayers.MAX_PLAYERS` is untouched: those
players hold no video decoder.

**What it unlocks**: an overlay chroma key and blend modes, each now a shader line rather than an
impossibility, and an exact feather instead of a hard-edged clip.

### Sound library — effects and music, tap to listen, + to add

**Awaiting device verification.** Spec: `docs/superpowers/specs/2026-10-19-sound-effects-library-design.md`,
plan beside it in `plans/`. Server contract: `slimshot_server/docs/app-catalog-api.md` — build
against it alone. **Sound effects** on the audio menu (id `sound_effects`; `effects` stays the clip
menu's, which is why the old handler's "which menu is open" gate is gone) opens a 0.7-high sheet,
hidden without a server address (`isToolbarToolVisible`'s `hasCatalogServer`). **The audio menu
had never been reachable** (device-found): the root Audio tool is declared with a submenu, but a
handler keyed on `audio` opened the music library directly, ahead of the submenu branch; the
library now opens from the submenu's Music.

- **The only hardcoded name is the root, `kSoundEffectsRoot` (`sound-effects`).** The pills are
  its children, in the dashboard's order, under a fixed **Downloaded** pill; renaming, reordering,
  hiding and adding categories are the dashboard's and need no release. Music will be the same
  code pointed at `music`. An empty category is hidden from the dashboard, not filtered here.
- **The server has no previews, so the download is the preview** (the user's call, after
  comparing with CapCut): a tap on a row downloads the sound — they are tens of KB — and plays
  it. **The icon is download until the sound is on the phone, then +** (the user's call on the
  device): download fetches only, nothing played or added; **+** puts it on the timeline at the
  playhead (`addLibrarySound`, an ordinary `AudioTrackModel` through `addAudioTrack`: first free
  lane, selected, one undo step) and closes the sheet. **Accepted cost**: every sound listened
  to counts as a download in the dashboard.
- **A sound effect is orange on the timeline** (the user's call): a track added from the
  sound effects library carries `AudioTrackModel.isSoundEffect` — written to the draft only when
  true, so older drafts read as ordinary audio — and `audioTrackColor` draws it in
  `AppColors.soundEffect` where music and the user's own sound stay purple; its lane's gutter
  shows the tool's own glyph beside music's note. **The glyph is drawn, not Lucide's**
  (`SoundEffectIcon`, `core/theme/sound_effect_icon.dart`: a beamed note with a burst and three
  rays, the user's pick from a reference): `sparkles` is the clip Effects tool's and a bell read as
  an alarm, and Lucide has nothing with a hit in it. It is drawn in Lucide's manner — 24-unit grid,
  round strokes — and takes an `Icon`'s size and colour. `EditorTool.glyph` /
  `EditorToolTile.glyph` draw it in place of the icon; the gutter returns `LaneGutterKind`s and
  `laneGutterGlyph` draws each, so a kind without a Lucide glyph needs no special case. Music from the library is ordinary
  audio.
- **A selected audio clip is framed in white, with slim white handles outside it** (the user's
  call): the slab is 8px from the clip's edge outward (10 while held), the touch area 16px and
  reaching 4px into the clip (`_kAudioHandleInset`). Purple was the fill's own hue, so the frame
  and handles disappeared into it.
- **An item starting at 0:00 keeps its left handle inside itself** (`_atTimelineStart`, every
  lane — audio, text, photo, video overlay; `lane_trim_handles_test.dart`; the user's call).
  Drawn outside, the handle crossed the line marking the timeline's start and the item read as
  running past it. Not hidden: it still trims the start by dragging right. Main clips need no
  rule — their grips have always been drawn inside the clip.
- **The sheet opens on Downloaded when its library holds anything, otherwise on the first
  category** (the user's call; `_opensOnDownloaded`): what the user already chose comes first.
  The categories arriving does not move it.
- **Music is the same sheet, pointed at the server's `music` root** (`kMusicRoot`; the user's
  call, with the categories already in the dashboard). `SoundLibrarySheet` /
  `SoundLibraryController` serve both, opened by `_showSoundLibrary(root)`. Music adds **Import**
  beside the search (`onImport`; `pickAudioTrack` in `sound_library/import_audio.dart`, the old
  sheet's import unchanged — the user's file at 0:00). **The old Music sheet is deleted**
  (`AudioDrawer`): its "For you / Saved / Trending" tabs were labels over a spinner that never
  resolved. **Each library keeps its own**: a `LibrarySound` records its `library` (an entry from
  before there were two is a sound effect), and each sheet's Downloaded shows only its own; the
  browse cache is one file per root (`catalog_cache_<root>.json`, `catalogCacheProvider(root)`).
- **The search field and tabs are the old Music sheet's look**: the field over the categories as
  underlined text tabs, Import beside the field where offered.
- **A sideways swipe on the list changes tab** (the user's call): one page per tab in a
  `PageView`, and a neighbour slides in already showing what it last loaded
  (`controller.soundsFor(pill)` — the live list for the shown tab, the library for Downloaded,
  the cache for the rest). **A tap on a tab chooses it at once and slides there, and the tabs
  the slide passes are not opened** (`_sliding` holds `onPageChanged` off until it lands) —
  passing a tab is not choosing it, and opening each would fetch its first page for nothing. The
  chosen tab is scrolled into view in the row (`Scrollable.ensureVisible`), and a tab changed
  without a swipe (the sheet opening on the first category, a vanished one falling back to
  Downloaded) moves the pages after the frame (`_followSelection`). The test pumps at frame rate:
  in 100ms steps the slide skips the middle page and the guard goes unproven. **Search filters what the sheet
  already holds** (the user's call): the tab's loaded rows or the library, by title, ignoring
  case, underscores and dashes, since titles arrive as file names. The server has no search;
  scrolling a tab loads more of it to search. The audio menu's first tool is **Music** (id
  `music`), not "Sounds", which read as if effects were not sounds.
- **The library is `<documents>/sound_library/`** (`SoundLibrary`): not temp, which Clear Cache
  and the OS sweep, and not `drafts/<id>/`, since one sound serves every draft and
  `DraftFiles.deleteAll` must not take it. `<id>.part` renamed when whole; the cover beside it
  (a failed cover is not a failed download); `library.json` written through a temp file. **No
  delete**, so a draft can never point at a sound the app removed.
- **Offline**: `CatalogCache` keeps the pills and **every row each pill last loaded** — not just
  its first page; a scroll's later pages are saved too (the user's call) — in
  `<app support>/catalog_cache_<root>.json`, shown at once on every opening; the library plays and adds
  with no connection. **Rows are not dimmed or disabled offline** (the user's call): a download or
  a listen on a sound not on the phone is *tried*, and a connection failure says **"No internet
  connection"** (`SoundSheetNoticeKind.offline`, from `SlimshotApiException.network` or a
  `SoundDownloadFailed(offline: true)` mid-file). Tried rather than assumed, because the
  `offline` flag is only what the last request found. The download `url` is never stored.
- **`SoundLibraryController` holds every rule** apart from the widget (`sound_library_sheet.dart`
  is layout). Requests are numbered so a late page for another pill, or one from before a
  refresh, is dropped; pages deduplicate by id; a 404 root leaves Downloaded alone; a vanished
  category falls back to it; a 429 stops automatic requests until `retryAfterSeconds` passes,
  and Retry or pull-to-refresh wait it out. One add at a time; a listen and a + on one sound
  share a download (both in the controller and in `SoundLibrary`). A length the server did not
  know is read from the file. After the sheet closes an add in flight comes back empty while the
  file still lands.
- `SlimshotApi.sendPublicEnvelope` reads a public answer whole — the catalogue's `data` is a
  list and its pages carry `meta` — sharing `_refusal` with `_decode` so the two cannot drift.

### Playback stops when the app leaves the screen, or the audio is taken

**Awaiting device verification** (the owner's report, 2026-10-28: minimised, the video and music
played on). Nothing in the app listened for it: the engine's ExoPlayers and the `just_audio`
music never pause themselves, and the playhead froze in the background (Flutter draws no frames
there) while the sound ran on.

**`PlaybackGuard`** (`services/playback_guard.dart`, `playback_guard_test.dart`) pauses the
editor **through its own pause** — `setPlaying(false)`, the button's path — so the picture, the
clips' and overlays' sound, the music, the playhead and a voiceover take stop together:

- **The app leaving the screen** (`AppLifecycleListener.onHide`): Home, another app, the screen
  locking, a call screen, the gallery picker. Still on screen it plays on — the notifications
  pulled down or a permission prompt only make the app inactive. **Coming back it stays
  paused**, as CapCut does. Android silences a background app's microphone anyway, so a take left
  running would have filled with silence.
- **Something else taking the audio**: the editor **holds the phone's audio while it plays and
  gives it back on every pause** (`audio_session`, the session the app's `just_audio` players
  share — on Android one request for the whole app, so nothing in the app takes the audio from
  anything else; and releasing on every pause also clears the plugin's stale request after a
  refusal). A call, another app's sound (`pause`/`unknown` interruptions) or headphones coming
  out (`becomingNoisy`, Bluetooth included) pause the editor. **A duck does not**: a notification's
  ping asks the others to dip, the phone lowers the editor for a moment and it plays on — pausing
  there would stop every edit at every incoming message. An interruption ending resumes nothing.
- **The guard is the one owner of the editor's sound.** The music players are
  `AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false)`: left to
  itself `just_audio` paused only the music on a call (the video played on), resumed it by itself
  afterwards, and paused only the music on unplugged headphones (the clip sound carried on from
  the speaker). A test reads every `AudioPlayer(` under `lib/features/video_editor/` for both
  flags. Take and release run in order on one queue, so a release can never overtake a slow take
  and leave the audio held behind a paused editor; a session that cannot be had costs only the
  interruptions, never playback.
- **The sound library's listen** stops too (`SoundLibraryController.stopListening`, from the
  sheet's own `onHide`); a listen still downloading does not start when it lands.
- Outside the editor, `video_player` already pauses itself in the background (the compress,
  result, export and extract previews) and resumes on return; left as it is.
- **Tests send lifecycle the phone's way** (`test/support/app_lifecycle.dart`): one message on
  the lifecycle channel, from which the binding walks the states between — straight from resumed
  to hidden is not a move a phone makes, and `AppLifecycleListener` asserts on it.

**Device checks**: minimise while video and music play — silence, and back on the same frame,
paused; a call while playing; Spotify started over it; headphones out; a WhatsApp ping (the
volume dips, playback goes on); minimise mid-take; minimise while listening in the Music sheet.

### Audio — Extract and Record

**Awaiting device verification** (the capture, the remux and the playback alignment only run on a
device). Spec: `docs/superpowers/specs/2026-10-20-audio-extract-and-record-design.md`, plan beside
it in `plans/`. The audio menu's last two tools had been declared with no handler since the menu
existed — a tap did nothing.

**Both write into the draft's own `drafts/<id>/audio/`** (`DraftFiles.audioDir`), so the sound goes
with the draft and nowhere else — never temp, never a picker's cache — and both land as ordinary
purple `AudioTrackModel`s through **`placeAudioTrack`** (the library's add too): first free lane,
one undo step, and **the only selection** — `addAudioTrack` alone left whatever was selected
before selected beside it, with the toolbar out of step.

**Extract** (`_showExtractAudio`, `ExtractAudioSheet`, the owner's design): the gallery opens on
videos; a 90% sheet (`kExtractSheetHeightFraction`) plays the video over its sound's **real**
waveform with two handles, **Change video** and **Done**; Done puts the sound at the playhead.
- **The handles are the track's trim, not a cut** (`ExtractSelection`, `extractedTrack`): the whole
  sound is kept, so the track's edges can still be dragged out on the timeline. They never cross
  and never close below `kMinClipDurationSeconds`.
- **The selected part slides along, keeping its length** (`ExtractSelection.movedTo`, the owner's
  call): a drag anywhere between the handles moves the window, held inside the sound. It moves
  the moment the finger does — anchored on pointer-down, no long-press wait, no slop lost — and
  the handles sit above it and win where they overlap. The preview keeps looping the old part
  through a drag and seeks once on release: a seek per frame would flush the decoder on every
  move, which is the stutter.
- **Copied, not converted, wherever it can be** (`AudioExtractor`, `ExtractPlan.canRemux`): AAC —
  almost every phone video — goes into an `.m4a` unchanged through `ExportMuxer`, near-instant at
  any length; anything else — and an AAC the muxer refuses — is decoded by the export's
  `PcmAudioSource` and encoded by `AacFileEncoder`. **The track never points at the video**:
  playing a video for its sound would hold a hidden video decoder, the low-end failure fixed for
  overlays. Media3's `Mp4Muxer` keeps the caller's buffer (sample copying is off by default) but,
  with batching also off by default, writes every pending sample before `writeSampleData`
  returns — which is why the remux may reuse one buffer, and why the export always could.
- **Both gallery picks go through `pickVideoPath`**: a refused permission or a picker failure is
  one line (`kVideoAccessMessage`, `kVideoPickFailedMessage`), never an error nothing catches.
- The waveform is `WaveformPeaks`, fed a block at a time (`Accumulator`) so a long song is never
  held whole. Channel `slimshot_ai/audio_tools` (`AudioToolsChannel`).
- **"This video has no sound" is said in the sheet**, with Change video still offered and Done
  off. A sound extracted and not kept — the sheet closed, another video chosen — is deleted.
  A sound that cannot be saved (the draft's folder not writable) says `kExtractFailedMessage`
  the same way, never a sheet that spins.
- **The same video picked again keeps its sound and handles** (`isSameFile`): the gallery hands
  back a fresh copy on every pick, often under a new name, so the path cannot tell — the length
  and the first and last 64 KB can, at no cost next to taking the sound out again. Only while
  its sound is held: after a failure the same video is tried again. A waveform that cannot be
  read leaves the strip flat and the sound usable.
- **The sheet holds the player it opened** (`_player`, read once from the widget), and the
  editor makes it outside the route builder and disposes it when the sheet closes.
  Device-reported: closed without being used, the sound played on and looped until the app was
  closed. A route builder runs again whenever the route rebuilds, so a player made inside it
  reached the sheet fresh and never opened on every rebuild — closing disposed that one, and the
  handles steered it too, while the first played and looped for ever. **Anything a sheet must
  open and close itself belongs outside the builder.**
- **Known, from the review:** the preview player (`VideoPlayerExtractPreview`) is plugin code with
  no test; its loop is a position listener seeking back at the end handle.

**Record** (`_enterRecording`, `RecordController`, `RecordPanel`; the owner's design): the editor
turns into **recording mode** — the preview large, the timeline showing only the clips with the
take growing under them (`ScrollableTimeline.recordingTake`) and taking no touches, the panel one
round button with a pulsing purple ring. Record, pause, record again: **one take across every
pause**, starting where the playhead was. **No countdown** — built, and removed at the owner's
call after the first device run: a tap records at once. Done (✓, Back, the side tap — every keeping
close) puts it there; ✕ throws it away. Both play toggles are the record button while the mode is
on, and **anything that stops the video stops the take** (`onPlaybackStopped`), or the take would
run on over a still picture.
- **Why `AudioRecord` and not `MediaRecorder`** (`VoiceRecorder`, `CaptureGate`): the microphone
  runs from `open`, and only frames heard while capturing are kept — so it is warm before the video
  starts and a pause leaves no gap. `MediaRecorder`'s start delay cannot be measured.
- **Capture starts when the video is seen moving, not when play is asked for** (found by the
  branch review). Before play the editor composes the timeline and seeks — every play is a seek,
  a decoder flush, up to a few hundred milliseconds on a low-end phone — and a capture started
  at `play()` put every word that much late. The first playhead past the parked position starts
  it, aligned to that position (`setCapturing(alignTo:)`), and `CaptureGate.alignTo` pads the
  take with silence up to it: frame `n` of the file is always timeline `takeStart + n / rate`,
  through every pause. **Capture stops before the video does**, or the take keeps the sound of
  the moment the video took to stop, which nothing can take out again. A microphone taken away
  mid-take (`ERROR_DEAD_OBJECT`) ends the read loop instead of spinning a core. Channel `slimshot_ai/voice_recorder`;
  `RECORD_AUDIO` in the manifest; `permission_handler` asks, with a way to Settings when refused
  for good. A take that cannot be created (the folder not writable, a recorder failure it did
  not word) says `kRecordStartFailedMessage` and leaves the mode usable.
- **The preview is muted while recording, with a speaker toggle** — the phone's speaker would play
  into the microphone, under the voice, for good. **A monitor mute only**: the engine's `setVolume`
  (clips and overlay sound) and `AudioPlayerManager.monitorMuted` (imported music); never the
  project's `isMuted`, never a clip's volume, lifted when the mode ends, not remembered.
- **The device check that matters**: a clap on camera, recorded as a voiceover, should land on the
  clap's frame. What remains is small and late, never early: the microphone's own input latency,
  a 20ms read buffer, and the AAC encoder's priming — tens of milliseconds, under a frame or two.
  If the check shows more, measure it and trim it off the take's `sourceStart`; do not move the
  capture back ahead of the video. **Known:** a stall mid-take (the video buffering) leaves the
  rest of the take that much late — sound already kept cannot be taken out.

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

### Accounts and credits — stage 1: sign-in, claim, the pill, Settings

**Awaiting device verification.** Spec:
`docs/superpowers/specs/2026-10-05-app-accounts-credits-design.md`; plan
`docs/superpowers/plans/2026-10-05-accounts-stage1.md`. Server contract:
`slimshot_server/docs/app-credits-api.md`. Getting the Google keys: `docs/google-sign-in-setup.md`.
Stages 2 (the price step) and 3 (rewarded ads, invites, the Credits screen) follow.

**Signing in is optional; Auto captions is the first thing that needs it.** Google (the
phone's account picker through `google_sign_in` 7, the Web client ID from
`--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`, the button hidden without it) or an emailed
6-digit code. The first sign-in makes the account; a new account then chooses a username and
claims its free credits (`ClaimSheet`). **No number is promised before the claim** — the
bonus is the admin's to set and not every email or phone is eligible — so the home pill says
"Free credits" and only the claim names an amount. No Android ID anywhere: the server's
per-device rule is per install.

**Every secret is in the keystore** (`TokenVault`, `flutter_secure_storage`): the access and
refresh tokens, the install token — moved there from `shared_preferences` the first time it is
read — and the cached `/me`. A value that cannot be decrypted (a backup restored without its
keystore key) reads as absent, which leaves the app signed out rather than crashing.

**One session, shared** (`AccountSession`, `accountSessionProvider`). **Refreshes take
turns**: the server lets a refresh token work once and treats a second use as theft, ending
the session, so `refreshAfter` serialises them — a request refused with an access token that
has since been replaced just retries with the new one. Only a **401** on the refresh ends a
session; a 5xx or a proxy page is thrown and the session kept. Any request that ends the
session — a caption upload included — fires `ended`, and `AccountNotifier` flips the whole
app to signed out. **A refresh that lands after its session ended or was replaced is neither
saved nor allowed to end anything** (`_generation`, moved by `end` and `save`): the common
case is coming back after 15 minutes — the first request is refused, a refresh goes out — and
signing out before it answers, which used to put the tokens and the profile back on the
phone (found by the branch review, probe-confirmed). A late refusal likewise ends only the
session it was made with (`endIfCurrent`), never one signed in since.

**`SlimshotApi` has three kinds of request.** `send` is signed in: the access token as a
bearer, one refresh on `UNAUTHENTICATED`, then `SIGN_IN_REQUIRED` — never a loop.
`sendWithDevice` is a sign-in: no bearer, the install token in the body, a
`DEVICE_NOT_REGISTERED` install registered again once. `sendPublic` carries neither.
The install token is **not** an access token: the server refuses it as a bearer.

**`requireAccount` is the one door** (`features/account/account_gate.dart`): a kept session
whose profile has not loaded is refreshed rather than asked to sign in; signed out, the
sign-in sheet; unclaimed, the claim sheet. It answers from the account, not from how a sheet
closed — a claim that succeeded and was swiped away instead of closed with Done still counts.
`CaptionAccess.ensureAllowed` is it, called
**before** the Auto captions options sheet, and the caption client is built on the shared
session. After a run the profile is read again, which is what shows a refund.

**The signed-in state is app-wide** (`accountProvider`, not autoDispose): the cached profile
at once, then `/me`; offline, the cached one stays. Three races, each found by a test that
failed first:

- **An older answer never overwrites a newer one.** Every request whose answer becomes the
  profile takes a ticket when it *starts*, and an answer older than the last adopted is
  dropped — the launch's `/me` landing after a claim used to put the account back to
  "not claimed". The ticket and the state change together with no wait between, so an answer
  dropped as older can rely on the newer one already being on screen.
- **A profile never outlives its session.** One that lands after sign-out is not written
  back, and one whose keystore write overlapped a sign-out is taken back (`_adopt` checks the
  session again after writing).
- **Signing out and deleting show it at once.** The session's `ended` event arrives a
  microtask later, so `_forget` sets the signed-out state itself.

**Sign-out asks first** (`SignOutSheet`, "Sign out of <name>?" — device-reported: one tap
signed the user straight out); Cancel, a swipe or a tap outside keeps the account, and the button
is the ordinary primary, not red, since the credits stay with the account. **Then it happens on
the phone first**, and the server is told afterwards without being waited for: on Wi-Fi without internet the logout would otherwise hold the sign-out for its
whole 20 s timeout, and closing the app meanwhile kept the account. Account sheets are capped at 480 px,
open through `showEditorSheet`, and the code step's two links wrap rather than overflow at
large text. **They open on the root navigator** (`useRootNavigator: true`; device-reported):
home and Settings are `StatefulShellRoute` branches with navigators of their own, and the
shell's floating nav is painted above them, so a sheet opened on a tab's navigator slid up
*under* the nav. Any sheet reachable from a tab must do the same. The email step's
**Continue stays off until the field holds an email address**. The Google button carries
**Google's own four-colour G** (`assets/google_g.svg`, as its sign-in branding asks) — an asset,
since Lucide has no brand marks — and its label scales down rather than overflow on a narrow
phone with large text (`sign_in_sheet_test.dart` pins both).

### Accounts and credits — stage 2: the silent price check

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-10-06-credits-stage2-price-step.md`.
A run is **priced after the audio is rendered and before it is uploaded, silently** — the owner's
call on the device (2026-10-06): no "Checking price" stage, no confirm. It happens while the sheet
still says "Preparing audio". `AccountService.quote` sends the rendered WAV's own length — the
server measures that file again and charges what it measures, so the app **never works a price
out**. A quote without a price is refused (`badResponse`), never read as 0.

**A run the balance covers generates straight away. Only a shortfall is shown**:
`"Needs 30 credits · You have 0"` with Close — stage 3 puts **Watch an ad** there (rewarded ads
are verified on the server, SSV). The spec had a confirm step ("6 credits · You have 94" with
Generate); it was built, seen on the device, and dropped: `priceLine` and `CaptionStage.pricing`
are gone. The pipeline tells the sheet through `run(onShortfall:)`, whose answer says whether the
run may go on after all (stage 3: an ad earned the difference); **with nobody to tell, a short run
never uploads**. Closing the shortfall (Close, Back, a tap outside) stops the run.

**A retry under a held key is not priced again**: the user's earlier run already went to that
upload, the server charges at most once per key, and a fresh quote would read the balance the lost
upload already took — a shortfall with only Close, stranding the credits it paid (found by the
stage review). So the price is checked only while no key is held.

**The charge reaches the pill at once** (`onCharged` → `AccountNotifier.applyBalance`), ticketed
like every profile answer so a `/me` already on its way cannot put the old balance back.
**A paid job the server fails is refunded by the server**; `CaptionService` throws
`CaptionJobFailed` for a `failed` job (a `SlimshotApiException`, so its code still reads), and the
pipeline turns it into "Captioning failed. Your credits were returned." only when the upload
actually charged. `402 INSUFFICIENT_CREDITS` at the upload — the balance moved after the quote —
says how many from `details`. `409 IDEMPOTENCY_KEY_REUSED` takes one fresh key and uploads once
more; a second refusal is shown. The quote runs on the run's own client, so Cancel stops one in
flight.

### Accounts and credits — stage 3: earning

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-10-06-credits-stage3-earning.md`.
A signed-in user earns by **watching a rewarded ad** or **inviting a friend**, from the caption
shortfall and from the **Credits screen** (the pill and Settings' Credits row open it, on the root
navigator; balance, the ways to earn, the history paged by cursor).

**The app never grants credits.** `CreditAdService.watch` asks for a session (a new nonce per ad),
plays the ad through `RewardedAdPlayer` with `ServerSideVerificationOptions(userId: ssvUserId,
customData: nonce)` set **before** `show`, then polls the session once a second: up to 30s after a
watched ad, 5s after one closed early (AdMob may still call the server; past that "Watch to the end
to earn credits" — a 30s wait ending "on its way" for an ad the user skipped reads as broken). The
balance shown is the server's (`granted.balance` → `applyBalance`), and `/me` is read again after
every ad for today's count. `409 AD_DAILY_CAP_REACHED` plays nothing and the button reads "Back
tomorrow". **A poll that fails is ridden out** — dropped, a proxy page, a server hiccup — since the
user has already sat through the ad; only `NOT_FOUND` or `SIGN_IN_REQUIRED` ends it. **A reward
that lands after the poll gave up still arrives**: an "on its way" result looks at `/me` again at
30s and 90s (`EarnCreditsBlock.lateLooks`), and the block reports **every balance rise** through
`onEarned` — so a late grant carries a caption shortfall on exactly as a prompt one does (found by
the stage review: the sheet sat on "You have 0" while the credits had landed). `PluginRewardedAdPlayer` is the only plugin code, untested
by design (it needs a device).

**An ad is loaded before it is asked for** (device-reported: ads came only on a strong network,
otherwise "No ad right now"). Loading on the tap made the user wait out the consent check, the SDK
start and the load together inside a 15s limit. Now `EarnCreditsBlock` calls `prepare()` when it
shows (not at the cap, not with credit ads off), the player keeps **one** ad loaded (showable for
an hour; kept 50 minutes) and loads the next after every play, and a load that outlasts a tap's 15s
wait is kept for the next tap rather than thrown away. The button reads **Loading ad…** while the
tap waits for an ad (`watch(onPlayed:)` says when that wait is over). **A failure says why in debug
builds** — `AdPlay.failure` → `AdReward.failure`, appended by `adRewardMessage(withReason:
kDebugMode)`: AdMob's code and message, a consent check that failed or timed out, a show that
failed — and is logged under `SlimshotAds`; release builds keep the one line.

**Today's allowance can be unknown, and unknown is not "none left"** (`AdAllowance.known`; also
device-reported). A profile cached by a build before rewarded ads has no `ads`, and read as 0 left
it showed **Back tomorrow** to someone with every ad still to watch, until `/me` landed. Unknown
offers a plain **Watch an ad** with no count, and is not written back into the cache as a number.
Opening the Credits screen reads `/me` again, so a reward that landed while it was closed shows.

**Credit ads have their own switch** (`AdService.creditAdsEnabled`, on); `AdService.enabled` —
interstitials and the Pro-unlock ads — stays off. **Credit ads start the SDK themselves, when an
earning block first shows, after Google's consent step** (UMP: `requestConsentInfoUpdate`, then
`loadAndShowConsentFormIfRequired`, then `canRequestAds`) — the EEA, the UK and Switzerland need
consent for ads to serve, and a user who never earns credits never starts the SDK. **The last
answer is used first**, Google's own pattern: where an earlier check already allowed ads the SDK
starts at once and the check refreshes alongside; only with no answer yet is it waited for (10s at
most). The form shows only where the AdMob console's privacy message requires one; refused, it is
asked again next time.

**Credits come from their own unit: "earn credits", `…/2451324896`** (`AdService.creditAdUnitId`),
the unit with server-side verification set. Stage 3 first shipped on the older rewarded unit
(`…/3806842044`, `rewardedAdUnitId`, Pro unlocks) — which has **no** callback, so an ad watched to
the end reached nothing on the server and paid nothing (device-found: no `admob/ssv` line in the
VPS log). `ad_service_test.dart` pins the unit. **AdMob setup is outside the code**: the callback
`https://<server>/api/app/v1/rewards/admob/ssv` on that unit, the unit in the server's
`ADMOB_AD_UNIT_IDS` (or that list empty), and the test phone added as a test device — Google's
sample units never call the server, and clicking your own live ads breaks AdMob policy.

**`EarnCreditsBlock` is the one earning UI** (caption sheet and Credits screen). In the editor the
sheet takes it through `CaptionProgressSheet.earnCredits`, so the panel stays free of account
code; a balance that now covers the price carries the run on by itself (the shortfall's decision
completes `true` and the pipeline uploads), too little updates the line. **Invite a friend**
shares `inviteMessage(referralCode)` — the code and the Play Store link — through `Share.share` —
and the code is **shown** under it ("Your code · AB3DEF7K", tap to copy): a friend types it on
their claim step.

### Home and Settings — near-black, a little light, smoked glass; the editor stays dark

**Awaiting device verification** for the latest pass. Home and Settings sit on
**`ColourFieldBackdrop`** (`core/widgets/`): near-black lit by three soft glows
(`ColourFieldBackdrop.homeGlows`) — deep purple high on the right, fainter deep purple low on the
left, a whisper of white — drawn as radial gradients rather than through `ImageFiltered` so a
scroll pays no full-screen blur. Their surfaces are **`FrostedGlass`**: a backdrop blur under a
**neutral** white sheen fading from the top left, with an edge lit there. `blurSigma: 0` drops the
blur where content covers it anyway (draft thumbnails). `SettingsGroup` is the glass for a group
of Settings rows; `GlassCard` is gone.

**It was briefly a full colour field, and that was rejected on the device**: large purple, lilac
and white blobs over the whole screen, and glass whose fill mixed white into purple, read as "too
much purple" and less premium than the plain near-black it replaced. Tests now hold the line —
every glow at or under 30% and the white under 6% (`colour_field_backdrop_test.dart`), and the
glass fill neutral, no colour of its own (`frosted_glass_test.dart`). **Colour on these screens is
light, not paint.**

- **The New video card is the one block of colour** — deep purple (`primaryDeep` into
  `primaryEnd` and `primaryStart`), outranking the glass tools under it; a bright purple card
  added to the overload. **It is a button, not a banner** (`home_cards_test.dart`, **awaiting
  device verification**; the owner's call from mockups): it read as an advert — "Edit New Video",
  a slogan and a 3D picture, nothing that looked pressable — so people did not know it starts a
  project. Now **the owner's own design**: a white plus inside two soft rings with **"New Video"
  under it**, the sign every editor uses for "start something new", and three real photos fanned
  on a white stand on the right (`_PhotoFan`, `assets/home/new_video_{left,middle,right}.webp`,
  the middle one wearing a play mark) — a picture of making a video from your own clips. The
  photos decode at 360 px tall (`cacheHeight`), not their 1672. The whole card is the tap target.
- **The three tool cards under it are solid, not glass** (`_GridActionCard`, the owner's call;
  `home_cards_test.dart`): `AppColors.surface` with a `surfaceLight` hairline, the edge purple
  while pressed, the circle in each corner soft white (7%), not purple. Beside the New Video card's colour and photos the glass read as washed out. A
  design of the owner's own is to come.
- **Accents that sit on purple use `AppColors.lilac`, never the brand purple**, which vanishes
  there; "Video" is `lightAccentGradient` (white into lilac). Grey text on these screens is
  secondary, not tertiary. The coin is **`AppColors.credit`** (amber).
- **The credits pill is pinned to the right edge** (`HomeHeader`'s brand is `Expanded`): a
  `Flexible` brand let a short balance sit against it.
- **Account sheets sit on the same light**, everywhere (`AccountSheetFrame.glows`, the home
  composition moved closer in for a shorter shape; the top glow is wide because over a near-black
  screen that light is what shows where the sheet begins). **Light, not glass**: a glass version
  — a purple-and-white fill with a lit edge — was built and rejected on the device ("does not look
  good at all"). Inside the editor too: the glow is the sheet's own, below the picture, and an
  account sheet is not a choice judged against the footage.
- **A home card does what it says wherever it is touched** (`home_cards_test.dart`). Device-
  reported: Compress Video / Compress Photo / Privacy Strip sometimes opened a blank page with only
  the floating nav, until Back. The decorative circle in each card's corner was an
  `OpenContainer` — a widget that opens a page when tapped — whose page was an empty box, pushed
  inside the home tab; a tap on that corner went to it instead of the card. It is a plain circle
  now. **Decoration must not take gestures**: nothing decorative goes in a tappable widget.
- **The editor and its sheets stay plain dark — decided, not pending.** Colour is judged there
  (filters, Adjust, chroma key, the background), and colour around the picture shifts how the
  footage reads, so the export looks different from what was approved; a glass sheet would also
  blur the very frame being judged, over a live texture, on low-end GPUs. Purple stays an accent
  in the editor. No light mode: dark is the editing standard.

### The tab bar — one pill, gliding

**Awaiting device verification** (the owner's ask, 2026-10-28: smoother, more premium).
`FloatingNavBar` (`core/widgets/floating_nav_bar.dart`, tested in
`floating_nav_bar_test.dart`) is the shell's floating bar, moved out of
`main_shell_screen.dart` so it could be tested at all. The look is the one it had — glass, the
chosen tab a tinted pill with its name — and the motion is new. Before, the old tab's tint faded
out over 200ms while the new one's faded in, its border popped, the name was inserted in one
frame and every icon jumped sideways (66px in a frame, measured), and a 320dp phone overflowed.

- **One pill travels**, on springs (`withDurationAndBounce`). Its **leading edge is quicker than
  its trailing edge**, and the trailing edge holds 40ms from rest before it follows: the pill
  peels away from the tab it leaves, stretches toward the one chosen, and settles. A hold is
  taken only from rest, never mid-glide, and a second tap mid-glide turns the pill from where it
  is at the speed it has. Tuned against a model of the bar for every pair of tabs: a move to a
  narrower or farther tab stretches 1.15–1.6×, one to a wider neighbour hardly at all (the pill
  is growing into it anyway); all of it settles within about 0.6s, the visible part by ~0.35s.
- **The edges are springs in tab units, not pixels**: a whole number is exactly that tab's box
  in the current layout, so at rest the pill is glued to its tab even while the tab is still
  widening, and the targets never depend on a layout the ticker cannot see.
- **Names unfold and fold**: a tab widens as its name is revealed (60ms after the pill sets off,
  so the room opens as it comes), the other icons slide to make room, and a leaving name folds
  quicker than one arrives. **A name is drawn only inside the pill and inside its own tab, and
  only once the pill covers its icon** (`_iconCovered`) — rendered frames showed "Home" fading in
  ahead of the pill, text arriving before its tab; a test now walks every frame for it.
- **Colours are the app's**: the chosen icon and name `lilac` (accent on purple), the others
  `textSecondary`, the pill `primaryStart` lit from above. It was a hard-coded violet found
  nowhere else and Slate grey. The name's style is whole in itself (`inherit: false`): merged
  into an ambient style it picked up Flutter's yellow no-`Material` underline.
- **Never wider than the bar**: the tabs' padding narrows to 10, then the names scale down
  (labels also stop growing at 1.3× text). **A tap between two tabs chooses the nearer**; the
  gaps used to be dead. Each tab is a button with its name and selected state for screen
  readers. A press squeezes the tab to 90%, back with a little give; with animations off
  everything moves at once.
- **The bar's size is unchanged** (68px), so the screens' bottom padding for it still holds.

### The app icon — drawn from the logo, an adaptive icon on Android

**Awaiting device verification** (2026-10-27; device-reported as blurry). The old 1024 picture was
sharp, but it was the **only** icon: Android 8+ has no use for a single picture, so launchers
squeezed the whole square, its own rounded corners included, into their shape and the logo
arrived small and soft. Now `mipmap-anydpi-v26/ic_launcher.xml` is an **adaptive icon** — a
background layer (the dark grey fall, `#3D3D3E` to `#101011`) and the logo on a layer of its own,
which every launcher masks to its own shape at the phone's own density. Android 7 and older keep a
whole picture with its own corners; iOS gets a full square (it rounds the corners itself and
fills a transparent one with black).

- **Every source is drawn from `assets/logo.png`** (the owner's call — that drawing, bolder with
  slanted bars, not the SVG's nor the old icon's), at most 481px tall from its 487, so it is only
  ever made smaller, never stretched:
  `UPDATE_APP_ICON=1 flutter test test/app_icon_test.dart` redraws the four 1024 sources in
  `assets/icon/` (out of the APK — only top-level `assets/` files are bundled; the old
  `assets/app_icon.png` was being shipped for nothing), then `dart run flutter_launcher_icons`
  makes every size. Without the variable the test checks what is committed: the logo inside the
  66/108 circle every launcher shape keeps, the background with no holes, the iOS icon opaque to
  its corners, and the adaptive resources actually generated.
- **The logo is 47% of the icon's height**, as in the old artwork, and on the adaptive layer the
  same share of the middle 72/108 a launcher shows — so it is the same size on the phone.
- **Three drawings of the logo exist**: `logo.png` (the icon's and the splash screen's),
  `logo.svg` (the app's own header — a solid play triangle, rounded bars) and the old icon's
  thinner artwork. The icon and splash now agree; the header does not.

### The splash — the system's, then the app's

**Awaiting device verification**; the owner's picks (2026-10-27): B of three, then — the purple
glow it had turned down on the device — C of four replacements. **The native splash was
always native** (`flutter_native_splash` writes Android's launch theme); what changes on Android
12+ is that the *system* draws it and allows only a centred icon on a flat colour (and a small
mark at the foot) — no full-screen art, native or not. It looked broken because no Android 12
icon was set, so the system fell back to the launcher icon in a circle, on navy (`#020617`) —
not the app's `#09090B`, so the colour jumped when the app appeared.

- **Native: `logo.png`'s body dim (`kLaunchLogoRestingOpacity`, 35%), without its bars, on
  `#09090B`, on every version** — the bars arrive in the app's frames, and drawn natively they
  would be there already and then arrive a second time. Android 12+ gets a 1152 canvas (288dp at
  4x) with the body 1:1 in its middle, inside
  the 768 circle the system keeps, and **no `icon_background_color`** — a colour there draws a
  circle behind the logo. The generator treats its pictures as 4x, so the logo lands at
  `kLaunchLogoSize` (99.75×121.75dp) everywhere.
- **The app's first frame repeats it exactly, then finishes the logo** (`LaunchSplash`,
  `core/widgets/launch_splash.dart`, in `MaterialApp.router`'s `builder`): over 940ms the body
  lights and the three bars — the logo's speed lines — streak in from the left top first, 100ms
  apart, drawn out and landing exactly in place (`launchBarPose`: a bar's layer moved and
  stretched from the bars' right end, `_kBarsRightEdge`); the logo lifts and the name rises
  under it — Home's own wordmark — and the whole thing fades into the app, which has been
  building underneath since the first frame. `launchSplashFrameAt` is the timeline as a pure
  function. **Nothing glows behind the logo**: a purple glow shipped first and was turned down
  on the device; a test pins that the first frame draws the body alone and the finished logo
  four images and no circle. **The pictures are decoded in `main()` before the first frame** (beside the
  preferences; `preserve` holds the native splash meanwhile): an `Image.asset` would still be
  decoding when the first frame went out and the logo would blink off at the hand-over. Null
  art (tests, or a picture that will not load) means no splash, never no app.
- **Centred on the display, not the view** (`launchLogoCentre`): the native splash centres on
  the whole screen, and on many Android phones the app's view stops above the navigation bar,
  so centring on the view would drop the logo half a bar at the hand-over. A view short of the
  display by more than 12% (split screen, a window) uses its own centre. **This is the first
  suspect if the logo jumps at the hand-over on a device**; the size (4x) is the second.
- **The bars light separately** because `logo.png` is cut into four layers
  (`assets/splash/`: the white body and each purple bar, found by flood fill — they are
  slanted and their rows overlap). `test/launch_splash_art_test.dart` with
  `UPDATE_SPLASH_ART=1` redraws those and the two native pictures (`assets/native_splash/`,
  out of the APK), then `dart run flutter_native_splash:create`. Without the variable it checks
  the layers lay back together into `logo.png` with no pixel in two, the native picture is the
  body alone at the resting opacity, the Android 12 one sits in the circle, and the generated
  resources use them.
- **Animations off in the phone's settings: a 200ms fade only**, the controller on
  `AnimationBehavior.preserve` — a normal controller runs at 5% of its duration with animations
  off, and the splash already answers that setting itself. **Taps are held** while it covers an
  app nobody can see yet; its pictures are disposed when it ends.
- **The mockup's small "SlimShot AI" at the foot of the native splash was left out**: the name
  rises under the logo a moment later, and on Android 12 the system places a foot mark itself,
  so it could not be matched at the hand-over.
- **Home's header still draws `logo.svg`**, the other drawing of the logo.

### Onboarding — four things the app does best, the timeline first

**Awaiting device verification**; designed from mockups the owner picked (2026-10-24, the
transitions page 2026-10-28). `OnboardingScreen` is four pages on Home's light
(`ColourFieldBackdrop`), each a picture, a headline whose last words are lit in lilac, and one
line: **Edit like a pro**, **Transitions that wow**, **Clear on WhatsApp Status**, **Captions in
one tap** — transitions second, WhatsApp third (the owner's order, 2026-10-28). A step per page and Skip at the top (Skip gone on the last page, its width kept so the
steps do not jump), one full-width button at the foot — white Continue, then purple Get started.
Both Skip and Get started set `hasSeenOnboarding` and go Home.

- **The first page is the editor's own timeline, drawn** (`_TimelineVisual`, the owner's pick of
  three): a preview with a caption on it, a ruler, three clips as filmstrips with transitions on
  their seams, and a bar of each kind in the editor's colours — text (`border` grey), effect
  (`effectTrack`), photo (`photoTrack`), sound effect (`soundEffect`, its own glyph), music
  (`primaryEnd`, a waveform) — with the playhead stopping at the music bar. It says "a real
  editor" before a word is read. Drawn in code on a 360-wide layout (`_OnboardPage.visualSize`)
  and scaled to the room it has — down on a short phone rather than overflowing, **up to 1.6× on
  a tablet** (`_maxVisualScale`) rather than sitting phone-sized in an empty screen, in a column
  of at most 560.
- **Page 2 plays the app's own moves** (`_TransitionsVisual` over `onboarding_showreel.dart`;
  the owner's pick, A of three, with **Zoom Blur first, then the glitch**): one 9:16 clip in the
  white frame, looping the New Video card's three photos — dancer, gamer, neon girl — through
  **Zoom Blur, Glitch and Cube**, each resting 0.9 s first; the moves play *inside* the frame, as
  a transition plays inside a video. Under it the chips **Zoom Blur, Glitch, Cube, Swirl, +37**,
  the one playing or next lit white on purple. **Drawn in Flutter, after the app's own**: the
  engine's renderer belongs to the editor and is not running at onboarding, so the showreel
  follows the shaders rather than calling them — CrossZoom's sweeping centre, sine strength (0.4)
  and exponential swap, its samples as twelve weighted copies; the Glitch effect's torn bands
  (wrapping, some from the other photo), split channels and a band of swapped red and blue,
  stepped fifteen times a second while the photo flickers between the two; the Cube in true
  perspective with the app's 0.3 back-off and floor reflection. **The cube also backs off as far
  as it must to stay in the frame** (`_cubeFit`): a face turning about the cube's middle swings
  its far edge outward before depth draws it in, and a test caught it 2.7 px past the frame's
  border. **The line counts the catalogs** (`EditorTransition.values.length` transitions,
  `kVideoEffects.length` effects; "41 transitions and 47 effects.") so it cannot fall behind
  them; "smooth on any phone" was struck at the owner's call. It repaints only when its frame
  changes — a rest or a glitch tick holds — decodes the photos at 960 tall
  (`showreelPhoto`, precached once the first page is up), and with animations off holds on the first photo,
  Zoom Blur lit. `onboarding_showreel_test.dart` pins the loop's order and timing, the glitch's
  plan, the cube's geometry (faces meeting on their nearest edge, the new one from the right,
  inside the frame throughout) and what the painter draws.
- **Page 3** uses the New Video card's photo in its white frame: the same picture blurred and
  sharp, tagged.
- **Page 4 is the finale, the finished video** (`_FinalePage`, the owner's pick, A of four; it
  was a framed stock photo with a caption that never moved): the left photo of the New Video card
  edge to edge from the top of the screen, under the status bar and the step bar (a shade at the
  top keeps the bar readable), fading into the black where the words begin. **The photo is the
  room the words leave**, so on any screen the two meet and never overlap. Its caption plays
  word by word in the app's own Bubble look (`kDefaultCaptionLook`: Montserrat Bold, white, the
  soft shadow), the spoken word on a pill of the highlight row's **pink**
  (`kCaptionHighlightPink`, the owner's call over Bubble's purple): **"EDIT YOUR VIDEOS WITH
  PASSION"** (`kOnboardingCaptionWords`, the owner's line, after a Pidgin one read as
  machine-written). It sits low on the picture, where captions go and where the photo has
  faded dark enough for white words; it wraps rather than shrinks, is sized from the screen
  (22 on a phone, up to 38) and, like the app's captions, does not grow with the phone's text
  size. With animations off it holds still on its first word.
- **The pages run the whole screen**, with the step bar and the button laid over them
  (`_Column` keeps each page clear of both): the finale's photo could not otherwise reach the
  top edge. Only the bar and the button take touches, so a swipe between them still turns the
  page — a test pins it.
- **What it replaced**: screenshots of the old editor and generic lines ("Endless possibilities",
  "No cloud needed" — untrue since captions use the server). Their three PNGs are deleted.
- `onboarding_screen_test.dart` pins the bars, the playhead's foot, the walk through the pages,
  the transitions page's chips lighting in turn and its counted line,
  both ways out, every page on a small phone at 1.3× text and a tablet both ways up, the
  picture growing on a tablet while a phone's stays as laid out, the finale's photo edge to edge
  on a phone and a tablet, its caption's words lit in order on a pink pill, on the photo and
  clear of the headline at 1.3× text, unscaled by the text size, and the swipe.

### Compress video — Home's light, rows, the sizes left to the result

**Awaiting device verification.** Designed from a rendered mockup the user approved
(2026-10-07). The screen is `CompressVideoView` (`features/compression/widgets/`), a picture of
`CompressionState` with callbacks; `CompressVideoScreen` owns only the player and the provider,
which is what lets the layout be tested without a video. The parts are `compress_panels.dart` —
top bar, section label, glass group, choice row, switch row, segmented control, size card, info
chip, bottom bar and buttons — **so the photo screen can be rebuilt from the same pieces** rather
than a second look. The new primary button is not `GradientButton`, which then set its label
through Google Fonts.

- **On Home's light and glass** (`ColourFieldBackdrop`, `FrostedGlass`) — outside the editor,
  where no colour is being judged. The old screen hard-coded Slate (`0xFF334155`, `0xFF0F172A`).
- **Qualities are rows, not three squeezed tiles**: icon, name, one line, a tick; Smart wears
  **Recommended**. The video presets were renamed to fit (`Best quality` / `Smart` /
  `Smallest`, one short description each).
  **PRO shows only while ads are on** (`showPro: AdService.enabled`): with ads off nothing is
  locked, so the badge promised a lock that was not there.
- **No before-and-after here — the user's call on the device.** A Now → After card with an
  estimated range was built and removed: the sizes belong to the result screen, where "after" is
  the real file rather than a guess from a preset's "50-80%". The result screen's
  `CompressBeforeAfterCard` is where they went.
- **The title is centred on the screen**, not in the space beside the back button
  (`CompressTopBar` stacks them); a test pins the centre on a phone and a tablet.
- **The preview hugs the video's shape** (capped at 42% of the height for a tall one) and carries
  `videoInfoLabel` ("1080p · 0:42") and the size — the metadata was read and never shown.
  Compressing grows it and puts a progress ring on it (per-file %, "2 of 5" for a batch).
- **Several videos** get a thumbnail row (`VideoThumbnailService`, the filmstrip's extractor); a
  tap plays that one in the preview.
- **From 700 px wide, two columns** (`kCompressTwoColumnWidth`): video left, settings right.
  Tests pin no overflow at 320 px wide with text at 1.3×.

**The result screen is the same family** (`CompressResultView`, `compress_result_view.dart`;
**awaiting device verification**; designed from an approved mockup). "Done" centred with ✕
(home) beside it, in place of the bouncing tick and "Ready to Share!" — **no tick beside it** (the
owner's call; `compress_result_view_test.dart` pins it). The screen keeps the
player, saving, leaving (below) and the full-screen views; the view is tested without them.

- **Before → After lives here, with real sizes** (`CompressBeforeAfterCard`): the after's share of
  the before as a bar, the saving as a green "75% smaller" tag beside it — the tag shares the
  bar's row because beside the sizes it overflowed a small phone with large text. **No saving is
  claimed where the file did not get smaller**: the bar stays grey and the tag is gone, and where
  every video was handed back as it was (`skippedCompressions`) it says so — the old strip read
  "0%" as if something had failed.
- **Several files show totals for all of them** ("All 5 photos"). The old strip mixed the
  selected photo's sizes with the whole batch's percentage, so the three numbers did not agree.
- **Nothing but the result** (the owner's call, **awaiting device verification**): it read as
  another step to take — a details list, a full-width Save over Share and "New video". It is the
  export screen's shape now: the picture larger, the sizes card, and **Save and Share side by
  side**, Share the purple one since posting is usually why the file was compressed. The details
  card and "New video" are gone. **✕ and the phone's Back both go home** (`PopScope` in the view):
  Back used to step back to the compress screen.
- **Video**: play, a scrubbable time bar and full screen on the picture (`ResultVideoFrame`).
  **Photos**: the compare slider labelled Before / After (`ResultPhotoFrame`). Several of either
  get the thumbnail row; a tap previews that file (a video re-opens the player on it).
- **Save** (or "Save 5") and **Share**, pinned. Two columns from 700 px.

**Compress photo is the video screen's design** (`CompressPhotoView`; **awaiting device
verification**; from an approved mockup). All three screens — video, photo, result — sit on one
`CompressScaffold` (the light, the top bar, the picture, a thumbnail row, content scrolling under
a pinned action, two columns from 700 px), so they cannot drift. What photos have of their own:
the photo drawn over a blurred fill of itself, so a portrait photo in a wide frame has no dead
bars; "HEIC · 12 MP" (`photoInfoLabel`); **JPG | PNG | WebP**; no WhatsApp option (the photo
compressor has none). **The photo's shape comes from the decoded image, never the file header**
— a phone stores most portrait photos sideways with a rotation flag the decoder applies and the
header does not, so the header would draw them squashed; the megapixels do come from the header
(`ImageDescriptor`), since width × height is the same either way round. **An option's control
drops onto its own line when it does not fit beside its label** (`CompressOptionRow` is an
`OverflowBar`), and the segmented control scales down only as the last resort after that: three
format segments overflowed a 320 px phone at 1.3× text, and a test pins it. The image presets
were renamed to match the video ones (`Best quality` / `Smart` / `Smallest`), and
`expectedCompression` — read only by the old tiles' "-50%" — is gone.

**WhatsApp Status — a file already in the shape Status keeps** (`logic/status_plan.dart`,
**awaiting device verification**; spec `docs/superpowers/specs/2026-10-23-whatsapp-status-compression-design.md`).
The owner's main reason to compress is posting to Status without WhatsApp blurring it. Their
evidence: an edit exported at 1080×1920 blurred on Status, the same edit downloaded back from
Instagram at 720×1280 — smaller, a third of the bitrate — stayed clear. WhatsApp keeps something
like 720×1280 and shrinks anything larger itself, fast and cheap. So the switch (renamed from
"WhatsApp ready", which scaled by width only and so left every portrait 1080×1920 as it was)
makes that shape: inside 720×1280 / 1280×720, never enlarged, even sides; a constant rate (60 →
30, 50 → 25, capped at 30); H.264 High 3.1, x264 `veryfast`, CRF 21 under **Instagram's own
ceiling** (`kStatusMaxVideoKbps` 1500, held per second — `bufsize` equals it — and a keyframe every
5 s, as the file that stayed sharp has); HDR (PQ/HLG) tone-mapped; **no denoise** — measured
with FFmpeg on the owner's videos it was 35% of all the work, the biggest step, and lowered SSIM
(0.9945 against 0.9950 without); AAC 128 kbps 44.1 kHz. **FFmpeg sizes the output from the upright frames itself**, never
from the probe: device-reported, a portrait video came out squashed into landscape — stored on
its side with a rotation label the probe missed, it read as 1920×1080 and was sent
`scale=1280:720`, which FFmpeg applied to the already-upright picture. The first device run also
found it soft once (a 2 Mbps cap with a 4 Mb buffer let bursts near 4 Mbps) and slow (`medium`,
and the denoise on full-size frames before the shrink). A file
already in that shape is **copied, not encoded** (`statusPlan(...).copyOnly`); the result is kept
even when larger than the input, because a small 1080p original is exactly what blurs. On screen
it sits **first, in a box of its own above Quality** (the owner's call: it is why most people
compress, and it overrides what is below it), and it overrides quality and format (dimmed, out of reach, "Overrides quality and format"). No tip about WhatsApp's HD option — the owner's call.
No splitting of long videos — also the owner's. **The editor's export gets the same rule once this
is confirmed on a device** (a "WhatsApp Status" switch under Resolution and Frame rate, already
chosen). The probe reads ffprobe's JSON through `VideoMetadata.fromProbe`, pure and tested.

**A cancelled compression cannot touch a restarted one** (`compression_cancel_test.dart`). Every
run asked "is *a* compression running?" rather than "is *mine*?": after Cancel and a restart, the
cancelled run's FFmpeg call ended late as a failure, saw the new run's "running", marked it failed
and stopped, and threw its result away, while its progress landed on the new run's ring. Each run
now takes a number (`_run`), Cancel and `reset` retire the current one before anything is awaited,
and a run writes state only while its number is current; a file a retired run produced is deleted.

**Target sizes and quick presets are gone** (removed 2026-10-07 at the user's call: "remove the
ones that are not wired"). `CompressionMode.targetSize`, the target-size lists, `OutputPreset`
with its WhatsApp / Status / Email / Form upload / Profile entries, `applyOutputPreset`,
`setTargetImageSize`/`setTargetVideoSize`, and both compressors' target-size paths (the image
quality-and-dimension search, the video bitrate-from-size command) had no caller anywhere in the
app — about 530 lines. Compression is a quality preset plus the options on screen. If a "fit
under N MB" feature is wanted, it is a new design, not a revival of this.

**Shared files reach the compress screens through the route** (`compressInputsFromExtra`). The
share sheet used to put them in the provider and open the screen without them — and each
compress screen resets the provider as it opens, so sharing a video or photo into SlimShot
opened a screen that found nothing and closed itself. Opened from the share sheet there is
nothing beneath it, so back goes home rather than popping.

### Privacy Strip — what the photo really carries, removed without re-saving it

**Awaiting device verification** (the reader is Kotlin; the screens from an approved mockup).
`PrivacyStripView` and `PrivacyReportView` (`features/privacy/widgets/`) sit on the compress
screens' `CompressScaffold`, tested without a device; the screens own the provider, the picker
and the photo's shape (`PhotoInspector`, shared with Compress photo).

- **The screen shows what each photo really holds**, read through `PhotoMetadataReader.kt`
  (`slimshot_ai/photo_metadata`, Android's `ExifInterface`): location as coordinates, camera,
  date taken, author — one photo's values, or "In 3 of 5" across several; only what is there,
  and "No location, camera or date in this photo." where nothing is. The old screen listed four
  fixed chips for every photo, which was a claim, not a fact. An empty GPS block reads 0,0 and
  is not a location (`PhotoMetadata.fromMap`). HEIC reads from Android 9; a file the reader
  cannot open is "nothing found", never an error, because the strip still runs on it.
- **The report reads each cleaned file back** (`PrivacyState.remaining`) and ticks a detail only
  where it is confirmed gone; one that survived says **Still there**, and a file that could not be
  read back is left unticked rather than assumed clean. "Details removed" shows only when every
  file is verified clean.
- **A JPEG is cleaned without re-encoding** (`stripJpegMetadata`, `logic/jpeg_metadata.dart`,
  the user's call): its EXIF, XMP, IPTC, comments, JFXX thumbnail, MPF and any trailer after the
  image's end are dropped and every other byte copied, so the picture is identical. The old path
  re-saved it at quality 100 — called "lossless" in a comment, it was not: a little quality lost
  and usually a bigger file. **EXIF also holds the rotation flag**, without which a portrait photo
  shows on its side, so it is written back alone in a minimal EXIF block. Kept: JFIF, the colour
  profile (`ICC_PROFILE`), Adobe's colour flag, every table and frame segment. **Not done through
  `ExifInterface`**: it leaves the embedded thumbnail (which can show the photo before a crop) and
  IPTC. A JPEG too unusual to walk falls back to re-encoding; PNG re-encodes losslessly; HEIC and
  WebP become a quality-100 JPEG as before (`DefaultPhotoStripper`), since nothing can rewrite
  them in place. A test plants "secret" in every hiding place and asserts none survives and the
  image bytes are untouched.
- `CompressionLoaderOverlay` is gone — the three screens that used it share the progress ring.

### Temporary files — gone once off screen, and History with them

**Awaiting device verification** (the owner's call, 2026-10-28: the app should not fill the phone
with files nobody can reach). A compression, a stripped photo and an export are the app's own
temporary files (`slimshot_temp_`, `slimshot_export_`), of no use once off screen: a saved one is
in the gallery and a shared one is a copy (share_plus copies into `cache/share_plus/` before
handing it over, so the original may go at once).

- **Leaving a result deletes its files** (`ResultExit`, `core/utils/result_exit.dart`) — the
  compress result, the Privacy Strip report and the export screen alike, by ✕ or Back (each
  routes Back through the same leave with a `PopScope`). **One nobody saved or shared is asked
  about first**: "Discard this video?",
  "Discard these 5 photos?" (`confirmDiscard`, `core/widgets/discard_dialog.dart`, the drafts'
  Delete Draft? look) — Cancel or a tap outside stays. Saving marks it kept, and so does a share
  sheet closed on a target: `MediaSaveService.shareFiles` answers whether it was **not** dismissed,
  so a phone that cannot say how the share went counts as kept and nobody is asked twice. Back
  on the Privacy report still steps back to the strip screen, asking first.
- **A result never deletes the files it was made from.** A result handed back as it was
  (`skippedCompressions`) *is* its picked file, so `ResultExit` leaves out the inputs; the screen
  they were picked for deletes those **when it closes** — Compress photo, Compress video and
  Privacy Strip, whose Change photos also deletes the picks it replaces.
- **`FileUtils.deleteTempFiles` deletes only inside the temporary folder**, by resolved path, and
  the picker's folder once empty: image_picker copies each pick to `cache/<uuid>/`,
  receive_sharing_intent a shared file to the cache root, and a file outside the cache is the
  user's own. **Never sweep the picker's copies by name**: a draft's clips play from them.
- **The launch clears what a previous session left** (`cleanupStartup`): every app-prefixed file
  and every share_plus copy written before this launch — exports included, which nothing ever
  deleted before — so a compression begun the moment the app opened keeps its file. Settings >
  Clear Cache takes the same set at any time.
- **History is gone** — the screen, its service and model, the `/history` route and the
  Workspace header's button (its 44px stays, so the drafts did not move). Its entries pointed at
  temporary files the launch cleanup had already deleted, so most could not be saved or shown.
  Its stored list is removed on launch (`forgetRemovedFeatures`).
- **Back during an export cancels it**, as ✕ always did. It used to pop the screen and leave the
  export running, with the editor's renderer held by it until it finished.
- **Known:** a pick or a shared file whose screen never closed — the app killed on it — stays in
  the cache until the system clears it; nothing can tell it from a draft's clip.

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
| Dismissing a panel | **Back, an empty stretch of the timeline, and a tap in the space beside the picture close an open panel, keeping its edits** — modal semantics, as a sheet's dismissal keeps its live edits; ✕ stays the explicit discard. Mask alone has no ✕/✓ bar (`kHeaderlessTools`): it has nothing to discard. **The space beside the picture also clears the selection, one level per tap** (`tapIsBesidePicture`, `outsideTapActionFor`; `preview_side_tap_test.dart`, user's call 2026-10-10): an open panel closes first and the selection stays — device-reported, closing both at once made the user select the clip again for its next tool — and with no panel open the next tap deselects everything. Every panel closes there, Mask, Crop and Zoom included, because they are used *on* the picture and the picture keeps its own tap (play/pause). It replaced a rule that made those three ignore the whole canvas tap, which left a side tap closing Volume but not Mask and deselecting a text but not a clip. A tap within `kPictureTapMarginPx` (24) of the picture's edge does nothing: handles hang half past the edge, and Flutter cannot hit them out there. Only with no tool open does Back leave the editor. `logic/tool_dismissal.dart`. |

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
  **The exception is a tool that is not unfinished but misplaced.** The root
  menu once carried an `effects` entry whose handler was gated on the clip
  menu, so it fell through to "Effects controls coming soon" for a feature
  built and shipping one tap away on the clip's own menu — a wrong signpost,
  removed. It is back since the effects track, now with a handler: Effects
  adds a bar, and the clip menu's entry is the one that went
  (`editor_menu_test.dart` pins both). The root menu's **`animate`** entry went
  the same way and was worse: the string appeared *once* in the whole
  codebase — the entry itself — so nothing handled it at all, while the real
  tool ships as `animation` on the image- and video-overlay menus and as the
  text editor's Animation tab. An animation also needs a target, and the root
  menu is the no-selection menu. The **audio** menu's Effects is now
  built — the sound effects library, under its own id `sound_effects` — and
  `templates` keeps its deliberate "coming soon" panel, the rule applied as
  written. **Clips still have no in/out animation tool**;
  if one is built its home is the clip menu, with a handler.
