# REACT recorded live — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A REACT reaction is drawn and mixed while it is recorded, so stop means the file is finished — with today's make-it-after way kept, unchanged, for phones that cannot.

**Architecture:** A native live recorder in `camera/react/` (own EGL, CameraX Preview-only into its camera `SurfaceTexture`, ExoPlayer into its video `SurfaceTexture`) draws one composite per camera frame into a separate Flutter texture and, while recording, into an H.264 encoder; a mixer thread mixes the microphone with the video's own sound (decoded at the media time the player showed) under a live talk gate and encodes AAC; both go through an `Mp4Muxer` straight into a MediaStore pending entry. Dart keeps every decision: which way a phone records, the layout geometry (sent as rects), the controller's recording flow (the existing start/pause/resume/stop calls, routed natively).

**Tech Stack:** Flutter/Dart (Riverpod-free camera feature), Kotlin, CameraX 1.6.2, Media3 ExoPlayer + `media3-muxer`, OpenGL ES 2.0, `MediaCodec`, `AudioRecord`, MediaStore.

**Spec:** `docs/superpowers/specs/2026-11-06-react-live-recording-design.md`

## Global Constraints

- **The editor's engines are untouched.** No file under `nativepreview/`, `export/`, `thumbnails/` or `lib/features/video_editor/` changes. They may be *called* (`PcmAudioSource`, `ExportCapabilities`, `DeviceDecoderFacts`, `StillImageDecoder`); anything that would need a change there gets its own small copy in `camera/react/`.
- minSdk 24; OpenGL ES 2.0 only; every new Kotlin class `internal`, `@UnstableApi` where it touches Media3.
- The lowering numbers stay defined in Dart (`kReactionDuckVolume` 0.25, `kReactionMicGateVolume` 0.1, `kSpeechRampMs` 150) and travel in the start call.
- Copy, exactly: `kReactStepTo720Message = 'The next reaction will record at 720p.'`, `kReactStepToAfterMessage = 'This phone will make reactions after recording.'`, `kReactLiveFailedMessage = 'Live recording stopped on this phone. Reactions will be made after recording.'`
- House rules: island-pill toasts, `AppColors`, Lucide, minimal copy; CRLF files keep CRLF.

## Review Focus

1. **Talking from the take's very first instant** (the commonest reaction opening) — the voice must come through, never gated before the detector has data. Pinned in Task 2 (`LiveTalkGateTest`).
2. **Loud music in the video with nobody talking** — must not read as talking (no dip, mic held back). Pinned in Task 2.
3. **A phone whose camera drops to 15 fps in low light** — not a "choppy" take; the miss counter adapts to the camera's own rate. Pinned in Task 2 (`MissedFramesTest`).
4. **Pause the take while the video is held, then resume** — the video stays held, the file has no gap. Pinned in Task 2 (`FileClockTest`, `MediaTimeMapTest`) and Task 5 (controller).
5. **The app pulled away mid-take** — the file is finished with what it had and arrives as `RecordingEnded`. Pinned in Task 5 (controller) and on the device list.

---

## File Structure

**Dart — create**
- `lib/features/camera/logic/react_live.dart` — which way a phone records (`ReactCapture`, `ReactLiveFacts`, `chooseReactCapture`, `takeWasChoppy`, `stepAfterChoppy`), the scene sent to the recorder (`ReactionQuad`, `ReactionScene`, `reactionScene`), the take's sound settings (`ReactLiveTake`), the copy.
- `lib/features/camera/logic/react_capture_store.dart` — the remembered step per build.

**Dart — modify**
- `lib/features/camera/logic/camera_controller.dart` — backend calls, events, `RecordedVideo`/`VideoShot` frame counts, the live REACT flow.
- `lib/features/camera/services/method_channel_camera.dart` — the channel side of the above.
- `lib/features/camera/widgets/reaction_frame.dart` — a `composite` picture for live mode; `probeReactionSource`.
- `lib/features/camera/screens/camera_screen.dart` — the live REACT flow.
- `test/support/fake_camera.dart` — the fake side.

**Kotlin — create** (`android/app/src/main/kotlin/com/techfamz/slimshotai/camera/react/`)
- Pure, JVM-tested: `ReactScene.kt`, `FileClock.kt`, `MissedFrames.kt`, `MediaTimeMap.kt`, `LiveTalkGate.kt`.
- Device-only: `ReactEgl.kt`, `ReactCompositor.kt`, `ReactVideoEncoder.kt`, `ReactAacEncoder.kt`, `ReactMuxer.kt`, `ReactOutput.kt`, `ReactAudioMixer.kt`, `ReactLiveRecorder.kt`, `ReactCapabilityProbe.kt`.

**Kotlin — modify**: `camera/CameraChannel.kt`.

---

### Task 1: Dart — the way, the scene, the take settings

**Files:**
- Create: `lib/features/camera/logic/react_live.dart`, `lib/features/camera/logic/react_capture_store.dart`
- Test: `test/features/camera/react_live_test.dart`

**Interfaces:**
- Produces:
  - `enum ReactCapture { live1080, live720, afterwards }` with `int? get shortSide` (1080, 720, null).
  - `class ReactLiveFacts { const ReactLiveFacts({required double fps1080, required double fps720}); static const none; static ReactLiveFacts fromMap(Map<Object?, Object?>? map); }` — frames a second the AVC encoder achieves at 1080x1920 / 720x1280, 0 where it cannot take the size.
  - `const double kReactComfortableFps = 40; const double kReactMinimumFps = 30;`
  - `ReactCapture chooseReactCapture(ReactLiveFacts facts, {int step = 0})` — step 0 none, 1 at most 720, 2 afterwards.
  - `bool takeWasChoppy({required int frames, required int missedFrames})` — missed ≥ max(10, 5% of frames + missed).
  - `int stepAfterChoppy(ReactCapture used)` — live1080 → 1, otherwise 2.
  - `class ReactionQuad { const ReactionQuad({required Rect dst, required Rect src}); Map<String, Object?> toJson(); }` — `{'dst': [l, t, w, h], 'src': [l, t, w, h]}`, fractions, y-down.
  - `class ReactionScene { const ReactionScene({required ReactionQuad camera, ReactionQuad? video}); Map<String, Object?> toJson(); }`
  - `ReactionScene reactionScene({required ReactionLayout layout, required ReactionWindow window, required double cameraAspect, required double videoAspect, required bool hasVideo, bool removed = false})`
  - `class ReactLiveTake { const ReactLiveTake({required bool lowerVideo, double duckVolume = kReactionDuckVolume, double micGateVolume = kReactionMicGateVolume, int rampMs = kSpeechRampMs}); Map<String, Object?> toJson(); }` — keys `lowerVideo`, `duck`, `gate`, `rampMs`.
  - `class ReactCaptureStore { static const key = 'react_capture_step'; static Future<int> load(String? build); static Future<void> save(int step, String? build); }` — `{build, step}` JSON; another build reads 0; no build reads 0 and saves nothing.
  - The three message constants (Global Constraints).

- [ ] **Step 1: Write the failing tests** (`react_live_test.dart`):
  - `chooseReactCapture`: fps1080 60, fps720 120 → live1080; fps1080 35, fps720 60 → live720 (borderline 1080); fps1080 0, fps720 30 → live720; both 20 → afterwards; step 1 with fps1080 60 → live720; step 2 → afterwards.
  - `takeWasChoppy`: (frames 900, missed 9) false; (900, 40) false (under 5% of 940); (900, 50) true; (100, 12) true (≥ 10, the floor).
  - `stepAfterChoppy`: live1080 → 1, live720 → 2.
  - `reactionScene`, for every layout with `window = ReactionWindow.initial`, `cameraAspect: 9/16`, `videoAspect: 16/9`: `camera.dst == reactionPlaces(...).camera`, `camera.src == coverCrop(contentAspect: 9/16, regionAspect: reactionRegionAspect(places.camera))`; `video.dst == places.video`; split `video.src == coverCrop(16/9, regionAspect of places.video)`, float `video.src == Rect.fromLTWH(0, 0, 1, 1)`.
  - `hasVideo: false` → `scene.video == null`, camera as above. `removed: true` → camera dst `Rect.fromLTWH(0, 0, 1, 1)`, src `coverCrop(cameraAspect, 9/16)`, no video.
  - `ReactionScene.toJson()` for a known scene equals the literal map; `ReactLiveTake(lowerVideo: true).toJson()` equals `{'lowerVideo': true, 'duck': 0.25, 'gate': 0.1, 'rampMs': 150}`.
  - `ReactCaptureStore`: save 1 for build `b1` → load(`b1`) 1, load(`b2`) 0; load(null) 0.
- [ ] **Step 2: Run** `flutter test test/features/camera/react_live_test.dart` — Expected: FAIL (file missing).
- [ ] **Step 3: Implement** `react_live.dart` and `react_capture_store.dart` (SharedPreferences, every read/write in try/catch).
- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: Commit** `feat(camera): REACT live — the way a phone records, and the scene`.

### Task 2: Kotlin — the pure parts of the recorder

**Files:**
- Create: `camera/react/ReactScene.kt`, `FileClock.kt`, `MissedFrames.kt`, `MediaTimeMap.kt`, `LiveTalkGate.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/camera/react/{ReactSceneTest,FileClockTest,MissedFramesTest,MediaTimeMapTest,LiveTalkGateTest}.kt`

**Interfaces:**
- Produces:
  - `internal data class ReactRect(left, top, width, height: Float)`; `internal data class ReactQuad(dst: ReactRect, src: ReactRect)`; `internal data class ReactScene(camera: ReactQuad?, video: ReactQuad?)` with `companion fun fromMap(map: Map<*, *>?): ReactScene` (malformed → that quad null) and `val EMPTY`.
  - `internal object ReactGeometry { fun positions(dst: ReactRect): FloatArray; fun texCoords(src: ReactRect, quarterTurns: Int = 0, mirrored: Boolean = false, yUp: Boolean = true): FloatArray }` — 8 floats, vertex order TL, BL, TR, BR (a triangle strip). Positions: x = 2·left − 1, y = 1 − 2·top. Tex coords: the upright y-down point (u, v) is mirrored first (u → 1 − u), then un-turned into the buffer (one clockwise quarter turn: buffer x = v, y = 1 − u; repeat per turn), then `t = 1 − y` when `yUp`.
  - `internal class FileClock { fun start(nanos: Long); fun pause(nanos: Long); fun resume(nanos: Long); val isPaused: Boolean; fun fileNanos(nanos: Long): Long?; fun durationNanos(nanos: Long): Long; companion fun frameNanos(timestamp: Long, arrival: Long): Long }` — null before start or inside a pause; `frameNanos` keeps the timestamp when within 200 ms of the arrival, else the arrival.
  - `internal class MissedFrames { fun onFrame(timestampNanos: Long); val frames: Int; val missed: Int }` — a gap counts `floor(gap / interval + 0.5) − 1` missed when gap > 1.5 × interval, interval = median of the last 30 gaps (33.3 ms before any).
  - `internal class MediaTimeMap { fun sample(nanos: Long, positionMs: Long, playing: Boolean); fun mediaMsAt(nanos: Long): Long?; fun prune(beforeNanos: Long) }` — `@Synchronized`; between samples `i` and `i+1`, playing at `i` → position_i + elapsed, capped at position_{i+1}; not playing at `i` → null; after the last sample → extrapolated when playing, else null; before the first → null.
  - `internal class LiveTalkGate(lowerVideo: Boolean, duck: Double, gate: Double, rampMs: Int) { fun addBlock(fileMs: Long, micDb: Double, videoDb: Double); fun gainsAt(fileMs: Long): Gains; data class Gains(val video: Double, val mic: Double) }` with `BLOCK_MS 10, LOOKAHEAD_MS 250, LEAD_MS 80, TAIL_MS 200, BRIDGE_MS 400, MIN_TALK_MS 120, WINDOW_MS 6000, MARGIN_DB 8.0, SILENT_DB -50.0, DEFAULT_BLEED_DB -20.0`.
- Algorithm the tests do not fix (`LiveTalkGate`): per block, room = 10th percentile of micDb over the window; bleed = 25th percentile of (micDb − videoDb) over the window's blocks where videoDb > −45 (else `DEFAULT_BLEED_DB`); expected = max(room, videoDb + bleed); voiced = micDb ≥ expected + `MARGIN_DB` and micDb > `SILENT_DB`. Voiced runs bridge gaps < `BRIDGE_MS`; a run shorter than `MIN_TALK_MS` once closed is dropped; talking = within [start − `LEAD_MS`, end + `TAIL_MS`], ramped over `rampMs` outside it. Gains: `lowerVideo` → video = 1 − (1 − duck)·s, mic = gate + (1 − gate)·s; else (1, 1). **Before the window holds 500 ms of blocks, mic = 1** (fail open).

- [ ] **Step 1: Write the failing tests**:
  - `ReactSceneTest`: positions of the full rect = `[-1, 1, -1, -1, 1, 1, 1, -1]`; texCoords full, no turn, yUp = `[0, 1, 0, 0, 1, 1, 1, 0]`; src bottom half `(0, 0.5, 1, 0.5)` yUp = `[0, 0.5, 0, 0, 1, 0.5, 1, 0]`; one quarter turn, full, y-down: TL samples buffer `(0, 1)`; mirrored, no turn, y-down: TL samples `(1, 0)`; `yUp = false` for a bitmap passes y-down through; `fromMap` reads `{'camera': {'dst': [..], 'src': [..]}}`, junk → nulls.
  - `FileClockTest`: start 1 000 → fileNanos(3 000) = 2 000; pause 3 000, resume 7 000 → fileNanos(5 000) null, fileNanos(8 000) = 3 000, durationNanos(8 000) = 3 000; before start null; `frameNanos(ts 1 000 000 000, arrival 1 010 000 000)` = ts, `(ts 5, arrival 1 010 000 000)` = arrival.
  - `MissedFramesTest`: 30 fps steady → 0 missed; one 100 ms gap at 30 fps → 2 missed; a steady 15 fps stream → 0 missed after the median settles.
  - `MediaTimeMapTest`: samples (0 ns, 0 ms, playing), (1 s, 1000, playing) → mediaMsAt(0.5 s) 500; (1 s, 1000, paused) after → mediaMsAt(1.5 s) null; resume sample (3 s, 1000, playing) → mediaMsAt(3.5 s) 1500; before the first → null; extrapolates past the last while playing.
  - `LiveTalkGateTest`: `lowerVideo = false` → always (1, 1); bleed only (videoDb −10, micDb −30 for 8 s) → gainsAt(6 000) = (1, gate); **loud music** (videoDb −3, micDb −23) → (1, gate); voice over bleed (micDb −8 for 1 s inside bleed) → mid-talk (duck, 1), ramps at the edges; **talking from the first block** (micDb −8 from 0 ms, videoDb −10) → gainsAt(100).mic == 1; a 10 ms click → no talk; two words 200 ms apart → one talk span; quiet room (videoDb −120, micDb −60 then −15) → talking at −15.
- [ ] **Step 2: Run** `.\gradlew.bat :app:testDebugUnitTest --tests "com.techfamz.slimshotai.camera.react.*"` (from `android/`) — Expected: FAIL (classes missing).
- [ ] **Step 3: Implement** the five classes.
- [ ] **Step 4: Run** the same command — Expected: PASS.
- [ ] **Step 5: Commit** `feat(camera): REACT live — scene geometry, file clock, missed frames, media time, talk gate`.

### Task 3: Kotlin — the recorder

**Files:**
- Create: `camera/react/ReactEgl.kt`, `ReactCompositor.kt`, `ReactVideoEncoder.kt`, `ReactAacEncoder.kt`, `ReactMuxer.kt`, `ReactOutput.kt`, `ReactAudioMixer.kt`, `ReactLiveRecorder.kt`, `ReactCapabilityProbe.kt`

**Interfaces:**
- Consumes: Task 2's classes; `PcmAudioSource(path, 1.0, rate)` (`open`, `seekTo(us)`, `read(FloatArray, offset, frames)` stereo float); `StillImageDecoder.decode(path, maxW, maxH)`; `ExportCapabilities.alignedEncoderSize(w, h)`; `GalleryShots.values(name, mime)` / `galleryName(file)`.
- Produces (what Task 4 calls):
  - `ReactCapabilityProbe.facts(): Map<String, Any>` — `fps1080`, `fps720` (achievable upper bound where the codec reports one, else supported, 0 when the aligned size is refused), `size1080`, `size720` (`[w, h]` aligned).
  - `class ReactLiveRecorder(context, previewEntry: TextureRegistry.SurfaceTextureEntry, mainExecutor, events: (Map<String, Any?>) -> Unit)`:
    - `val surfaceProvider: Preview.SurfaceProvider` — gives CameraX the camera `SurfaceTexture`; remembers `rotationDegrees`, `isMirroring`, `hasCameraTransform` from the transformation info.
    - `fun setSource(path: String, photo: Boolean, done: (String?) -> Unit)` (error message or null); `fun clearSource()`; `fun setScene(scene: ReactScene)`; `fun setPlaying(playing: Boolean)`; `fun setSpeakerOn(on: Boolean)`.
    - `fun start(path: String, toGallery: Boolean, audio: Boolean, shortSide: Int, take: TakeSound)`; `fun pause()`; `fun resume()`; `fun stop(done: (Map<String, Any?>) -> Unit)` → `{path, uri?, durationMs, frames, missedFrames}` (empty map when nothing usable); `val isRecording: Boolean`; `fun release()`.
    - Events: `recording` `{durationMs, paused}` every 250 ms; `reactVideoEnded`; `reactFailed` `{message}`.
  - `data class TakeSound(val lowerVideo: Boolean, val duck: Double, val gate: Double, val rampMs: Int)` with `fromMap`.
- Rules the code must keep (from the spec): own EGL with `EGL_RECORDABLE_ANDROID` (0x3142); composite preview 720x1280 into `previewEntry`; per camera frame: latch camera (and video if new), draw scene to the preview surface, and while recording draw again to the encoder surface stamped with `FileClock.fileNanos(frameNanos)` then drain; camera quad sampled through its `SurfaceTexture` matrix with `quarterTurns`/`mirrored` only when `!hasCameraTransform`; photo through a 2D texture with `yUp = false`; black clear; ExoPlayer on the main thread, video `Surface` from the GL thread's `SurfaceTexture`, `repeatMode` off, `STATE_ENDED` → `reactVideoEnded`; the player starts with the recording and pauses/resumes with the take (remembering whether it was playing); media-time samples every engine tick (30 ms) and on every play/pause/end; mixer thread 250 ms behind live, 10 ms blocks at the mic's rate (48 000, else 44 100), mono mic into stereo, video PCM read at `MediaTimeMap.mediaMsAt` (re-aimed with `seekTo` beyond 40 ms of drift, silence while null), gains from `LiveTalkGate`; AAC LC 192 kbps; `ReactMuxer` expects 2 tracks when there is any sound source, else 1; `ReactOutput` makes a MediaStore pending entry via `GalleryShots.values` when `toGallery`, else the given camera-folder path, and publishes or deletes at the end; on stop: video EOS + drain, audio mixed to the last frame's time + EOS, muxer close, publish; `MissedFrames` fed with camera timestamps while recording; any exception on the GL or mixer thread → finish what can be finished, emit `reactFailed`.
- [ ] **Step 1: Write the nine classes.**
- [ ] **Step 2: Compile** `.\gradlew.bat :app:compileDebugKotlin` (from `android/`) — Expected: BUILD SUCCESSFUL.
- [ ] **Step 3: Run** Task 2's tests again — Expected: PASS.
- [ ] **Step 4: Commit** `feat(camera): REACT live — the recorder`.

### Task 4: Kotlin — the camera channel

**Files:** Modify `camera/CameraChannel.kt`.

**Interfaces:**
- Consumes: Task 3's `ReactLiveRecorder`, `ReactCapabilityProbe`, `TakeSound`, `ReactScene.fromMap`.
- Produces (channel contract Task 5 uses):
  - mode `react_live` in `open`/`configure` with `liveShortSide` (1080 | 720): binds **Preview only**, its surface provider the recorder's; `describe()`'s `textureId` is the recorder's composite entry; `mode` answered as `react_live`.
  - `reactLiveFacts` → `ReactCapabilityProbe.facts()`.
  - `reactSource {path, photo}` → `null` or error `react_source_failed`; `reactClearSource`; `reactScene {camera?, video?}`; `reactPlayback {playing}`; `reactSound {on}`.
  - In `react_live`, `startRecording {path, audio, gallery, react}` / `pauseRecording` / `resumeRecording` / `stopRecording` go to the recorder; stop answers `{path, uri?, durationMs, frames, missedFrames}`.
  - The activity stopping mid-take (`Lifecycle.Event.ON_STOP`) stops the recorder and emits `recordingEnded` with its answer.
  - Leaving `react_live` (another mode, `close`) releases the recorder and its entry.
- [ ] **Step 1: Implement** the above; photo and video modes stay byte-for-byte as they are.
- [ ] **Step 2: Compile** and run every Kotlin unit test: `.\gradlew.bat :app:testDebugUnitTest --tests "com.techfamz.slimshotai.camera.*" --tests "com.techfamz.slimshotai.nativepreview.*" --tests "com.techfamz.slimshotai.export.*"` — Expected: PASS.
- [ ] **Step 3: Commit** `feat(camera): REACT live — the channel`.

### Task 5: Dart — backend and controller

**Files:**
- Modify: `camera_controller.dart`, `method_channel_camera.dart`, `test/support/fake_camera.dart`
- Test: `test/features/camera/camera_controller_test.dart`, `test/features/camera/method_channel_camera_test.dart`

**Interfaces:**
- Consumes: Task 1 (`ReactCapture`, `ReactLiveFacts`, `ReactionScene`, `ReactLiveTake`); Task 4's channel contract.
- Produces:
  - `CameraBackend` gains `Future<ReactLiveFacts> reactLiveFacts()`, `Future<void> reactSource(String path, {required bool photo})` (throws `CameraFailure`), `Future<void> reactClearSource()`, `Future<void> reactScene(ReactionScene scene)`, `Future<void> reactPlayback({required bool playing})`, `Future<void> reactSound({required bool on})`; `open`/`configure` gain `int? liveShortSide`; `startRecording` gains `ReactLiveTake? reactLive`.
  - Events `ReactVideoEnded`, `ReactRecorderFailed({String? message})`.
  - `RecordedVideo` and `VideoShot` gain `frames`, `missedFrames` (default 0).
  - `CameraController`: `setMode(CameraMode.react, {CameraLens? lens, int? reactLiveShortSide})`; `bool get reactLive` (react mode bound live); `shutter({ReactLiveTake? reactLive})`; a live take goes to the gallery like video (`_galleryAllowed`); `bool reactVideoEnded` (set by the event, cleared at each start); `bool takeReactLiveFailure()` (once).
- [ ] **Step 1: Write the failing tests**: configure in react with `reactLiveShortSide: 720` sends `liveShortSide` 720 and the channel mode `react_live` (and without it `video`, as today); a live take passes `reactLive` and `gallery: true`; stop returns a `VideoShot` with `frames`/`missedFrames`; `ReactVideoEnded` sets `reactVideoEnded`; `ReactRecorderFailed` sets the failure once and the message; pause while recording still calls `pauseRecording`; `cameraEventFrom` parses `reactVideoEnded` and `reactFailed`; `recordedVideoFrom` reads `frames`/`missedFrames`.
- [ ] **Step 2: Run** the two test files — Expected: FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** `flutter test test/features/camera` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(camera): REACT live — backend and controller`.

### Task 6: Dart — the screen

**Files:**
- Modify: `camera_screen.dart`, `reaction_frame.dart`
- Test: `test/features/camera/camera_react_live_test.dart` (new), `camera_react_screen_test.dart` (the old way, unchanged behaviour)

**Interfaces:**
- Consumes: Tasks 1 and 5.
- Produces:
  - `ReactionFrame` gains `Widget? composite`: when set, the frame draws it under everything and draws neither picture itself; the video's place keeps its gesture area, placeholder and chrome.
  - `typedef ReactionSourceProbe = Future<ReactionSourceInfo?> Function(String path)`; `class ReactionSourceInfo { const ReactionSourceInfo({required double aspect, required bool isPhoto}); }`; `Future<ReactionSourceInfo?> probeReactionSource(String path)` (the editor's `MediaImportService` probe).
  - `CameraScreen` gains `ReactionSourceProbe? probeReactionSource`.
  - On entering REACT: facts (asked once per screen) + `ReactCaptureStore.load(appBuildStamp())` → `chooseReactCapture` → `setMode(react, lens: front, reactLiveShortSide: capture.shortSide)`; `afterwards` → today's flow, untouched.
  - Live: choosing → probe → `reactSource` → scene; layout/window/✕/removal → `reactScene`; tap the video mid-take → `reactPlayback`; the sound button → `reactSound`; `ReactVideoEnded` → the take's ✕; shutter → `shutter(reactLive: ReactLiveTake(lowerVideo: videoSoundReachesMicrophone(headphones: …, videoSoundOn: …) && !isPhoto))`; the shot lands on the pile as a plain video; a choppy take saves `stepAfterChoppy` and says `kReactStepTo720Message` / `kReactStepToAfterMessage` once; a failure saves step 2 and says `kReactLiveFailedMessage`.
- [ ] **Step 1: Write the failing tests** (`camera_react_live_test.dart`, `FakeCamera` with facts fps1080 60): entering REACT binds `react_live` 1080 and shows `Texture` with the composite id; choosing a video sends `reactSource` then a scene whose video quad matches `reactionPlaces`; the layout button sends a new scene; dragging the window sends scenes; ✕ clears the source (`reactClearSource`) and the scene loses its video; a take starts with `reactLive.lowerVideo` true out loud and false with headphones; tapping the video sends `reactPlayback(false)` then `(true)`; `ReactVideoEnded` shows `react_take_remove`, its tap sends a removed scene; stop lands the shot on the pile with no `reaction`; a choppy stop (frames 900, missed 60) saves step 1 and shows the 720 message, a second choppy one at 720 saves 2; a `ReactRecorderFailed` saves 2; facts all 0 → the old flow (`configure` mode `video`).
- [ ] **Step 2: Run** them — Expected: FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** `flutter test test/features/camera` — Expected: PASS (the old-way tests unchanged).
- [ ] **Step 5: Commit** `feat(camera): REACT live — the screen`.

### Task 7: Notes, suite, build

**Files:** Modify `CLAUDE.md` (the REACT section: live recording, the way per phone, what stays).

- [ ] **Step 1:** Update CLAUDE.md.
- [ ] **Step 2: Run** `flutter test` and `flutter analyze --no-pub` — Expected: all pass; no new analyzer issues (41 today).
- [ ] **Step 3: Build** `flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=env/env.json`; copy to `../test-builds/slimshot-test-camera-react-arm64.apk`; install on a connected phone.
- [ ] **Step 4: Commit** `docs: REACT recorded live`.
