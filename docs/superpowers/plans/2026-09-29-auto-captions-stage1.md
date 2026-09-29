# Auto Captions — Stage 1 (Generate) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Text → Auto captions turns the project's own sound into word-timed captions on a caption lane, in sync through trims, speed and transitions, and exports them correctly.

**Architecture:** The native export mixer renders the chosen sources as mono 16 kHz AAC from timeline 0, so the server's word times are timeline times with no conversion. A Dart pipeline renders, uploads through a new `SlimshotApi` client, polls, rebuilds spacing, groups words into captions, and the notifier places them as ordinary text overlays carrying their words. Two export gaps a long caption set would hit — textures never freed, fonts never awaited — are closed, and an existing double-mix of video-overlay sound is fixed on the way.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, Riverpod `StateNotifier`, `package:http` (+ `http/testing` `MockClient`), `http_parser`, `shared_preferences`, `uuid`; Kotlin, MediaCodec, Media3 `Mp4Muxer`, JUnit 4.

**Spec:** `docs/superpowers/specs/2026-09-29-auto-captions-design.md` (Stage 1 sections: Data model, Stage 1 — Generate, Persistence, Testing).

## Global Constraints

- Work on branch `feat/auto-captions`. Never commit to `main`, never push, never merge — the user device-tests, merges and pushes.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `flutter analyze --no-pub` must report **exactly 48 issues** after every task. `flutter_lints` counts `prefer_const_constructors` / `prefer_const_literals_to_create_immutables`: add `const` wherever the analyzer asks, in tests too.
- Kotlin unit tests are pure JVM (JUnit 4 only). Nothing touching the Android framework goes in `android/app/src/test`.
- Colours from `AppColors`; never `color: Colors.white` or `Colors.white54` in `widgets/panels/` (`panel_theme_test.dart`); `Colors.white24` only for a grab handle; no `fontSize: 13` + `FontWeight.w600` on one line in panels.
- Sheets open through `showEditorSheet`; a sheet does not repeat the tool's name as a title.
- Undo: `saveStateForUndo()` before a structural edit; one user action = one undo step.
- Serialisation is hand-written and defensive on read; new keys are omitted when absent so old drafts are byte-identical.
- User-facing copy, exactly: tool `Auto captions`; sections `Source` / `Language` / `Length`; sources `Video sound` / `Audio tracks` / `All`; `Auto detect`; lengths `Word` / `Phrase` / `Line`; button `Generate`; stages `Preparing audio` / `Uploading` / `Listening` / `Placing captions`; `Cancel`, `Try again`, `Close`; dialog `Replace captions?` with `Cancel` / `Replace`; error lines exactly as in Task 10.
- Server contract: `POST /api/app/v1/devices` `{platform}` → `data.token`; `POST /api/app/v1/captions` multipart field `audio` (`audio/mp4`), optional field `language` (two lowercase letters), header `Idempotency-Key` (8–64 `[A-Za-z0-9_-]`); `GET /api/app/v1/captions/{jobId}` → `status` `queued|processing|completed|failed`, `pollAfterMs`, `result {provider, language, durationSeconds, text, words[{text,start,end,confidence}]}`, `error {code,message}`. Envelope `{success:true,data}` / `{success:false,error:{code,message,traceId}}`.
- The server address comes only from `--dart-define=SLIMSHOT_API_URL=…`; without it the tool is not shown.

## Review Focus

1. **Provider word times that overlap or run backwards** — two captions must never overlap on the lane, and every caption must have a length. Test in Task 8.
2. **A punctuation-only token** (`—`, a closing quote) — never a caption of its own, even straight after a sentence ends. Test in Task 8.
3. **A device token refused again after re-registering** — one retry, then an error; never a loop of registrations. Test in Task 9.
4. **Caption word offsets out of reach of the text** (a hand-edited or corrupt draft) — clamped or dropped on read, never thrown. Test in Task 5.
5. **Regenerating over an existing set** — the old set is removed before a lane is chosen, plain text is kept, and the new set is the only one. Test in Task 12.

## Rulings made while writing this plan (against the spec)

- **No separate 0.3s minimum.** A caption ends at its last word's end plus up to 0.4s, capped only at the next caption's start — so it is under 0.3s only when the next caption starts within 0.3s, where there is no room to extend it anyway. The spec's minimum is already implied; `kMinCaptionSeconds` is not built. Cost if wrong: one constant and a test.
- **`boxWidth` stays null** instead of 85% of the canvas. Every caption shares one `referenceCanvasSize`, so every caption already wraps at the same width (`reference width − kDefaultTextBoxMargin`); a fixed `boxWidth` would also stretch a boxed caption style's background across the full width in Stage 4. Cost if wrong: set one field in `buildCaptionOverlays`.
- **Cancel aborts the upload by closing the HTTP client** (`SlimshotApi.close()`); `package:http` 1.2 has no per-request abort.
- **Reversed clips are skipped inside the mixer** (`MixConfig.skipsReversedClips`), not filtered out of its clip list: the mixer resolves transition crossfades by clip **index**, so a filtered list would fade the wrong clips.
- **Existing bug fixed in Task 2:** since `7c1828b`, a video overlay's sound reached the export twice — once as an audio track at 1× (`NativeTimelinePreviewManager.startExport`'s `overlayAudio`) and once through the mixer's `overlays` at its own speed: double volume at 1×, two voices out of step at any other speed. Caption audio uses the same mixer and the same parsing, so it is fixed here.

---

## File map

| File | Responsibility |
| :--- | :--- |
| `android/.../export/MixConfig.kt` (new) | Rate, channels, bit rate, gain rule, reversed-clip rule; PCM writing incl. mono downmix |
| `android/.../export/AudioExportMixer.kt` | Reads `MixConfig` instead of constants |
| `android/.../export/TimelineAudioTracks.kt` (new) | Imported tracks from a composed timeline — and only those |
| `android/.../export/CaptionAudioSources.kt` (new) | Which sounds a caption pass mixes and how long it runs |
| `android/.../export/CaptionAudioRenderer.kt` (new) | Mixer → `ExportMuxer`, one audio track, cancellable |
| `android/.../nativepreview/gl/ExpiredStills.kt` (new) | Which still textures an export may free |
| `android/.../nativepreview/gl/OverlayRenderer.kt` | `releaseImageTexture(path)` |
| `android/.../nativepreview/gl/OverlayDrawBuilder.kt` | Frees expired stills in export |
| `android/.../nativepreview/NativeTimelinePreviewManager.kt` | `renderCaptionAudio` / `cancelCaptionAudio`; export uses `TimelineAudioTracks` |
| `lib/features/video_editor/logic/captions/caption_word.dart` (new) | `CaptionWord` |
| `lib/features/video_editor/logic/captions/caption_settings.dart` (new) | `CaptionSource`, `CaptionLength`, `CaptionSettings`, `kCaptionLanguages` |
| `lib/features/video_editor/logic/captions/caption_transcript.dart` (new) | `TranscriptWord`, `CaptionTranscript`, `SpacedWord`, `rebuildTranscriptSpacing` |
| `lib/features/video_editor/logic/captions/caption_grouping.dart` (new) | `CaptionDraft`, `groupCaptionWords` |
| `lib/features/video_editor/logic/captions/caption_placement.dart` (new) | `captionDefaultTemplate`, `buildCaptionOverlays` |
| `lib/features/video_editor/models/text_overlay_model.dart` | `captionSetId`, `captionWords`, `isCaption` |
| `lib/features/video_editor/models/video_editor_state.dart` | `captionSettings`, `hasCaptions` |
| `lib/core/models/draft_project.dart` | `captionSettings` map |
| `lib/core/services/slimshot_api.dart` (new) | `SlimshotApi`, `SlimshotApiException`, `DeviceTokenStore`, `PrefsDeviceTokenStore` |
| `lib/features/video_editor/services/caption_audio_result.dart` (new) | `CaptionAudioResult`, `CaptionAudioCancelled` |
| `lib/features/video_editor/services/caption_errors.dart` (new) | `CaptionCancelled`, `CaptionFailure`, `kCaptionPollTimeout`, `captionErrorMessage` |
| `lib/features/video_editor/services/caption_service.dart` (new) | `CaptionJobStart`, `CaptionService` (upload, poll) |
| `lib/features/video_editor/services/caption_pipeline.dart` (new) | `CaptionStage`, `CaptionRequest`, `CaptionPipeline` |
| `lib/features/video_editor/services/caption_access.dart` (new) | `CaptionAccess.ensureAllowed` — the sign-in hook |
| `lib/features/video_editor/services/native_timeline_preview_service.dart` | `renderCaptionAudio`, `cancelCaptionAudio`, fonts awaited before export |
| `lib/features/video_editor/providers/video_editor_notifier.dart` | `placeCaptions`; draft save/load of `captionSettings` |
| `lib/features/video_editor/widgets/timeline/lane_gutter_icons.dart` (new) | `laneGutterIcons` |
| `lib/features/video_editor/widgets/timeline/scrollable_timeline.dart` | Gutter reads `laneGutterIcons` |
| `lib/features/video_editor/widgets/panels/caption_sheet_parts.dart` (new) | `SheetGrabHandle`, `SheetActionButton`, `CaptionPillRow` |
| `lib/features/video_editor/widgets/panels/auto_caption_sheet.dart` (new) | Source / Language / Length / Generate |
| `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart` (new) | Stages, Cancel, error + Try again |
| `lib/features/video_editor/widgets/panels/replace_captions_dialog.dart` (new) | `confirmReplaceCaptions` |
| `lib/features/video_editor/logic/toolbar_visibility.dart` | `hasCaptionServer` rule |
| `lib/screens/video_editor_screen.dart` | `_textMenu` entry, handler, `_startAutoCaptions` |
| `android/app/src/debug/AndroidManifest.xml` | Cleartext for the LAN test server, debug only |
| `pubspec.yaml` | `http_parser` as a direct dependency |
| `CLAUDE.md` | The Stage 1 section |

`android/...` = `android/app/src/main/kotlin/com/techfamz/slimshotai`. Kotlin tests live under `android/app/src/test/kotlin/com/techfamz/slimshotai/`.

---

### Task 1: `MixConfig` — the mixer's settings as a value

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/MixConfig.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/AudioExportMixer.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/export/MixConfigTest.kt`

**Interfaces:**
- Produces: `internal data class MixConfig(sampleRate: Int, channels: Int, bitRate: Int, unityGain: Boolean, skipsReversedClips: Boolean)` with `gain(level: Double, crossfade: Double = 1.0): Double`, `writePcm(mix: FloatArray, frames: Int, out: ShortArray): Int`, `MixConfig.EXPORT`, `MixConfig.CAPTIONS`. `AudioExportMixer(..., durationSeconds: Double, config: MixConfig = MixConfig.EXPORT)`.

- [ ] **Step 1: Write the failing test**

```kotlin
package com.techfamz.slimshotai.export

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The mixer's settings. The export keeps exactly what it had; captions are the
 * same mix, mono at 16 kHz, every source at full level.
 */
class MixConfigTest {

    @Test
    fun `the export keeps exactly the settings it had`() {
        assertEquals(MixConfig(44_100, 2, 128_000, unityGain = false, skipsReversedClips = false), MixConfig.EXPORT)
    }

    @Test
    fun `captions are mono 16 kHz at full level, without reversed speech`() {
        assertEquals(MixConfig(16_000, 1, 48_000, unityGain = true, skipsReversedClips = true), MixConfig.CAPTIONS)
    }

    @Test
    fun `the export multiplies the level into the crossfade`() {
        assertEquals(0.25, MixConfig.EXPORT.gain(level = 0.5, crossfade = 0.5), 1e-12)
    }

    @Test
    fun `unity gain ignores the level but keeps the crossfade`() {
        assertEquals(0.5, MixConfig.CAPTIONS.gain(level = 0.0, crossfade = 0.5), 1e-12)
        assertEquals(1.0, MixConfig.CAPTIONS.gain(level = 0.2), 1e-12)
    }

    @Test
    fun `stereo writes both channels`() {
        val out = ShortArray(4)
        val written = MixConfig.EXPORT.writePcm(floatArrayOf(0.5f, -0.5f, 0f, 1f), 2, out)
        assertEquals(4, written)
        assertArrayEquals(shortArrayOf(16384, -16384, 0, 32767), out)
    }

    @Test
    fun `mono is the mean of left and right`() {
        val out = ShortArray(2)
        val written = MixConfig.CAPTIONS.writePcm(floatArrayOf(0.5f, 0f, -0.25f, -0.75f), 2, out)
        assertEquals(2, written)
        assertArrayEquals(shortArrayOf(8192, -16384), out)
    }

    @Test
    fun `a sum past full scale clips instead of wrapping`() {
        val out = ShortArray(2)
        MixConfig.EXPORT.writePcm(floatArrayOf(3f, -3f), 1, out)
        assertArrayEquals(shortArrayOf(32767, -32768), out)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.export.MixConfigTest"`
Expected: FAIL — compilation error, `Unresolved reference: MixConfig`.

- [ ] **Step 3: Write `MixConfig.kt`**

```kotlin
package com.techfamz.slimshotai.export

/**
 * How a timeline mix is rendered: its rate, its channels, its bit rate, and
 * whether each source keeps the level the user set.
 *
 * The export and the caption audio are **the same mix with different
 * settings** — the caption pass runs the export's own mixer, which is why a
 * word's time in the transcript is a timeline time with no conversion.
 */
internal data class MixConfig(
    val sampleRate: Int,
    val channels: Int,
    val bitRate: Int,
    /**
     * Every source at full level: volume, its keyframes and the project mute
     * are ignored; the transition crossfade is kept, because it is timing, not
     * level. For listening rather than hearing — a muted clip's words were
     * still spoken, and recognition wants every word at full level.
     */
    val unityGain: Boolean,
    /**
     * Leaves reversed clips out. Their sound is speech played backwards —
     * nothing a transcript can put words to. Skipped inside the mixer rather
     * than filtered from its clip list, because transition crossfades find
     * their clips by index into that list.
     */
    val skipsReversedClips: Boolean,
) {
    init {
        require(channels == 1 || channels == 2) { "channels must be 1 or 2, got $channels" }
    }

    /** A source's gain: its [level] times the [crossfade], or the crossfade alone at unity. */
    fun gain(level: Double, crossfade: Double = 1.0): Double =
        if (unityGain) crossfade else level * crossfade

    /**
     * Writes [frames] frames of the stereo float [mix] into [out] as 16-bit
     * samples in this config's layout, and returns how many samples it wrote.
     * Mono is the mean of left and right.
     */
    fun writePcm(mix: FloatArray, frames: Int, out: ShortArray): Int {
        var n = 0
        for (i in 0 until frames) {
            val left = mix[i * 2]
            val right = mix[i * 2 + 1]
            if (channels == 1) {
                out[n++] = toPcm16((left + right) / 2f)
            } else {
                out[n++] = toPcm16(left)
                out[n++] = toPcm16(right)
            }
        }
        return n
    }

    companion object {
        /** The export's settings, unchanged from before this class existed. */
        val EXPORT = MixConfig(
            sampleRate = 44_100,
            channels = 2,
            bitRate = 128_000,
            unityGain = false,
            skipsReversedClips = false,
        )

        /** What speech recognition wants, at a sixth of the export's size. */
        val CAPTIONS = MixConfig(
            sampleRate = 16_000,
            channels = 1,
            bitRate = 48_000,
            unityGain = true,
            skipsReversedClips = true,
        )

        private const val PCM_16_SCALE = 32768f

        // Clip rather than wrap: summed sources can exceed full scale, and
        // wrapping turns a loud moment into a crack.
        private fun toPcm16(sample: Float): Short =
            (sample * PCM_16_SCALE)
                .coerceIn(-PCM_16_SCALE, PCM_16_SCALE - 1)
                .toInt()
                .toShort()
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.export.MixConfigTest"`
Expected: PASS, 7 tests.

- [ ] **Step 5: Make `AudioExportMixer` read the config**

In `AudioExportMixer.kt`:

1. Constructor — the last parameter becomes:

```kotlin
    private val durationSeconds: Double,
    /** Rate, channels, bit rate and gain rule — the export's unless a caller says otherwise. */
    private val config: MixConfig = MixConfig.EXPORT,
) {
```

2. In `encodeTo`, the format block becomes:

```kotlin
            val format = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                config.sampleRate,
                config.channels,
            ).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, config.bitRate)
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                )
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, BLOCK_FRAMES * config.channels * 4)
            }
```

3. The buffers and the write loop become (the mix stays stereo — `PcmAudioSource` always delivers stereo):

```kotlin
            val totalFrames = (durationSeconds * config.sampleRate).toLong()
            val mix = FloatArray(BLOCK_FRAMES * STEREO)
            val scratch = FloatArray(BLOCK_FRAMES * STEREO)
            val samples = ShortArray(BLOCK_FRAMES * STEREO)
            val pcm = ByteBuffer
                .allocateDirect(BLOCK_FRAMES * config.channels * 2)
                .order(ByteOrder.nativeOrder())
```

and, replacing the `pcm.clear()` … `pcm.flip()` block inside the loop:

```kotlin
                pcm.clear()
                val count = config.writePcm(mix, block, samples)
                for (i in 0 until count) pcm.putShort(samples[i])
                pcm.flip()
```

4. Every other `SAMPLE_RATE` becomes `config.sampleRate`: the two in `mixSource` (`blockStart`, `blockEnd`) and the one computing `t`; the timestamp in `queue`; the one in `signalEnd`; the three `PcmAudioSource(...)` constructions in `buildSources`.

5. In `buildSources`, the clip loop's first checks and gain become:

```kotlin
        for (clip in clips) {
            if (clip.isImage) {
                skipped += "${clip.id}:image"
                continue
            }
            if (config.skipsReversedClips && clip.isReversed) {
                skipped += "${clip.id}:reversed"
                continue
            }
            if (!config.unityGain && masterVolume <= 0.0) {
                skipped += "muted"
                continue
            }
```

keep the existing keyframed-volume comment and change its check to `if (!config.unityGain && !clip.volume.isAnimated && clip.volume.baseValue <= 0.0) {`, and the clip `gainAt` to:

```kotlin
                    gainAt = { t ->
                        config.gain(
                            masterVolume * clip.volumeAt(clip.clipProgressAt(t)),
                            crossfadeGain(clip, t),
                        )
                    },
```

6. The overlay loop's first line becomes two:

```kotlin
            if (!overlay.isVideo) continue
            if (!config.unityGain && !overlay.hasAudibleSound) continue
```

and its gain `gainAt = { config.gain(masterVolume * overlay.effectiveVolume) },`.

7. The track loop's first line becomes `if (!config.unityGain && track.volume <= 0.0) continue` and its gain `gainAt = { config.gain(track.volume) },`.

8. In the companion object delete `SAMPLE_RATE`, `CHANNELS`, `BIT_RATE` and `PCM_16_SCALE`, and add:

```kotlin
        /** `PcmAudioSource` always delivers stereo; [MixConfig] folds it to the output layout. */
        const val STEREO = 2
```

Under `MixConfig.EXPORT` every expression is the one it replaces: `gain(level, crossfade)` is `level * crossfade`, and every skip condition is unchanged.

- [ ] **Step 6: Run the whole Kotlin suite (it compiles the mixer too)**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL, all tests pass (the existing suite plus `MixConfigTest`).

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/export/MixConfig.kt android/app/src/main/kotlin/com/techfamz/slimshotai/export/AudioExportMixer.kt android/app/src/test/kotlin/com/techfamz/slimshotai/export/MixConfigTest.kt
git commit -m "refactor(audio): the mixer's rate, layout and gain rule become a MixConfig

The export keeps exactly its settings; the caption pass will be the same
mixer at mono 16 kHz with every source at full level.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: One reading of a timeline's tracks — and a video overlay's sound mixed once

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/TimelineAudioTracks.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelinePreviewManager.kt:66-88` (delete `parseAudioTracks`), `:172-189` (the `overlayAudio` block)
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/export/TimelineAudioTracksTest.kt`

**Interfaces:**
- Produces: `internal object TimelineAudioTracks { fun fromTimeline(timeline: Map<String, Any?>): List<AudioExportMixer.TimelineAudioTrack> }`.

- [ ] **Step 1: Write the failing test**

```kotlin
package com.techfamz.slimshotai.export

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The imported tracks a composed timeline carries — and only those.
 *
 * A video overlay's sound used to be listed here as well as reaching the mixer
 * as an overlay, so the export played it twice: double volume at 1x, two
 * voices out of step at any other speed.
 */
class TimelineAudioTracksTest {

    private fun track(vararg entries: Pair<String, Any?>) = mapOf(*entries)

    @Test
    fun `reads an imported track`() {
        val tracks = TimelineAudioTracks.fromTimeline(
            mapOf(
                "audioTracks" to listOf(
                    track(
                        "filePath" to "/m.mp3",
                        "sourceStart" to 2.0,
                        "timelineStart" to 1.0,
                        "timelineEnd" to 9.0,
                        "volume" to 0.4,
                    ),
                ),
            ),
        )
        assertEquals(listOf(AudioExportMixer.TimelineAudioTrack("/m.mp3", 2.0, 1.0, 9.0, 0.4)), tracks)
    }

    @Test
    fun `skips a track with no file or no length, and clamps the volume`() {
        val tracks = TimelineAudioTracks.fromTimeline(
            mapOf(
                "audioTracks" to listOf(
                    track("filePath" to "", "timelineEnd" to 4.0),
                    track("filePath" to "/a.mp3"),
                    track("filePath" to "/b.mp3", "timelineStart" to 5.0, "timelineEnd" to 5.0),
                    track("filePath" to "/c.mp3", "timelineEnd" to 3.0, "volume" to 7.0),
                    "junk",
                ),
            ),
        )
        assertEquals(listOf("/c.mp3"), tracks.map { it.filePath })
        assertEquals(1.0, tracks.single().volume, 0.0)
    }

    @Test
    fun `a video overlay is never read as a track`() {
        val tracks = TimelineAudioTracks.fromTimeline(
            mapOf(
                "overlays" to listOf(
                    mapOf(
                        "id" to "o",
                        "kind" to "video",
                        "path" to "/v.mp4",
                        "startSeconds" to 0.0,
                        "endSeconds" to 4.0,
                    ),
                ),
            ),
        )
        assertTrue(tracks.isEmpty())
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.export.TimelineAudioTracksTest"`
Expected: FAIL — `Unresolved reference: TimelineAudioTracks`.

- [ ] **Step 3: Write `TimelineAudioTracks.kt`** (the body is the manager's `parseAudioTracks`, moved)

```kotlin
package com.techfamz.slimshotai.export

/**
 * The imported audio tracks a composed timeline carries — **and only those**.
 *
 * A video overlay's sound is not one of them. It reaches the mixer as an
 * overlay, at its own speed, so the sound runs with the picture; the export
 * also listed it here, at 1x, and so mixed it twice — double volume at normal
 * speed, two voices out of step at any other.
 */
internal object TimelineAudioTracks {

    fun fromTimeline(timeline: Map<String, Any?>): List<AudioExportMixer.TimelineAudioTrack> {
        val raw = timeline["audioTracks"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val path = map["filePath"] as? String ?: return@mapNotNull null
            if (path.isBlank()) return@mapNotNull null

            val timelineStart = (map["timelineStart"] as? Number)?.toDouble() ?: 0.0
            val timelineEnd = (map["timelineEnd"] as? Number)?.toDouble()
                ?: return@mapNotNull null
            if (timelineEnd <= timelineStart) return@mapNotNull null

            AudioExportMixer.TimelineAudioTrack(
                filePath = path,
                sourceStart = (map["sourceStart"] as? Number)?.toDouble() ?: 0.0,
                timelineStart = timelineStart,
                timelineEnd = timelineEnd,
                volume = ((map["volume"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0),
            )
        }
    }
}
```

- [ ] **Step 4: Point the export at it and drop the second copy**

In `NativeTimelinePreviewManager.kt`:
- delete the private `parseAudioTracks` function (lines 66–88);
- in `startExport`, delete the comment and the `val overlayAudio = overlays.filter { ... }.map { ... }` block, and replace `val audioTracks = parseAudioTracks(timeline) + overlayAudio` with:

```kotlin
        // Imported tracks only. A video overlay's sound reaches the mixer
        // through `overlays`, at its own speed — listing it here as well mixed
        // it twice.
        val audioTracks = TimelineAudioTracks.fromTimeline(timeline)
```

- replace `import com.techfamz.slimshotai.export.AudioExportMixer` with `import com.techfamz.slimshotai.export.TimelineAudioTracks` (nothing else in the manager names the mixer).

- [ ] **Step 5: Run the Kotlin suite**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL. The double mix itself is proven on the device (checklist item 12): a JVM test cannot run the manager.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/export/TimelineAudioTracks.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelinePreviewManager.kt android/app/src/test/kotlin/com/techfamz/slimshotai/export/TimelineAudioTracksTest.kt
git commit -m "fix(export): a video overlay's sound is mixed once, not twice

Since the mixer learned to take overlays at their own speed, the export
also kept listing each video overlay as a 1x audio track: double volume
at normal speed, two voices out of step at any other. The timeline's
tracks now have one reader, which reads imported tracks only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The native caption audio pass

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/CaptionAudioSources.kt`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/CaptionAudioRenderer.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelinePreviewManager.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/export/CaptionAudioSourcesTest.kt`

**Interfaces:**
- Consumes: `MixConfig.CAPTIONS`, `AudioExportMixer(..., config)` (Task 1); `TimelineAudioTracks.fromTimeline` (Task 2).
- Produces: channel method `renderCaptionAudio` — args `{timeline: Map, outputPath: String, include: List<String> of "clips"|"overlays"|"tracks"}`, result `{outputPath: String, durationSeconds: Double, hasSound: Boolean}`, errors `caption_audio_cancelled`, `caption_audio_failed`, `caption_audio_busy`, `invalid_caption_audio`; events `{type: "captionAudioProgress", progress: 0..1}`; method `cancelCaptionAudio`.

- [ ] **Step 1: Write the failing test**

```kotlin
package com.techfamz.slimshotai.export

import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which of a timeline's sounds auto captions listen to, and for how long. */
class CaptionAudioSourcesTest {

    private fun clip(id: String, start: Double, end: Double, image: Boolean = false, reversed: Boolean = false) =
        NativeTimelineClip.fromMap(
            mapOf(
                "id" to id,
                "sourceVideoPath" to "/$id.mp4",
                "sourceStart" to 0.0,
                "sourceEnd" to end - start,
                "timelineStart" to start,
                "timelineEnd" to end,
                "isImage" to image,
                "isReversed" to reversed,
            ),
            "/$id.mp4",
        )!!

    private fun overlay(id: String, end: Double, kind: String = "video") =
        NativeTimelineOverlay.fromMap(
            mapOf("id" to id, "kind" to kind, "path" to "/$id.mp4", "startSeconds" to 0.0, "endSeconds" to end),
        )!!

    private val clips = listOf(clip("a", 0.0, 4.0), clip("b", 4.0, 9.0))
    private val overlays = listOf(overlay("o", 6.0), overlay("p", 12.0, kind = "image"))
    private val tracks = listOf(AudioExportMixer.TimelineAudioTrack("/m.mp3", 0.0, 0.0, 15.0, 1.0))

    @Test
    fun `the wire names the kinds of sound`() {
        assertEquals(
            CaptionAudioSources.Include(clips = true, overlays = true, tracks = false),
            CaptionAudioSources.Include.fromWire(listOf("clips", "overlays", "radio")),
        )
        assertEquals(CaptionAudioSources.Include(false, false, false), CaptionAudioSources.Include.fromWire(null))
    }

    @Test
    fun `video sound is the clips and video overlays, never the music`() {
        val chosen = CaptionAudioSources.select(
            CaptionAudioSources.Include(clips = true, overlays = true, tracks = false),
            clips, overlays, tracks,
        )
        assertEquals(listOf("a", "b"), chosen.clips.map { it.id })
        assertEquals(listOf("o"), chosen.overlays.map { it.id })
        assertTrue(chosen.tracks.isEmpty())
        assertEquals(9.0, chosen.durationSeconds, 0.0)
    }

    @Test
    fun `audio tracks alone run to the end of the music`() {
        val chosen = CaptionAudioSources.select(
            CaptionAudioSources.Include(clips = false, overlays = false, tracks = true),
            clips, overlays, tracks,
        )
        assertTrue(chosen.clips.isEmpty())
        assertEquals(15.0, chosen.durationSeconds, 0.0)
    }

    @Test
    fun `photos and reversed clips stay in the list but end nothing`() {
        // The full list travels to the mixer, which finds transition clips by
        // index; only the duration ignores what has no speech in it.
        val withSilence = clips + clip("photo", 9.0, 12.0, image = true) + clip("back", 12.0, 14.0, reversed = true)
        val chosen = CaptionAudioSources.select(
            CaptionAudioSources.Include(clips = true, overlays = false, tracks = false),
            withSilence, overlays, tracks,
        )
        assertEquals(4, chosen.clips.size)
        assertEquals(9.0, chosen.durationSeconds, 0.0)
    }

    @Test
    fun `nothing included runs for no time at all`() {
        val chosen = CaptionAudioSources.select(CaptionAudioSources.Include(false, false, false), clips, overlays, tracks)
        assertEquals(0.0, chosen.durationSeconds, 0.0)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.export.CaptionAudioSourcesTest"`
Expected: FAIL — `Unresolved reference: CaptionAudioSources`.

- [ ] **Step 3: Write `CaptionAudioSources.kt`**

```kotlin
package com.techfamz.slimshotai.export

import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay

/** Which of a timeline's sounds auto captions listen to, and for how long. */
internal object CaptionAudioSources {

    /** The kinds of sound a caption pass mixes — `clips`, `overlays`, `tracks` on the wire. */
    data class Include(val clips: Boolean, val overlays: Boolean, val tracks: Boolean) {
        companion object {
            fun fromWire(raw: Any?): Include {
                val names = (raw as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
                return Include(
                    clips = "clips" in names,
                    overlays = "overlays" in names,
                    tracks = "tracks" in names,
                )
            }
        }
    }

    data class Selection(
        /**
         * The **whole** clip list when clips are included: the mixer finds a
         * transition's two clips by index into it, so filtering here would fade
         * the wrong clips. Photos and reversed clips are skipped by the mixer.
         */
        val clips: List<NativeTimelineClip>,
        val overlays: List<NativeTimelineOverlay>,
        val tracks: List<AudioExportMixer.TimelineAudioTrack>,
        /** Where the last included sound ends; 0 when there is none. */
        val durationSeconds: Double,
    )

    fun select(
        include: Include,
        clips: List<NativeTimelineClip>,
        overlays: List<NativeTimelineOverlay>,
        tracks: List<AudioExportMixer.TimelineAudioTrack>,
    ): Selection {
        val chosenClips = if (include.clips) clips else emptyList()
        val chosenOverlays = if (include.overlays) overlays.filter { it.isVideo } else emptyList()
        val chosenTracks = if (include.tracks) tracks else emptyList()
        // A photo has no sound and a reversed clip's is backwards speech, so
        // neither is somewhere the transcript could end.
        val clipEnd = chosenClips
            .filter { !it.isImage && !it.isReversed }
            .maxOfOrNull { it.timelineEnd } ?: 0.0
        val end = maxOf(
            clipEnd,
            chosenOverlays.maxOfOrNull { it.endSeconds } ?: 0.0,
            chosenTracks.maxOfOrNull { it.timelineEnd } ?: 0.0,
        )
        return Selection(chosenClips, chosenOverlays, chosenTracks, end)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.export.CaptionAudioSourcesTest"`
Expected: PASS, 5 tests.

- [ ] **Step 5: Write `CaptionAudioRenderer.kt`** (framework code — proven on the device, compiled by the suite)

```kotlin
package com.techfamz.slimshotai.export

import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.nativepreview.NativeTimelineTransitionIntent
import java.io.File

/**
 * Renders the sound auto captions listen to: the chosen sources through the
 * export's own mixer, mono 16 kHz AAC in an M4A, starting at timeline 0.
 *
 * Starting at timeline 0 and running at timeline rate is the point: the server
 * reports word times from the start of the file, so they arrive as timeline
 * times — through trims, speed, curves and crossfades — with no conversion.
 */
@UnstableApi
internal class CaptionAudioRenderer(
    private val selection: CaptionAudioSources.Selection,
    private val transitions: List<NativeTimelineTransitionIntent>,
) {

    data class Result(
        val outputPath: String,
        val durationSeconds: Double,
        val hasSound: Boolean,
        val cancelled: Boolean = false,
    )

    @Volatile
    private var cancelled = false

    fun cancel() {
        cancelled = true
    }

    fun render(outputPath: String, onProgress: (Double) -> Unit): Result {
        val silent = Result(outputPath, 0.0, hasSound = false)
        if (selection.durationSeconds <= 0.0) return silent

        val mixer = AudioExportMixer(
            clips = selection.clips,
            audioTracks = selection.tracks,
            overlays = selection.overlays,
            masterVolume = 1.0,
            transitions = transitions,
            durationSeconds = selection.durationSeconds,
            config = MixConfig.CAPTIONS,
        )
        if (!mixer.prepare()) {
            mixer.release()
            return silent
        }

        val muxer = ExportMuxer(outputPath, expectedTracks = 1)
        try {
            mixer.encodeTo(muxer, isCancelled = { cancelled }, onProgress = onProgress)
        } finally {
            muxer.close()
        }

        if (cancelled || mixer.producedNothing) {
            File(outputPath).delete()
            return silent.copy(cancelled = cancelled)
        }
        Log.i(TAG, "caption audio: ${selection.durationSeconds}s, ${mixer.diagnostics}")
        return Result(outputPath, selection.durationSeconds, hasSound = true)
    }

    private companion object {
        const val TAG = "SlimshotExport"
    }
}
```

- [ ] **Step 6: Add the channel methods to the manager**

In `NativeTimelinePreviewManager.kt`, add imports:

```kotlin
import com.techfamz.slimshotai.export.CaptionAudioRenderer
import com.techfamz.slimshotai.export.CaptionAudioSources
```

a field next to `exportEngine`:

```kotlin
    /** The caption audio pass in flight, so Cancel can reach it. */
    private var captionAudio: CaptionAudioRenderer? = null
```

two cases in `onMethodCall`, before `"dispose"`:

```kotlin
            "renderCaptionAudio" -> {
                val timeline = call.argument<Map<String, Any?>>("timeline")
                val outputPath = call.argument<String>("outputPath")
                if (timeline == null || outputPath.isNullOrBlank()) {
                    result.error(
                        "invalid_caption_audio",
                        "Caption audio needs a timeline and an output path.",
                        null,
                    )
                    return
                }
                startCaptionAudio(
                    timeline,
                    outputPath,
                    CaptionAudioSources.Include.fromWire(call.argument<List<String>>("include")),
                    result,
                )
            }

            "cancelCaptionAudio" -> {
                captionAudio?.cancel()
                result.success(null)
            }
```

and the method, after `startExport`:

```kotlin
    /**
     * Renders the sound auto captions listen to, off the main thread.
     *
     * Audio only: the lane surfaces stay attached and the preview is not
     * touched — the caller pauses playback, because the render is a snapshot
     * of the timeline.
     */
    private fun startCaptionAudio(
        timeline: Map<String, Any?>,
        outputPath: String,
        include: CaptionAudioSources.Include,
        result: MethodChannel.Result,
    ) {
        if (captionAudio != null) {
            result.error("caption_audio_busy", "Caption audio is already rendering.", null)
            return
        }
        val selection = CaptionAudioSources.select(
            include,
            NativeTimelineClips.fromTimeline(timeline),
            NativeTimelineOverlays.fromTimeline(timeline),
            TimelineAudioTracks.fromTimeline(timeline),
        )
        val renderer = CaptionAudioRenderer(
            selection,
            NativeTimelineTransitionIntents.fromTimeline(timeline),
        )
        captionAudio = renderer

        Thread({
            try {
                val rendered = renderer.render(outputPath) { progress ->
                    sendEvent(mapOf("type" to "captionAudioProgress", "progress" to progress))
                }
                mainHandler.post {
                    captionAudio = null
                    if (rendered.cancelled) {
                        result.error("caption_audio_cancelled", "Cancelled.", null)
                    } else {
                        result.success(
                            mapOf(
                                "outputPath" to rendered.outputPath,
                                "durationSeconds" to rendered.durationSeconds,
                                "hasSound" to rendered.hasSound,
                            ),
                        )
                    }
                }
            } catch (error: Exception) {
                Log.e("SlimshotExport", "Caption audio failed", error)
                mainHandler.post {
                    captionAudio = null
                    result.error(
                        "caption_audio_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }, "slimshot-caption-audio").start()
    }
```

- [ ] **Step 7: Run the Kotlin suite (compiles the renderer and the manager)**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 8: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/export/CaptionAudioSources.kt android/app/src/main/kotlin/com/techfamz/slimshotai/export/CaptionAudioRenderer.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelinePreviewManager.kt android/app/src/test/kotlin/com/techfamz/slimshotai/export/CaptionAudioSourcesTest.kt
git commit -m "feat(captions): the native pass that renders the sound captions listen to

The chosen sources through the export's own mixer, mono 16 kHz AAC from
timeline 0, so the server's word times are timeline times.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: An export frees a still once it is finished with it

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/ExpiredStills.kt`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayRenderer.kt` (after `imageTexture`)
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayDrawBuilder.kt` (`releaseExpired`)
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/gl/ExpiredStillsTest.kt`

**Interfaces:**
- Produces: `ExpiredStills.releasable(spans: List<ExpiredStills.Span>, t: Double): Set<String>`; `OverlayRenderer.releaseImageTexture(path: String)`.

- [ ] **Step 1: Write the failing test**

```kotlin
package com.techfamz.slimshotai.nativepreview.gl

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which uploaded stills an export may free. A caption set is a hundred text
 * atlases; kept to the end of the export they were all on the GPU at once.
 */
class ExpiredStillsTest {

    private val caption1 = ExpiredStills.Span("/atlas1.png", endSeconds = 2.0)
    private val caption2 = ExpiredStills.Span("/atlas2.png", endSeconds = 4.0)

    @Test
    fun `nothing is freed while its overlay still shows`() {
        assertEquals(emptySet<String>(), ExpiredStills.releasable(listOf(caption1, caption2), 1.9))
    }

    @Test
    fun `a still is freed from its overlay's end`() {
        assertEquals(setOf("/atlas1.png"), ExpiredStills.releasable(listOf(caption1, caption2), 2.0))
        assertEquals(setOf("/atlas1.png", "/atlas2.png"), ExpiredStills.releasable(listOf(caption1, caption2), 9.0))
    }

    @Test
    fun `a photo placed twice is kept until its last use ends`() {
        val early = ExpiredStills.Span("/photo.jpg", endSeconds = 2.0)
        val late = ExpiredStills.Span("/photo.jpg", endSeconds = 6.0)
        assertEquals(emptySet<String>(), ExpiredStills.releasable(listOf(early, late), 3.0))
        assertEquals(setOf("/photo.jpg"), ExpiredStills.releasable(listOf(early, late), 6.0))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.nativepreview.gl.ExpiredStillsTest"`
Expected: FAIL — `Unresolved reference: ExpiredStills`.

- [ ] **Step 3: Write `ExpiredStills.kt`**

```kotlin
package com.techfamz.slimshotai.nativepreview.gl

/**
 * Which uploaded stills an export can free at an instant.
 *
 * A still's texture used to live until the whole export ended, so a project
 * carrying a hundred captions held a hundred text atlases on the GPU at once —
 * hundreds of megabytes on the low-end parts this app runs on. The export's
 * clock only walks forward, so a path every overlay has finished with is never
 * needed again. A path a later overlay still uses (a photo placed twice) is
 * kept, or it would be decoded and uploaded a second time.
 */
internal object ExpiredStills {

    data class Span(val path: String, val endSeconds: Double)

    fun releasable(spans: List<Span>, t: Double): Set<String> {
        val finished = mutableSetOf<String>()
        val inUse = mutableSetOf<String>()
        for (span in spans) {
            if (t >= span.endSeconds) finished += span.path else inUse += span.path
        }
        return finished - inUse
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.techfamz.slimshotai.nativepreview.gl.ExpiredStillsTest"`
Expected: PASS, 3 tests.

- [ ] **Step 5: Free them**

In `OverlayRenderer.kt`, after `imageTexture(...)`:

```kotlin
    /** Frees [path]'s uploaded texture, if there is one. Call on the GL thread. */
    fun releaseImageTexture(path: String) {
        val entry = imageTextures.remove(path) ?: return
        GlUtil.deleteTexture(entry.first)
    }
```

In `OverlayDrawBuilder.kt`, add a field beside `realtimeDecoders`:

```kotlin
    /** Stills this export has already freed, so each is released once. */
    private val releasedStills = mutableSetOf<String>()
```

and at the end of `releaseExpired(t)`, after the `for` loop:

```kotlin
        // The export only walks forward, so a still every overlay has finished
        // with is never drawn again. The preview keeps its stills: its playhead
        // scrubs back, and a freed still would be decoded again on the next
        // frame that shows it.
        if (!realtime) {
            val spans = overlays
                .filter { !it.isVideo }
                .map { ExpiredStills.Span(it.path, it.endSeconds) }
            for (path in ExpiredStills.releasable(spans, t)) {
                if (releasedStills.add(path)) renderer.overlays.releaseImageTexture(path)
            }
        }
```

- [ ] **Step 6: Run the Kotlin suite**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/ExpiredStills.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayRenderer.kt android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayDrawBuilder.kt android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/gl/ExpiredStillsTest.kt
git commit -m "fix(export): a still's texture is freed once its overlay has ended

Every text atlas and photo stayed on the GPU until the export finished,
so a captioned project held a hundred atlases at once.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Captions in the model, the state and the draft

**Files:**
- Create: `lib/features/video_editor/logic/captions/caption_word.dart`
- Create: `lib/features/video_editor/logic/captions/caption_settings.dart`
- Modify: `lib/features/video_editor/models/text_overlay_model.dart` (fields, constructor, `copyWith`, `toJson`, `fromJson`)
- Modify: `lib/features/video_editor/models/video_editor_state.dart` (field, constructor, `copyWith`, `hasCaptions`)
- Modify: `lib/core/models/draft_project.dart`
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart:295-327` (save), `:476-535` (load)
- Test: `test/features/video_editor/logic/captions/caption_model_test.dart`

**Interfaces:**
- Produces: `CaptionWord({required int textStart, required int textEnd, required Duration start, required Duration end})` with `toJson()`, `static CaptionWord? fromJson(Object? json, int textLength)`, `static List<CaptionWord>? listFromJson(Object? json, int textLength)`; `enum CaptionSource { video, tracks, all }` with `List<String> include`; `enum CaptionLength { word, phrase, line }` with `int maxWords`, `int maxChars`; `CaptionSettings({required String setId, CaptionSource source = video, String? language, CaptionLength length = phrase})` with `toJson()`, `static CaptionSettings? fromJson(Object?)`; `const kCaptionLanguages` of `({String code, String name})`; `TextOverlayModel.captionSetId`, `.captionWords`, `.isCaption`, `copyWith(captionSetId:, captionWords:, clearCaption:)`; `VideoEditorState.captionSettings`, `.hasCaptions`, `copyWith(captionSettings:, clearCaptionSettings:)`; `DraftProject.captionSettings` (`Map<String, dynamic>?`).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A caption is an ordinary text that also carries its words' timing.
void main() {
  const words = [
    CaptionWord(
      textStart: 0,
      textEnd: 5,
      start: Duration.zero,
      end: Duration(milliseconds: 320),
    ),
    CaptionWord(
      textStart: 6,
      textEnd: 11,
      start: Duration(milliseconds: 420),
      end: Duration(milliseconds: 800),
    ),
  ];

  group('CaptionWord', () {
    test('round-trips through JSON', () {
      for (final w in words) {
        expect(CaptionWord.fromJson(w.toJson(), 11), w);
      }
    });

    test('offsets are clamped into the text; an end never precedes its start',
        () {
      expect(
        CaptionWord.fromJson(
          {'from': -3, 'to': 99, 'startMs': -50, 'endMs': -80},
          5,
        ),
        const CaptionWord(
          textStart: 0,
          textEnd: 5,
          start: Duration.zero,
          end: Duration.zero,
        ),
      );
    });

    test('an entry with nothing left to place is dropped, never thrown', () {
      expect(
        CaptionWord.fromJson({'from': 7, 'to': 9, 'startMs': 0, 'endMs': 1}, 5),
        isNull,
      );
      expect(
        CaptionWord.fromJson({'from': 'a', 'to': 2, 'startMs': 0, 'endMs': 1}, 5),
        isNull,
      );
      expect(CaptionWord.fromJson('junk', 5), isNull);
      expect(
        CaptionWord.listFromJson([words.first.toJson(), 'junk', null], 11),
        [words.first],
      );
      expect(CaptionWord.listFromJson('junk', 11), isNull);
    });
  });

  group('a text overlay as a caption', () {
    TextOverlayModel caption() => TextOverlayModel(
          id: 'c',
          text: 'Hello world',
          captionSetId: 'captions_1',
          captionWords: words,
        );

    test('ordinary text writes no caption keys', () {
      final json = TextOverlayModel(id: 't', text: 'hi').toJson();
      expect(json.containsKey('captionSetId'), isFalse);
      expect(json.containsKey('captionWords'), isFalse);
      final back = TextOverlayModel.fromJson(json);
      expect(back.isCaption, isFalse);
      expect(back.captionWords, isNull);
    });

    test('a caption keeps its set and its words through a draft', () {
      final back = TextOverlayModel.fromJson(caption().toJson());
      expect(back.captionSetId, 'captions_1');
      expect(back.captionWords, words);
      expect(back.isCaption, isTrue);
    });

    test('words out of reach of a hand-edited text are dropped on read', () {
      final json = caption().toJson()..['text'] = 'Hello';
      expect(TextOverlayModel.fromJson(json).captionWords, [words.first]);
    });

    test('copyWith keeps the caption; clearCaption drops set and words', () {
      expect(caption().copyWith(text: 'x').captionSetId, 'captions_1');
      final plain = caption().copyWith(clearCaption: true);
      expect(plain.captionSetId, isNull);
      expect(plain.captionWords, isNull);
    });
  });

  group('CaptionSettings', () {
    const settings = CaptionSettings(
      setId: 'captions_1',
      source: CaptionSource.all,
      language: 'yo',
      length: CaptionLength.line,
    );

    test('round-trips, and Auto detect writes no language', () {
      expect(CaptionSettings.fromJson(settings.toJson()), settings);
      const auto = CaptionSettings(setId: 's');
      expect(auto.toJson().containsKey('language'), isFalse);
      expect(CaptionSettings.fromJson(auto.toJson()), auto);
    });

    test('unknown names fall back to the defaults; no set id is no settings',
        () {
      expect(
        CaptionSettings.fromJson(
          {'setId': 's', 'source': 'radio', 'length': 'essay', 'language': 7},
        ),
        const CaptionSettings(setId: 's'),
      );
      expect(CaptionSettings.fromJson({'source': 'all'}), isNull);
      expect(CaptionSettings.fromJson('junk'), isNull);
    });

    test('each source names the sounds the native pass mixes', () {
      expect(CaptionSource.video.include, ['clips', 'overlays']);
      expect(CaptionSource.tracks.include, ['tracks']);
      expect(CaptionSource.all.include, ['clips', 'overlays', 'tracks']);
    });

    test('the lengths are the spec limits', () {
      expect(CaptionLength.word.maxWords, 1);
      expect(
        (CaptionLength.phrase.maxWords, CaptionLength.phrase.maxChars),
        (3, 20),
      );
      expect(
        (CaptionLength.line.maxWords, CaptionLength.line.maxChars),
        (7, 32),
      );
    });

    test('every language is a code the server accepts, listed once', () {
      final codes = kCaptionLanguages.map((l) => l.code).toList();
      expect(codes.every(RegExp(r'^[a-z]{2}$').hasMatch), isTrue);
      expect(codes.toSet(), hasLength(codes.length));
    });
  });

  group('the project', () {
    const asset = MediaAsset(
      id: 'a',
      path: '/v.mp4',
      type: MediaAssetType.video,
      durationSeconds: 30,
      width: 1080,
      height: 1920,
      hasAudio: true,
    );
    const settings = CaptionSettings(
      setId: 'captions_1',
      source: CaptionSource.all,
      language: 'yo',
      length: CaptionLength.line,
    );

    DraftProject draft({Map<String, dynamic>? captionSettings}) => DraftProject(
          id: 'd1',
          sourceVideoPath: '/v.mp4',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          durationSeconds: 30,
          assets: [asset.toJson()],
          segments: [
            VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)
                .toJson(),
          ],
          textOverlays: const [],
          imageOverlays: const [],
          videoOverlays: const [],
          audioTracks: const [],
          selectedRatioName: 'ratio9x16',
          customCropRect: const [0, 0, 1, 1],
          videoScale: 1,
          videoPanX: 0,
          videoPanY: 0,
          filterIntensity: 1,
          backgroundType: 'black',
          backgroundColorValue: 0xFF000000,
          backgroundBlurIntensity: 20,
          isMuted: false,
          captionSettings: captionSettings,
        );

    test('knows whether it has captions', () {
      expect(
        VideoEditorState(textOverlays: [TextOverlayModel(id: 't', text: 'hi')])
            .hasCaptions,
        isFalse,
      );
      expect(
        VideoEditorState(
          textOverlays: [
            TextOverlayModel(id: 'c', text: 'hi', captionSetId: 'captions_1'),
          ],
        ).hasCaptions,
        isTrue,
      );
    });

    test('a draft without captions writes no key', () {
      expect(draft().toJson().containsKey('captionSettings'), isFalse);
      expect(DraftProject.fromJson(draft().toJson()).captionSettings, isNull);
    });

    test('caption settings survive a save and a reopen', () async {
      SharedPreferences.setMockInitialValues({});
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          draftId: 'd1',
          assets: const [asset],
          segments: [
            VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5),
          ],
          captionSettings: settings,
        );
      await n.saveDraft();
      final saved = await DraftService.getDraftById('d1');
      expect(saved?.captionSettings, settings.toJson());

      final reopened = VideoEditorNotifier(VideoEditorService());
      await reopened.loadDraft(saved!, rerenderMissingProxies: false);
      expect(reopened.state.captionSettings, settings);
    });

    test('a draft saved before captions reopens with none', () async {
      final n = VideoEditorNotifier(VideoEditorService());
      await n.loadDraft(draft(), rerenderMissingProxies: false);
      expect(n.state.captionSettings, isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/video_editor/logic/captions/caption_model_test.dart`
Expected: FAIL — compilation errors: the `caption_word.dart` / `caption_settings.dart` imports do not exist.

- [ ] **Step 3: Write `caption_word.dart`**

```dart
import 'dart:math' as math;

/// One spoken word inside a caption: where it sits in the caption's text and
/// when it is said, **relative to the caption's own start** — so dragging a
/// caption bar moves its words with it.
///
/// Offsets are UTF-16, the unit `TextGlyphBox.charIndex` already counts in: a
/// glyph belongs to the word whose `[textStart, textEnd)` holds its index, with
/// no second way of counting characters.
class CaptionWord {
  const CaptionWord({
    required this.textStart,
    required this.textEnd,
    required this.start,
    required this.end,
  });

  /// UTF-16 offset of the word's first code unit, inclusive.
  final int textStart;

  /// UTF-16 offset just past the word, exclusive.
  final int textEnd;

  final Duration start;
  final Duration end;

  Map<String, dynamic> toJson() => {
        'from': textStart,
        'to': textEnd,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
      };

  /// Null for an entry with nothing left to place once clamped into a text of
  /// [textLength] code units; otherwise non-negative, with an end never before
  /// its start. A hand-edited or damaged draft must open, not throw.
  static CaptionWord? fromJson(Object? json, int textLength) {
    if (json is! Map) return null;
    final from = _int(json['from']);
    final to = _int(json['to']);
    final startMs = _int(json['startMs']);
    final endMs = _int(json['endMs']);
    if (from == null || to == null || startMs == null || endMs == null) {
      return null;
    }
    final a = from.clamp(0, textLength);
    final b = to.clamp(a, textLength);
    if (b == a) return null;
    final s = math.max(0, startMs);
    return CaptionWord(
      textStart: a,
      textEnd: b,
      start: Duration(milliseconds: s),
      end: Duration(milliseconds: math.max(s, endMs)),
    );
  }

  /// The readable entries of [json], or null when it is not a list at all.
  static List<CaptionWord>? listFromJson(Object? json, int textLength) {
    if (json is! List) return null;
    return json
        .map((entry) => fromJson(entry, textLength))
        .whereType<CaptionWord>()
        .toList();
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  @override
  bool operator ==(Object other) =>
      other is CaptionWord &&
      other.textStart == textStart &&
      other.textEnd == textEnd &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(textStart, textEnd, start, end);

  @override
  String toString() =>
      'CaptionWord([$textStart, $textEnd) ${start.inMilliseconds}–${end.inMilliseconds}ms)';
}
```

- [ ] **Step 4: Write `caption_settings.dart`**

```dart
/// Which sound auto captions listen to.
enum CaptionSource {
  /// The clips and the video overlays — the speech in the footage. The
  /// default, so background music does not become lyric captions.
  video(['clips', 'overlays']),

  /// Imported audio tracks — a voiceover recorded elsewhere, or music.
  tracks(['tracks']),

  all(['clips', 'overlays', 'tracks']);

  const CaptionSource(this.include);

  /// The kinds of sound the native caption pass mixes
  /// (`CaptionAudioSources.Include` on the Kotlin side).
  final List<String> include;
}

/// How much of the speech one caption holds.
enum CaptionLength {
  word(maxWords: 1, maxChars: 1 << 30),
  phrase(maxWords: 3, maxChars: 20),
  line(maxWords: 7, maxChars: 32);

  const CaptionLength({required this.maxWords, required this.maxChars});

  final int maxWords;

  /// Grapheme clusters, separators included.
  final int maxChars;
}

/// The languages the sheet offers after Auto detect, as the server's ISO 639-1
/// codes. Which of them transcribe well depends on the provider the server has
/// active; a refusal comes back as an ordinary caption error.
const List<({String code, String name})> kCaptionLanguages = [
  (code: 'en', name: 'English'),
  (code: 'fr', name: 'French'),
  (code: 'es', name: 'Spanish'),
  (code: 'pt', name: 'Portuguese'),
  (code: 'de', name: 'German'),
  (code: 'it', name: 'Italian'),
  (code: 'nl', name: 'Dutch'),
  (code: 'ar', name: 'Arabic'),
  (code: 'hi', name: 'Hindi'),
  (code: 'zh', name: 'Chinese'),
  (code: 'ja', name: 'Japanese'),
  (code: 'ko', name: 'Korean'),
  (code: 'ru', name: 'Russian'),
  (code: 'tr', name: 'Turkish'),
  (code: 'id', name: 'Indonesian'),
  (code: 'sw', name: 'Swahili'),
  (code: 'yo', name: 'Yoruba'),
  (code: 'ig', name: 'Igbo'),
  (code: 'ha', name: 'Hausa'),
];

/// What a project's caption set was made with — what the sheet reopens on and
/// what a regeneration starts from.
class CaptionSettings {
  const CaptionSettings({
    required this.setId,
    this.source = CaptionSource.video,
    this.language,
    this.length = CaptionLength.phrase,
  });

  /// The `captionSetId` every caption of the set carries.
  final String setId;

  final CaptionSource source;

  /// An ISO 639-1 code, or null for Auto detect.
  final String? language;

  final CaptionLength length;

  Map<String, dynamic> toJson() => {
        'setId': setId,
        'source': source.name,
        if (language != null) 'language': language,
        'length': length.name,
      };

  /// Null for anything without a set id; unknown names read as the defaults.
  static CaptionSettings? fromJson(Object? json) {
    if (json is! Map) return null;
    final setId = json['setId'];
    if (setId is! String || setId.isEmpty) return null;
    final language = json['language'];
    return CaptionSettings(
      setId: setId,
      source: CaptionSource.values.asNameMap()[json['source']] ??
          CaptionSource.video,
      language: language is String ? language : null,
      length: CaptionLength.values.asNameMap()[json['length']] ??
          CaptionLength.phrase,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.setId == setId &&
      other.source == source &&
      other.language == language &&
      other.length == length;

  @override
  int get hashCode => Object.hash(setId, source, language, length);
}
```

- [ ] **Step 5: Add the caption fields to `TextOverlayModel`**

Import `'../logic/captions/caption_word.dart'`. After the `keyframes` field:

```dart
  /// The caption set this text belongs to, or null for ordinary text.
  ///
  /// A string rather than a flag: one set per project today, but a translated
  /// second set is the obvious next feature, and an id now costs no migration
  /// then.
  String? captionSetId;

  /// A caption's spoken words, in text order; null for ordinary text.
  List<CaptionWord>? captionWords;

  bool get isCaption => captionSetId != null;
```

Constructor: add `this.captionSetId,` and `this.captionWords,` after `this.keyframes = OverlayKeyframes.none,`.

`copyWith`: add parameters `String? captionSetId, List<CaptionWord>? captionWords, bool clearCaption = false,` and, after `keyframes: keyframes ?? this.keyframes,`:

```dart
      captionSetId: clearCaption ? null : captionSetId ?? this.captionSetId,
      captionWords: clearCaption ? null : captionWords ?? this.captionWords,
```

`toJson`: after the `keyframes` entry:

```dart
      // Omitted on ordinary text, so a draft without captions is unchanged.
      if (captionSetId != null) 'captionSetId': captionSetId,
      if (captionWords != null)
        'captionWords': [for (final w in captionWords!) w.toJson()],
```

`fromJson`: add `final text = json['text'] as String;` before `return TextOverlayModel(`, change `text: json['text'] as String,` to `text: text,`, and after `keyframes: OverlayKeyframes.fromJson(json['keyframes']),`:

```dart
      captionSetId:
          json['captionSetId'] is String ? json['captionSetId'] as String : null,
      captionWords: CaptionWord.listFromJson(json['captionWords'], text.length),
```

- [ ] **Step 6: Add `captionSettings` to the state and the draft**

`VideoEditorState` — import `'../logic/captions/caption_settings.dart'`; constructor `this.captionSettings,`; field after `adjustments`:

```dart
  /// What the project's caption set was made with; null until one exists.
  final CaptionSettings? captionSettings;

  /// Whether any text on the timeline is a caption.
  bool get hasCaptions => textOverlays.any((t) => t.isCaption);
```

`copyWith` parameters `CaptionSettings? captionSettings, bool clearCaptionSettings = false,` and in the constructor call:

```dart
      captionSettings: clearCaptionSettings
          ? null
          : captionSettings ?? this.captionSettings,
```

`DraftProject` — field `final Map<String, dynamic>? captionSettings;`, constructor `this.captionSettings,`, `toJson` entry `if (captionSettings != null) 'captionSettings': captionSettings,`, `fromJson`:

```dart
      captionSettings: json['captionSettings'] is Map
          ? Map<String, dynamic>.from(json['captionSettings'] as Map)
          : null,
```

Notifier `saveDraft`: add `captionSettings: state.captionSettings?.toJson(),` after `isMuted: state.isMuted,`. `loadDraft`: before `state = state.copyWith(`, add `final captionSettings = CaptionSettings.fromJson(draft.captionSettings);`, and in that `copyWith`, after `isMuted: draft.isMuted,`:

```dart
      captionSettings: captionSettings,
      clearCaptionSettings: captionSettings == null,
```

(import `'../logic/captions/caption_settings.dart'` in the notifier).

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/logic/captions/caption_model_test.dart`
Expected: PASS, all tests.

- [ ] **Step 8: Run the analyzer and the neighbouring suites**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.
Run: `flutter test test/features/video_editor/providers test/features/video_editor/models` → Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/features/video_editor/logic/captions/caption_word.dart lib/features/video_editor/logic/captions/caption_settings.dart lib/features/video_editor/models/text_overlay_model.dart lib/features/video_editor/models/video_editor_state.dart lib/core/models/draft_project.dart lib/features/video_editor/providers/video_editor_notifier.dart test/features/video_editor/logic/captions/caption_model_test.dart
git commit -m "feat(captions): a caption is a text that carries its words

TextOverlayModel gains a caption set id and word timings, the project
remembers how its captions were made, and both survive a draft. Nothing
is written for ordinary text, so older drafts are unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The Dart side of the caption audio pass — and fonts before export

**Files:**
- Create: `lib/features/video_editor/services/caption_audio_result.dart`
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart` (constructor, `exportVideo`, two new methods)
- Test: `test/features/video_editor/services/caption_audio_channel_test.dart`

**Interfaces:**
- Consumes: `CaptionSource.include` (Task 5); the channel contract from Task 3.
- Produces: `CaptionAudioResult({required String outputPath, required double durationSeconds, required bool hasSound})`, `CaptionAudioResult.fromMap`; `class CaptionAudioCancelled implements Exception`; `NativeTimelinePreviewService({..., Future<void> Function()? fontsReady})`; `Future<CaptionAudioResult> renderCaptionAudio(VideoEditorState state, {required String outputPath, required CaptionSource source, void Function(double progress)? onProgress})`; `Future<void> cancelCaptionAudio()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// The Dart half of the caption audio pass, and the export's wait for fonts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('slimshot_ai/native_timeline_preview');
  const events = EventChannel('test/caption_audio_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall call)? answer;

  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 10,
    width: 1080,
    height: 1920,
    hasAudio: true,
  );
  final state = VideoEditorState(
    assets: const [asset],
    segments: [VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)],
  );
  const rendered = {
    'outputPath': '/tmp/c.m4a',
    'durationSeconds': 4.5,
    'hasSound': true,
  };

  setUp(() {
    calls.clear();
    answer = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer?.call(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('asks for exactly the chosen sounds, into the given file', () async {
    answer = (_) async => rendered;
    final service = NativeTimelinePreviewService(playbackEventChannel: events);
    for (final source in CaptionSource.values) {
      calls.clear();
      await service.renderCaptionAudio(
        state,
        outputPath: '/tmp/c.m4a',
        source: source,
      );
      final call = calls.single;
      expect(call.method, 'renderCaptionAudio');
      final args = call.arguments as Map;
      expect(args['outputPath'], '/tmp/c.m4a');
      expect(args['include'], source.include);
      expect(args['timeline'], isA<Map>());
    }
  });

  test('reads what the pass produced', () async {
    answer = (_) async => rendered;
    final result = await NativeTimelinePreviewService(
      playbackEventChannel: events,
    ).renderCaptionAudio(state, outputPath: '/tmp/c.m4a', source: CaptionSource.video);
    expect(result.outputPath, '/tmp/c.m4a');
    expect(result.durationSeconds, 4.5);
    expect(result.hasSound, isTrue);
  });

  test('a render stopped natively is CaptionAudioCancelled', () async {
    answer = (_) async =>
        throw PlatformException(code: 'caption_audio_cancelled');
    await expectLater(
      NativeTimelinePreviewService(playbackEventChannel: events)
          .renderCaptionAudio(state, outputPath: '/tmp/c.m4a', source: CaptionSource.video),
      throwsA(isA<CaptionAudioCancelled>()),
    );
  });

  test('progress events reach the caller; other events do not', () async {
    final seen = <double>[];
    final progressed = Completer<void>();
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          sink.success({'type': 'position', 'positionSeconds': 1.0});
          sink.success({'type': 'captionAudioProgress', 'progress': 0.5});
        },
      ),
    );
    answer = (_) async {
      await progressed.future;
      return rendered;
    };
    await NativeTimelinePreviewService(playbackEventChannel: events)
        .renderCaptionAudio(
      state,
      outputPath: '/tmp/c.m4a',
      source: CaptionSource.video,
      onProgress: (p) {
        seen.add(p);
        if (!progressed.isCompleted) progressed.complete();
      },
    );
    expect(seen, [0.5]);
  });

  test('Cancel reaches the engine', () async {
    await NativeTimelinePreviewService().cancelCaptionAudio();
    expect(calls.single.method, 'cancelCaptionAudio');
  });

  test('export waits for fonts still loading before it draws any text',
      () async {
    final fonts = Completer<void>();
    answer = (_) async => {
          'outputPath': '/tmp/o.mp4',
          'durationSeconds': 5.0,
          'frameCount': 150,
          'degradedTransitions': 0,
        };
    final export = NativeTimelinePreviewService(fontsReady: () => fonts.future)
        .exportVideo(state, outputPath: '/tmp/o.mp4');
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty, reason: 'nothing may be rasterised before fonts land');
    fonts.complete();
    await export;
    expect(calls.single.method, 'exportVideo');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/video_editor/services/caption_audio_channel_test.dart`
Expected: FAIL — `caption_audio_result.dart` does not exist; `renderCaptionAudio` and `fontsReady` are undefined.

- [ ] **Step 3: Write `caption_audio_result.dart`**

```dart
/// What the native caption audio pass produced.
class CaptionAudioResult {
  const CaptionAudioResult({
    required this.outputPath,
    required this.durationSeconds,
    required this.hasSound,
  });

  final String outputPath;
  final double durationSeconds;

  /// False when the chosen sources hold nothing audible: the file was not
  /// written, and nothing may be uploaded.
  final bool hasSound;

  factory CaptionAudioResult.fromMap(Map<String, dynamic> map) {
    return CaptionAudioResult(
      outputPath: map['outputPath'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      hasSound: map['hasSound'] as bool? ?? false,
    );
  }
}

/// The native pass stopped because Cancel asked it to.
class CaptionAudioCancelled implements Exception {
  const CaptionAudioCancelled();
}
```

- [ ] **Step 4: Extend `NativeTimelinePreviewService`**

Imports: `package:google_fonts/google_fonts.dart`, `'../logic/captions/caption_settings.dart'`, `'caption_audio_result.dart'`.

Constructor gains a parameter and field:

```dart
    Future<void> Function()? fontsReady,
  })  : _methodChannel = ...,            // unchanged
        _playbackEventChannel = ...,     // unchanged
        _timelineComposer = timelineComposer,
        _fontsReady = fontsReady ?? _pendingFonts;

  /// Completes once every font a text may use has finished loading.
  final Future<void> Function() _fontsReady;

  static Future<void> _pendingFonts() async {
    await GoogleFonts.pendingFonts();
  }
```

First line of `exportVideo`'s body:

```dart
    // A font still downloading when export starts would be rasterised in the
    // fallback face while the preview shows the real one — the file would
    // differ from the canvas with nothing saying why.
    await _fontsReady();
```

After `cancelExport()`:

```dart
  /// Renders the sound auto captions listen to — [source] through the
  /// export's own mixer, mono 16 kHz AAC from timeline 0 — into [outputPath].
  ///
  /// Throws [CaptionAudioCancelled] when [cancelCaptionAudio] stopped it.
  Future<CaptionAudioResult> renderCaptionAudio(
    VideoEditorState state, {
    required String outputPath,
    required CaptionSource source,
    void Function(double progress)? onProgress,
  }) async {
    final timeline = _timelineComposer.compose(state);
    final progress = onProgress == null
        ? null
        : events
            .where((e) => e.type == 'captionAudioProgress' && e.progress != null)
            .listen((e) => onProgress(e.progress!));
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'renderCaptionAudio',
        {
          'timeline': timeline.toJson(),
          'outputPath': outputPath,
          'include': source.include,
        },
      );
      if (result == null) {
        throw StateError('Caption audio returned no result.');
      }
      return CaptionAudioResult.fromMap(result);
    } on PlatformException catch (e) {
      if (e.code == 'caption_audio_cancelled') {
        throw const CaptionAudioCancelled();
      }
      rethrow;
    } finally {
      await progress?.cancel();
    }
  }

  Future<void> cancelCaptionAudio() {
    return _methodChannel.invokeMethod<void>('cancelCaptionAudio');
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/services/caption_audio_channel_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 6: Analyzer and service suites**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.
Run: `flutter test test/features/video_editor/services` → Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/video_editor/services/caption_audio_result.dart lib/features/video_editor/services/native_timeline_preview_service.dart test/features/video_editor/services/caption_audio_channel_test.dart
git commit -m "feat(captions): render caption audio from Dart; export waits for fonts

Also closes a gap the captions would hit first: nothing awaited fonts
still downloading, so export could rasterise text in the fallback face.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The transcript, and the spacing the server drops

**Files:**
- Create: `lib/features/video_editor/logic/captions/caption_transcript.dart`
- Test: `test/features/video_editor/logic/captions/caption_transcript_test.dart`

**Interfaces:**
- Produces: `TranscriptWord({required String text, required double start, required double end})`; `CaptionTranscript({required String text, required List<TranscriptWord> words, String? language})`, `factory CaptionTranscript.fromJson(Map<String, dynamic>)`; `SpacedWord(String separator, TranscriptWord word)`; `List<SpacedWord> rebuildTranscriptSpacing(String text, List<TranscriptWord> words)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';

void main() {
  TranscriptWord w(String text, double start, double end) =>
      TranscriptWord(text: text, start: start, end: end);

  group('CaptionTranscript.fromJson', () {
    test('reads the server result', () {
      final t = CaptionTranscript.fromJson({
        'provider': 'elevenlabs',
        'language': 'en',
        'durationSeconds': 6.2,
        'text': 'Welcome back.',
        'words': [
          {'text': 'Welcome', 'start': 0.18, 'end': 0.5, 'confidence': 1},
          {'text': 'back.', 'start': 0.6, 'end': 0.8, 'confidence': 0.97},
        ],
      });
      expect(t.text, 'Welcome back.');
      expect(t.language, 'en');
      expect(t.words.map((x) => (x.text, x.start, x.end)), [
        ('Welcome', 0.18, 0.5),
        ('back.', 0.6, 0.8),
      ]);
    });

    test('drops words with no text or no usable time; a backwards end is pulled up',
        () {
      final t = CaptionTranscript.fromJson({
        'text': 'a b c d',
        'words': [
          {'text': 'a', 'start': 0.1, 'end': 0.2},
          {'text': '  ', 'start': 0.3, 'end': 0.4},
          {'text': 'b', 'start': 'soon', 'end': 0.5},
          {'text': 'c', 'start': -1, 'end': 0.5},
          {'text': 'd', 'start': 0.9, 'end': 0.6},
          'junk',
        ],
      });
      expect(t.words.map((x) => x.text), ['a', 'd']);
      expect(t.words.last.end, 0.9);
    });

    test('an empty result is an empty transcript', () {
      final t = CaptionTranscript.fromJson(const {});
      expect(t.text, '');
      expect(t.words, isEmpty);
      expect(t.language, isNull);
    });
  });

  group('rebuildTranscriptSpacing', () {
    List<String> separators(String text, List<String> words) =>
        rebuildTranscriptSpacing(text, [for (final x in words) w(x, 0, 0)])
            .map((s) => s.separator)
            .toList();

    test('spaced languages keep one space between words', () {
      expect(
        separators(
          'Welcome back to the channel.',
          ['Welcome', 'back', 'to', 'the', 'channel.'],
        ),
        ['', ' ', ' ', ' ', ' '],
      );
    });

    test('a script written without spaces gets none', () {
      expect(separators('你好世界', ['你', '好', '世', '界']), ['', '', '', '']);
    });

    test('mixed scripts follow the transcript', () {
      expect(separators('Hello 世界', ['Hello', '世', '界']), ['', ' ', '']);
    });

    test('a run of whitespace or a line break is one space', () {
      expect(separators('one  \n two', ['one', 'two']), ['', ' ']);
    });

    test('a repeated word is found in order', () {
      expect(separators('the the end', ['the', 'the', 'end']), ['', ' ', ' ']);
    });

    test('a word the transcript lacks falls back to one space', () {
      expect(
        separators('alpha gamma', ['alpha', 'beta', 'gamma']),
        ['', ' ', ' '],
      );
    });

    test('the first word never carries a separator', () {
      expect(separators('  lead', ['lead']), ['']);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/video_editor/logic/captions/caption_transcript_test.dart`
Expected: FAIL — `caption_transcript.dart` does not exist.

- [ ] **Step 3: Write `caption_transcript.dart`**

```dart
/// A word as the server reports it, in seconds from the start of the uploaded
/// audio — which starts at timeline 0, so these are timeline seconds.
class TranscriptWord {
  const TranscriptWord({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final double start;
  final double end;
}

/// A finished caption job's result.
class CaptionTranscript {
  const CaptionTranscript({
    required this.text,
    required this.words,
    this.language,
  });

  /// The whole transcript, with the provider's own spacing.
  final String text;
  final List<TranscriptWord> words;
  final String? language;

  /// Defensive, like every read here: a word with no text, or a start that is
  /// not a finite, non-negative number, is dropped; an end before its start is
  /// pulled up to it.
  factory CaptionTranscript.fromJson(Map<String, dynamic> json) {
    double? number(Object? value) => value is num ? value.toDouble() : null;

    final words = <TranscriptWord>[];
    final raw = json['words'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final text = entry['text'];
        final start = number(entry['start']);
        final end = number(entry['end']);
        if (text is! String || text.trim().isEmpty) continue;
        if (start == null || !start.isFinite || start < 0) continue;
        words.add(
          TranscriptWord(
            text: text.trim(),
            start: start,
            end: end == null || !end.isFinite || end < start ? start : end,
          ),
        );
      }
    }
    final text = json['text'];
    final language = json['language'];
    return CaptionTranscript(
      text: text is String ? text : '',
      words: words,
      language: language is String ? language : null,
    );
  }
}

/// A transcript word and the separator written before it.
class SpacedWord {
  const SpacedWord(this.separator, this.word);

  /// `' '` or `''` — never anything else.
  final String separator;
  final TranscriptWord word;
}

final RegExp _whitespace = RegExp(r'\s');

/// Each word's leading separator, recovered from the transcript [text].
///
/// The server drops the provider's spacing tokens, so words arrive without the
/// spaces between them — and joining them with a space would put spaces
/// through Chinese and Japanese, which are written without any. The whole
/// transcript still has the true spacing: each word is found in it, in order,
/// and whatever lies between two words is the separator — one space if it
/// holds any whitespace, nothing otherwise. A word the transcript does not
/// contain falls back to one space.
List<SpacedWord> rebuildTranscriptSpacing(
  String text,
  List<TranscriptWord> words,
) {
  final spaced = <SpacedWord>[];
  var cursor = 0;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final at = text.indexOf(word.text, cursor);
    var separator = ' ';
    if (at >= 0) {
      separator = text.substring(cursor, at).contains(_whitespace) ? ' ' : '';
      cursor = at + word.text.length;
    }
    spaced.add(SpacedWord(i == 0 ? '' : separator, word));
  }
  return spaced;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/logic/captions/caption_transcript_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Analyzer, then commit**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.

```bash
git add lib/features/video_editor/logic/captions/caption_transcript.dart test/features/video_editor/logic/captions/caption_transcript_test.dart
git commit -m "feat(captions): read the transcript and recover its spacing

Words arrive without the spaces between them; the full transcript still
has them, so Chinese and Japanese are not spaced through.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Words into captions

**Files:**
- Create: `lib/features/video_editor/logic/captions/caption_grouping.dart`
- Test: `test/features/video_editor/logic/captions/caption_grouping_test.dart`

**Interfaces:**
- Consumes: `SpacedWord`, `TranscriptWord` (Task 7); `CaptionLength`, `CaptionWord` (Task 5).
- Produces: `const double kCaptionPauseBreakSeconds = 0.6`, `const double kCaptionHoldSeconds = 0.4`; `CaptionDraft({required String text, required Duration start, required Duration end, required List<CaptionWord> words})`; `List<CaptionDraft> groupCaptionWords(List<SpacedWord> words, CaptionLength length)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';

void main() {
  SpacedWord sw(String text, double start, double end, {String sep = ' '}) =>
      SpacedWord(sep, TranscriptWord(text: text, start: start, end: end));

  /// Words 0.3s apart, 0.25s long: no pauses, no punctuation.
  List<SpacedWord> steady(List<String> texts) => [
        for (var i = 0; i < texts.length; i++)
          sw(texts[i], i * 0.3, i * 0.3 + 0.25, sep: i == 0 ? '' : ' '),
      ];

  List<String> texts(List<CaptionDraft> d) => d.map((c) => c.text).toList();

  group('where a caption breaks', () {
    test('a phrase holds at most three words', () {
      expect(
        texts(groupCaptionWords(
          steady(['one', 'two', 'three', 'four', 'five', 'six', 'seven']),
          CaptionLength.phrase,
        )),
        ['one two three', 'four five six', 'seven'],
      );
    });

    test('a phrase holds at most twenty characters', () {
      expect(
        texts(groupCaptionWords(
          steady(['extraordinary', 'people', 'wonderful']),
          CaptionLength.phrase,
        )),
        ['extraordinary people', 'wonderful'],
      );
    });

    test('Word is one word per caption', () {
      expect(
        texts(groupCaptionWords(steady(['a', 'b', 'c']), CaptionLength.word)),
        ['a', 'b', 'c'],
      );
    });

    test('a line holds at most seven words', () {
      expect(
        texts(groupCaptionWords(
          steady(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i']),
          CaptionLength.line,
        )),
        ['a b c d e f g', 'h i'],
      );
    });

    test('a sentence ends a caption whatever the length', () {
      expect(
        texts(groupCaptionWords(
          steady(['Hi.', 'there', 'friend']),
          CaptionLength.line,
        )),
        ['Hi.', 'there friend'],
      );
      expect(
        texts(groupCaptionWords([
          sw('你', 0, 0.2, sep: ''),
          sw('好。', 0.3, 0.5, sep: ''),
          sw('世', 0.6, 0.8, sep: ''),
          sw('界', 0.9, 1.1, sep: ''),
        ], CaptionLength.line)),
        ['你好。', '世界'],
      );
    });

    test('a pause of 0.6s ends a caption; a shorter one does not', () {
      expect(
        texts(groupCaptionWords([
          sw('one', 0, 0.2, sep: ''),
          sw('two', 0.8, 1.0),
          sw('three', 1.59, 1.8),
        ], CaptionLength.line)),
        ['one', 'two three'],
      );
    });

    test('a word longer than the limit is a caption of its own, never dropped',
        () {
      expect(
        texts(groupCaptionWords(
          steady(['see', 'https://slimshot.example/very/long/path', 'now']),
          CaptionLength.phrase,
        )),
        ['see', 'https://slimshot.example/very/long/path', 'now'],
      );
    });

    test('a punctuation-only token joins the caption before it', () {
      expect(
        texts(groupCaptionWords([
          sw('Wait', 0, 0.3, sep: ''),
          sw('—', 0.3, 0.35),
          sw('what', 1.2, 1.5),
        ], CaptionLength.phrase)),
        ['Wait —', 'what'],
      );
    });

    test('…even straight after a sentence has ended', () {
      expect(
        texts(groupCaptionWords([
          sw('Stop.', 0, 0.3, sep: ''),
          sw('"', 0.3, 0.3, sep: ''),
          sw('Go', 1.0, 1.2),
        ], CaptionLength.line)),
        ['Stop."', 'Go'],
      );
    });

    test('no words, no captions', () {
      expect(groupCaptionWords(const [], CaptionLength.phrase), isEmpty);
    });
  });

  group('when a caption shows', () {
    test('it holds 0.4s past its last word when nothing follows soon', () {
      final d = groupCaptionWords(
        [sw('Hi.', 1.0, 1.3, sep: ''), sw('Bye.', 3.0, 3.2)],
        CaptionLength.line,
      );
      expect(d[0].start, const Duration(milliseconds: 1000));
      expect(d[0].end, const Duration(milliseconds: 1700));
      expect(d[1].end, const Duration(milliseconds: 3600));
    });

    test('the hold stops at the next caption', () {
      final d = groupCaptionWords(
        [sw('Hi.', 1.0, 1.3, sep: ''), sw('Bye.', 1.5, 1.7)],
        CaptionLength.line,
      );
      expect(d[0].end, const Duration(milliseconds: 1500));
      expect(d[1].start, const Duration(milliseconds: 1500));
    });

    test('provider times that overlap or run backwards never overlap captions',
        () {
      final d = groupCaptionWords([
        sw('One.', 1.0, 1.6, sep: ''),
        sw('Two.', 1.2, 1.4),
        sw('Three.', 0.9, 1.1),
      ], CaptionLength.line);
      expect(d, hasLength(3));
      for (var i = 0; i < d.length; i++) {
        expect(d[i].end > d[i].start, isTrue, reason: 'caption $i has length');
        if (i > 0) {
          expect(
            d[i].start >= d[i - 1].end,
            isTrue,
            reason: 'caption $i starts after caption ${i - 1} ends',
          );
        }
      }
    });
  });

  group('what a caption holds', () {
    test('UTF-16 offsets, and word times relative to the caption', () {
      final d = groupCaptionWords(
        [sw('Hello,', 2.0, 2.4, sep: ''), sw('world', 2.5, 2.9)],
        CaptionLength.phrase,
      );
      expect(d.single.text, 'Hello, world');
      expect(d.single.words, const [
        CaptionWord(
          textStart: 0,
          textEnd: 6,
          start: Duration.zero,
          end: Duration(milliseconds: 400),
        ),
        CaptionWord(
          textStart: 7,
          textEnd: 12,
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 900),
        ),
      ]);
    });

    test('a script without spaces joins with nothing', () {
      final d = groupCaptionWords(
        [sw('你', 0, 0.2, sep: ''), sw('好', 0.3, 0.5, sep: '')],
        CaptionLength.phrase,
      );
      expect(d.single.text, '你好');
      expect(
        d.single.words.map((w) => (w.textStart, w.textEnd)),
        [(0, 1), (1, 2)],
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/video_editor/logic/captions/caption_grouping_test.dart`
Expected: FAIL — `caption_grouping.dart` does not exist.

- [ ] **Step 3: Write `caption_grouping.dart`**

```dart
import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'caption_settings.dart';
import 'caption_transcript.dart';
import 'caption_word.dart';

/// A silence at least this long starts a new caption.
const double kCaptionPauseBreakSeconds = 0.6;

/// How long a caption stays after its last word, so it does not flicker off
/// between two phrases — never past the next caption's start. This also keeps
/// every caption at least 0.4s long wherever there is room for it.
const double kCaptionHoldSeconds = 0.4;

/// One caption before it becomes a text overlay.
class CaptionDraft {
  const CaptionDraft({
    required this.text,
    required this.start,
    required this.end,
    required this.words,
  });

  final String text;

  /// Timeline instants.
  final Duration start;
  final Duration end;

  /// Relative to [start].
  final List<CaptionWord> words;
}

final RegExp _sentenceEnd = RegExp(r'[.!?…。！？]$');
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Groups [words] into captions of [length] and times them.
///
/// A caption breaks after sentence-ending punctuation, before a word that
/// follows a pause of [kCaptionPauseBreakSeconds], and where the next word
/// would pass the length's word or character limit. A word longer than the
/// limit stands alone rather than being split or dropped. A token with no
/// letter or digit — a dash, a stray quote — never starts a caption of its own:
/// it joins the one before.
///
/// Every caption starts no earlier than the previous one ends and has a
/// length, whatever order or overlap the provider's times arrive in, so a set
/// always fits on one lane.
List<CaptionDraft> groupCaptionWords(
  List<SpacedWord> words,
  CaptionLength length,
) {
  final groups = <List<SpacedWord>>[];
  var current = <SpacedWord>[];
  var chars = 0;
  var wordCount = 0;

  void close() {
    if (current.isEmpty) return;
    groups.add(current);
    current = [];
    chars = 0;
    wordCount = 0;
  }

  for (final w in words) {
    final isWord = _letterOrDigit.hasMatch(w.word.text);
    if (!isWord && current.isEmpty && groups.isNotEmpty) {
      groups.last.add(w);
      continue;
    }
    final size = w.word.text.characters.length;
    if (isWord && current.isNotEmpty) {
      final pause =
          w.word.start - current.last.word.end >= kCaptionPauseBreakSeconds;
      final tooLong = wordCount + 1 > length.maxWords ||
          chars + w.separator.characters.length + size > length.maxChars;
      if (pause || tooLong) close();
    }
    chars += (current.isEmpty ? 0 : w.separator.characters.length) + size;
    if (isWord) wordCount++;
    current.add(w);
    if (_sentenceEnd.hasMatch(w.word.text)) close();
  }
  close();

  int ms(double seconds) => (seconds * 1000).round();
  final drafts = <CaptionDraft>[];
  var floor = 0;
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final start = math.max(ms(group.first.word.start), floor);
    final lastEnd = math.max(
      group.map((x) => ms(x.word.end)).reduce(math.max),
      start,
    );
    var end = lastEnd + ms(kCaptionHoldSeconds);
    if (i + 1 < groups.length) {
      final next = ms(groups[i + 1].first.word.start);
      if (next > start) end = math.min(end, next);
    }

    final text = StringBuffer();
    final captionWords = <CaptionWord>[];
    for (var j = 0; j < group.length; j++) {
      if (j > 0) text.write(group[j].separator);
      final from = text.length;
      text.write(group[j].word.text);
      final wordStart = math.max(0, ms(group[j].word.start) - start);
      captionWords.add(
        CaptionWord(
          textStart: from,
          textEnd: text.length,
          start: Duration(milliseconds: wordStart),
          end: Duration(
            milliseconds: math.max(wordStart, ms(group[j].word.end) - start),
          ),
        ),
      );
    }

    drafts.add(
      CaptionDraft(
        text: text.toString(),
        start: Duration(milliseconds: start),
        end: Duration(milliseconds: end),
        words: captionWords,
      ),
    );
    floor = end;
  }
  return drafts;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/logic/captions/caption_grouping_test.dart`
Expected: PASS, 16 tests.

- [ ] **Step 5: Mutation check the rules that could pass vacuously**

Temporarily change `if (next > start) end = math.min(end, next);` to `if (next > start) {}` and rerun — the "hold stops at the next caption" and "never overlap" tests must fail. Temporarily change `math.max(ms(group.first.word.start), floor)` to `ms(group.first.word.start)` — the "never overlap" test must fail. Temporarily delete the `groups.last.add(w); continue;` branch — the "even straight after a sentence" test must fail. Restore each change and rerun until green.

- [ ] **Step 6: Analyzer, then commit**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.

```bash
git add lib/features/video_editor/logic/captions/caption_grouping.dart test/features/video_editor/logic/captions/caption_grouping_test.dart
git commit -m "feat(captions): group words into timed captions

Breaks at sentence ends, pauses and the chosen length; holds briefly
into silence; never overlaps two captions whatever order the provider's
times arrive in.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `SlimshotApi` — the app's one server client

**Files:**
- Create: `lib/core/services/slimshot_api.dart`
- Test: `test/core/services/slimshot_api_test.dart`

**Interfaces:**
- Produces: `SlimshotApiException(String code, [String message])` with `static const network = 'NETWORK'`, `static const badResponse = 'BAD_RESPONSE'`; `abstract class DeviceTokenStore { Future<String?> read(); Future<void> write(String token); Future<void> clear(); }`; `PrefsDeviceTokenStore` (key `slimshot_device_token`); `SlimshotApi({required String baseUrl, http.Client? client, DeviceTokenStore tokens = const PrefsDeviceTokenStore()})` with `static const String configuredBaseUrl`, `static bool get isConfigured`, `Uri uri(String path)`, `Future<Map<String, dynamic>> send(http.BaseRequest Function() build, {Duration timeout = SlimshotApi.defaultTimeout})`, `void close()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

class MemoryTokens implements DeviceTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

http.Response failure(String code, int status) => http.Response(
      jsonEncode({
        'success': false,
        'error': {'code': code, 'message': 'm', 'traceId': 't'},
      }),
      status,
    );

Matcher throwsCode(String code) => throwsA(
      isA<SlimshotApiException>().having((e) => e.code, 'code', code),
    );

void main() {
  test('registers once, keeps the token, and sends it', () async {
    final seen = <http.Request>[];
    final tokens = MemoryTokens();
    final api = SlimshotApi(
      baseUrl: 'https://api.test/',
      tokens: tokens,
      client: MockClient((request) async {
        seen.add(request);
        if (request.url.path.endsWith('/devices')) {
          return envelope({'token': 'tok-1'}, 201);
        }
        return envelope({'ok': true});
      }),
    );
    await api.send(() => http.Request('GET', api.uri('/captions/x')));
    await api.send(() => http.Request('GET', api.uri('/captions/x')));

    expect(seen.where((r) => r.url.path == '/api/app/v1/devices'), hasLength(1));
    expect(jsonDecode(seen.first.body), {'platform': 'android'});
    expect(tokens.token, 'tok-1');
    expect(seen.last.headers['Authorization'], 'Bearer tok-1');
    expect(seen.last.url.toString(), 'https://api.test/api/app/v1/captions/x');
  });

  test('a stored token is used without registering', () async {
    var registrations = 0;
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 'kept',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) registrations++;
        return envelope({'auth': request.headers['Authorization']});
      }),
    );
    final data = await api.send(() => http.Request('GET', api.uri('/x')));
    expect(data, {'auth': 'Bearer kept'});
    expect(registrations, 0);
  });

  test('a token the server no longer knows is replaced once and the request rebuilt',
      () async {
    var built = 0;
    final tokens = MemoryTokens()..token = 'stale';
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: tokens,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) {
          return envelope({'token': 'fresh'}, 201);
        }
        return request.headers['Authorization'] == 'Bearer fresh'
            ? envelope({'ok': true})
            : failure('UNAUTHENTICATED', 401);
      }),
    );
    final data = await api.send(() {
      built++;
      return http.Request('GET', api.uri('/x'));
    });
    expect(data, {'ok': true});
    expect(built, 2);
    expect(tokens.token, 'fresh');
  });

  test('a second refusal is an answer, not a loop', () async {
    var registrations = 0;
    var sends = 0;
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) {
          registrations++;
          return envelope({'token': 'tok-$registrations'}, 201);
        }
        sends++;
        return failure('UNAUTHENTICATED', 401);
      }),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsCode('UNAUTHENTICATED'),
    );
    expect(sends, 2);
    expect(registrations, 2);
  });

  test('a server refusal carries its code and message', () async {
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) async => failure('CAPTIONS_UNAVAILABLE', 503)),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsA(
        isA<SlimshotApiException>()
            .having((e) => e.code, 'code', 'CAPTIONS_UNAVAILABLE')
            .having((e) => e.message, 'message', 'm'),
      ),
    );
  });

  test('no connection is NETWORK', () async {
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsCode(SlimshotApiException.network),
    );
  });

  test('a request that never answers times out as NETWORK', () async {
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      api.send(
        () => http.Request('GET', api.uri('/x')),
        timeout: const Duration(milliseconds: 20),
      ),
      throwsCode(SlimshotApiException.network),
    );
  });

  test('a body that is not the envelope is BAD_RESPONSE', () async {
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) async => http.Response('<html>', 502)),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsCode(SlimshotApiException.badResponse),
    );
  });

  test('the token is kept in preferences', () async {
    SharedPreferences.setMockInitialValues({});
    const store = PrefsDeviceTokenStore();
    expect(await store.read(), isNull);
    await store.write('t');
    expect(await store.read(), 't');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a build without a server address has no server', () {
    expect(SlimshotApi.isConfigured, isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/services/slimshot_api_test.dart`
Expected: FAIL — `slimshot_api.dart` does not exist.

- [ ] **Step 3: Write `slimshot_api.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A request the server refused, or one that never reached it.
class SlimshotApiException implements Exception {
  const SlimshotApiException(this.code, [this.message = '']);

  /// The server's error code (`CAPTIONS_UNAVAILABLE`, `NOT_FOUND`, …) or one
  /// of the local codes below.
  final String code;
  final String message;

  /// No connection, a timeout, or a request cut off.
  static const String network = 'NETWORK';

  /// A body that was not the server's envelope.
  static const String badResponse = 'BAD_RESPONSE';

  @override
  String toString() =>
      'SlimshotApiException($code${message.isEmpty ? '' : ': $message'})';
}

/// Where this install's device token is kept.
abstract class DeviceTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// The token in `shared_preferences`.
///
/// An anonymous device token grants only caption jobs. It moves to secure
/// storage when sign-in makes a token worth protecting.
class PrefsDeviceTokenStore implements DeviceTokenStore {
  const PrefsDeviceTokenStore();

  static const String key = 'slimshot_device_token';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, token);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

/// The app's one client for SlimShot's own server.
///
/// Auto captions is the first server feature of several (fonts and sign-in
/// follow), so registration, the token and the response envelope live here
/// rather than in any one feature.
class SlimshotApi {
  SlimshotApi({
    required String baseUrl,
    http.Client? client,
    DeviceTokenStore tokens = const PrefsDeviceTokenStore(),
  })  : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _tokens = tokens;

  /// The server this build talks to: `--dart-define=SLIMSHOT_API_URL=…`.
  /// Empty when the build carries none.
  static const String configuredBaseUrl =
      String.fromEnvironment('SLIMSHOT_API_URL');

  /// Whether this build has a server at all. Auto captions is offered only
  /// then — it is not offered before it works.
  static bool get isConfigured => configuredBaseUrl.isNotEmpty;

  static const Duration defaultTimeout = Duration(seconds: 20);

  final String _base;
  final http.Client _client;
  final DeviceTokenStore _tokens;

  Uri uri(String path) => Uri.parse('$_base/api/app/v1$path');

  /// Sends the request [build] makes, as this device, and returns the
  /// envelope's `data`.
  ///
  /// [build] runs again for the one retry after a 401: a request can be sent
  /// only once, and a multipart body is a stream.
  Future<Map<String, dynamic>> send(
    http.BaseRequest Function() build, {
    Duration timeout = defaultTimeout,
  }) async {
    var token = await _tokens.read() ?? await _register(timeout);
    var response = await _perform(_authorised(build(), token), timeout);
    if (response.statusCode == HttpStatus.unauthorized) {
      // A token the server no longer knows — a reset database, a revoked
      // install. Register again once; a second refusal is an answer, not a
      // reason to loop.
      await _tokens.clear();
      token = await _register(timeout);
      response = await _perform(_authorised(build(), token), timeout);
    }
    return _decode(response);
  }

  /// Aborts anything in flight — how Cancel stops an upload.
  void close() => _client.close();

  http.BaseRequest _authorised(http.BaseRequest request, String token) {
    request.headers['Authorization'] = 'Bearer $token';
    return request;
  }

  Future<String> _register(Duration timeout) async {
    final request = http.Request('POST', uri('/devices'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'platform': 'android'});
    final data = _decode(await _perform(request, timeout));
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No device token.',
      );
    }
    await _tokens.write(token);
    return token;
  }

  Future<http.Response> _perform(
    http.BaseRequest request,
    Duration timeout,
  ) async {
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const SlimshotApiException(SlimshotApiException.network, 'Timed out.');
    } on SocketException catch (e) {
      throw SlimshotApiException(SlimshotApiException.network, e.message);
    } on http.ClientException catch (e) {
      throw SlimshotApiException(SlimshotApiException.network, e.message);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      body = null;
    }
    if (body is Map && body['success'] == true && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      final code = error['code'];
      final message = error['message'];
      throw SlimshotApiException(
        code is String ? code : 'HTTP_${response.statusCode}',
        message is String ? message : '',
      );
    }
    throw SlimshotApiException(
      SlimshotApiException.badResponse,
      'HTTP ${response.statusCode}',
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/services/slimshot_api_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Mutation check the loop guard**

Temporarily wrap the retry in a `while (response.statusCode == HttpStatus.unauthorized)` loop instead of `if` and rerun: "a second refusal is an answer, not a loop" must fail (hang or wrong counts — cap the run with `--timeout 30s`). Restore.

- [ ] **Step 6: Analyzer, then commit**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.

```bash
git add lib/core/services/slimshot_api.dart test/core/services/slimshot_api_test.dart
git commit -m "feat(server): SlimshotApi, the app's one client for its own server

Registers the device once, keeps its token, re-registers once on a 401
and decodes the response envelope into one typed error.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: `CaptionService` and the error lines

**Files:**
- Modify: `pubspec.yaml` (add `http_parser: ^4.1.2` under `dependencies`, beside `http`)
- Create: `lib/features/video_editor/services/caption_errors.dart`
- Create: `lib/features/video_editor/services/caption_service.dart`
- Test: `test/features/video_editor/services/caption_service_test.dart`

**Interfaces:**
- Consumes: `SlimshotApi`, `SlimshotApiException` (Task 9); `CaptionTranscript` (Task 7).
- Produces: `class CaptionCancelled implements Exception`; `class CaptionFailure implements Exception { code; noSound, noSpeech, renderFailed }`; `const String kCaptionPollTimeout = 'POLL_TIMEOUT'`; `String captionErrorMessage(Object error)`; `CaptionJobStart({required String jobId, required Duration pollAfter})`; `CaptionService(SlimshotApi api, {Future<void> Function(Duration)? delay, DateTime Function()? clock})` with `Future<CaptionJobStart> start({required String audioPath, String? language, required String idempotencyKey})` and `Future<CaptionTranscript> result(CaptionJobStart job, {required bool Function() isCancelled})`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `http: ^1.2.1`, add `  http_parser: ^4.1.2` (already in `pubspec.lock` as a transitive dependency of `http`; `MediaType` lives there). Run: `flutter pub get --offline` → Expected: `Got dependencies!`.

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';

class MemoryTokens implements DeviceTokenStore {
  String? token = 'tok';

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

void main() {
  late File audio;
  const job = CaptionJobStart(jobId: 'cap_1', pollAfter: Duration(milliseconds: 1500));

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('captions');
    audio = File('${dir.path}/a.m4a')..writeAsBytesSync([1, 2, 3, 4]);
  });

  CaptionService serviceWith(
    MockClient client, {
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  }) =>
      CaptionService(
        SlimshotApi(baseUrl: 'https://api.test', client: client, tokens: MemoryTokens()),
        delay: delay ?? (_) async {},
        clock: clock,
      );

  group('upload', () {
    test('sends the audio, the language and the key as the server expects',
        () async {
      late http.Request upload;
      final service = serviceWith(MockClient((request) async {
        upload = request;
        return envelope({'jobId': 'cap_1', 'status': 'queued', 'pollAfterMs': 900}, 202);
      }));
      final started = await service.start(
        audioPath: audio.path,
        language: 'fr',
        idempotencyKey: 'key-12345678',
      );

      expect(started.jobId, 'cap_1');
      expect(started.pollAfter, const Duration(milliseconds: 900));
      expect(upload.method, 'POST');
      expect(upload.url.path, '/api/app/v1/captions');
      expect(upload.headers['Idempotency-Key'], 'key-12345678');
      expect(upload.headers['Authorization'], 'Bearer tok');
      expect(upload.headers['Content-Type'], startsWith('multipart/form-data'));
      final body = latin1.decode(upload.bodyBytes);
      expect(body, contains('name="audio"; filename="captions.m4a"'));
      expect(body, contains('content-type: audio/mp4'));
      expect(body, contains('name="language"'));
    });

    test('Auto detect sends no language', () async {
      late http.Request upload;
      final service = serviceWith(MockClient((request) async {
        upload = request;
        return envelope({'jobId': 'cap_1', 'status': 'queued'}, 202);
      }));
      final started = await service.start(audioPath: audio.path, idempotencyKey: 'key-12345678');
      expect(latin1.decode(upload.bodyBytes), isNot(contains('name="language"')));
      expect(started.pollAfter, CaptionService.defaultPollAfter);
    });
  });

  group('polling', () {
    test("polls at the server's pace until the words arrive", () async {
      final statuses = ['queued', 'processing', 'completed'];
      final waits = <Duration>[];
      final service = serviceWith(
        MockClient((_) async {
          final status = statuses.removeAt(0);
          if (status != 'completed') {
            return envelope({'jobId': 'cap_1', 'status': status, 'pollAfterMs': 700});
          }
          return envelope({
            'jobId': 'cap_1',
            'status': 'completed',
            'result': {
              'provider': 'elevenlabs',
              'language': 'en',
              'durationSeconds': 1.2,
              'text': 'Hi there.',
              'words': [
                {'text': 'Hi', 'start': 0.1, 'end': 0.3, 'confidence': 1},
                {'text': 'there.', 'start': 0.4, 'end': 0.8, 'confidence': 0.9},
              ],
            },
          });
        }),
        delay: (d) async => waits.add(d),
      );
      final transcript = await service.result(job, isCancelled: () => false);
      expect(transcript.words.map((w) => w.text), ['Hi', 'there.']);
      expect(waits, const [
        Duration(milliseconds: 1500),
        Duration(milliseconds: 700),
        Duration(milliseconds: 700),
      ]);
    });

    test('a failed job carries its code', () async {
      final service = serviceWith(MockClient((_) async => envelope({
            'jobId': 'cap_1',
            'status': 'failed',
            'error': {'code': 'PROVIDER_FAILED', 'message': 'no'},
          })));
      await expectLater(
        service.result(job, isCancelled: () => false),
        throwsA(isA<SlimshotApiException>().having((e) => e.code, 'code', 'PROVIDER_FAILED')),
      );
    });

    test('gives up after ten minutes', () async {
      var now = DateTime(2026);
      final service = serviceWith(
        MockClient((_) async => envelope({'jobId': 'cap_1', 'status': 'processing', 'pollAfterMs': 1500})),
        delay: (_) async {
          now = now.add(const Duration(minutes: 3));
        },
        clock: () => now,
      );
      await expectLater(
        service.result(job, isCancelled: () => false),
        throwsA(isA<SlimshotApiException>().having((e) => e.code, 'code', kCaptionPollTimeout)),
      );
    });

    test('a cancel stops polling before the next request', () async {
      var polls = 0;
      var cancelled = false;
      final service = serviceWith(MockClient((_) async {
        polls++;
        cancelled = true;
        return envelope({'jobId': 'cap_1', 'status': 'processing', 'pollAfterMs': 10});
      }));
      await expectLater(
        service.result(job, isCancelled: () => cancelled),
        throwsA(isA<CaptionCancelled>()),
      );
      expect(polls, 1);
    });
  });

  group('captionErrorMessage', () {
    test('every cause has its one line', () {
      const expected = {
        SlimshotApiException.network: 'No connection. Check your internet and try again.',
        'CAPTIONS_UNAVAILABLE': 'Auto captions are unavailable right now.',
        'UNAUTHENTICATED': 'Auto captions are unavailable right now.',
        'PROVIDER_FAILED': "Couldn't transcribe this audio. Try again.",
        'VALIDATION_FAILED': "Couldn't transcribe this audio. Try again.",
        'PAYLOAD_TOO_LARGE': 'This video is too long for auto captions.',
        'NOT_FOUND': 'Captions expired before they arrived. Try again.',
        kCaptionPollTimeout: 'Captions took too long. Try again.',
      };
      expected.forEach((code, line) {
        expect(captionErrorMessage(SlimshotApiException(code)), line, reason: code);
      });
      expect(captionErrorMessage(const CaptionFailure(CaptionFailure.noSpeech)), 'No speech found.');
      expect(captionErrorMessage(const CaptionFailure(CaptionFailure.noSound)), 'No sound to caption.');
      expect(
        captionErrorMessage(PlatformException(code: 'caption_audio_failed')),
        "Couldn't read this project's sound. Try again.",
      );
      expect(captionErrorMessage(StateError('?')), "Couldn't transcribe this audio. Try again.");
    });
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/features/video_editor/services/caption_service_test.dart`
Expected: FAIL — `caption_errors.dart` / `caption_service.dart` do not exist.

- [ ] **Step 4: Write `caption_errors.dart`**

```dart
import 'package:flutter/services.dart';

import '../../../core/services/slimshot_api.dart';

/// Polling ran for [CaptionService.pollLimit] without an answer.
const String kCaptionPollTimeout = 'POLL_TIMEOUT';

/// Auto captions stopped because the user cancelled — never shown as an error.
class CaptionCancelled implements Exception {
  const CaptionCancelled();
}

/// A reason auto captions ended that the app decided, not the server.
class CaptionFailure implements Exception {
  const CaptionFailure(this.code);

  final String code;

  /// The chosen sources hold nothing audible.
  static const String noSound = 'NO_SOUND';

  /// The server heard no words.
  static const String noSpeech = 'NO_SPEECH';

  /// The native audio pass failed.
  static const String renderFailed = 'RENDER_FAILED';
}

/// The one line the user sees for [error] — no title, no code.
String captionErrorMessage(Object error) {
  final code = switch (error) {
    SlimshotApiException(:final code) => code,
    CaptionFailure(:final code) => code,
    PlatformException() => CaptionFailure.renderFailed,
    _ => '',
  };
  return switch (code) {
    SlimshotApiException.network =>
      'No connection. Check your internet and try again.',
    'CAPTIONS_UNAVAILABLE' || 'UNAUTHENTICATED' =>
      'Auto captions are unavailable right now.',
    'PAYLOAD_TOO_LARGE' => 'This video is too long for auto captions.',
    'NOT_FOUND' => 'Captions expired before they arrived. Try again.',
    kCaptionPollTimeout => 'Captions took too long. Try again.',
    CaptionFailure.noSpeech => 'No speech found.',
    CaptionFailure.noSound => 'No sound to caption.',
    CaptionFailure.renderFailed =>
      "Couldn't read this project's sound. Try again.",
    _ => "Couldn't transcribe this audio. Try again.",
  };
}
```

- [ ] **Step 5: Write `caption_service.dart`**

```dart
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/captions/caption_transcript.dart';
import 'caption_errors.dart';

/// A caption job the server has accepted.
class CaptionJobStart {
  const CaptionJobStart({required this.jobId, required this.pollAfter});

  final String jobId;
  final Duration pollAfter;
}

/// Auto captions on the server: upload the audio, then poll until the words
/// arrive.
class CaptionService {
  CaptionService(
    this._api, {
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  })  : _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now;

  final SlimshotApi _api;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;

  /// Minutes of speech on a slow connection.
  static const Duration uploadTimeout = Duration(seconds: 120);

  /// How long a job may take before the app stops asking. The server keeps a
  /// finished result for 180s, so a job that is merely late is never given up
  /// on early.
  static const Duration pollLimit = Duration(minutes: 10);

  static const Duration defaultPollAfter = Duration(milliseconds: 1500);

  /// Uploads [audioPath] and returns the job. [idempotencyKey] names this
  /// upload: sent again with the same key, the server answers with the same
  /// job instead of starting a second one.
  Future<CaptionJobStart> start({
    required String audioPath,
    String? language,
    required String idempotencyKey,
  }) async {
    final bytes = await File(audioPath).readAsBytes();
    final data = await _api.send(
      () {
        final request = http.MultipartRequest('POST', _api.uri('/captions'))
          ..headers['Idempotency-Key'] = idempotencyKey
          ..files.add(
            http.MultipartFile.fromBytes(
              'audio',
              bytes,
              filename: 'captions.m4a',
              contentType: MediaType('audio', 'mp4'),
            ),
          );
        if (language != null) request.fields['language'] = language;
        return request;
      },
      timeout: uploadTimeout,
    );
    final jobId = data['jobId'];
    if (jobId is! String || jobId.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No job id.',
      );
    }
    return CaptionJobStart(jobId: jobId, pollAfter: _pollAfter(data));
  }

  /// Polls [job] until its words arrive, at the pace the server asks for.
  Future<CaptionTranscript> result(
    CaptionJobStart job, {
    required bool Function() isCancelled,
  }) async {
    final began = _clock();
    var wait = job.pollAfter;
    while (true) {
      if (isCancelled()) throw const CaptionCancelled();
      if (_clock().difference(began) >= pollLimit) {
        throw const SlimshotApiException(kCaptionPollTimeout);
      }
      await _delay(wait);
      if (isCancelled()) throw const CaptionCancelled();

      final data = await _api.send(
        () => http.Request('GET', _api.uri('/captions/${job.jobId}')),
      );
      switch (data['status']) {
        case 'completed':
          final result = data['result'];
          if (result is! Map) {
            throw const SlimshotApiException(
              SlimshotApiException.badResponse,
              'No result.',
            );
          }
          return CaptionTranscript.fromJson(Map<String, dynamic>.from(result));
        case 'failed':
          final error = data['error'];
          final code = error is Map ? error['code'] : null;
          final message = error is Map ? error['message'] : null;
          throw SlimshotApiException(
            code is String ? code : 'PROVIDER_FAILED',
            message is String ? message : '',
          );
        default:
          wait = _pollAfter(data);
      }
    }
  }

  static Duration _pollAfter(Map<String, dynamic> data) {
    final ms = data['pollAfterMs'];
    return ms is num && ms > 0
        ? Duration(milliseconds: ms.toInt())
        : defaultPollAfter;
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/services/caption_service_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 7: Analyzer, then commit**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.

```bash
git add pubspec.yaml pubspec.lock lib/features/video_editor/services/caption_errors.dart lib/features/video_editor/services/caption_service.dart test/features/video_editor/services/caption_service_test.dart
git commit -m "feat(captions): upload, poll, and one line for every failure

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: `CaptionPipeline` — render, upload, listen, place

**Files:**
- Create: `lib/features/video_editor/services/caption_pipeline.dart`
- Test: `test/features/video_editor/services/caption_pipeline_test.dart`

**Interfaces:**
- Consumes: `CaptionAudioResult`, `CaptionAudioCancelled` (Task 6); `CaptionJobStart` (Task 10); `CaptionCancelled`, `CaptionFailure` (Task 10); `SlimshotApiException` (Task 9); `rebuildTranscriptSpacing` (Task 7); `groupCaptionWords`, `CaptionDraft` (Task 8); `CaptionSource`, `CaptionLength` (Task 5).
- Produces: `enum CaptionStage { preparing, uploading, listening, placing }`; `CaptionRequest({CaptionSource source = video, String? language, CaptionLength length = phrase})`; `CaptionPipeline({required Future<String> Function() audioPath, required Future<CaptionAudioResult> Function(String outputPath, CaptionSource source, void Function(double) onProgress) renderAudio, required Future<CaptionJobStart> Function(String audioPath, String? language, String idempotencyKey) startJob, required Future<CaptionTranscript> Function(CaptionJobStart job, bool Function() isCancelled) awaitJob, required void Function() onCancel, Future<void> Function(String path)? deleteFile, String Function()? newKey})` with `Future<List<CaptionDraft>> run(CaptionRequest request, {required void Function(CaptionStage stage, double? progress) onProgress})` and `void cancel()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';

void main() {
  const hello = CaptionTranscript(
    text: 'Hello world',
    words: [
      TranscriptWord(text: 'Hello', start: 0.2, end: 0.5),
      TranscriptWord(text: 'world', start: 0.6, end: 0.9),
    ],
  );
  const sound = CaptionAudioResult(outputPath: '/tmp/captions.m4a', durationSeconds: 3, hasSound: true);
  const job = CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero);

  late List<String> deleted;
  late List<String> keys;
  late int cancels;

  setUp(() {
    deleted = [];
    keys = [];
    cancels = 0;
  });

  CaptionPipeline pipeline({
    Future<CaptionAudioResult> Function(CaptionSource source)? render,
    Future<CaptionJobStart> Function(String? language)? start,
    Future<CaptionTranscript> Function(bool Function() isCancelled)? transcript,
  }) {
    var n = 0;
    return CaptionPipeline(
      audioPath: () async => '/tmp/captions.m4a',
      deleteFile: (path) async => deleted.add(path),
      newKey: () => 'key-${++n}',
      renderAudio: (path, source, onProgress) async {
        onProgress(0.5);
        return render == null ? sound : render(source);
      },
      startJob: (path, language, key) async {
        keys.add(key);
        return start == null ? job : start(language);
      },
      awaitJob: (job, isCancelled) =>
          transcript == null ? Future.value(hello) : transcript(isCancelled),
      onCancel: () => cancels++,
    );
  }

  test('render → upload → listen → place, and the audio file is cleaned up',
      () async {
    final stages = <CaptionStage>[];
    final progress = <double?>[];
    final drafts = await pipeline().run(
      const CaptionRequest(),
      onProgress: (stage, value) {
        if (stages.isEmpty || stages.last != stage) stages.add(stage);
        progress.add(value);
      },
    );
    expect(stages, CaptionStage.values);
    expect(progress, contains(0.5));
    expect(drafts.single.text, 'Hello world');
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('the chosen sound and language reach the steps that use them', () async {
    CaptionSource? rendered;
    String? sent = 'unset';
    await pipeline(
      render: (source) async {
        rendered = source;
        return sound;
      },
      start: (language) async {
        sent = language;
        return job;
      },
    ).run(
      const CaptionRequest(source: CaptionSource.tracks, language: 'yo'),
      onProgress: (_, __) {},
    );
    expect(rendered, CaptionSource.tracks);
    expect(sent, 'yo');
  });

  test('nothing to hear stops before any upload', () async {
    await expectLater(
      pipeline(render: (_) async => const CaptionAudioResult(outputPath: '', durationSeconds: 0, hasSound: false))
          .run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionFailure>().having((e) => e.code, 'code', CaptionFailure.noSound)),
    );
    expect(keys, isEmpty);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('no words is No speech found', () async {
    await expectLater(
      pipeline(transcript: (_) async => const CaptionTranscript(text: '', words: []))
          .run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionFailure>().having((e) => e.code, 'code', CaptionFailure.noSpeech)),
    );
  });

  test('a cancel while listening ends in CaptionCancelled and places nothing',
      () async {
    late CaptionPipeline p;
    p = pipeline(transcript: (isCancelled) async {
      p.cancel();
      expect(isCancelled(), isTrue);
      return hello;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionCancelled>()),
    );
    expect(cancels, 1);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('a render stopped natively is a cancel', () async {
    await expectLater(
      pipeline(render: (_) async => throw const CaptionAudioCancelled())
          .run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionCancelled>()),
    );
  });

  test('Try again after an upload that never landed reuses its key', () async {
    var attempts = 0;
    final p = pipeline(start: (_) async {
      if (attempts++ == 0) throw const SlimshotApiException(SlimshotApiException.network);
      return job;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<SlimshotApiException>()),
    );
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-1']);
  });

  test('Try again after the server had the job takes a new key', () async {
    var attempts = 0;
    final p = pipeline(transcript: (_) async {
      if (attempts++ == 0) throw const SlimshotApiException('PROVIDER_FAILED');
      return hello;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<SlimshotApiException>()),
    );
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-2']);
  });

  test('a finished run retires its key', () async {
    final p = pipeline();
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-2']);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/video_editor/services/caption_pipeline_test.dart`
Expected: FAIL — `caption_pipeline.dart` does not exist.

- [ ] **Step 3: Write `caption_pipeline.dart`**

```dart
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/captions/caption_grouping.dart';
import '../logic/captions/caption_settings.dart';
import '../logic/captions/caption_transcript.dart';
import 'caption_audio_result.dart';
import 'caption_errors.dart';
import 'caption_service.dart';

/// Where a run is, for the progress sheet.
enum CaptionStage { preparing, uploading, listening, placing }

/// What the caption sheet asked for.
class CaptionRequest {
  const CaptionRequest({
    this.source = CaptionSource.video,
    this.language,
    this.length = CaptionLength.phrase,
  });

  final CaptionSource source;

  /// ISO 639-1, or null for Auto detect.
  final String? language;
  final CaptionLength length;
}

/// Timeline sound → server → caption drafts, one step at a time and
/// cancellable at every one of them.
///
/// Every step arrives as a function so the order, the cancel and the key rule
/// are tested without a device or a network; the screen wires the real ones.
class CaptionPipeline {
  CaptionPipeline({
    required this.audioPath,
    required this.renderAudio,
    required this.startJob,
    required this.awaitJob,
    required this.onCancel,
    Future<void> Function(String path)? deleteFile,
    String Function()? newKey,
  })  : _deleteFile = deleteFile ?? _deleteQuietly,
        _newKey = newKey ?? const Uuid().v4;

  final Future<String> Function() audioPath;
  final Future<CaptionAudioResult> Function(
    String outputPath,
    CaptionSource source,
    void Function(double progress) onProgress,
  ) renderAudio;
  final Future<CaptionJobStart> Function(
    String audioPath,
    String? language,
    String idempotencyKey,
  ) startJob;
  final Future<CaptionTranscript> Function(
    CaptionJobStart job,
    bool Function() isCancelled,
  ) awaitJob;

  /// Stops whatever is in flight: the native render, the upload.
  final void Function() onCancel;

  final Future<void> Function(String path) _deleteFile;
  final String Function() _newKey;

  String? _key;
  bool _cancelled = false;

  Future<List<CaptionDraft>> run(
    CaptionRequest request, {
    required void Function(CaptionStage stage, double? progress) onProgress,
  }) async {
    _cancelled = false;
    var jobStarted = false;
    final path = await audioPath();
    try {
      onProgress(CaptionStage.preparing, 0);
      final audio = await renderAudio(
        path,
        request.source,
        (p) => onProgress(CaptionStage.preparing, p),
      );
      _throwIfCancelled();
      if (!audio.hasSound) throw const CaptionFailure(CaptionFailure.noSound);

      onProgress(CaptionStage.uploading, null);
      final job = await startJob(path, request.language, _key ??= _newKey());
      jobStarted = true;
      _throwIfCancelled();

      onProgress(CaptionStage.listening, null);
      final transcript = await awaitJob(job, () => _cancelled);
      _throwIfCancelled();

      onProgress(CaptionStage.placing, null);
      final drafts = groupCaptionWords(
        rebuildTranscriptSpacing(transcript.text, transcript.words),
        request.length,
      );
      if (drafts.isEmpty) throw const CaptionFailure(CaptionFailure.noSpeech);
      _key = null;
      return drafts;
    } catch (error) {
      if (_cancelled ||
          error is CaptionAudioCancelled ||
          error is CaptionCancelled) {
        throw const CaptionCancelled();
      }
      // A key names one upload. Once the server holds a job for it, the same
      // key answers with that job — a failed one included — so a retry after
      // it needs a fresh key. A retry after an upload that never landed must
      // reuse its key, or a lost response becomes a second job.
      final uploadLost = !jobStarted &&
          error is SlimshotApiException &&
          error.code == SlimshotApiException.network;
      if (!uploadLost) _key = null;
      rethrow;
    } finally {
      await _deleteFile(path);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    onCancel();
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const CaptionCancelled();
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone, or never written: nothing to clean up.
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/services/caption_pipeline_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Mutation check the key rule**

Temporarily replace `if (!uploadLost) _key = null;` with `_key = null;` — "reuses its key" must fail. Then with nothing (never reset) — "takes a new key" must fail. Restore.

- [ ] **Step 6: Analyzer, then commit**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.

```bash
git add lib/features/video_editor/services/caption_pipeline.dart test/features/video_editor/services/caption_pipeline_test.dart
git commit -m "feat(captions): the pipeline from timeline sound to caption drafts

Cancellable at every step; a retry reuses the upload key only when the
upload never landed, so a lost response never becomes a second job.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Placing captions on the timeline

**Files:**
- Create: `lib/features/video_editor/logic/captions/caption_placement.dart`
- Create: `lib/features/video_editor/widgets/timeline/lane_gutter_icons.dart`
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart` (after `addTextOverlay`, ~line 2960)
- Modify: `lib/features/video_editor/widgets/timeline/scrollable_timeline.dart:1655-1665` (the gutter's icon list)
- Test: `test/features/video_editor/logic/captions/caption_placement_test.dart`

**Interfaces:**
- Consumes: `CaptionDraft` (Task 8); `CaptionSettings` (Task 5); `TextOverlayModel.isCaption` (Task 5).
- Produces: `final TextTemplate captionDefaultTemplate`; `List<TextOverlayModel> buildCaptionOverlays({required List<CaptionDraft> drafts, required String setId, required int lane, Size? canvasSize})`; `VideoEditorNotifier.placeCaptions(List<CaptionDraft> drafts, CaptionSettings settings, {Size? canvasSize})`; `List<IconData> laneGutterIcons({required int lane, required List<AudioTrackModel> audios, required List<TextOverlayModel> texts, required List<ImageOverlayModel> images, required List<VideoOverlayModel> videos})`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_placement.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/lane_gutter_icons.dart';

void main() {
  const hello = [
    CaptionWord(textStart: 0, textEnd: 5, start: Duration.zero, end: Duration(milliseconds: 300)),
    CaptionWord(textStart: 6, textEnd: 11, start: Duration(milliseconds: 400), end: Duration(milliseconds: 700)),
  ];
  const drafts = [
    CaptionDraft(
      text: 'Hello world',
      start: Duration(milliseconds: 1000),
      end: Duration(milliseconds: 2000),
      words: hello,
    ),
    CaptionDraft(
      text: 'Goodbye',
      start: Duration(milliseconds: 2000),
      end: Duration(milliseconds: 2600),
      words: [
        CaptionWord(textStart: 0, textEnd: 7, start: Duration.zero, end: Duration(milliseconds: 200)),
      ],
    ),
  ];
  const settings = CaptionSettings(setId: 'captions_1');

  VideoEditorNotifier withTexts(List<TextOverlayModel> texts) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(textOverlays: texts);

  List<TextOverlayModel> captionsOf(VideoEditorNotifier n) =>
      n.state.textOverlays.where((t) => t.isCaption).toList();

  test('each caption is a text in the default look, on the given lane', () {
    final list = buildCaptionOverlays(
      drafts: drafts,
      setId: 'captions_1',
      lane: 2,
      canvasSize: const Size(360, 640),
    );
    expect(list.map((t) => t.text), ['Hello world', 'Goodbye']);
    expect(list.map((t) => t.id).toSet(), hasLength(2));

    final first = list.first;
    expect((first.startTime, first.endTime), (drafts.first.start, drafts.first.end));
    expect(first.captionSetId, 'captions_1');
    expect(first.captionWords, hello);
    expect(first.laneIndex, 2);
    expect(first.referenceCanvasSize, const Size(360, 640));
    expect(first.boxWidth, isNull, reason: 'a shared reference canvas already wraps them alike');
    // The Subtitle look, less its fades: a half-second fade is most of a
    // one-second caption's life.
    expect([first.inAnimation, first.outAnimation, first.loopAnimation], ['none', 'none', 'none']);
    expect(
      captionDefaultTemplate.isAppliedTo(
        first.copyWith(
          inAnimation: captionDefaultTemplate.inAnimation,
          outAnimation: captionDefaultTemplate.outAnimation,
        ),
      ),
      isTrue,
    );
  });

  test('places the set on the first lane free across it, as one undo step', () {
    final n = withTexts([
      TextOverlayModel(
        id: 'title',
        text: 'Title',
        startTime: const Duration(milliseconds: 1500),
        endTime: const Duration(seconds: 4),
      ),
    ]);
    n.placeCaptions(drafts, settings);

    final captions = captionsOf(n);
    expect(captions, hasLength(2));
    expect(captions.every((t) => t.laneIndex == 1), isTrue);
    expect(n.state.captionSettings, settings);

    n.undo();
    expect(captionsOf(n), isEmpty);
    expect(n.state.captionSettings, isNull);
  });

  test('regenerating replaces the set, keeps plain text, and reuses the freed lane',
      () {
    final n = withTexts([
      TextOverlayModel(
        id: 'title',
        text: 'Title',
        startTime: const Duration(milliseconds: 1500),
        endTime: const Duration(seconds: 4),
      ),
    ]);
    n.placeCaptions(drafts, settings);
    n.placeCaptions(
      const [
        CaptionDraft(
          text: 'Fresh',
          start: Duration(milliseconds: 1000),
          end: Duration(milliseconds: 1800),
          words: [
            CaptionWord(textStart: 0, textEnd: 5, start: Duration.zero, end: Duration(milliseconds: 300)),
          ],
        ),
      ],
      const CaptionSettings(setId: 'captions_2'),
    );

    final captions = captionsOf(n);
    expect(captions.map((t) => t.text), ['Fresh']);
    expect(captions.single.captionSetId, 'captions_2');
    expect(captions.single.laneIndex, 1);
    expect(n.state.textOverlays.any((t) => t.id == 'title'), isTrue);
    expect(n.state.captionSettings?.setId, 'captions_2');
  });

  test('nothing to place changes nothing and takes no undo step', () {
    final n = withTexts(const []);
    n.placeCaptions(const [], settings);
    expect(n.state.canUndo, isFalse);
    expect(n.state.captionSettings, isNull);
  });

  test('a caption lane is marked as captions in the gutter', () {
    final caption = TextOverlayModel(id: 'c', text: 'Hi', captionSetId: 's', laneIndex: 1);
    final plain = TextOverlayModel(id: 't', text: 'Hi');
    List<IconData> icons(int lane, List<TextOverlayModel> texts) => laneGutterIcons(
          lane: lane,
          audios: const [],
          texts: texts,
          images: const [],
          videos: const [],
        );
    expect(icons(1, [caption, plain]), [LucideIcons.subtitles]);
    expect(icons(0, [caption, plain]), [LucideIcons.type]);
    expect(
      icons(0, [plain, caption.copyWith(laneIndex: 0)]),
      [LucideIcons.type, LucideIcons.subtitles],
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/video_editor/logic/captions/caption_placement_test.dart`
Expected: FAIL — `caption_placement.dart` and `lane_gutter_icons.dart` do not exist.

- [ ] **Step 3: Write `caption_placement.dart`**

```dart
import 'dart:ui';

import '../../models/text_overlay_model.dart';
import '../text_template_catalog.dart';
import 'caption_grouping.dart';

/// The look captions wear until the styles stage: the Subtitle template —
/// white, a black outline, a soft shadow, in the lower third.
final TextTemplate captionDefaultTemplate =
    kTextTemplates.firstWhere((t) => t.id == 'subtitle');

/// [drafts] as text overlays of caption set [setId] on [lane].
///
/// **No in/out animation**, whatever the template carries: a half-second fade
/// on a one-second caption is most of its life. `boxWidth` stays unset — every
/// caption shares one reference canvas, so every caption already wraps at the
/// same width, and a boxed style's background still hugs its words.
List<TextOverlayModel> buildCaptionOverlays({
  required List<CaptionDraft> drafts,
  required String setId,
  required int lane,
  Size? canvasSize,
}) {
  return [
    for (var i = 0; i < drafts.length; i++)
      captionDefaultTemplate
          .apply(
            id: '${setId}_$i',
            startTime: drafts[i].start,
            endTime: drafts[i].end,
            canvasSize: canvasSize,
          )
          .copyWith(
            text: drafts[i].text,
            inAnimation: 'none',
            outAnimation: 'none',
            loopAnimation: 'none',
            laneIndex: lane,
            captionSetId: setId,
            captionWords: drafts[i].words,
          ),
  ];
}
```

- [ ] **Step 4: Add `placeCaptions` to the notifier** (imports: `'../logic/captions/caption_grouping.dart'`, `'../logic/captions/caption_placement.dart'`)

```dart
  /// Puts a caption set on the timeline — replacing the project's current one,
  /// if any — as one undo step.
  ///
  /// The old set goes before a lane is chosen, so the new captions take the
  /// lane it freed instead of opening one beneath it; plain text is untouched.
  void placeCaptions(
    List<CaptionDraft> drafts,
    CaptionSettings settings, {
    Size? canvasSize,
  }) {
    if (drafts.isEmpty) return;
    saveStateForUndo();
    final kept = [
      for (final t in state.textOverlays)
        if (!t.isCaption) t,
    ];
    double seconds(Duration d) => d.inMicroseconds / 1e6;
    final lane = firstFreeLane(
      laneSpansOf(
        texts: kept,
        images: state.imageOverlays,
        videos: state.videoOverlays,
        audios: state.audioTracks,
      ),
      seconds(drafts.first.start),
      seconds(drafts.last.end),
    );
    state = state.copyWith(
      textOverlays: [
        ...kept,
        ...buildCaptionOverlays(
          drafts: drafts,
          setId: settings.setId,
          lane: lane,
          canvasSize: canvasSize,
        ),
      ],
      captionSettings: settings,
      clearSelectedTextId: true,
      currentMenuId: 'root',
    );
    _compactLanes();
  }
```

- [ ] **Step 5: Write `lane_gutter_icons.dart` and use it**

```dart
import 'package:flutter/widgets.dart';

import '../../../../core/theme/lucide_icons.dart';
import '../../models/audio_track_model.dart';
import '../../models/image_overlay_model.dart';
import '../../models/text_overlay_model.dart';
import '../../models/video_overlay_model.dart';

/// One icon per kind of thing [lane] holds, for the gutter before 00:00.
/// Captions are text, but a lane of them reads as captions.
List<IconData> laneGutterIcons({
  required int lane,
  required List<AudioTrackModel> audios,
  required List<TextOverlayModel> texts,
  required List<ImageOverlayModel> images,
  required List<VideoOverlayModel> videos,
}) {
  return [
    if (audios.any((a) => a.laneIndex == lane)) LucideIcons.music,
    if (texts.any((t) => t.laneIndex == lane && !t.isCaption))
      LucideIcons.type,
    if (texts.any((t) => t.laneIndex == lane && t.isCaption))
      LucideIcons.subtitles,
    if (images.any((i) => i.laneIndex == lane)) LucideIcons.image,
    if (videos.any((v) => v.laneIndex == lane)) LucideIcons.video,
  ];
}
```

In `scrollable_timeline.dart` `_buildLaneGutter`, replace the `final icons = <IconData>[ … ];` literal with:

```dart
      final icons = laneGutterIcons(
        lane: lane,
        audios: widget.audioTracks,
        texts: widget.textOverlays,
        images: widget.imageOverlays,
        videos: widget.videoOverlays,
      );
```

and import `'lane_gutter_icons.dart'`. (The file is CRLF: use the Edit tool, not a regex over LF.)

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/logic/captions/caption_placement_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 7: Mutation check the replace**

Temporarily change `if (!t.isCaption) t` to `t` in `placeCaptions` — "regenerating replaces the set" must fail. Restore.

- [ ] **Step 8: Analyzer and the timeline suites**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.
Run: `flutter test test/features/video_editor/widgets test/features/video_editor/providers` → Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/features/video_editor/logic/captions/caption_placement.dart lib/features/video_editor/widgets/timeline/lane_gutter_icons.dart lib/features/video_editor/widgets/timeline/scrollable_timeline.dart lib/features/video_editor/providers/video_editor_notifier.dart test/features/video_editor/logic/captions/caption_placement_test.dart
git commit -m "feat(captions): place a caption set on its own lane, one undo step

Captions are Subtitle-look texts carrying their words; a new set replaces
the old on the lane it freed, and the gutter marks the lane as captions.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: The sheets — choose, wait, replace

**Files:**
- Create: `lib/features/video_editor/services/caption_access.dart`
- Create: `lib/features/video_editor/widgets/panels/caption_sheet_parts.dart`
- Create: `lib/features/video_editor/widgets/panels/auto_caption_sheet.dart`
- Create: `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart`
- Create: `lib/features/video_editor/widgets/panels/replace_captions_dialog.dart`
- Test: `test/features/video_editor/widgets/auto_caption_sheets_test.dart`

**Interfaces:**
- Consumes: `CaptionRequest`, `CaptionPipeline`, `CaptionStage` (Task 11); `captionErrorMessage`, `CaptionCancelled` (Task 10); `CaptionSettings`, `kCaptionLanguages` (Task 5); `CaptionDraft` (Task 8).
- Produces: `CaptionAccess.ensureAllowed(BuildContext) → Future<bool>`; `AutoCaptionSheet({CaptionSettings? initial})` popping `CaptionRequest`; `CaptionProgressSheet({required CaptionPipeline pipeline, required CaptionRequest request})` popping `List<CaptionDraft>` on success and nothing otherwise; `Future<bool> confirmReplaceCaptions(BuildContext context)`; `SheetGrabHandle`, `SheetActionButton({required String label, required VoidCallback onTap, bool filled = false})`, `CaptionPillRow<T>`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/services/caption_access.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/auto_caption_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/caption_progress_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/replace_captions_dialog.dart';

void main() {
  /// Opens [builder] as an editor sheet and records what it pops.
  Future<List<Object?>> open(WidgetTester tester, WidgetBuilder builder) async {
    final popped = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => popped.add(await showEditorSheet<Object?>(context, builder: builder)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return popped;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('AutoCaptionSheet', () {
    testWidgets('offers the choices and starts on the defaults', (tester) async {
      final popped = await open(tester, (_) => const AutoCaptionSheet());
      for (final label in [
        'Video sound', 'Audio tracks', 'All', 'Auto detect', 'Word', 'Phrase', 'Line', 'Generate',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tapKey(tester, 'caption_generate');
      final request = popped.single as CaptionRequest;
      expect(request.source, CaptionSource.video);
      expect(request.language, isNull);
      expect(request.length, CaptionLength.phrase);
    });

    testWidgets('returns what was chosen', (tester) async {
      final popped = await open(tester, (_) => const AutoCaptionSheet());
      await tapKey(tester, 'caption_source_all');
      await tapKey(tester, 'caption_language_fr');
      await tapKey(tester, 'caption_length_line');
      await tapKey(tester, 'caption_generate');
      final request = popped.single as CaptionRequest;
      expect(
        (request.source, request.language, request.length),
        (CaptionSource.all, 'fr', CaptionLength.line),
      );
    });

    testWidgets("reopens on the project's last choices", (tester) async {
      final popped = await open(
        tester,
        (_) => const AutoCaptionSheet(
          initial: CaptionSettings(
            setId: 's',
            source: CaptionSource.tracks,
            language: 'yo',
            length: CaptionLength.word,
          ),
        ),
      );
      await tapKey(tester, 'caption_generate');
      final request = popped.single as CaptionRequest;
      expect(
        (request.source, request.language, request.length),
        (CaptionSource.tracks, 'yo', CaptionLength.word),
      );
    });
  });

  group('CaptionProgressSheet', () {
    const hello = CaptionTranscript(
      text: 'Hello',
      words: [TranscriptWord(text: 'Hello', start: 0.2, end: 0.5)],
    );

    CaptionPipeline pipelineWith({
      required Future<CaptionAudioResult> Function() render,
      Future<CaptionTranscript> Function()? transcript,
      void Function()? onCancel,
    }) =>
        CaptionPipeline(
          audioPath: () async => '/tmp/none.m4a',
          deleteFile: (_) async {},
          renderAudio: (path, source, onProgress) => render(),
          startJob: (path, language, key) async =>
              const CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero),
          awaitJob: (job, isCancelled) => transcript == null ? Future.value(hello) : transcript(),
          onCancel: onCancel ?? () {},
        );

    const sound = CaptionAudioResult(outputPath: '/tmp/none.m4a', durationSeconds: 1, hasSound: true);

    testWidgets('names each stage, then closes with the captions', (tester) async {
      final rendered = Completer<CaptionAudioResult>();
      final heard = Completer<CaptionTranscript>();
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(render: () => rendered.future, transcript: () => heard.future),
          request: const CaptionRequest(),
        ),
      );
      expect(find.text('Preparing audio'), findsOneWidget);

      rendered.complete(sound);
      await tester.pump();
      await tester.pump();
      expect(find.text('Listening'), findsOneWidget);

      heard.complete(hello);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect((popped.single as List<CaptionDraft>).single.text, 'Hello');
    });

    testWidgets('a failure shows its line; Try again runs again', (tester) async {
      var runs = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(render: () async {
            runs++;
            return const CaptionAudioResult(outputPath: '', durationSeconds: 0, hasSound: false);
          }),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      expect(find.text('No sound to caption.'), findsOneWidget);
      await tapKey(tester, 'caption_retry');
      expect(runs, 2);
      await tapKey(tester, 'caption_close');
      expect(popped.single, isNull);
    });

    testWidgets('Cancel closes the sheet and stops the run', (tester) async {
      var cancels = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () => Completer<CaptionAudioResult>().future,
            onCancel: () => cancels++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tapKey(tester, 'caption_cancel');
      expect(popped.single, isNull);
      expect(cancels, 1);
    });
  });

  group('replacing captions', () {
    Future<List<bool>> ask(WidgetTester tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => answers.add(await confirmReplaceCaptions(context)),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.text('Replace captions?'), findsOneWidget);
      return answers;
    }

    testWidgets('Replace says yes', (tester) async {
      final answers = await ask(tester);
      await tester.tap(find.byKey(const Key('replace_captions_confirm')));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('Cancel, or a tap outside, says no', (tester) async {
      final answers = await ask(tester);
      await tester.tap(find.byKey(const Key('replace_captions_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(answers, [false, false]);
    });
  });

  testWidgets('every run is allowed until sign-in exists', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
    );
    expect(await CaptionAccess.ensureAllowed(context), isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/video_editor/widgets/auto_caption_sheets_test.dart`
Expected: FAIL — the five new files do not exist.

- [ ] **Step 3: Write `caption_access.dart`**

```dart
import 'package:flutter/widgets.dart';

/// The one door every auto-caption run passes before any audio is rendered.
///
/// **It always opens today.** Auto captions will become signed-in and
/// credit-based: this is where the Google / email sign-in sheet and the
/// balance check go, and nothing else changes when they do.
class CaptionAccess {
  const CaptionAccess._();

  static Future<bool> ensureAllowed(BuildContext context) async => true;
}
```

- [ ] **Step 4: Write `caption_sheet_parts.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// The grab handle, drawn as every other sheet draws it.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// A full-height sheet button: purple when it is the action, quiet otherwise.
class SheetActionButton extends StatelessWidget {
  const SheetActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryStart : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of choice pills: the filled capsule is the current one.
class CaptionPillRow<T> extends StatelessWidget {
  const CaptionPillRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.keyFor,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final Key Function(T value) keyFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                key: keyFor(value),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(value);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == selected
                        ? AppColors.primaryStart
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    label(value),
                    style: TextStyle(
                      color: value == selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Write `auto_caption_sheet.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/captions/caption_settings.dart';
import '../../services/caption_pipeline.dart';
import 'caption_sheet_parts.dart';
import 'editor_sheet.dart';

/// Text → Auto captions: which sound, which language, how long a caption.
///
/// No title — the user tapped Auto captions to get here. Pops a
/// [CaptionRequest] on Generate, nothing on dismissal.
class AutoCaptionSheet extends StatefulWidget {
  const AutoCaptionSheet({super.key, this.initial});

  /// The project's last choices, so a second run starts where the first did.
  final CaptionSettings? initial;

  @override
  State<AutoCaptionSheet> createState() => _AutoCaptionSheetState();
}

class _AutoCaptionSheetState extends State<AutoCaptionSheet> {
  late CaptionSource _source = widget.initial?.source ?? CaptionSource.video;
  late String? _language = widget.initial?.language;
  late CaptionLength _length = widget.initial?.length ?? CaptionLength.phrase;

  static String _sourceLabel(CaptionSource s) => switch (s) {
        CaptionSource.video => 'Video sound',
        CaptionSource.tracks => 'Audio tracks',
        CaptionSource.all => 'All',
      };

  static String _lengthLabel(CaptionLength l) => switch (l) {
        CaptionLength.word => 'Word',
        CaptionLength.phrase => 'Phrase',
        CaptionLength.line => 'Line',
      };

  static String _languageLabel(String? code) => code == null
      ? 'Auto detect'
      : kCaptionLanguages.firstWhere((l) => l.code == code).name;

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        MediaQuery.sizeOf(context).height * kEditorSheetPreviewFraction;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetGrabHandle(),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section('Source'),
                      CaptionPillRow<CaptionSource>(
                        values: CaptionSource.values,
                        selected: _source,
                        label: _sourceLabel,
                        keyFor: (s) => Key('caption_source_${s.name}'),
                        onSelected: (s) => setState(() => _source = s),
                      ),
                      _section('Language'),
                      CaptionPillRow<String?>(
                        values: [null, for (final l in kCaptionLanguages) l.code],
                        selected: _language,
                        label: _languageLabel,
                        keyFor: (c) => Key('caption_language_${c ?? 'auto'}'),
                        onSelected: (c) => setState(() => _language = c),
                      ),
                      _section('Length'),
                      CaptionPillRow<CaptionLength>(
                        values: CaptionLength.values,
                        selected: _length,
                        label: _lengthLabel,
                        keyFor: (l) => Key('caption_length_${l.name}'),
                        onSelected: (l) => setState(() => _length = l),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: SheetActionButton(
                    key: const Key('caption_generate'),
                    label: 'Generate',
                    filled: true,
                    onTap: () => Navigator.of(context).pop(
                      CaptionRequest(
                        source: _source,
                        language: _language,
                        length: _length,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Write `caption_progress_sheet.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../services/caption_errors.dart';
import '../../services/caption_pipeline.dart';
import 'caption_sheet_parts.dart';

/// Runs [pipeline] and says where it is. Pops the caption drafts on success.
///
/// It holds the editor on purpose: the audio is a snapshot of the timeline,
/// and a clip moved while the server listens would misplace every later word.
/// Any way the sheet closes before the words land — Cancel, a tap outside,
/// Back — stops the run.
class CaptionProgressSheet extends StatefulWidget {
  const CaptionProgressSheet({
    super.key,
    required this.pipeline,
    required this.request,
  });

  final CaptionPipeline pipeline;
  final CaptionRequest request;

  @override
  State<CaptionProgressSheet> createState() => _CaptionProgressSheetState();
}

class _CaptionProgressSheetState extends State<CaptionProgressSheet> {
  CaptionStage _stage = CaptionStage.preparing;
  double? _progress = 0;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    if (!_finished) widget.pipeline.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final drafts = await widget.pipeline.run(
        widget.request,
        onProgress: (stage, progress) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _progress = progress;
          });
        },
      );
      _finished = true;
      if (mounted) Navigator.of(context).pop(drafts);
    } on CaptionCancelled {
      // Closed by the user; the sheet is already on its way out.
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captionErrorMessage(error));
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _stage = CaptionStage.preparing;
      _progress = 0;
    });
    unawaited(_run());
  }

  static String _label(CaptionStage stage) => switch (stage) {
        CaptionStage.preparing => 'Preparing audio',
        CaptionStage.uploading => 'Uploading',
        CaptionStage.listening => 'Listening',
        CaptionStage.placing => 'Placing captions',
      };

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SheetGrabHandle()),
              const SizedBox(height: 8),
              if (error == null) ...[
                Text(
                  _label(_stage),
                  key: const Key('caption_progress_stage'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 4,
                    color: AppColors.primaryStart,
                    backgroundColor: AppColors.surfaceLight,
                  ),
                ),
                const SizedBox(height: 20),
                SheetActionButton(
                  key: const Key('caption_cancel'),
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ] else ...[
                Text(
                  error,
                  key: const Key('caption_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SheetActionButton(
                        key: const Key('caption_close'),
                        label: 'Close',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SheetActionButton(
                        key: const Key('caption_retry'),
                        label: 'Try again',
                        filled: true,
                        onTap: _retry,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Write `replace_captions_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'caption_sheet_parts.dart';

/// Asks before a new caption set replaces the project's current one — hand
/// fixes to the old set go with it. True only for Replace.
Future<bool> confirmReplaceCaptions(BuildContext context) async {
  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Replace captions?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SheetActionButton(
                    key: const Key('replace_captions_cancel'),
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SheetActionButton(
                    key: const Key('replace_captions_confirm'),
                    label: 'Replace',
                    filled: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return replace ?? false;
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `flutter test test/features/video_editor/widgets/auto_caption_sheets_test.dart`
Expected: PASS, 9 tests. If "names each stage" shows `Uploading` rather than `Listening` after one pump, add one more `await tester.pump();` — each awaited step is a microtask hop, and the assertion is about the stage label, not the pump count.

- [ ] **Step 9: Analyzer and the panel guards**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.
Run: `flutter test test/features/video_editor/widgets/panel_theme_test.dart test/features/video_editor/widgets` → Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add lib/features/video_editor/services/caption_access.dart lib/features/video_editor/widgets/panels/caption_sheet_parts.dart lib/features/video_editor/widgets/panels/auto_caption_sheet.dart lib/features/video_editor/widgets/panels/caption_progress_sheet.dart lib/features/video_editor/widgets/panels/replace_captions_dialog.dart test/features/video_editor/widgets/auto_caption_sheets_test.dart
git commit -m "feat(captions): the caption sheet, the progress sheet and Replace

Also the access gate the sign-in sheet will fill; it lets every run
through until then.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Wiring — the tool, the flow, the debug network

**Files:**
- Modify: `lib/features/video_editor/logic/toolbar_visibility.dart`
- Modify: `lib/screens/video_editor_screen.dart` (`_textMenu` ~line 275–293, the tool dispatch ~line 2079, the `isToolbarToolVisible` call ~line 1850, a new `_startAutoCaptions` after `_addText`)
- Modify: `android/app/src/debug/AndroidManifest.xml`
- Test: `test/features/video_editor/logic/toolbar_visibility_test.dart`, `test/features/video_editor/widgets/editor_menu_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: `isToolbarToolVisible(..., required bool hasCaptionServer)`.

- [ ] **Step 1: Write the failing tests**

In `toolbar_visibility_test.dart`, add `bool captionServer = true,` to the `visible(...)` helper's parameters and `hasCaptionServer: captionServer,` to its call, then add:

```dart
  test('Auto captions is offered only in a build that has a server', () {
    // "Not offered before it works": without SLIMSHOT_API_URL there is
    // nothing to send the audio to.
    expect(visible('auto_captions', captionServer: false), isFalse);
    expect(visible('auto_captions', captionServer: true), isTrue);
    expect(declaredTools('_textMenu'), contains('auto_captions'));
  });
```

In `editor_menu_test.dart`, add:

```dart
  test('the Text tool offers Auto captions, and the screen handles it', () {
    expect(menuSource('_textMenu'), contains("id: 'auto_captions'"));
    expect(
      screen.readAsStringSync(),
      contains("tool.id == 'auto_captions'"),
      reason: 'a declared tool with no handler is a dead signpost',
    );
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/video_editor/logic/toolbar_visibility_test.dart test/features/video_editor/widgets/editor_menu_test.dart`
Expected: FAIL — `hasCaptionServer` is not a parameter; `_textMenu` lacks `auto_captions`.

- [ ] **Step 3: The visibility rule**

In `toolbar_visibility.dart`, add `required bool hasCaptionServer,` to the parameters and a case:

```dart
    case 'auto_captions':
      // Not offered before it works: a build without a server address has
      // nowhere to send the audio.
      return hasCaptionServer;
```

- [ ] **Step 4: The menu entry, the call site, the handler** (the screen is CRLF — use the Edit tool)

Imports:

```dart
import 'package:path_provider/path_provider.dart';
import '../core/services/slimshot_api.dart';
import '../features/video_editor/logic/captions/caption_grouping.dart';
import '../features/video_editor/logic/captions/caption_settings.dart';
import '../features/video_editor/services/caption_access.dart';
import '../features/video_editor/services/caption_pipeline.dart';
import '../features/video_editor/services/caption_service.dart';
import '../features/video_editor/widgets/panels/auto_caption_sheet.dart';
import '../features/video_editor/widgets/panels/caption_progress_sheet.dart';
import '../features/video_editor/widgets/panels/replace_captions_dialog.dart';
```

`_textMenu` — replace the doc sentence "Auto captions joins them when its server exists; it is not offered before it works." with "Auto captions is the third way, offered only in a build that carries a server address (`isToolbarToolVisible`)." and add the entry after `add_template`:

```dart
    EditorTool(
      id: 'auto_captions',
      label: 'Auto captions',
      icon: LucideIcons.subtitles,
    ),
```

In the `isToolbarToolVisible(` call add `hasCaptionServer: SlimshotApi.isConfigured,`.

In the tool dispatch, after the `add_template` branch:

```dart
                  } else if (tool.id == 'auto_captions') {
                    unawaited(_startAutoCaptions());
```

After `_addText`:

```dart
  /// Text → Auto captions: choose, wait for the words, place them.
  ///
  /// The audio is a snapshot of the timeline, so playback stops and the
  /// progress sheet holds the editor until the words land. The captions are
  /// placed as one undo step, replacing an existing set only after asking.
  Future<void> _startAutoCaptions() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final request = await showEditorSheet<CaptionRequest>(
      context,
      builder: (_) => AutoCaptionSheet(
        initial: ref.read(videoEditorProvider).captionSettings,
      ),
    );
    if (request == null || !mounted) return;
    if (!await CaptionAccess.ensureAllowed(context) || !mounted) return;
    if (ref.read(videoEditorProvider).hasCaptions &&
        !await confirmReplaceCaptions(context)) {
      return;
    }
    if (!mounted) return;

    notifier.setPlaying(false);
    _audioPlayerManager.pauseAll();
    unawaited(_nativePreviewService.pause());

    final api = SlimshotApi(baseUrl: SlimshotApi.configuredBaseUrl);
    final captions = CaptionService(api);
    final pipeline = CaptionPipeline(
      audioPath: () async {
        final dir = await getTemporaryDirectory();
        return '${dir.path}/captions_${DateTime.now().millisecondsSinceEpoch}.m4a';
      },
      renderAudio: (path, source, onProgress) =>
          _nativePreviewService.renderCaptionAudio(
        ref.read(videoEditorProvider),
        outputPath: path,
        source: source,
        onProgress: onProgress,
      ),
      startJob: (path, language, key) => captions.start(
        audioPath: path,
        language: language,
        idempotencyKey: key,
      ),
      awaitJob: (job, isCancelled) =>
          captions.result(job, isCancelled: isCancelled),
      onCancel: () {
        unawaited(_nativePreviewService.cancelCaptionAudio());
        api.close();
      },
    );
    final drafts = await showEditorSheet<List<CaptionDraft>>(
      context,
      builder: (_) => CaptionProgressSheet(pipeline: pipeline, request: request),
    );
    api.close();
    if (drafts == null || !mounted) return;

    notifier.placeCaptions(
      drafts,
      CaptionSettings(
        setId: 'captions_${DateTime.now().millisecondsSinceEpoch}',
        source: request.source,
        language: request.language,
        length: request.length,
      ),
      canvasSize: ref.read(videoCanvasSizeProvider),
    );
  }
```

- [ ] **Step 5: Cleartext for the LAN test server, debug builds only**

`android/app/src/debug/AndroidManifest.xml` gains, inside `<manifest>` after the permission:

```xml
    <!-- The caption server under test runs on the development PC over plain
         HTTP. Debug builds only: release has no cleartext, and the deployed
         server must be HTTPS. -->
    <application android:usesCleartextTraffic="true" />
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/video_editor/logic/toolbar_visibility_test.dart test/features/video_editor/widgets/editor_menu_test.dart`
Expected: PASS.

- [ ] **Step 7: Full verification**

Run: `flutter analyze --no-pub` → Expected: `48 issues found`.
Run: `flutter test > build/flutter_test.log 2>&1; tail -5 build/flutter_test.log` → Expected: `All tests passed!` (`build/` is git-ignored).
Run: `cd android && ./gradlew :app:testDebugUnitTest` → Expected: BUILD SUCCESSFUL.
Run: `flutter build apk --debug` → Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 8: Commit**

```bash
git add lib/features/video_editor/logic/toolbar_visibility.dart lib/screens/video_editor_screen.dart android/app/src/debug/AndroidManifest.xml test/features/video_editor/logic/toolbar_visibility_test.dart test/features/video_editor/widgets/editor_menu_test.dart
git commit -m "feat(captions): Text > Auto captions

Offered only in a build that carries SLIMSHOT_API_URL. Debug builds may
reach the LAN test server over plain HTTP; release may not.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the section**

Add a section `### Auto captions — generating a set (Stage 1)` after the "Replace clip" section, marked **awaiting device verification**, recording, in the file's voice:

- Captions are ordinary text overlays (`captionSetId`, `captionWords` — UTF-16 offsets, times relative to the caption), for the emoji reason; spec `docs/superpowers/specs/2026-09-29-auto-captions-design.md`, plan beside it.
- The audio is the export's own mixer (`MixConfig.CAPTIONS`: mono 16 kHz, unity gain, reversed clips skipped **inside** the mixer because crossfades resolve clips by index) from timeline 0 — why word times need no conversion.
- `SlimshotApi` is the one server client; `SLIMSHOT_API_URL` gates the tool; the device token lives in `shared_preferences` until sign-in; one re-register on a 401, never a loop.
- The key rule: reused only after an upload that never landed.
- Spacing is rebuilt from the transcript (the server drops spacing tokens).
- Grouping rules and constants; why there is no separate minimum; captions never overlap.
- Placement: Subtitle look without fades, `boxWidth` unset and why, one lane via `firstFreeLane` after removing the old set, one undo step, Replace asks.
- `CaptionAccess.ensureAllowed` is where sign-in and credits go.
- Three export fixes that came with it: a video overlay's sound was mixed twice (`TimelineAudioTracks` reads imported tracks only), still textures are freed once their overlay ends (`ExpiredStills`), and export awaits pending fonts.
- Debug-only cleartext; release needs HTTPS.

Also update the Text submenu paragraph ("Auto captions joins the submenu when its server exists…") to say it is now there, gated on the server address, and add to the overlay-sound paragraph under "Overlays are drawn natively in the preview too" that the export had mixed it twice until `TimelineAudioTracks`.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: auto captions, stage 1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Device checklist (for the user, before merge)

Run the server on the PC, phone on the same Wi-Fi, then
`flutter run --dart-define=SLIMSHOT_API_URL=http://192.168.1.158:2700`.

1. Text shows **Auto captions** beside Add text and Templates; a plain `flutter run` (no define) does not.
2. A clip of speech, defaults → Preparing audio → Uploading → Listening → captions on one lane, lower third, in sync with the words.
3. Several clips with trims, a 2× clip and a transition → captions stay in sync across all of them.
4. Auto detect on a non-English clip → captions in that language.
5. Source **Audio tracks** on a music-only project → lyrics, or "No speech found."
6. Clips muted in the project, Source **Video sound** → captions still appear.
7. Cancel while Listening → no captions, the editor works normally.
8. Airplane mode → "No connection. Check your internet and try again." → reconnect → **Try again** works.
9. Generate again → "Replace captions?" → Replace puts the new set on the same lane; Undo brings the old set back.
10. Export → captions appear in the file at the right moments.
11. A two-minute captioned project exports without stalling or crashing.
12. A video overlay with sound at 1× exports at the loudness the preview plays (it was doubled); at 2× only one voice is heard.
13. Close and reopen the draft → the captions are there and the sheet opens on the last choices.
