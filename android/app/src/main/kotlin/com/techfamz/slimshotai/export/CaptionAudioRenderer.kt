package com.techfamz.slimshotai.export

import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.nativepreview.NativeTimelineTransitionIntent
import java.io.File

/**
 * Renders the sound auto captions listen to: the chosen sources through the
 * export's own mixer, mono 16 kHz PCM in a WAV, starting at timeline 0.
 *
 * Starting at timeline 0 and running at timeline rate is the point: the server
 * reports word times from the start of the file, so they arrive as timeline
 * times — through trims, speed, curves and crossfades — with no conversion.
 *
 * **PCM, not AAC**, for the same reason. Device-reported: captions showed a
 * little after their words. An AAC encoder opens every stream with a run of
 * priming samples — tens of milliseconds at this rate — and nothing in the
 * file told the transcriber to skip them, so every word was heard that much
 * late. A WAV has no codec to delay anything. It is larger (about 2 MB a
 * minute), which a short-form video can afford.
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

        // Closes the sources itself, whether or not the file could be opened.
        mixer.writeWavTo(File(outputPath), isCancelled = { cancelled }, onProgress = onProgress)

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
