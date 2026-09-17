package com.techfamz.slimshotai.export

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import androidx.media3.common.util.UnstableApi
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * One file's audio, decoded to stereo float PCM at the export's sample rate.
 *
 * Deliberately built on nothing but `MediaExtractor` + `MediaCodec`. An earlier
 * version routed every source through Media3's `SonicAudioProcessor` to get
 * pitch-preserved speed changes, and that processor's state machine threw an
 * `IllegalStateException` during open — which the source treated as "this clip
 * has no audio" and dropped, exporting a silent file. Losing the audio entirely
 * is a far worse outcome than any fidelity gain, so the base path now has no
 * dependency that can fail.
 *
 * Sample-rate conversion and playback speed are the same operation here: both
 * change how fast the source is consumed per output frame, so one linear
 * resampler covers both. At the common case — source already at the output rate,
 * speed 1.0 — the step is exactly 1.0 and samples pass through untouched.
 *
 * **Known limitation:** because this resamples rather than time-stretches, a
 * clip with a changed speed shifts pitch in the export, where the preview (which
 * uses ExoPlayer's Sonic) preserves it. Worth closing once the path is proven,
 * but not at the cost of silence.
 *
 * A file with no audio track is normal, not an error: [open] returns false and
 * the mixer treats the source as silence.
 */
@UnstableApi
internal class PcmAudioSource(
    private val path: String,
    private val speed: Double,
    private val outputSampleRate: Int,
    /**
     * Rate as a function of **source seconds**, for a clip whose speed ramps;
     * null for the flat [speed]. Read per output frame, so the step follows
     * the curve exactly where the video decoder does — a fixed step would
     * leave the sound sliding against the picture through the ramp.
     */
    private val speedAtSource: ((Double) -> Double)? = null,
) {

    private var extractor: MediaExtractor? = null
    private var codec: MediaCodec? = null
    private val bufferInfo = MediaCodec.BufferInfo()

    private var sourceChannels = 2
    private var sourceSampleRate = outputSampleRate
    private var inputDone = false
    private var outputDone = false

    /** Source frames consumed per output frame: rate conversion and speed in one. */
    private var step = 1.0

    /** The rate-conversion half of [step], for a curve to multiply per frame. */
    private var rateStep = 1.0

    /** Source frames consumed so far since the last seek, for the curve's clock. */
    private var sourceFramesConsumed = 0.0

    /** Where the last seek landed, in source seconds; the curve's origin. */
    private var seekSourceSeconds = 0.0

    /** Decoded source frames waiting to be resampled, interleaved stereo. */
    private var decoded = FloatArray(0)
    private var decodedOffset = 0
    private var decodedCount = 0

    // Two-point interpolation window over the source stream.
    private var haveWindow = false
    private var curL = 0f
    private var curR = 0f
    private var nextL = 0f
    private var nextR = 0f
    private var fraction = 0.0
    private var sourceEnded = false

    /** Why [open] returned false, for reporting rather than guessing. */
    var failureReason: String? = null
        private set

    fun open(): Boolean {
        val name = File(path).name
        return try {
            val ex = MediaExtractor()
            ex.setDataSource(path)

            // A file can carry several audio tracks — a camera original with a
            // second language, or a re-mux that kept both. The first is used,
            // which is the one a player picks by default, and the rest are
            // logged so an unexpected pick is visible rather than silent.
            var trackIndex = -1
            var format: MediaFormat? = null
            val audioMimes = mutableListOf<String>()
            val allMimes = mutableListOf<String>()

            for (i in 0 until ex.trackCount) {
                val candidate = try {
                    ex.getTrackFormat(i)
                } catch (error: Exception) {
                    Log.w(TAG, "$name: track $i unreadable", error)
                    continue
                }
                val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
                allMimes += mime
                if (!mime.startsWith("audio/")) continue

                audioMimes += mime
                if (trackIndex < 0) {
                    trackIndex = i
                    format = candidate
                }
            }

            if (audioMimes.size > 1) {
                Log.i(TAG, "$name has ${audioMimes.size} audio tracks; using the first")
            }

            val audioFormat = format
            if (trackIndex < 0 || audioFormat == null) {
                failureReason = "$name has no audio track (${allMimes.joinToString()})"
                Log.w(TAG, failureReason!!)
                ex.release()
                return false
            }

            ex.selectTrack(trackIndex)
            val mime = audioFormat.getString(MediaFormat.KEY_MIME) ?: "audio/mp4a-latm"
            val decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(audioFormat, null, null, 0)
            decoder.start()

            sourceChannels = audioFormat.intOr(MediaFormat.KEY_CHANNEL_COUNT, 2)
            sourceSampleRate = audioFormat.intOr(MediaFormat.KEY_SAMPLE_RATE, outputSampleRate)
            rateStep = sourceSampleRate.toDouble() / outputSampleRate
            step = rateStep * speed

            Log.i(
                TAG,
                "audio open: $name mime=$mime rate=$sourceSampleRate " +
                    "ch=$sourceChannels speed=$speed step=$step",
            )

            extractor = ex
            codec = decoder
            true
        } catch (error: Exception) {
            failureReason = "$name: ${error.javaClass.simpleName} ${error.message}"
            Log.w(TAG, "No usable audio in $path", error)
            release()
            false
        }
    }

    fun seekTo(sourceUs: Long) {
        // Reset first, unconditionally. If the seek itself throws, the reader
        // must still be in a coherent state — leaving `inputDone` or the
        // interpolation window stale would make it read nothing at all.
        inputDone = false
        outputDone = false
        sourceEnded = false
        haveWindow = false
        fraction = 0.0
        decodedOffset = 0
        decodedCount = 0
        sourceFramesConsumed = 0.0
        seekSourceSeconds = sourceUs / 1_000_000.0

        val ex = extractor ?: return
        val decoder = codec ?: return
        try {
            ex.seekTo(sourceUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            // `flush()` only. In synchronous mode the codec stays started, and
            // calling `start()` on a started codec throws IllegalStateException.
            decoder.flush()
        } catch (error: Exception) {
            Log.w(TAG, "Audio seek failed on $path", error)
        }
    }

    /**
     * Writes up to [frames] stereo frames into [dest] starting at [destOffset].
     *
     * A short read means the source has run out; the mixer fills the rest with
     * silence.
     */
    fun read(dest: FloatArray, destOffset: Int, frames: Int): Int {
        var written = 0

        while (written < frames) {
            if (!haveWindow) {
                if (!primeWindow()) break
            }

            // Walk the window forward until the read position sits inside it.
            while (fraction >= 1.0) {
                curL = nextL
                curR = nextR
                if (!pullSourceFrame { l, r -> nextL = l; nextR = r }) {
                    sourceEnded = true
                    break
                }
                fraction -= 1.0
            }
            if (sourceEnded && fraction >= 1.0) break

            val t = fraction.toFloat()
            val out = (destOffset + written) * 2
            dest[out] = curL + (nextL - curL) * t
            dest[out + 1] = curR + (nextR - curR) * t

            val curve = speedAtSource
            if (curve != null) {
                val sourceSeconds = seekSourceSeconds + sourceFramesConsumed / sourceSampleRate
                step = rateStep * curve(sourceSeconds)
            }
            fraction += step
            sourceFramesConsumed += step
            written++
        }

        return written
    }

    private fun primeWindow(): Boolean {
        if (!pullSourceFrame { l, r -> curL = l; curR = r }) return false
        if (!pullSourceFrame { l, r -> nextL = l; nextR = r }) {
            // A single frame is still playable; hold it steady.
            nextL = curL
            nextR = curR
        }
        haveWindow = true
        fraction = 0.0
        return true
    }

    /** Hands the next decoded source frame to [emit]. False at end of stream. */
    private inline fun pullSourceFrame(emit: (Float, Float) -> Unit): Boolean {
        if (decodedCount == 0 && !decodeMore()) return false
        val i = decodedOffset * 2
        emit(decoded[i], decoded[i + 1])
        decodedOffset++
        decodedCount--
        return true
    }

    /** Decodes one buffer into [decoded]. False when the stream is spent. */
    private fun decodeMore(): Boolean {
        val decoder = codec ?: return false
        if (outputDone) return false

        var guard = 0
        while (guard++ < MAX_STEPS) {
            feedInput(decoder)

            val index = decoder.dequeueOutputBuffer(bufferInfo, DEQUEUE_TIMEOUT_US)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (inputDone && outputDone) return false

                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val out = decoder.outputFormat
                    sourceChannels = out.intOr(MediaFormat.KEY_CHANNEL_COUNT, sourceChannels)
                    val rate = out.intOr(MediaFormat.KEY_SAMPLE_RATE, sourceSampleRate)
                    if (rate != sourceSampleRate) {
                        // The decoder is the authority: a container can disagree
                        // with what actually comes out.
                        sourceSampleRate = rate
                        rateStep = rate.toDouble() / outputSampleRate
                        step = rateStep * speed
                    }
                }

                index < 0 -> Unit

                else -> {
                    val out = decoder.getOutputBuffer(index)
                    var produced = false
                    if (out != null && bufferInfo.size > 0) {
                        out.position(bufferInfo.offset)
                        out.limit(bufferInfo.offset + bufferInfo.size)
                        store(out)
                        produced = decodedCount > 0
                    }
                    val end = bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    decoder.releaseOutputBuffer(index, false)
                    if (end) outputDone = true
                    if (produced) return true
                    if (end) return false
                }
            }
        }
        return false
    }

    private fun feedInput(decoder: MediaCodec) {
        if (inputDone) return
        val ex = extractor ?: return

        val index = decoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
        if (index < 0) return

        val buffer = decoder.getInputBuffer(index) ?: return
        val size = ex.readSampleData(buffer, 0)
        if (size < 0) {
            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            inputDone = true
            return
        }
        decoder.queueInputBuffer(index, 0, size, ex.sampleTime, 0)
        ex.advance()
    }

    /** Converts a decoder buffer to interleaved stereo floats. */
    private fun store(buffer: ByteBuffer) {
        val shorts = buffer.order(ByteOrder.nativeOrder()).asShortBuffer()
        val channels = sourceChannels.coerceAtLeast(1)
        val frames = shorts.remaining() / channels
        decodedOffset = 0
        decodedCount = 0
        if (frames <= 0) return

        if (decoded.size < frames * 2) decoded = FloatArray(frames * 2)

        for (frame in 0 until frames) {
            val base = frame * channels
            val left = shorts.get(base) / PCM_16_SCALE
            // Mono goes to both sides rather than one, or the clip would play
            // out of a single speaker.
            val right = if (channels == 1) left else shorts.get(base + 1) / PCM_16_SCALE
            decoded[frame * 2] = left
            decoded[frame * 2 + 1] = right
        }
        decodedCount = frames
    }

    fun release() {
        try {
            codec?.stop()
        } catch (_: Exception) {
            // Already broken; releasing is all that is left.
        }
        codec?.release()
        codec = null
        extractor?.release()
        extractor = null
    }

    private companion object {
        const val TAG = "SlimshotExport"
        const val DEQUEUE_TIMEOUT_US = 10_000L
        const val MAX_STEPS = 256
        const val PCM_16_SCALE = 32768f

        fun MediaFormat.intOr(key: String, fallback: Int): Int {
            return if (containsKey(key)) getInteger(key) else fallback
        }
    }
}
