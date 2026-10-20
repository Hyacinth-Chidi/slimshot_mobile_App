# Audio Extract and Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the audio menu's Extract (sound from a gallery video, trimmed in a 90% sheet, onto the timeline at the playhead) and Record (a voiceover recording mode) tools.

**Architecture:** Both write an `.m4a` into the draft's own `drafts/<id>/audio/` folder through native Kotlin, then land as ordinary `AudioTrackModel`s through `addAudioTrack`. Extract remuxes the video's AAC track unchanged (transcoding through a shared AAC encoder otherwise) and reduces the sound to waveform peaks for the sheet. Record keeps an `AudioRecord` running and writes samples only while "capturing", so the mic is warm before the video starts and the take starts on the frame recording began; a Dart `RecordController` owns the mode's state machine.

**Tech Stack:** Flutter/Riverpod, `video_player`, `permission_handler`, `image_picker` (existing); Kotlin `MediaExtractor`/`MediaCodec`/`AudioRecord` + the existing `ExportMuxer` (Media3 `Mp4Muxer`).

**Spec:** `docs/superpowers/specs/2026-10-20-audio-extract-and-record-design.md`

## Global Constraints

- Branch `audio-extract-record`. Never push; the owner pushes and device-tests before any merge.
- Test-first: every task's test fails before its code exists. Work in the main session, no subagents.
- `flutter analyze --no-pub` stays at **44 issues**; full `flutter test` green before each commit.
- Kotlin: `.\android\gradlew.bat -p android compileDebugKotlin` and `testDebugUnitTest` green where a task touches Kotlin.
- Commits via `git commit -F <file>`, message ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Colours from `AppColors` only (`panel_theme_test.dart` scans `widgets/panels/`); motion from `AppMotion`; sheets through `showEditorSheet`; toasts through `ToastUtils.show`; one-line messages, no titles.
- Files live in `drafts/<draftId>/audio/`, written as `<name>.part` and renamed when whole. Never temp, never a picker's cache.
- Tracks land through `VideoEditorNotifier.addAudioTrack` (first free lane, selected, one undo step), `isSoundEffect` false.
- Exact copy: **"This video has no sound"**, **"Move the playhead back to record over your video"**.
- Countdown 3-2-1; extract sheet ~90% of the screen; minimum selection `kMinClipDurationSeconds`.
- Monitor mute: muted by default while recording, speaker toggle; never touches `isMuted` or any clip volume; not saved.

## Review Focus

1. A video whose sound is not AAC (AMR, Opus, PCM) — must still extract through the transcode path, not fail. → Task 3 test `transcodes when the codec cannot be remuxed` (JVM-tested chooser) and the device check.
2. The user leaves recording mode mid-take (Back, a canvas side tap, an empty-timeline tap) — must behave as Done (keep the take), per the panel dismissal rule. → Task 8 test `dismissing the record panel keeps the take`.
3. The microphone held by another app / `AudioRecord` refusing to start — one line, mode stays usable. → Task 7 test `a recorder that will not open says so and stays idle`.
4. The engine reaching the project's end mid-take — pauses, Done still adds. → Task 7 test `reaching the end pauses`.
5. Change video picked, then cancelled in the gallery — the sheet keeps the first video and its handles. → Task 5 test `cancelling Change video keeps the current video`.

---

### Task 1: The draft's audio folder

**Files:**
- Modify: `lib/core/services/draft_files.dart`
- Test: `test/core/services/draft_files_test.dart` (exists; add to it)

**Interfaces:**
- Produces: `static Future<Directory> DraftFiles.audioDir(String draftId, {Directory? root})` — `drafts/<id>/audio/`, created if absent.

- [ ] **Step 1: Failing tests** — `audioDir lives in the draft's folder` (path ends with `drafts/d1/audio`, exists); `deleteAll takes the audio folder with the draft` (a file in it is gone after `deleteAll('d1')`).
- [ ] **Step 2:** `flutter test test/core/services/draft_files_test.dart` → FAIL, `audioDir` undefined.
- [ ] **Step 3:** Implement `audioDir`, mirroring `proxiesDir`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat(audio): a draft owns an audio folder`.

---

### Task 2: A shared AAC file encoder (Kotlin)

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/AacFileEncoder.kt`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/PcmFrames.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/audio/PcmFramesTest.kt`

**Interfaces:**
- Produces:
  - `internal class AacFileEncoder(outputPath: String, sampleRate: Int, channels: Int, bitRate: Int = 128_000)` with `fun write(samples: ShortArray, count: Int)` (interleaved 16-bit), `fun finish(): Long` (returns frames written; closes the file), `fun abandon()` (closes, deletes the file). Owns one `MediaCodec` AAC-LC encoder and one `ExportMuxer(outputPath, 1)`; presentation time from frames written, so timestamps are exact.
  - `internal object PcmFrames` — pure: `fun floatToShort(src: FloatArray, count: Int, dest: ShortArray)` (clamped), `fun usForFrames(frames: Long, sampleRate: Int): Long`.

The export's own encoder in `AudioExportMixer` is **not** touched (it is device-verified); this is a second, small user of the same codec setup.

- [ ] **Step 1: Failing JVM tests** in `PcmFramesTest`: `float samples clamp to the 16-bit range` (`2f → 32767`, `-2f → -32768`, `0.5f → 16383` or `16384` — assert within 1); `frames convert to microseconds exactly` (`usForFrames(44_100, 44_100) == 1_000_000`, `usForFrames(1, 48_000) == 20`).
- [ ] **Step 2:** `.\android\gradlew.bat -p android testDebugUnitTest --tests "*PcmFramesTest*"` → FAIL (unresolved).
- [ ] **Step 3:** Implement `PcmFrames` and `AacFileEncoder` (encoder loop shaped like `AudioExportMixer.encodeTo`'s queue/drain/signalEnd).
- [ ] **Step 4:** Tests PASS; `compileDebugKotlin` green.
- [ ] **Step 5: Commit** `feat(audio): an AAC file encoder for extracted and recorded sound`.

---

### Task 3: Extract and waveform on the native side

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/AudioExtractor.kt`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/WaveformPeaks.kt`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/AudioToolsChannel.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/MainActivity.kt` (register the channel)
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/audio/WaveformPeaksTest.kt`, `.../audio/ExtractPlanTest.kt`

**Interfaces:**
- Consumes: `AacFileEncoder`, `PcmFrames` (Task 2); `PcmAudioSource` (export, existing: `open()`, `read(dest, offset, frames)`, `release()`).
- Produces (channel `slimshot_ai/audio_tools`, all work off the main thread):
  - `extract({videoPath, outputPath})` → `{"hasSound": false}` or `{"hasSound": true, "path": String, "durationMs": Int, "remuxed": Boolean}`. Writes `outputPath + ".part"`, renames when whole, deletes the part on failure (error code `extract_failed`).
  - `peaks({path, count})` → `List<Double>`, `count` values in 0..1.
  - `internal object WaveformPeaks { fun reduce(samples: FloatArray, frames: Int, channels: Int, buckets: Int): DoubleArray }` — peak absolute value per bucket, normalised so the loudest bucket is 1.0 (all-silent input stays all 0.0).
  - `internal object ExtractPlan { fun canRemux(mime: String): Boolean }` — true for `audio/mp4a-latm` only.

- [ ] **Step 1: Failing JVM tests.** `WaveformPeaksTest`: `one bucket per requested count` (size == buckets); `the loudest bucket is 1` (a 0.5-amplitude burst in bucket 3 of 4 → `[0,0,0,1]`-shaped, max 1.0); `silence stays silent` (all 0.0, no NaN); `stereo takes the louder channel`; `fewer frames than buckets does not throw`. `ExtractPlanTest`: `AAC remuxes`; `transcodes when the codec cannot be remuxed` (`audio/3gpp`, `audio/opus`, `audio/raw`, `audio/mpeg` → false).
- [ ] **Step 2:** Run them → FAIL.
- [ ] **Step 3:** Implement `WaveformPeaks`, `ExtractPlan`, `AudioExtractor` (remux: `MediaExtractor` → `ExportMuxer` with the track's `MediaFormat`; otherwise `PcmAudioSource(path, 1.0, 44_100)` → `AacFileEncoder`; peaks via `PcmAudioSource` at a low rate, e.g. 8 kHz), and `AudioToolsChannel` (a `MethodCallHandler` like `PhotoMetadataReader`: single worker thread, results posted to the main looper). Register it in `MainActivity` beside the metadata reader and release it in `onDestroy`.
- [ ] **Step 4:** Tests PASS; `compileDebugKotlin` green.
- [ ] **Step 5: Commit** `feat(audio): take a video's sound out natively, and its waveform`.

---

### Task 4: The Dart side of audio tools, and the extract selection

**Files:**
- Create: `lib/features/audio_tools/audio_tools_service.dart`
- Create: `lib/features/audio_tools/extract_selection.dart`
- Test: `test/features/audio_tools/audio_tools_service_test.dart`, `test/features/audio_tools/extract_selection_test.dart`

**Interfaces:**
- Produces:
  - `class ExtractedSound { final String path; final double durationSeconds; }`
  - `class AudioToolsService { AudioToolsService({MethodChannel? channel}); Future<ExtractedSound?> extract({required String videoPath, required String outputPath}); Future<List<double>> peaks(String path, {int count = 200}); }` — `extract` returns null for `hasSound: false`, throws `AudioToolsException(message)` on a channel error.
  - `class ExtractSelection` (immutable): `ExtractSelection.whole(double durationSeconds)`, fields `durationSeconds`, `start`, `end`; `ExtractSelection withStart(double s)`, `withEnd(double e)` — clamped to `[0, duration]`, never closer than `kMinClipDurationSeconds` (whole sound when shorter than that).
  - `AudioTrackModel extractedTrack({required String id, required ExtractedSound sound, required ExtractSelection selection, required double playhead})` — `filePath = sound.path`, `sourceDuration = sound.durationSeconds`, `sourceStart/End` from the selection, `timelineStart = playhead`, `isSoundEffect` false.

- [ ] **Step 1: Failing tests.** Service (mock the channel with `TestDefaultBinaryMessengerBinding`): `no sound is null`; `a sound comes back with its length in seconds` (`durationMs: 1500 → 1.5`); `a channel error becomes AudioToolsException`; `peaks are returned as doubles`. Selection: `starts as the whole sound`; `the start never passes the end less the minimum`; `the end never passes the duration`; `handles never cross`; `a sound shorter than the minimum stays whole`. Track: `lands at the playhead with the selection as its trim` (`sourceStart 2, sourceEnd 5, timelineStart 7.5`, `isSoundEffect` false).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat(audio): extract service and the sheet's selection rules`.

---

### Task 5: The Extract sheet, wired to the menu

**Files:**
- Create: `lib/features/video_editor/widgets/panels/extract_audio_sheet.dart`
- Create: `lib/features/audio_tools/extract_preview_player.dart`
- Modify: `lib/screens/video_editor_screen.dart` (handler for `extract`)
- Test: `test/features/video_editor/widgets/extract_audio_sheet_test.dart`; `test/features/video_editor/widgets/editor_menu_test.dart` (add)

**Interfaces:**
- Consumes: `AudioToolsService`, `ExtractedSound`, `ExtractSelection`, `extractedTrack` (Task 4); `DraftFiles.audioDir` (Task 1).
- Produces:
  - `abstract class ExtractPreviewPlayer { Future<void> open(String videoPath); Future<void> playRange(double start, double end); Future<void> pause(); Future<void> dispose(); Widget view(); }` and `VideoPlayerExtractPreview` over `video_player` (loops the range with a position listener; plugin code, device-tested).
  - `ExtractAudioSheet({required String initialVideoPath, required Future<String?> Function() pickVideo, required Future<ExtractedSound?> Function(String videoPath) extract, required Future<List<double>> Function(String path) peaks, required ExtractPreviewPlayer player})` — pops with `({ExtractedSound sound, ExtractSelection selection})?`.
  - Screen: `_showExtractAudio()` — `MediaPickerService().pickVideo()`; nothing picked → nothing; else `showEditorSheet` at ~0.9 height; on a result, `notifier.addAudioTrack(extractedTrack(... playhead: state.currentPlaybackPosition))`. A `null` from `extract` (no sound) toasts **"This video has no sound"** and adds nothing; an `AudioToolsException` toasts its message.

- [ ] **Step 1: Failing widget tests** (fakes for extract, peaks, picker, player): `shows the video and the waveform once peaks arrive`; `dragging a handle trims and the player plays only the range`; `Done returns the sound and the selection`; `closing adds nothing`; `Change video swaps the video and resets the handles`; `cancelling Change video keeps the current video`; `a video with no sound says so and returns nothing`. Menu: `the audio menu's Extract is handled` (`source` contains `tool.id == 'extract'`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the sheet (video on top, waveform painter with two handles anchor-based like the trim handles, `Change video`, `Done`), the player, and the screen handler.
- [ ] **Step 4:** Run → PASS; full suite green; analyze 44.
- [ ] **Step 5: Commit** `feat(audio): Extract — pick a video, trim its sound, add it at the playhead`.

---

### Task 6: The voice recorder (Kotlin) and its permission

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/VoiceRecorder.kt`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/CaptureGate.kt`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/audio/VoiceRecorderChannel.kt`
- Modify: `MainActivity.kt` (register); `android/app/src/main/AndroidManifest.xml` (`<uses-permission android:name="android.permission.RECORD_AUDIO"/>`)
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/audio/CaptureGateTest.kt`

**Interfaces:**
- Consumes: `AacFileEncoder` (Task 2).
- Produces (channel `slimshot_ai/voice_recorder`):
  - `open({outputPath})` → `{"sampleRate": Int}`; starts `AudioRecord` (mono, 16-bit, 44_100 first, then 48_000, 22_050, 16_000) reading continuously on its own thread; error `recorder_unavailable` with a one-line message if none starts.
  - `setCapturing({capturing: Boolean})` → `{"capturedMs": Int}`; samples read while not capturing are dropped.
  - `close({keep: Boolean})` → `{"path": String, "durationMs": Int}` when kept and anything was captured, else `{}` (file deleted).
  - `internal class CaptureGate` — pure: `fun accept(frames: Int, capturing: Boolean): Int` (frames to write), `val capturedFrames: Long`. Flipping to capturing at a buffer boundary counts only frames read after the flip.

- [ ] **Step 1: Failing JVM tests** `CaptureGateTest`: `nothing is written before capturing starts`; `a pause drops what the mic hears`; `resumed frames add on` (`accept(1000,true); accept(500,false); accept(200,true)` → `capturedFrames == 1200`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `CaptureGate`, `VoiceRecorder` (read loop → gate → `PcmFrames` → `AacFileEncoder`; the encoder writes `<path>.part`, renamed on a kept close), the channel, the manifest permission.
- [ ] **Step 4:** Tests PASS; `compileDebugKotlin` green.
- [ ] **Step 5: Commit** `feat(audio): a voice recorder whose take starts when capture does`.

---

### Task 7: The record controller

**Files:**
- Create: `lib/features/audio_tools/voice_recorder_service.dart`
- Create: `lib/features/audio_tools/record_controller.dart`
- Test: `test/features/audio_tools/record_controller_test.dart`

**Interfaces:**
- Produces:
  - `abstract class VoiceRecorder { Future<void> open(String outputPath); Future<void> setCapturing(bool on); Future<RecordedTake?> close({required bool keep}); }`, `class RecordedTake { final String path; final double durationSeconds; }`, `class ChannelVoiceRecorder implements VoiceRecorder` (channel `slimshot_ai/voice_recorder`, `VoiceRecorderException(message)` on `recorder_unavailable`).
  - `enum RecordPhase { idle, countdown, recording, paused }`; `enum MicPermission { granted, denied, permanentlyDenied }`.
  - `class RecordController extends ChangeNotifier` with constructor parameters `VoiceRecorder recorder`, `Future<MicPermission> Function() requestMic`, `Future<String> Function() newTakePath`, `void Function() play`, `void Function() pause`, `void Function(bool muted) setMonitorMuted`, `double Function() playhead`, `double Function() projectEnd`, `Duration countdownStep = const Duration(seconds: 1)`. State: `phase`, `countdown` (3,2,1), `takeStart` (timeline seconds, null before the first capture), `takeLength`, `monitorMuted` (starts `true`), `message` (one-line notice, cleared on read via `takeMessage()`).
  - Methods: `Future<void> enter()` (sets the monitor mute); `Future<void> toggle()` (idle/paused → countdown → recording; recording → paused); `void onPlayhead(double seconds)` (grows `takeLength` while recording; at or past `projectEnd` pauses); `void toggleMonitor()`; `Future<RecordedTake?> finish()` (Done: pause, close keeping, restore monitor, null when nothing captured); `Future<void> discard()` (✕: close not keeping, restore monitor).
  - Order inside `toggle` on resume: recorder already open → countdown → `setCapturing(true)` → `play()`. On pause: `pause()` → `setCapturing(false)`.

- [ ] **Step 1: Failing tests** (fake recorder records calls; fake clock via `fakeAsync`): `entering mutes the preview, leaving restores it`; `muting never touches the project's mute` (no `setMuted` reachable — assert only `setMonitorMuted` called); `the toggle unmutes and mutes again`; `first record asks for the mic`; `a refused mic says how to allow it and stays idle`; `a permanently refused mic says to open Settings`; `a recorder that will not open says so and stays idle`; `countdown runs 3-2-1 before capturing` (no `setCapturing(true)` and no `play()` before 3 steps); `capture starts before playback`; `pause stops playback then capture`; `one take across pauses` (one `open`, one `close`); `takeStart is the playhead when capture first began`; `reaching the end pauses`; `at the end already it says to move back and does not start` (message **"Move the playhead back to record over your video"**); `Done with nothing recorded adds nothing`; `Done returns the take`; `✕ keeps nothing`.
- [ ] **Step 2:** `flutter test test/features/audio_tools/record_controller_test.dart` → FAIL.
- [ ] **Step 3:** Implement the service and the controller.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat(audio): the recording mode's rules`.

---

### Task 8: Recording mode in the editor

**Files:**
- Create: `lib/features/video_editor/widgets/panels/record_panel.dart`
- Modify: `lib/features/video_editor/widgets/timeline/scrollable_timeline.dart` (recording mode)
- Modify: `lib/features/video_editor/services/audio_player_manager.dart` (monitor mute)
- Modify: `lib/screens/video_editor_screen.dart` (`record` handler, panel case, ✕/✓/dismissal, monitor mute wiring)
- Test: `test/features/video_editor/widgets/record_panel_test.dart`, `test/features/video_editor/widgets/timeline_recording_mode_test.dart`, `test/features/video_editor/services/audio_player_monitor_mute_test.dart`; add the panel to `tool_panel_sizing_test.dart`; `editor_menu_test.dart` (add)

**Interfaces:**
- Consumes: `RecordController`, `RecordPhase`, `ChannelVoiceRecorder` (Task 7); `DraftFiles.audioDir` (Task 1); `NativeTimelinePreviewService.setVolume` (existing).
- Produces:
  - `RecordPanel({required RecordController controller})` — the round button (record glyph idle/paused, pause glyph recording) with a pulsing `AppColors.primaryStart` ring while recording, the countdown number over it, and a speaker toggle (`LucideIcons.volume2` / `volumeX`).
  - `ScrollableTimeline.recordingTake` (`({double start, double length})?`): non-null → only the clip track is drawn (no lane gutter, no overlay/audio lanes), a take bar from `start` for `length` under the thumbnails, and scrubbing ignored.
  - `double AudioPlayerManager.effectiveVolume(AudioTrackModel track)` and `set monitorMuted(bool)` — every volume the manager sets goes through `effectiveVolume`, which is 0 while monitor-muted.
  - Screen: `record` → if the playhead is at the project end the controller's message is shown and nothing opens; else `setActiveTool('record')` with a `RecordController` whose `setMonitorMuted` calls `_nativePreviewService.setVolume(muted ? 0 : 1)` and `_audioPlayerManager.monitorMuted = muted`, whose `play`/`pause` drive the editor's own playback, whose `onPlayhead` is fed from position updates. ✓ **and every keeping dismissal** (Back, side tap, empty timeline) → `finish()` → `addAudioTrack` at `takeStart`; ✕ → `discard()`. The panel header label is "Record".

- [ ] **Step 1: Failing tests.** Panel: `idle shows record`; `recording shows pause with a pulsing ring`; `the countdown shows its number`; `the speaker toggle flips the monitor`. Timeline: `recording mode hides every lane but the clips`; `the take is drawn from its start for its length`; `a drag does not scrub while recording`. Music: `monitor mute silences every track and lifting it restores their volumes`. Screen/menu: `the audio menu's Record is handled`; `dismissing the record panel keeps the take` (a dismissal routes to `finish`, not `discard` — test the dismissal helper the screen calls). `tool_panel_sizing_test`: the record panel lays out unbounded.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS; full suite green; analyze 44; `compileDebugKotlin` green.
- [ ] **Step 5: Commit** `feat(audio): Record — a voiceover mode with record, pause and a muted monitor`.

---

### Task 9: Notes and the finished branch

**Files:**
- Modify: `CLAUDE.md` (a section "Audio — Extract and Record", awaiting device verification), `docs/roadmap.md` if it lists these tools.

- [ ] **Step 1:** Write the section: the file folder, remux vs transcode, the capture gate and why it is not `MediaRecorder`, monitor mute vs `isMuted`, recording mode hiding lanes, the device checks (a clap recorded lands on its frame; an AAC and a non-AAC video both extract; an extracted song plays in preview and export).
- [ ] **Step 2:** Full `flutter test`, analyze 44, `testDebugUnitTest`, `compileDebugKotlin` → all green.
- [ ] **Step 3: Commit** `docs(audio): Extract and Record`.
- [ ] **Step 4:** Self-review of the whole branch against the spec (no subagents); fix Critical/Important findings test-first; report rulings and deferred minors to the owner.
