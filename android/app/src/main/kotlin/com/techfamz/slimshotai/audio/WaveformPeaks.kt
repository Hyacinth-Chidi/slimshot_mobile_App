package com.techfamz.slimshotai.audio

import kotlin.math.abs

/**
 * A sound reduced to the peaks the Extract sheet draws: one value per bucket,
 * the loudest bucket at 1.0 so a quiet recording still fills the strip. Pure
 * and JVM-tested; the decoding that feeds it is [AudioExtractor.peaks].
 */
internal object WaveformPeaks {

    /** [frames] interleaved frames of [channels] in [samples], into [buckets] peaks. */
    fun reduce(samples: FloatArray, frames: Int, channels: Int, buckets: Int): DoubleArray {
        val acc = Accumulator(frames.toLong(), buckets)
        acc.add(samples, frames, channels)
        return acc.result()
    }

    /**
     * The same reduction fed a block at a time, so a long sound is never held
     * whole in memory. [totalFrames] places each frame in its bucket; frames
     * past it land in the last bucket rather than being lost.
     */
    class Accumulator(private val totalFrames: Long, private val buckets: Int) {
        private val peaks = DoubleArray(buckets.coerceAtLeast(0))
        private var seen = 0L

        fun add(samples: FloatArray, frames: Int, channels: Int) {
            if (peaks.isEmpty() || totalFrames <= 0) {
                seen += frames
                return
            }
            for (f in 0 until frames) {
                val bucket = ((seen * buckets) / totalFrames).toInt().coerceIn(0, buckets - 1)
                var loudest = 0.0
                for (c in 0 until channels) {
                    val v = abs(samples[f * channels + c].toDouble())
                    if (v > loudest) loudest = v
                }
                if (loudest > peaks[bucket]) peaks[bucket] = loudest
                seen++
            }
        }

        fun result(): DoubleArray {
            val max = peaks.maxOrNull() ?: 0.0
            if (max <= 0.0) return DoubleArray(peaks.size)
            return DoubleArray(peaks.size) { peaks[it] / max }
        }
    }
}

/** Which sound is copied into an `.m4a` as it is, and which is converted. */
internal object ExtractPlan {
    /** Only AAC goes into an MP4 audio file unchanged on every Android version. */
    fun canRemux(mime: String): Boolean = mime == "audio/mp4a-latm"
}
