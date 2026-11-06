# SlimShot Camera — design

**Status:** agreed with the owner in conversation (2026-11-05, mockups in the brainstorm session
`.superpowers/brainstorm/1219-1793891659`). The owner's words: "build this first then I will
test, we amend as we build." Built in two steps, each device-tested before the next.

## What it is

A camera of its own, opened from **Home** — not an editor tool. A full-screen camera in the
Snapchat / phone-camera family. What it shoots can be saved, shared, or opened in the editor
like any picked video. "Many features" means the camera **grows**: face tracking, effects and
the like come later, one after another, so it is built on a pipeline that can take them.

## Step 1 — photo and video (this build)

- **Home:** a **Camera** tool card, first in the row of tools (my call; easy to move).
- **The screen:** the picture fills the screen. ✕ top-left; flip camera and flash on the right.
  At the bottom a mode switch **PHOTO · VIDEO** (tap or swipe), the shutter, and while
  recording a **pause** button and the running time.
- **Photo:** tap the shutter. **Video:** tap to start, tap to stop; pause and carry on in the
  same video. **No hold-to-record** (the owner's call: everything else from both mockups stays).
- **Flip, flash, pinch to zoom, tap to focus.** Flash: off / auto / on for photos, a torch for
  video. Zoom between the camera's own limits.
- **Front camera saves mirrored**, as it was seen (my call, Snapchat and Instagram do).
- **Saved as it is taken** (amended 2026-11-05, the owner's design after the first device run —
  the review screen with Retake · Save is gone: a phone's camera does not ask): every shot goes
  straight into the gallery's **SlimShotAI** album, where the app's exports already go. Android 10
  and older ask for storage access once; refused, shots stay in SlimShot's own folder.
- **The pile:** left of the shutter, the last shots stacked — **three cards at most**, the newest
  on top, two tilted behind. A tap opens **the viewer**: the shot large, newest first, every shot
  in a strip at the foot; swipe left for older ones, and **one more swipe past the oldest returns
  to the camera**. **Delete** (see-through, bottom left, asks first), **Share**, and **Edit —
  videos only, a scissors icon** — which opens the editor on it as a new project.
- **Only the camera's own shots** are in the pile and the viewer: the app holds no permission to
  read the whole gallery (the system picker needs none). An in-app picker of the CapCut kind — and
  the whole gallery in the viewer — needs the media permissions and a Play declaration first; a
  feature of its own, later.
- **Permissions:** camera, and the microphone for video, asked when needed; refused for good →
  a way to Settings. `CAMERA` is new to the manifest, with the camera feature declared **not
  required** so Play keeps phones without one.

## Step 2 — REACT

**Built 2026-11-06, awaiting device verification** — see CLAUDE.md's REACT section for what was
decided while building: the take records only you and the reaction is rendered after it by the
editor's export engine from a two-layer project (option A, the owner's pick); the video takes the
first place of a split; the Bubble was not built (the Window covers it); the sync is measured per
run, with a slipped run made a piece of its own; the video's sound is kept clean only where the
microphone did not hear it (headphones, or the video silent), and muted in the project otherwise.

A third mode, **PHOTO · VIDEO · REACT**. Pick a video from the gallery first; it plays while the
camera records you. **Both kinds of layout, the owner's call (2026-11-05)**: a **split** —
**Top / bottom**, **Side by side** — and a **float**: the camera fills the frame and the video
plays in a window over it that the user drags to any position (and sizes). The earlier
**Bubble** (you in a circle over the video) is the float turned round, the same mechanism; kept
unless the owner drops it when this is built. Our own GL composites the two pictures, so a layout
is only where each is drawn and switching costs nothing. Pause stops both;
recording ends at stop or at the video's end. Review as above: Save and Share give one finished
video; **Edit** opens the editor with the video and your recording as **separate layers** (main
clip + video overlay, placed and masked by the layout) so the layout can still change. Whether
the video's sound plays out loud is a toggle; how the two sounds are kept apart (echo
cancelling, headphones) is settled when it is built.

## How it is built

- **CameraX** (`androidx.camera` 1.6.2: core, camera2, lifecycle, video), driven from Kotlin —
  not the Flutter `camera` plugin, which cannot composite REACT into one recorded file or run
  per-frame effects. Step 2 adds a CameraX **`CameraEffect`** — our own OpenGL between the
  camera and the preview and recording — which is also where face tracking and effects go later.
- The preview reaches Flutter as a **`Texture`**, the editor's own path. Recording is CameraX's
  `Recorder` (H.264 + AAC, MP4), Full HD falling back to lower; photos are `ImageCapture` JPEGs.
- Channel `slimshot_ai/camera` + events `slimshot_ai/camera_events`; the Dart side keeps the
  decisions (mode, recording state, the cover-fit and tap-to-focus maths) as pure, tested code.
- CameraX ships a native library: checked for **16 KB alignment and its NDK** like every other.

## Not in step 1

REACT; a last-shot thumbnail; timer; recording speed; filters, beauty and face effects; video
length limits; photo formats other than JPEG.
