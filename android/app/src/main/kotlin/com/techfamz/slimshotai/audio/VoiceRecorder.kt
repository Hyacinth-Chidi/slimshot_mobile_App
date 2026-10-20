package com.techfamz.slimshotai.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.media3.common.util.UnstableApi
import java.io.File

/**
 * A voiceover take: the microphone, mono, encoded to AAC as it is heard.
 *
 * Not `MediaRecorder`, whose start delay cannot be measured: `AudioRecord` runs
 * from [open] on, and [capturing] decides which frames are kept ([CaptureGate]),
 * so the microphone is warm before the video starts and a pause leaves no gap.
 * The file is written as `<path>.part` and renamed only when kept.
 */
@UnstableApi
internal class VoiceRecorder private constructor(
    private val outputPath: String,
    private val record: AudioRecord,
    val sampleRate: Int,
) {
    class Unavailable(message: String) : Exception(message)

    private val part = File("$outputPath.part")
    private val encoder = AacFileEncoder(part.path, sampleRate, 1, BIT_RATE)
    private val gate = CaptureGate()

    @Volatile
    var capturing = false

    @Volatile
    private var running = true

    private val thread = Thread({ readLoop() }, "slimshot-voice-recorder").apply { start() }

    private fun readLoop() {
        val buffer = ShortArray(sampleRate / BUFFERS_PER_SECOND)
        while (running) {
            val read = record.read(buffer, 0, buffer.size)
            if (read <= 0) continue
            val keep = gate.accept(read, capturing)
            if (keep > 0) encoder.write(buffer, keep)
        }
    }

    val capturedMs: Long get() = gate.capturedMs(sampleRate)

    /**
     * Stops the microphone. Kept with anything captured, the take is renamed
     * into place and its path and length returned; otherwise it is deleted and
     * null returned.
     */
    fun close(keep: Boolean): Pair<String, Long>? {
        running = false
        try {
            thread.join(JOIN_MS)
        } catch (_: InterruptedException) {
        }
        try {
            record.stop()
        } catch (error: Exception) {
            Log.w(TAG, "AudioRecord stop failed", error)
        }
        record.release()

        if (!keep || gate.capturedFrames == 0L) {
            encoder.abandon()
            return null
        }
        encoder.finish()
        val target = File(outputPath)
        target.delete()
        if (!part.renameTo(target)) {
            part.delete()
            throw Unavailable("The recording could not be saved.")
        }
        return target.path to capturedMs
    }

    companion object {
        private const val TAG = "SlimshotAudio"
        private const val BIT_RATE = 96_000
        private const val BUFFERS_PER_SECOND = 50
        private const val JOIN_MS = 1_000L

        /** 44.1 kHz is the only rate Android guarantees; the rest are fallbacks. */
        private val RATES = intArrayOf(44_100, 48_000, 22_050, 16_000)

        /** Opens the microphone at the first rate this device accepts. */
        @SuppressLint("MissingPermission") // Dart asks for RECORD_AUDIO before opening.
        fun open(outputPath: String): VoiceRecorder {
            for (rate in RATES) {
                val min = AudioRecord.getMinBufferSize(
                    rate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                if (min <= 0) continue
                val record = try {
                    AudioRecord(
                        MediaRecorder.AudioSource.MIC,
                        rate,
                        AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        maxOf(min, rate / 5 * 2),
                    )
                } catch (error: Exception) {
                    continue
                }
                if (record.state != AudioRecord.STATE_INITIALIZED) {
                    record.release()
                    continue
                }
                try {
                    record.startRecording()
                } catch (error: Exception) {
                    record.release()
                    continue
                }
                if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    record.release()
                    continue
                }
                return try {
                    VoiceRecorder(outputPath, record, rate)
                } catch (error: Exception) {
                    record.stop()
                    record.release()
                    throw Unavailable("The recording could not be started.")
                }
            }
            throw Unavailable("The microphone is in use or unavailable.")
        }
    }
}
