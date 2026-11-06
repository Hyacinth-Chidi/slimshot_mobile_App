package com.techfamz.slimshotai.camera.react

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.export.PcmAudioSource
import kotlin.math.min

/** A live take's sound settings, from Dart's `ReactLiveTake`. */
internal data class TakeSound(val cancelEcho: Boolean) {
    companion object {
        val PLAIN = TakeSound(cancelEcho = false)

        fun fromMap(map: Map<*, *>?): TakeSound = TakeSound(cancelEcho = map?.get("cancelEcho") == true)
    }
}

/**
 * A live reaction's sound, mixed while it is recorded the way a screen
 * recorder mixes it: your microphone and the video's own sound, both at full —
 * nothing lowered while you talk — summed under [MixLimiter] and encoded as
 * AAC.
 *
 * Out loud the microphone hears the speaker play the video, and that copy
 * under the clean sound in the file is an echo. So out loud
 * ([TakeSound.cancelEcho]) the microphone is the phone's call input,
 * `VOICE_COMMUNICATION`, whose echo canceller takes the speaker's copy out —
 * the input Android's own screen recorder records the microphone through, for
 * the same reason. With headphones, or a photo, nothing reaches the
 * microphone but you, and it is the camcorder input, tuned for a voice in a
 * video.
 *
 * The microphone is one continuous stream ([MicPlacer]): anchored by when it
 * was heard (`AudioRecord.getTimestamp`, in file time — [FileClock]), so
 * pauses drop out of the sound exactly as they drop out of the picture, and
 * laid end to end between. The video's sound is decoded separately from what
 * the speaker plays, at the moment of the video that was on screen
 * ([MediaTimeMap]), and stays continuous too ([VideoSoundFollower]); it fades
 * over [FADE_MS] where it starts, stops or jumps, so a hold or a restart never
 * clicks. The mix runs [LAG_MS] behind live, for the microphone's samples to
 * arrive, plus one block held back to see where the video's sound stops; it
 * catches up at [finish].
 */
@UnstableApi
internal class ReactAudioMixer(
    private val micWanted: Boolean,
    private val videoPath: String?,
    private val take: TakeSound,
    private val clock: FileClock,
    private val media: MediaTimeMap,
) {
    var sampleRate: Int = PREFERRED_RATE
        private set

    private var record: AudioRecord? = null
    private var echoCanceller: AcousticEchoCanceler? = null
    private var source: PcmAudioSource? = null
    private var encoder: ReactAacEncoder? = null
    private var limiter = MixLimiter(PREFERRED_RATE)

    private lateinit var ring: ShortArray
    private lateinit var stamps: LongArray

    @Volatile
    private var micUpTo = 0L

    @Volatile
    private var running = false

    @Volatile
    private var endFileNanos = -1L

    private var micThread: Thread? = null
    private var mixThread: Thread? = null

    /** Where the video's decoder stands, in media ms; null before its first seek. Mix thread only. */
    private var readerMs: Double? = null

    /**
     * How fast the decoder reads through the block in hand: a source frame
     * more or fewer than the block, spread over it by the decoder's own
     * resampler. Read by [source] on the mix thread, inside `read`.
     */
    private var trim = 1.0

    /** Opens the microphone and the video's sound; true when the file will have any sound. */
    fun prepare(): Boolean {
        if (micWanted) record = openMic()
        val path = videoPath
        if (path != null) {
            val reader = PcmAudioSource(path, 1.0, sampleRate) { trim }
            source = if (reader.open()) reader else null.also { reader.release() }
        }
        limiter = MixLimiter(sampleRate)
        val capacity = sampleRate * RING_SECONDS
        ring = ShortArray(capacity)
        stamps = LongArray(capacity) { -1L }
        val mic = record
        if (mic != null) {
            running = true
            mic.startRecording()
            micThread = Thread({ readMic(mic) }, "slimshot-react-mic").apply { start() }
        }
        return record != null || source != null
    }

    fun start(muxer: ReactMuxer) {
        encoder = ReactAacEncoder(muxer, sampleRate)
        running = true
        mixThread = Thread({ mixLoop() }, "slimshot-react-mix").apply { start() }
    }

    /** Mixes up to [upToFileNanos] — the last frame's time — and finishes the sound. */
    fun finish(upToFileNanos: Long) {
        val target = upToFileNanos * sampleRate / NANOS
        val deadline = System.nanoTime() + MIC_CATCH_UP_NANOS
        while (record != null && micUpTo < target && System.nanoTime() < deadline) Thread.sleep(10)
        endFileNanos = upToFileNanos.coerceAtLeast(0)
        mixThread?.join(FINISH_TIMEOUT_MS)
        close()
    }

    /** Lets everything go without finishing the sound: the take is thrown away. */
    fun release() {
        endFileNanos = 0
        running = false
        mixThread?.join(FINISH_TIMEOUT_MS)
        close()
    }

    private fun close() {
        running = false
        micThread?.join(FINISH_TIMEOUT_MS)
        try {
            record?.stop()
        } catch (_: Exception) {
        }
        echoCanceller?.release()
        echoCanceller = null
        record?.release()
        record = null
        source?.release()
        source = null
        encoder?.release()
        encoder = null
    }

    @SuppressLint("MissingPermission")
    private fun openMic(): AudioRecord? {
        val inputs = if (take.cancelEcho) {
            intArrayOf(MediaRecorder.AudioSource.VOICE_COMMUNICATION, MediaRecorder.AudioSource.CAMCORDER)
        } else {
            intArrayOf(MediaRecorder.AudioSource.CAMCORDER)
        }
        for (input in inputs) {
            for (rate in intArrayOf(PREFERRED_RATE, FALLBACK_RATE)) {
                try {
                    val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                    if (min <= 0) continue
                    val mic = AudioRecord(input, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, rate / 5 * 2))
                    if (mic.state != AudioRecord.STATE_INITIALIZED) {
                        mic.release()
                        continue
                    }
                    sampleRate = rate
                    val callInput = input == MediaRecorder.AudioSource.VOICE_COMMUNICATION
                    if (callInput) attachEchoCanceller(mic)
                    Log.i(
                        TAG,
                        "REACT microphone: ${if (callInput) "call input" else "camcorder input"} at $rate Hz, " +
                            "echo canceller ${if (echoCanceller != null) "on" else "none"}",
                    )
                    return mic
                } catch (error: Exception) {
                    Log.w(TAG, "microphone input $input at $rate refused", error)
                }
            }
        }
        return null
    }

    /**
     * The call input applies the phone's echo cancelling where its audio
     * setup says so; asking for the canceller as well covers the phones whose
     * setup leaves it to the app. Enabling one that is already on changes
     * nothing.
     */
    private fun attachEchoCanceller(mic: AudioRecord) {
        if (!AcousticEchoCanceler.isAvailable()) return
        try {
            echoCanceller = AcousticEchoCanceler.create(mic.audioSessionId)?.also { it.setEnabled(true) }
        } catch (error: Exception) {
            Log.w(TAG, "echo canceller refused", error)
        }
    }

    private fun readMic(mic: AudioRecord) {
        val block = ShortArray(sampleRate / 100)
        val stamp = AudioTimestamp()
        val placer = MicPlacer(sampleRate)
        var framesRead = 0L
        // Where frame 0 would have arrived at the least delay seen: the
        // steady guess at when a block was heard where the phone gives no
        // timestamp, so one late arrival does not move the stream.
        var arrivalBase = Long.MAX_VALUE
        var placedEnd = -1L
        var lastSample: Short = 0
        while (running) {
            val read = mic.read(block, 0, block.size)
            if (read == AudioRecord.ERROR_DEAD_OBJECT) break
            if (read <= 0) continue
            val arrival = System.nanoTime()
            val heard = if (mic.getTimestamp(stamp, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS) {
                stamp.nanoTime + (framesRead - stamp.framePosition) * NANOS / sampleRate
            } else {
                arrivalBase = minOf(arrivalBase, arrival - (framesRead + read) * NANOS / sampleRate)
                arrivalBase + framesRead * NANOS / sampleRate
            }
            framesRead += read
            val first = placer.place(clock.fileNanos(heard), read)
            if (first == null) {
                placedEnd = -1L
                continue
            }
            // A nudge forward leaves one frame open: it repeats the sample
            // before it rather than leaving a frame of silence, a click.
            if (placedEnd >= 0 && first == placedEnd + 1) put(placedEnd, lastSample)
            for (k in 0 until read) put(first + k, block[k])
            lastSample = block[read - 1]
            placedEnd = first + read
            if (placedEnd > micUpTo) micUpTo = placedEnd
        }
    }

    private fun put(index: Long, sample: Short) {
        if (index < 0) return
        val slot = (index % ring.size).toInt()
        ring[slot] = sample
        stamps[slot] = index
    }

    private class Block(
        val frame: Long,
        val mic: FloatArray,
        val video: FloatArray,
        val videoOn: Boolean,
        val jumped: Boolean,
    )

    private fun mixLoop() {
        val blockFrames = sampleRate / 100
        val mix = FloatArray(blockFrames * 2)
        val out = ShortArray(blockFrames * ReactAacEncoder.CHANNELS)
        var analysed = 0L
        var held: Block? = null
        var videoWasOn = false
        try {
            while (true) {
                val end = endFileNanos
                val available = if (end >= 0) end else clock.durationNanos(System.nanoTime()) - LAG_MS * 1_000_000L
                val availableFrames = available * sampleRate / NANOS
                while (analysed + blockFrames <= availableFrames) {
                    val block = analyse(analysed, blockFrames)
                    analysed += blockFrames
                    held?.let { videoWasOn = emit(it, videoWasOn, block, mix, out) }
                    held = block
                }
                if (end >= 0) {
                    held?.let { emit(it, videoWasOn, null, mix, out) }
                    break
                }
                if (!running) return
                Thread.sleep(10)
            }
            encoder?.finish()
        } catch (error: Exception) {
            Log.w(TAG, "the reaction's sound stopped", error)
        }
    }

    private fun analyse(frame: Long, frames: Int): Block {
        val mic = FloatArray(frames)
        if (record != null) {
            for (k in 0 until frames) {
                val index = frame + k
                val slot = (index % ring.size).toInt()
                if (stamps[slot] == index) mic[k] = ring[slot] / 32768f
            }
        }
        val video = FloatArray(frames * 2)
        var videoOn = false
        var jumped = false
        val reader = source
        if (reader != null) {
            val real = clock.realNanos(frame * NANOS / sampleRate)
            val showing = real?.let { media.mediaMsAt(it) }
            val adjust = when (val step = VideoSoundFollower.step(showing, readerMs)) {
                VideoSoundFollower.Step.Silence -> null
                is VideoSoundFollower.Step.Seek -> {
                    reader.seekTo(step.ms * 1_000L)
                    readerMs = step.ms.toDouble()
                    jumped = true
                    0
                }
                is VideoSoundFollower.Step.Read -> step.adjust
            }
            if (adjust != null) {
                trim = (frames + adjust).toDouble() / frames
                val got = reader.read(video, 0, frames)
                if (got < frames) video.fill(0f, got * 2, frames * 2)
                readerMs = (readerMs ?: 0.0) + (frames + adjust) * 1_000.0 / sampleRate
                videoOn = got > 0
            }
            if (real != null && frame % (sampleRate.toLong() * 5) < frames) media.prune(real - PRUNE_NANOS)
        }
        return Block(frame, mic, video, videoOn, jumped)
    }

    /**
     * Mixes [block] — its video sound faded in where it starts or jumps, and
     * out where [next] shows it stopping or jumping — and encodes it. Returns
     * whether the block had the video's sound.
     */
    private fun emit(block: Block, videoWasOn: Boolean, next: Block?, mix: FloatArray, out: ShortArray): Boolean {
        val frames = block.mic.size
        val video = block.video
        if (block.videoOn) {
            if (!videoWasOn || block.jumped) fade(video, frames, rising = true)
            if (next != null && (!next.videoOn || next.jumped)) fade(video, frames, rising = false)
        }
        // Over the video's own sound the voice is lifted, as Android's
        // screen recorder lifts it over the phone's sound; alone it is left
        // as recorded.
        val micGain = if (source != null) MIC_GAIN_OVER_VIDEO else 1f
        for (k in 0 until frames) {
            val voice = block.mic[k] * micGain
            mix[2 * k] = video[2 * k] + voice
            mix[2 * k + 1] = video[2 * k + 1] + voice
        }
        limiter.process(mix, frames)
        for (i in 0 until frames * 2) out[i] = toShort(mix[i])
        encoder?.write(out, frames)
        return block.videoOn
    }

    private fun fade(video: FloatArray, frames: Int, rising: Boolean) {
        val length = min(frames, (sampleRate * FADE_MS / 1000).toInt())
        for (k in 0 until length) {
            val gain = (k + 1).toFloat() / (length + 1)
            val f = if (rising) k else frames - 1 - k
            video[2 * f] *= gain
            video[2 * f + 1] *= gain
        }
    }

    private fun toShort(value: Float): Short = (value.coerceIn(-1f, 1f) * 32767f).toInt().toShort()

    private companion object {
        const val TAG = "SlimshotCamera"
        const val NANOS = 1_000_000_000L
        const val PREFERRED_RATE = 48_000
        const val FALLBACK_RATE = 44_100
        const val RING_SECONDS = 4
        const val LAG_MS = 200L
        const val FADE_MS = 5L

        /** Android's screen recorder's lift for the microphone over the phone's own sound. */
        const val MIC_GAIN_OVER_VIDEO = 1.4f
        const val MIC_CATCH_UP_NANOS = 400_000_000L
        const val FINISH_TIMEOUT_MS = 5_000L
        const val PRUNE_NANOS = 5_000_000_000L
    }
}
