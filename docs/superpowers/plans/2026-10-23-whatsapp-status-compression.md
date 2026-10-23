# WhatsApp Status compression — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Compress video screen's switch, renamed **WhatsApp Status**, makes a file already in the shape WhatsApp Status keeps — so posting it with HD on stays as clear as an Instagram round trip.

**Architecture:** The probe becomes a pure parse of ffprobe's JSON into a richer `VideoMetadata`. A pure `statusPlan(VideoMetadata)` decides the output (size, frame rate, tone-map, audio, or copy-only), a pure `statusCommand` turns a plan into the FFmpeg arguments, and the service picks a job (`keep the original` / `run this command`) through one testable method. The screen dims what the switch overrides, and the result names what was applied.

**Tech Stack:** Flutter/Dart, Riverpod, `ffmpeg_kit_flutter_new` (full-gpl: x264, zimg).

**Spec:** `docs/superpowers/specs/2026-10-23-whatsapp-status-compression-design.md`

**Branch:** `feat/whatsapp-status-compression`, cut from `main` (the timing work stays on its own branch). Commit the spec there first.

## Global Constraints

- Output box: short side ≤ 720 **and** long side ≤ 1280, aspect kept, both sides even, never larger than the source; a square fits 720×720.
- Frame rate constant: 60 → 30, 50 → 25, otherwise the source's rate capped at 30.
- Video: `libx264 -preset medium -profile:v high -level 3.1 -pix_fmt yuv420p`, CRF 21, `maxrate` = `kStatusMaxVideoKbps` (provisional **2000**), `bufsize` = twice it, tagged BT.709.
- HDR = colour transfer `smpte2084` (PQ) or `arib-std-b67` (HLG) → tone-mapped to SDR BT.709 first; 10-bit SDR → simply 8-bit.
- Mild `hqdn3d` before scaling; Lanczos scaling; square pixels out.
- Audio: AAC-LC 128 kbps, 44.1 kHz; > 2 channels → stereo, mono stays mono, no track stays none.
- MP4, `-movflags +faststart`, rotation applied to the pixels, the metadata switch respected.
- Already status-ready → `-c copy` (metadata stripped if the switch is on), never the untouched original.
- In this mode the output is kept even when larger than the input.
- Copy: switch label **"WhatsApp Status"**; note under it **"Overrides quality and format"**. No tip line about WhatsApp's HD option (the owner's call).
- Colours from `AppColors`; `flutter analyze --no-pub` stays at 44; tests first, each watched failing.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- A phone video stored sideways (coded 1920×1080, rotation −90) must come out 720×1280 portrait, and is never "ready" for copy — Task 2.
- A probe that fails (no metadata) must still give a status-shaped file, not the old "assume 1920×1080" default — Task 4.
- A video with no sound track must encode (`-an`), not fail on a missing stream — Task 3.
- WebM chosen before the switch was turned on must still produce an `.mp4` — Task 4.
- A small source (e.g. 320×240, or odd 641×361) is never enlarged, and stays even — Task 2.

---

### Task 1: The probe reads what the plan needs

**Files:**
- Modify: `lib/features/compression/logic/compression_presets.dart` (`VideoMetadata`)
- Modify: `lib/features/compression/services/video_compression_service.dart` (`getVideoMetadata`)
- Test: `test/features/compression/logic/video_metadata_probe_test.dart`

**Interfaces:**
- Produces: `VideoMetadata` gains, all with defaults so every existing constructor call compiles: `double frameRate = 0` (`r_frame_rate`), `double avgFrameRate = 0` (`avg_frame_rate`), `int bitDepth = 8`, `String? colorTransfer`, `int rotation = 0` (degrees, normalised to 0/90/180/270), `String? audioCodec`, `int audioChannels = 0`; getters `int get displayWidth`, `int get displayHeight` (swapped at 90/270). `factory VideoMetadata.fromProbe(Map<String, dynamic> json)` over ffprobe's `{streams: [...], format: {...}}` shape; returns a metadata with width 0 when there is no video stream.

- [ ] **Step 1: Write the failing tests** — `fromProbe` on hand-written maps:
  - `'reads a phone video stored sideways'`: video stream `{codec_type: video, codec_name: h264, width: 1920, height: 1080, r_frame_rate: '30/1', avg_frame_rate: '30/1', pix_fmt: 'yuv420p', side_data_list: [{side_data_type: 'Display Matrix', rotation: -90}], bit_rate: '9000000'}` → `rotation == 270` (or 90; pin whichever normalisation you choose), `displayWidth == 1080`, `displayHeight == 1920`, `bitrateKbps == 9000`, `frameRate == 30`.
  - `'an older file's rotate tag counts too'`: `tags: {rotate: '90'}` → `rotation == 90`.
  - `'HDR and bit depth'`: `pix_fmt: 'yuv420p10le', color_transfer: 'arib-std-b67'` → `bitDepth == 10`, `colorTransfer == 'arib-std-b67'`.
  - `'fractional and variable rates'`: `r_frame_rate: '30000/1001'` → `frameRate` ≈ 29.97; `avg_frame_rate: '0/0'` → `avgFrameRate == 0`.
  - `'audio stream'`: `{codec_type: audio, codec_name: aac, channels: 6}` → `audioCodec == 'aac'`, `audioChannels == 6`; no audio stream → `audioCodec == null`, `audioChannels == 0`.
  - `'falls back to the container bitrate and duration'`: no stream `bit_rate`, `format: {bit_rate: '2400000', duration: '35.5'}` → `bitrateKbps == 2400`, `durationSecs == 35.5`.

- [ ] **Step 2: Run** `flutter test test/features/compression/logic/video_metadata_probe_test.dart` — Expected: FAIL, `fromProbe` not defined.

- [ ] **Step 3: Implement** `VideoMetadata.fromProbe` and the fields; `getVideoMetadata` becomes `VideoMetadata.fromProbe(information.getAllProperties() ?? {})`, returning null when width is 0 (as today when there is no video stream). Numbers in ffprobe JSON arrive as strings or numbers — read both.

- [ ] **Step 4: Run** the new test and `flutter test test/features/compression` — Expected: PASS.

- [ ] **Step 5: Commit** — `feat(compress): the probe reads frame rate, colour, rotation and sound`

---

### Task 2: The status plan

**Files:**
- Create: `lib/features/compression/logic/status_plan.dart`
- Test: `test/features/compression/logic/status_plan_test.dart`

**Interfaces:**
- Consumes: `VideoMetadata` (Task 1).
- Produces:
  - `const int kStatusMaxVideoKbps = 2000;` (doc comment: provisional, set by the measurement in the spec), `const int kStatusCrf = 21;`, `const String kStatusX264Preset = 'medium';`
  - `class StatusPlan { final bool copyOnly; final int? width; final int? height; final double frameRate; final bool toneMap; final int audioChannels; }` — `width`/`height` null when the source size is unknown; `audioChannels` 0 means no audio.
  - `StatusPlan statusPlan(VideoMetadata? source)` — null source → `StatusPlan(copyOnly: false, width: null, height: null, frameRate: 30, toneMap: false, audioChannels: 2)`.
  - `double statusFrameRate(double source)` — exposed for its own tests.

- [ ] **Step 1: Write the failing tests**:
  - Size: 1080×1920 → 720×1280; 1920×1080 → 1280×720; 3840×2160 → 1280×720; 720×1612 → 572×1280; 1080×1080 → 720×720; 1079×1919 → 720×1280; 640×360 → 640×360; 320×240 → 320×240; 641×361 → 640×360; coded 1920×1080 with rotation 90 → 720×1280.
  - Frame rate (`statusFrameRate`): 60 → 30; 59.94 → 29.97 (±0.01); 50 → 25; 48 → 24; 120 → 30; 33 → 30; 30 → 30; 25 → 25; 24 → 24; 0 → 30. The plan uses `avgFrameRate` when it is above 0, else `frameRate`.
  - Tone-map: `colorTransfer` `smpte2084` → true; `arib-std-b67` → true; `bt709` with 10-bit → false.
  - Audio: channels 6 → 2; 1 → 1; 0 / no codec → 0.
  - Copy-only — true for: h264, aac, 720×1280, 30/30 fps, 8-bit, bt709, rotation 0, 1800 kbps. Then false when each one changes alone: hevc; opus audio; 1080×1920; frame rate 60; `frameRate` 30 with `avgFrameRate` 27 (variable); 10-bit; HLG; rotation 90; 2500 kbps; bitrate 0 (unknown). No audio stream (codec null) and otherwise ready → true.
  - Null source → the default plan above.

- [ ] **Step 2: Run** `flutter test test/features/compression/logic/status_plan_test.dart` — Expected: FAIL, file missing.

- [ ] **Step 3: Implement** `statusPlan` and `statusFrameRate` in `status_plan.dart`.
  - Size: box (1280, 720) for landscape (`displayWidth > displayHeight`), else (720, 1280); `scale = min(1, boxW/w, boxH/h)`; each side is the nearest even number to `side × scale`, then held to ≤ the box and ≤ the source's even floor.
  - Frame rate: the largest `source / n` (integer n ≥ 1) that is ≤ 30 and ≥ 24; failing that, `min(source, 30)`; 0 → 30.
  - Variable means `frameRate` and `avgFrameRate` both above 0 and more than 0.5 apart.

- [ ] **Step 4: Run** the test — Expected: PASS.

- [ ] **Step 5: Commit** — `feat(compress): a status plan decides size, rate, colour and sound`

---

### Task 3: The command a plan runs

**Files:**
- Modify: `lib/features/compression/logic/status_plan.dart`
- Test: `test/features/compression/logic/status_command_test.dart`

**Interfaces:**
- Consumes: `StatusPlan`, the constants (Task 2).
- Produces: `String statusCommand(StatusPlan plan, {required String input, required String output, required bool removeMetadata})` — FFmpegKit argument string, input and output double-quoted like `_buildCommand`.

- [ ] **Step 1: Write the failing tests** (assert on substrings and their order, not the whole string):
  - Re-encode of a 720×1280, 30 fps, stereo plan: contains `-map 0:v:0`, `-map 0:a:0?`, `-c:v libx264 -preset medium -profile:v high -level 3.1 -pix_fmt yuv420p -crf 21 -maxrate 2000k -bufsize 4000k`, `-color_primaries bt709 -color_trc bt709 -colorspace bt709`, `-c:a aac -b:a 128k -ar 44100 -ac 2`, `-movflags +faststart`; ends with `"<output>"`.
  - The `-vf` chain is, in order: `hqdn3d=`, `scale=720:1280:flags=lanczos`, `setsar=1`, `fps=30`, `format=yuv420p`.
  - `toneMap: true` → the chain *begins* with `zscale=t=linear`, contains `tonemap=tonemap=hable`, and its `zscale=t=bt709:m=bt709:r=tv` comes before `hqdn3d`.
  - Unknown size (`width: null`) → `scale=` uses `force_original_aspect_ratio=decrease` and `force_divisible_by=2` with the 720/1280 bounds chosen by `gte(iw,ih)`, and still never upscales (`min(…,iw)`/`min(…,ih)`).
  - `fps=29.97` for a 29.97 plan (no float noise like `29.970000001`).
  - `audioChannels: 0` → contains `-an`, no `-c:a`.
  - `removeMetadata: true` → `-map_metadata -1`; false → absent.
  - `copyOnly: true` → `-c copy -movflags +faststart`, no `-vf`, no `libx264`; with `removeMetadata` it still carries `-map_metadata -1`.

- [ ] **Step 2: Run** `flutter test test/features/compression/logic/status_command_test.dart` — Expected: FAIL, `statusCommand` not defined.

- [ ] **Step 3: Implement** `statusCommand`. Tone-map chain (FFmpeg's standard HDR→SDR):
  ```
  zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p
  ```
  Denoise `hqdn3d=1.5:1.5:6:6` (mild; the builder may tune within "mild").

- [ ] **Step 4: Run** the test — Expected: PASS.

- [ ] **Step 5: Commit** — `feat(compress): a status plan becomes one FFmpeg command`

---

### Task 4: The service runs the WhatsApp Status job

**Files:**
- Modify: `lib/features/compression/services/video_compression_service.dart`
- Test: `test/features/compression/services/video_compression_job_test.dart`

**Interfaces:**
- Consumes: `statusPlan`, `statusCommand` (Tasks 2–3), `VideoMetadata` (Task 1).
- Produces:
  - `sealed class VideoJob`; `class KeepOriginal extends VideoJob`; `class RunFfmpeg extends VideoJob { final String command; final bool keepIfLarger; }`.
  - `VideoJob jobFor({required String inputPath, required String outputPath, required CompressionPreset preset, required VideoMetadata? metadata, required bool whatsAppStatus, required bool removeMetadata, required String targetFormat})` — a public method on `VideoCompressionService`, pure (no FFmpeg call).
  - `String outputExtension({required bool whatsAppStatus, required String targetFormat})` — `'mp4'` whenever `whatsAppStatus`.

- [ ] **Step 1: Write the failing tests**:
  - WhatsApp Status, 1080×1920 metadata → `RunFfmpeg` whose command contains `scale=720:1280` and `keepIfLarger == true`.
  - WhatsApp Status, ready metadata (as Task 2's ready case) → `RunFfmpeg` whose command contains `-c copy`; never `KeepOriginal`.
  - WhatsApp Status with `best_quality` preset and metadata whose `isAlreadyOptimized` is true → still `RunFfmpeg` (the preset skip does not apply).
  - WhatsApp Status, `metadata: null` → `RunFfmpeg` with `force_original_aspect_ratio=decrease` (no assumed 1920×1080).
  - WhatsApp Status with `targetFormat: 'webm'` → command has no `libvpx`; `outputExtension(whatsAppStatus: true, targetFormat: 'webm') == 'mp4'`.
  - Switch off, `best_quality`, already optimized → `KeepOriginal`; switch off, `smart` → `RunFfmpeg` with `-preset superfast -crf 26` and `keepIfLarger == false` (today's behaviour unchanged).

- [ ] **Step 2: Run** `flutter test test/features/compression/services/video_compression_job_test.dart` — Expected: FAIL, `jobFor` not defined.

- [ ] **Step 3: Implement** `jobFor` and `outputExtension`; `compressVideo` uses them: `KeepOriginal` → return `inputPath`; the output path's extension from `outputExtension`; the "output ≥ input → original" swap only when `!keepIfLarger`. The old `whatsAppOptimize` branch inside `_buildCommand` and `_shouldDownscaleForWhatsapp` are deleted. `compressVideo`'s parameter keeps its name `whatsAppOptimize` (the provider's field is not renamed).

- [ ] **Step 4: Run** the test and `flutter test test/features/compression` — Expected: PASS.

- [ ] **Step 5: Commit** — `feat(compress): WhatsApp Status compresses to the shape Status keeps`

---

### Task 5: The switch overrides quality and format on screen

**Files:**
- Modify: `lib/features/compression/widgets/compress_panels.dart` (`CompressSwitchRow` gains `note`)
- Modify: `lib/features/compression/widgets/compress_video_view.dart`
- Test: `test/features/compression/widgets/compress_video_view_test.dart`

**Interfaces:**
- Produces: `CompressSwitchRow({..., String? note})` — a second line under the label in `AppColors.textSecondary`, 12 px. The quality group and the format row are wrapped so that, with the switch on, they draw at reduced opacity and ignore taps (one private widget, keyed `compress_overridden_quality` and `compress_overridden_format`).

- [ ] **Step 1: Write the failing tests** (add a `whatsApp` flag to the file's `_state` helper):
  - `'the switch is called WhatsApp Status'` → `find.text('WhatsApp Status')` one, `'WhatsApp ready'` none.
  - `'on, it overrides quality and format'`: `find.text('Overrides quality and format')` one; tapping `compress_preset_best_quality` leaves `calls.presets` empty; tapping `compress_format_webm` leaves `calls.formats` empty; an `Opacity` above each overridden block has opacity < 1.
  - `'off, quality and format answer as before'`: the note absent; both taps reach their callbacks.
  - The existing `320 px at 1.3× text, no overflow` test, run with the switch on as well.

- [ ] **Step 2: Run** `flutter test test/features/compression/widgets/compress_video_view_test.dart` — Expected: the new tests FAIL.

- [ ] **Step 3: Implement** the label, the note (only while on) and the override wrapper.

- [ ] **Step 4: Run** the test file — Expected: PASS.

- [ ] **Step 5: Commit** — `feat(compress): the WhatsApp Status switch overrides quality and format`

---

### Task 6: The result names what was applied; notes

**Files:**
- Modify: `lib/screens/result_screen.dart`
- Modify: `CLAUDE.md` (the "Compress video" section)
- Test: `test/features/compression/logic/compress_labels_test.dart`

**Interfaces:**
- Produces: `String resultQualityLabel({required bool whatsAppStatus, required String? presetName})` and `String resultFormatName({required bool isVideo, required bool whatsAppStatus, required String videoFormat, required String imageFormat})` in `lib/features/compression/logic/compress_labels.dart`; `result_screen.dart` passes them to `CompressResultView`'s `quality` and `format`.

- [ ] **Step 1: Write the failing tests**: `resultQualityLabel(whatsAppStatus: true, presetName: 'Smart') == 'WhatsApp Status'`; false → `'Smart'`; `resultFormatName(isVideo: true, whatsAppStatus: true, videoFormat: 'webm', ...) == 'MP4'`; switch off → `formatName('webm')`'s answer; a photo ignores the switch.

- [ ] **Step 2: Run** `flutter test test/features/compression/logic/compress_labels_test.dart` — Expected: the new tests FAIL.

- [ ] **Step 3: Implement** the two functions and the screen's wiring; add a "WhatsApp Status" paragraph to CLAUDE.md's Compress video section: the evidence (720×1280 clear, 1080×1920 blurred), the rule, copy-not-encode for ready files, the provisional ceiling awaiting measurement, no HD tip by the owner's call, **awaiting device verification**, and that the editor's export follows once confirmed.

- [ ] **Step 4: Verify the whole branch** — `flutter test` (all pass), `flutter analyze --no-pub` (44 issues).

- [ ] **Step 5: Commit** — `feat(compress): the result names WhatsApp Status`

---

**After the plan (not code):** the measurement in the spec — the owner's camera clip, FFmpeg on this computer (ask first), the variants, the delivered copies — sets `kStatusMaxVideoKbps`, a one-line change with its findings beside it.
