package com.techfamz.slimshotai.camera.react

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.export.PcmAudioSource
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt

/** A live take's sound settings, from Dart's `ReactLiveTake`. */
internal data class TakeSound(val lowerVideo: Boolean, val duck: Double, val gate: Double, val rampMs: Int) {
    companion object {
        val PLAIN = TakeSound(lowerVideo = false, duck = 1.0, gate = 1.0, rampMs = 150)

        fun fromMap(map: Map<*, *>?): TakeSound {
            if (map == null) return PLAIN
            fun number(key: String, fallback: Double) = (map[key] as? Number)?.toDouble()?.takeIf { it.isFinite() } ?: fallback
            return TakeSound(
                lowerVideo = map["lowerVideo"] == true,
                duck = number("duck", 1.0).coerceIn(0.0, 1.0),
                gate = number("gate", 1.0).coerceIn(0.0, 1.0),
                rampMs = number("rampMs", 150.0).toInt().coerceIn(10, 2_000),
            )
        }
    }
}

/**
 * A live reaction's sound, mixed while it is recorded: your microphone, and
 * the video's own sound — decoded separately from what the speaker plays, at
 * the moment of the video that was on screen ([MediaTimeMap]) — under the
 * talk gate ([LiveTalkGate]), encoded as AAC.
 *
 * The microphone's samples are placed by when they were heard
 * (`AudioRecord.getTimestamp`) in file time ([FileClock]), so pauses drop out
 * of the sound exactly as they drop out of the picture. The mix runs a little
 * behind live — [LAG_MS] for the microphone's samples to arrive, then the
 * gate's look-ahead — and catches up at [finish].
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
    private var source: PcmAudioSource? = null
    private var encoder: ReactAacEncoder? = null
    private val gate = LiveTalkGate(take.lowerVideo, take.duck, take.gate, take.rampMs)

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

    /** Opens the microphone and the video's sound; true when the file will have any sound. */
    fun prepare(): Boolean {
        if (micWanted) record = openMic()
        val path = videoPath
        if (path != null) {
            val reader = PcmAudioSource(path, 1.0, sampleRate)
            source = if (reader.open()) reader else null.also { reader.release() }
        }
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
        record?.release()
        record = null
        source?.release()
        source = null
        encoder?.release()
        encoder = null
    }

    @SuppressLint("MissingPermission")
    private fun openMic(): AudioRecord? {
        for (rate in intArrayOf(PREFERRED_RATE, FALLBACK_RATE)) {
            try {
                val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                if (min <= 0) continue
                val mic = AudioRecord(
                    MediaRecorder.AudioSource.CAMCORDER,
                    rate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(min, rate / 5 * 2),
                )
                if (mic.state == AudioRecord.STATE_INITIALIZED) {
                    sampleRate = rate
                    return mic
                }
                mic.release()
            } catch (error: Exception) {
                Log.w(TAG, "microphone at $rate refused", error)
            }
        }
        return null
    }

    private fun readMic(mic: AudioRecord) {
        val block = ShortArray(sampleRate / 100)
        val stamp = AudioTimestamp()
        var framesRead = 0L
        while (running) {
            val read = mic.read(block, 0, block.size)
            if (read == AudioRecord.ERROR_DEAD_OBJECT) break
            if (read <= 0) continue
            val arrival = System.nanoTime()
            val heard = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                mic.getTimestamp(stamp, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS
            ) {
                stamp.nanoTime + (framesRead - stamp.framePosition) * NANOS / sampleRate
            } else {
                arrival - read.toLong() * NANOS / sampleRate
            }
            framesRead += read
            val fileNanos = clock.fileNanos(heard) ?: continue
            val first = fileNanos * sampleRate / NANOS
            for (k in 0 until read) {
                val index = first + k
                val slot = (index % ring.size).toInt()
                ring[slot] = block[k]
                stamps[slot] = index
            }
            if (first + read > micUpTo) micUpTo = first + read
        }
    }

    private class Pending(val frame: Long, val mic: FloatArray, val video: FloatArray)

    private fun mixLoop() {
        val blockFrames = sampleRate / 100
        val lookaheadFrames = LiveTalkGate.LOOKAHEAD_MS * sampleRate / 1000
        val pending = ArrayDeque<Pending>()
        var analysed = 0L
        var gains = gate.gainsAt(0)
        val out = ShortArray(blockFrames * ReactAacEncoder.CHANNELS)
        try {
            while (true) {
                val end = endFileNanos
                val available = if (end >= 0) end else clock.durationNanos(System.nanoTime()) - LAG_MS * 1_000_000L
                val availableFrames = available * sampleRate / NANOS
                while (analysed + blockFrames <= availableFrames) {
                    pending.addLast(analyse(analysed, blockFrames))
                    analysed += blockFrames
                }
                while (pending.isNotEmpty() &&
                    (end >= 0 || pending.first().frame + blockFrames + lookaheadFrames <= analysed)
                ) {
                    gains = emit(pending.removeFirst(), gains, out)
                }
                if (end >= 0) break
                if (!running) return
                Thread.sleep(10)
            }
            encoder?.finish()
        } catch (error: Exception) {
            Log.w(TAG, "the reaction's sound stopped", error)
        }
    }

    private fun analyse(frame: Long, frames: Int): Pending {
        val mic = FloatArray(frames)
        if (record != null) {
            for (k in 0 until frames) {
                val index = frame + k
                val slot = (index % ring.size).toInt()
                if (stamps[slot] == index) mic[k] = ring[slot] / 32768f
            }
        }
        val video = FloatArray(frames * 2)
        val reader = source
        if (reader != null) {
            val real = clock.realNanos(frame * NANOS / sampleRate)
            val moment = real?.let { media.mediaMsAt(it) }
            if (moment != null) {
                val at = readerMs
                if (at == null || abs(at - moment) > DRIFT_MS) {
                    reader.seekTo(moment * 1_000L)
                    readerMs = moment
                }
                val got = reader.read(video, 0, frames)
                if (got < frames) video.fill(0f, got * 2, frames * 2)
                readerMs = (readerMs ?: moment) + frames * 1_000L / sampleRate
            }
            if (real != null && frame % (sampleRate.toLong() * 5) < frames) media.prune(real - PRUNE_NANOS)
        }
        gate.addBlock(frame * 1_000 / sampleRate, levelDb(mic, 1), levelDb(video, 2))
        return Pending(frame, mic, video)
    }

    private var readerMs: Long? = null

    /** Mixes one block with the gains eased from [from] to the block's own, and encodes it. */
    private fun emit(block: Pending, from: LiveTalkGate.Gains, out: ShortArray): LiveTalkGate.Gains {
        val to = gate.gainsAt(block.frame * 1_000 / sampleRate)
        val frames = block.mic.size
        for (k in 0 until frames) {
            val t = (k + 1).toDouble() / frames
            val videoGain = (from.video + (to.video - from.video) * t).toFloat()
            val micGain = (from.mic + (to.mic - from.mic) * t).toFloat()
            val voice = block.mic[k] * micGain
            out[2 * k] = toShort(block.video[2 * k] * videoGain + voice)
            out[2 * k + 1] = toShort(block.video[2 * k + 1] * videoGain + voice)
        }
        encoder?.write(out, frames)
        return to
    }

    private fun toShort(value: Float): Short = (value.coerceIn(-1f, 1f) * 32767f).toInt().toShort()

    private fun levelDb(samples: FloatArray, channels: Int): Double {
        var sum = 0.0
        for (v in samples) sum += v * v
        val rms = sqrt(sum / samples.size.coerceAtLeast(1))
        return if (rms <= 1e-6) SILENCE_DB else 20 * log10(rms)
    }

    private companion object {
        const val TAG = "SlimshotCamera"
        const val NANOS = 1_000_000_000L
        const val PREFERRED_RATE = 48_000
        const val FALLBACK_RATE = 44_100
        const val RING_SECONDS = 4
        const val LAG_MS = 200L
        const val DRIFT_MS = 40L
        const val SILENCE_DB = -120.0
        const val MIC_CATCH_UP_NANOS = 400_000_000L
        const val FINISH_TIMEOUT_MS = 5_000L
        const val PRUNE_NANOS = 5_000_000_000L
    }
}
