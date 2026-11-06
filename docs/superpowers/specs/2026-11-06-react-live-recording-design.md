# REACT, recorded live — design

2026-11-06. Owner-approved in conversation; written up for the build.

## Why

A REACT reaction is made **after** the take: the editor's export engine reads
the recording of you and the video back, draws them together frame by frame,
mixes the sound and writes a new file. Measured on the Infinix (Unisoc,
Android 12), that wait is about **1.7 seconds per second recorded**:

| Take | Wait after stop | Where it went |
| :--- | ---: | :--- |
| 37 s | 64 s | stills 3 s · reading loudness 7 s · sound mix 15 s · picture 39 s |
| 3 min 29 s | 5 min 54 s | stills 5 s · loudness 37 s · sound mix 92 s · picture 219 s |

A 30-minute reaction would wait about 50 minutes. The owner's words: *"I just
want it to be better, faster, without harming the editor engines. Even my
screen recording is 100x faster than it."* A screen recorder — and every
dual-camera app — writes the video **while** it records, so stop means done.
REACT will work the same way.

## Goals

- **Stop, and the reaction is finished** in a second or two, at any length.
- **What you see is what is recorded**: the screen shows the very drawing that
  goes into the file — your camera and the video, in the chosen layout.
- **The sound is mixed while recording**: out loud, the video's own clean sound,
  lowered while you talk, and your microphone let through only while you talk;
  with headphones (or the video's sound off), the clean video sound and your
  voice, nothing lowered.
- Everything REACT does today keeps working: the three layouts and the movable
  window, photos, tap the video to pause it, the end holding the last frame, the
  ✕ that takes the video away so you fill the frame, pause/resume of the take,
  the pile, the viewer.
- **Older phones are measured, never guessed**: 1080p where the phone can,
  720p where it is close, today's way where it cannot — and a step down is said
  once.

## Non-goals

- **Two layers for a new reaction** (owner: "yeah am okay"). A live reaction
  opens in Edit as **one finished video** — trim, text, captions, music,
  effects all work; the layout, the window and the voice/video balance are set
  before recording. Reactions already made keep their two layers.
- Changing the layout or moving the window **during** a take (my call; the
  owner saw it played back). Set before you start, as now.
- Making today's way faster. It stays exactly as it is, as the fallback.
- Front and back camera at once.

## Anti-goals

- **Anything that changes how the editor previews or exports.** The new
  recorder lives in the camera feature. It may *use* building blocks the export
  uses (`VideoFrameEncoder`, `PcmAudioSource`, `ExportCapabilities`,
  `DeviceDecoderFacts`, `StillImageDecoder`) **without changing them**; where a
  block would need a change (the EGL setup, the muxer, the AAC encoder), the
  camera feature gets its own small one instead.
- A file that differs from what was on the screen.
- A quality drop nobody is told about.
- Losing a take: a recording the app is pulled away from mid-take is finished
  with what it had, as today.

## Constraints

- minSdk 24; CameraX 1.6.2; Media3 (ExoPlayer, `media3-muxer`'s `Mp4Muxer`);
  OpenGL ES 2.0.
- The target includes phones like the Infinix: ~105 fps of 1080p decoding
  across every decoder at once, and the export wrote 1080x1920 at ~29 fps while
  also decoding the take. Live recording decodes **less** (only the video
  reacted to; your camera comes straight from the sensor).
- The canvas is 9:16, the editor's shape; the file is portrait.
- House rules: toasts are the island pill, colours from `AppColors`, Lucide
  icons, minimal copy, no toast for a preview-only fallback.

## How it works

### One drawing, two places

A native **live recorder** (`camera/react/`) owns a GL thread with its own EGL
context (recordable config). Its inputs:

- **Your camera**: in live REACT, CameraX binds **Preview only**, and the
  preview's surface is the recorder's camera `SurfaceTexture` (not Flutter's).
  The texture's own transform turns and mirrors the picture, as it does on the
  screen today (`hasCameraTransform`); a selfie is mirrored as seen, the
  camera's rule.
- **The video**: an ExoPlayer in the recorder renders into the recorder's
  video `SurfaceTexture` and plays its sound to the speaker (or silently, with
  the sound toggle off). Tap-to-pause is `pause()`; the end is `STATE_ENDED`;
  the last frame simply stays on the texture.
- **A photo**: decoded once (`StillImageDecoder`) into a texture.

Its outputs, drawn from the same draw call each camera frame:

- **The screen**: a **separate Flutter texture** for the composite (a second
  `SurfaceTextureEntry`, never the camera's own — two producers on one buffer
  queue is the trap `CameraChannel` already documents). Sized for the screen
  (720x1280 is plenty).
- **The file**, while recording: the encoder's input surface
  (`VideoFrameEncoder`), at the recording size, each frame stamped with its
  file time (`eglPresentationTimeANDROID`).

**Dart computes, Kotlin draws.** The layout geometry stays in Dart
(`reactionPlaces`, `coverCrop`, `ReactionWindow.fittedFor`); Dart sends the
recorder the resolved rects as fractions of the frame — where the camera goes
and the part of it shown, where the video goes, how it fits, the mask — and the
shader only draws rects. No second copy of the layout rules to drift.
Before anything is chosen, the video's place is left dark and Flutter draws
the dashed "Select photo or video" frame over it, as now. After ✕, the camera
fills the frame.

### Time

Every timestamp is `System.nanoTime()`-based. **File time** = moment −
recording start − time spent paused. Camera frames take their `SurfaceTexture`
timestamp when its base matches `nanoTime` (checked against the arrival time),
else the arrival time. Pause of the take stops feeding both encoders; resume
shifts by the paused span.

### Sound, mixed live

- **Microphone**: `AudioRecord` (the camcorder source, as CameraX uses), its
  frames placed in file time through `AudioRecord.getTimestamp`.
- **The video's sound in the file** is decoded separately from what the
  speaker plays (`PcmAudioSource` on the same file), at the **media time the
  player was showing** at each moment: the player's position is sampled with
  `nanoTime` on every engine tick, giving a map from moment to media time —
  advancing while it plays, standing still while held. Held or ended: silence.
  A read that drifts from the map by more than a frame is re-aimed with a seek.
- **Lowering** (out loud only, `videoSoundReachesMicrophone`): a live talk
  detector on the microphone — the take's quiet level tracked as a running
  floor, talking what stands above it — drives the two gains: the video at
  `kReactionDuckVolume` (0.25) while you talk, the microphone at
  `kReactionMicGateVolume` (0.1) while you don't, each change ramped over
  150 ms. The mix runs a few hundred milliseconds behind live, which lets the
  detector look ahead so the video dips **with** your first word, not after it.
- **A photo** has no sound: the file is your microphone, nothing lowered.
  **A refused microphone**: the file has the video's sound alone, and it is said
  once, as the video mode says it.
- The lowering's numbers (`kReactionDuckVolume`, `kReactionMicGateVolume`, the
  ramp) stay defined once, in Dart, and travel with the start of the take — the
  old way's after-the-take curves read the same constants.
- AAC, written with the picture into one MP4.

### The file

- Written **straight into the gallery's SlimShotAI album** through a MediaStore
  pending entry and its file descriptor (CameraX's own way) — no copy of a long
  file afterwards; into the camera folder where the gallery is refused (Android
  10 and older without storage access), as today.
- A small camera-feature wrapper around Media3's `Mp4Muxer` takes the stream;
  the export's `ExportMuxer` (path-only) is left alone.
- **Stop**: the video encoder gets end-of-stream and drains; the sound is mixed
  up to the last frame's time and finished; the muxer closes; the pending entry
  is published. The reaction lands on the pile as a plain video
  (`RollShot` with no `reaction`), so Edit opens it as one clip.
- **Pulled away mid-take** (the app leaves the screen, the camera is taken):
  finished with what it had, as the video mode does, and reported the same way
  (`recordingEnded`).
- **A recorder that fails to start or dies mid-take** says so; what was
  written is kept where it can be, and the phone records today's way from then
  on (remembered, like a step down).

### Which way a phone records

Decided when REACT opens, from three things, and **never by a test run**:

1. **Ask the phone** (milliseconds, once per build): can its AVC encoder take
   1080x1920 portrait at 30 fps (`ExportCapabilities.alignedEncoderSize` plus
   `VideoCapabilities.areSizeAndRateSupported`), and does one more decoder fit
   its budget (`DeviceDecoderFacts`)? Borderline means 720x1280.
2. **Count during the take**: camera frames that never made it into the file,
   from the gaps in camera timestamps. Too many (well under one in twenty is
   normal) marks the take choppy.
3. **Remember** per phone and build: after a choppy take the next records at
   720p, after a choppy 720p take the next goes today's way — and the step down
   is said once ("The next reaction will record at 720p.").

Where the phone cannot record live at all, REACT is exactly today's REACT.

## On the Dart side

- `CameraBackend` / `MethodChannelCamera` gain the live calls: prepare the
  source (video or photo → its shape), set the layout rects, the sound toggle,
  tap-to-pause, remove the video; events for the video's end and the recorder
  failing. **Start, pause, resume and stop stay the calls the video mode uses**
  — in live REACT the channel routes them to the recorder and answers in the
  same shape (`recording` progress events, `{path, uri, durationMs}` at stop),
  so the controller's recording flow is the one already device-checked.
- `CameraController` decides live vs today's way at REACT entry and carries the
  live take's state (held, ended, removed) — the decisions stay pure and
  tested, as the rest of the controller's are.
- `CameraScreen` shows the composite texture with the same chrome over it: the
  layout, sound, Replace and ✕ buttons; the dashed frame; the window's drag and
  pinch (sending rects); the held play mark; the end's ✕. `ReactionFrame` stays
  for today's way only.

## Tests

- **Dart**: the choice of way (facts and memory → 1080 / 720 / today's way);
  the rects sent for every layout, window and the removed state; the controller
  and screen against fakes — live take, hold, end, ✕, pause, stop, failure
  falling back, the step-down said once.
- **Kotlin (JVM)**: the talk detector and gains (floors, thresholds, ramps,
  lookahead, no lowering with headphones); the media-time map (playing, held,
  ended, seek); file time across pauses; the missed-frame counter; the
  camera-timestamp base check.
- **On the phone only**: the GL drawing, the encoders, the sync of picture and
  sound, the gallery write. Device checks: each layout live and in the file; a
  1-minute and a 5-minute take ready within seconds of stop; tap-pause, the end
  hold and ✕ matching in the file; out loud the video dipping under talk with
  no echo between, headphones untouched; Edit opening one clip; the editor's
  own preview and export unchanged; the Infinix's choice (1080 or 720) and its
  frame count.

## Left to the builder

Thresholds and ramp shapes of the live talk detector; the preview texture's
size; bitrates (the export's `bitRateFor` is a fine start); the audio format
(48 kHz stereo suggested); thread layout; how the media-time map is sampled.
