package com.techfamz.slimshotai.audio

/** The arithmetic extracted and recorded sound is written with. Pure, JVM-tested. */
internal object PcmFrames {

    /** Float samples in -1..1 to 16-bit, clamped; only the first [count] are touched. */
    fun floatToShort(src: FloatArray, count: Int, dest: ShortArray) {
        for (i in 0 until count) {
            val scaled = (src[i] * Short.MAX_VALUE).toInt()
            dest[i] = scaled.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }
    }

    /** A frame count at [sampleRate] as microseconds — what a sample's timestamp is. */
    fun usForFrames(frames: Long, sampleRate: Int): Long = frames * 1_000_000L / sampleRate

    fun usForFrames(frames: Int, sampleRate: Int): Long = usForFrames(frames.toLong(), sampleRate)
}
