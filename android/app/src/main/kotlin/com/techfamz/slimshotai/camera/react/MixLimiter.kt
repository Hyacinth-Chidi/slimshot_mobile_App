package com.techfamz.slimshotai.camera.react

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max

/**
 * Keeps a live reaction's mix inside full scale without clipping it. Your
 * voice and the video's sound are both at full, so their sum can pass full
 * scale, and clamped every such peak is a crackle. Over [CEILING] the level
 * is taken down for that sample at once and given back over [RELEASE_MS];
 * a mix that stays inside passes exactly as it was. Both sides share the gain,
 * so the picture of the sound does not lean. Pure, JVM-tested.
 */
internal class MixLimiter(sampleRate: Int) {

    private var gain = 1f
    private val recover = (1.0 - exp(-1000.0 / (sampleRate * RELEASE_MS))).toFloat()

    /** Limits [frames] interleaved stereo frames of [stereo] in place. */
    fun process(stereo: FloatArray, frames: Int) {
        for (f in 0 until frames) {
            val left = stereo[2 * f]
            val right = stereo[2 * f + 1]
            if (gain < 1f) {
                gain += (1f - gain) * recover
                if (gain > SETTLED) gain = 1f
            }
            val peak = max(abs(left), abs(right))
            if (peak * gain > CEILING) gain = CEILING / peak
            if (gain < 1f) {
                stereo[2 * f] = left * gain
                stereo[2 * f + 1] = right * gain
            }
        }
    }

    companion object {
        const val CEILING = 0.98f
        const val RELEASE_MS = 100.0

        /** Close enough to 1 to be 1: a gain that only approaches it would never let a mix pass untouched again. */
        private const val SETTLED = 0.9999f
    }
}
