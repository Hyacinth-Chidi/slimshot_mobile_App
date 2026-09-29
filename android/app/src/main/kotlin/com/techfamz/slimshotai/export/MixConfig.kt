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
