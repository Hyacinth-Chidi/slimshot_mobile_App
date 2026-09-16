# Editor tools batch — twelve tools that need no server

**Status:** in progress. Approved 2026-09-17 ("we will implement all, so proceed").
Everything here runs on the phone; the audio catalog, captions, fonts, stock
backgrounds, templates and sticker libraries wait for `../slimshot_server`.

Rules carried from every previous plan: read `CLAUDE.md` and `docs/dead-ends.md`
before touching architecture; test first; `flutter analyze --no-pub` stays at 48;
`flutter test`; `.\android\gradlew.bat -p android :app:testDebugUnitTest`; a debug
APK when Kotlin changed; GLSL is proven only on device; one commit per tool.

## Order and batches

Grouped so each batch shares one device-verification pass.

### Batch A — the shader sampling path

- [x] **A1 Flip** (device check pending) (mirror horizontal / vertical). `VideoSegment.flipHorizontal/flipVertical`
  → clip JSON (written only when true) → `NativeTimelineClip` → per-lane `uFlip*` (vec2 of
  0/1) applied to `fitted` in `incomingAt`/`outgoingAt` before the content rect. Suspended
  in the clip-crop "plain" view like scale and pan, so the handles map. Merge rule refuses
  differing flips; split copies them; transform reset clears them. Two toggles on the
  Transform sheet's Rotate tab.
- [x] **A2 Clip opacity** (device check pending). `VideoSegment.opacity` (AnimatableDouble, base 1.0), the seventh
  keyframable property (`ClipProperty.opacity`). Per-lane `uOpacity*`; in the sampling
  helpers, `mix(backgroundAt(), graded, opacity)` **after `gradeClip`** (fading what the user
  sees) and **before the effect chain** (a blurred clip at 50% is a blurred clip,
  half-present). Never alpha — see the CLAUDE.md design note. The existing Opacity tool
  joins the clip menu and writes through `setClipProperty`; the overlay path is unchanged.
- [ ] **A3 Adjust** (brightness, contrast, saturation, temperature). Pure matrix maths in
  `logic/color/color_adjustments.dart` composing into the **existing** 4×5 colour matrices —
  clip adjustments into the clip grade, project adjustments into the canvas look — so no
  shader change. An Adjust sheet of four `ValueRuler`s with the filters' apply-to-all
  toggle deciding which level a drag writes to. Unlike filters, both levels may coexist:
  an adjustment applied twice is the user's intent, a filter applied twice is not.

### Batch B — mostly Dart

- [ ] **B1 Freeze frame.** Split at the playhead and insert a photo clip of that frame
  (frame via `VideoThumbnailService.frameAtSize`, written like a cover, `kDefaultPhotoDurationSeconds`).
  Clip menu tool.
- [ ] **B2 Blurred-clip background.** `EditorBackgroundType.blur` becomes real: the effect
  pass chain renders the active lane blurred, cover-fitted, as the letterbox fill. A third
  kind of tile in `BackgroundSheet`. Falls back to black **with a warning** where the chain
  cannot run.
- [ ] **B3 Apply to all** for Transform, clip crop and Effects, using `ApplyToAllToggle` the
  way Filters and Transitions do.

### Batch C — timeline feel

- [ ] **C1 Snapping.** Trims, moves and the playhead snap to clip edges and whole seconds
  within a pixel tolerance, with a haptic tick; hold to override.
- [ ] **C2 Keyframe drag-to-move.** Long-press-drag a diamond along the filmstrip; every
  property's keyframe at that progress moves together.
- [ ] **C3 Live volume.** The volume slider is audible while dragging, through an override
  channel shaped like `setClipTransform`.

### Batch D — larger

- [ ] **D1 Mask** (rectangle, circle, linear) with feather, per clip, on the sampling
  helpers; handles on the canvas like crop.
- [ ] **D2 Chroma key** for video overlays, on the overlay pass.
- [ ] **D3 Speed curves.** Source time as the integral of a speed curve — its own model,
  Kotlin port and fixture, and its own sheet. See the CLAUDE.md note on why speed cannot
  be a keyframe.
- [ ] **D4 Replace clip.** Swap a clip's asset keeping trims (clamped), transform, crop,
  keyframes and effects.

### Housekeeping

- [ ] **H1 Draft cache.** Proxies and caches move out of `getTemporaryDirectory()` into the
  documents dir per draft, deleted with the draft; a draft whose files are gone says so and
  re-renders them rather than pointing at nothing.

## Conventions this batch adds to

- A new per-clip field goes through **all** of: `VideoSegment` (field, ctor, copyWith, toJson
  written only when non-default, fromJson defensive), the split right-half constructor,
  `_canMergeForPlayback`, the composer's plain view where it is a *placement*, and
  `EditorTimelineVideoClip` + `NativeTimelineClip.fromMap`. Rotation and crop are the
  templates; the tests that caught their omissions are the ones to copy.
- Anything the user drags on a keyframed clip goes through `setClipProperty`.
- Every sheet opens through `showEditorSheet`; picture-judged sheets respect
  `kEditorSheetPreviewFraction`.
