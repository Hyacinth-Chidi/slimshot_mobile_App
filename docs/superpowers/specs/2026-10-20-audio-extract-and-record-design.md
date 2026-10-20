# Audio menu: Extract and Record — design

**Date:** 2026-10-20 · **Branch:** `audio-extract-record` · **Status:** awaiting the owner's review

The audio menu reads **Music · Sound effects · Extract · Record**. Music and Sound effects are
built (the sound library). **Extract** and **Record** are declared in `_audioMenu`
(`lib/screens/video_editor_screen.dart`, ids `extract` and `record`) and have **no handler** —
tapping either does nothing today. This builds both.

Marked **(owner)** where the owner decided, **(my call, accepted)** where I proposed and the
owner accepted, and **(builder's call)** where the detail is left to whoever implements it.

## Intent

- **Extract** takes the sound out of a video the user picks from the gallery and puts it on the
  timeline as an audio track — for the song or speech in a video they already have.
- **Record** is a voiceover: the user talks over their edit while it plays, and the take lands
  on the timeline exactly where they started speaking.

Both must feel like CapCut's: quick, nothing to learn, and the result an ordinary audio track the
user can move, trim and change the volume of like any other.

## Goals

1. Extract: gallery → a large sheet to choose the part of the sound → Done → an audio track at
   the playhead.
2. Record: a recording mode with one record/pause button → Done → an audio track where the
   recording began.
3. Both land as ordinary `AudioTrackModel`s through `addAudioTrack`: first free lane at that
   time, never on top of anything, selected, one undo step.
4. Both files survive app restarts and are deleted with the draft.
5. Preview and export agree: the extracted or recorded sound plays and exports exactly as heard.

## Non-goals

- Extracting from a clip already on the timeline (CapCut's "Extract audio" on a clip). **(owner)**
  — gallery only.
- Real waveforms on the timeline's audio clips (they draw a seeded fake today). The Extract sheet
  draws a real one; reusing it on the timeline is a later piece of work.
- Voice effects, noise reduction, or recording several takes and choosing between them.
- Fixing imported music's file living in `file_picker`'s cache (a separate, existing issue).

## Anti-goals — failures even if it "works"

- **A voiceover that is late or early against the picture.** The take must start on the frame
  recording began, not a few hundred milliseconds after.
- **A take with the video's own sound baked under the voice** because the speaker played into
  the microphone.
- **A track that points at a video file.** Playing a video only for its sound keeps a hidden
  video decoder open — the low-end-phone failure fixed for video overlays.
- **A file that disappears**: anything kept in temp or a picker's cache, which the OS reclaims.
- **A silent failure**: a video with no sound, a refused microphone, or a recorder that will not
  start must each say so in one line, never just do nothing.

## Extract

### Flow **(owner)**

1. Audio → **Extract** opens the system gallery, **videos only**
   (`MediaPickerService.pickVideo()`, which already exists and uses the Photo Picker).
2. On a pick, a **large sheet** slides up, about **90% of the screen** (through
   `showEditorSheet`, like every sheet). It holds:
   - **The video**, playing, at the top.
   - **Its real waveform** under it, with **two trim handles**. The video plays only the stretch
     between the handles, looping, so the user hears exactly what they will get.
   - **Change video**, which reopens the gallery without closing the sheet; the handles reset
     to the whole of the new sound.
   - **Done**, which puts the sound on the timeline at the playhead and closes the sheet.
   - Closing the sheet any other way (✕, Back, swipe) adds nothing.
3. A video with **no sound track** says **"This video has no sound"** and adds nothing.

### What the handles do **(my call, accepted)**

They do **not** cut the file. The whole sound is copied into the project; the handles set the
track's `sourceStart` / `sourceEnd`. The track then lands at the playhead with that trim, and
the user can still drag its edges out on the timeline to reach the rest.

Minimum selection is `kMinClipDurationSeconds`, the timeline's own minimum, so the sheet can
never make a track the timeline would refuse.

### Taking the sound out **(my call, accepted)**

Native Kotlin, a new channel (builder names it; e.g. `slimshot_ai/audio_extract`):

- **Remux, don't re-encode**, when the sound can go into an MP4 audio file as it is — AAC, which
  is what almost every phone video carries: `MediaExtractor` selects the audio track and the
  samples are written unchanged into `<id>.m4a`. Near-instant for any length, quality untouched.
  Media3's `Mp4Muxer` (already in the build, behind `ExportMuxer`) or the platform `MediaMuxer`
  — **builder's call**.
- **Otherwise transcode to AAC** through the decode and encode path the export already has
  (`PcmAudioSource` → the AAC encoder). Slower, still works.
- **The sheet's waveform** comes from the same side: decode the sound once and reduce it to
  peaks (one value per pixel-ish bucket — **builder's call** on the count), returned to Dart.
  A long video takes a moment: the sheet shows the video at once and the waveform when ready.
- Written as `<name>.part` and renamed when whole; a failure leaves nothing behind.

### Where the file lives **(my call, accepted)**

`drafts/<draftId>/audio/` via a new `DraftFiles.audioDir(draftId)`. Every editor project has a
draft id from the moment it opens (`loadAssets` assigns one), and `DraftFiles.deleteAll` already
deletes the whole `drafts/<id>/` folder, so the sound goes with the draft and nowhere else.

### The preview in the sheet

`video_player` (already a dependency) plays the picked video, looping between the handles,
muted when the sheet closes and disposed with it. **Builder's call** on exactly how the loop
is enforced (a position listener seeking back at the end handle is the obvious route).

## Record

### The mode **(owner)**

Audio → **Record** turns the editor into **recording mode**:

- **The preview stays large and visible.**
- **The timeline shows only the clip thumbnails.** Text, overlay and audio lanes are hidden
  while the mode is on.
- **A panel** replaces the toolbar, holding **one round button**: record, and pause while
  recording. While it records, a **purple ring pulses** around it (`AppColors.primaryStart`).
- **Done** puts the take on the timeline; then the mode ends and every lane comes back.

### Taking a take

- **First tap asks for the microphone** (`RECORD_AUDIO`, added to the manifest;
  `permission_handler` is already a dependency). Refused → one line saying how to allow it in
  Settings. Refused permanently → the same line with a way to open Settings.
- **Countdown 3-2-1 (my call, accepted)**, then the video plays from the playhead and the
  microphone records.
- **Pause** stops both; **record** again carries on from that exact spot. Pauses do not split
  the take: it is **one** file, one track.
- **The take grows on the timeline (my call, accepted)** as a bar under the thumbnails, from
  where recording began to where it is now.
- **No scrubbing in recording mode (my call, accepted)** — a moved playhead would make the
  take's pieces not follow on.
- **✕ discards (my call, accepted)**: the take is thrown away and nothing is added.
- **Reaching the end of the project** stops recording as if Pause were pressed; Done still adds
  what was recorded. Record with the playhead already at the end says **"Move the playhead back
  to record over your video"** and does not start **(my call)** — a voiceover is spoken over
  something.
- **The video stays paused through the countdown**, and the monitor mute applies to every sound
  the preview makes — clips, imported music and video overlays' sound alike **(my call)**.
- **Done** puts the take at the time recording began, on a free lane, selected, one undo step.
  Done with nothing recorded just leaves the mode.

### What the user hears while recording **(owner, on my recommendation)**

**The video's own sound is muted by default**, with a **speaker toggle** in the record panel to
hear it. The phone's speaker would otherwise play into the microphone and the take would carry a
quieter copy of the video's sound under the voice, for good. With headphones the user turns it
on to time their words.

The toggle affects **only what is heard while recording**: it is a monitor mute on the engine's
output (`setVolume`, which exists) and the imported-music players (`AudioPlayerManager`),
restored when the mode ends. **It never touches the project's own `isMuted`** or any clip's
volume, and is not saved. Remembered for the rest of the session **(builder's call)**.

### Timing **(my call, accepted)**

The anti-goal above is the reason this is native rather than a recording plugin or Android's
`MediaRecorder`, whose start delay cannot be measured:

- Kotlin `AudioRecord` captures raw microphone samples; the recorder knows exactly which sample
  it was on when the video started playing, and **drops everything before it**, so the first
  sample of the file is the frame recording began on.
- On pause both stop together and on resume both start together, trimmed the same way, so the
  joins are seamless in the file.
- Encoded to AAC in `<id>.m4a` in `drafts/<draftId>/audio/` — the format the preview player and
  `PcmAudioSource` both already read. An AAC encoder adds a few tens of milliseconds of start
  padding; **builder's call** whether to compensate (e.g. trim it through the track's
  `sourceStart`) — under a frame of lip-sync either way.
- Sample rate and channel: mono, at a rate the device's `AudioRecord` accepts (44.1 kHz is the
  only one Android guarantees) — **builder's call** within that.

A recorder that will not start (another app holding the microphone, an unsupported rate) says
so in one line and leaves the mode usable.

## Landing on the timeline (both)

- **At the playhead** for Extract, **where recording began** for Record **(owner)**.
- Through `addAudioTrack`, which already takes the **first free lane** at that time — never on
  top of anything **(owner)** — and selects the new track, one undo step.
- **Ordinary purple audio** (`isSoundEffect` false) **(my call, accepted)**.
- The track's length is the file's own, read once it is written (as `addLibrarySound` does when
  the server did not know it).

## Testing

Test-first, as the project works. Pure Dart carries every rule a test can reach:

- **Extract:** the trim handles' clamps (minimum length, the handles never cross, the range
  inside the sound); Done builds the track with `sourceStart`/`sourceEnd` from the handles at the
  playhead; ✕/Back adds nothing; "no sound" adds nothing and says so; Change video resets the
  handles. The sheet widget against a fake extractor and a fake player.
- **Record:** a controller with a fake recorder holds the state machine — idle → countdown →
  recording ⇄ paused → done / discarded — and is tested for: one take across pauses; the end of
  the project pausing; Done with nothing recorded adding nothing; ✕ adding nothing; the monitor
  mute set on entering and restored on leaving (and never touching `isMuted`); permission refused
  and refused permanently.
- **Timeline:** recording mode hides every lane but the thumbnails and draws the growing take;
  scrubbing is refused while it is on.
- **Menu:** `editor_menu_test.dart` pins that Extract and Record have handlers.
- **Native:** the trim-to-start sample arithmetic and the waveform peak reduction as pure Kotlin,
  JVM-tested. Capture, remux and playback alignment only run on a device — **device checks**:
  a clap on camera recorded as a voiceover lands on the clap's frame; an extracted song plays in
  the preview and the export in step with where it was put.

## Left to the builder

Channel names; the file names inside `drafts/<id>/audio/`; `Mp4Muxer` versus `MediaMuxer` for the
remux; the waveform's bucket count; how the extract sheet's loop is enforced; whether to
compensate AAC start padding; the recording sample rate within what the device accepts; whether
the monitor-mute choice is remembered for the session; exact layout of the sheet and the panel
within `AppColors`, `AppMotion` and the existing sheet look.
