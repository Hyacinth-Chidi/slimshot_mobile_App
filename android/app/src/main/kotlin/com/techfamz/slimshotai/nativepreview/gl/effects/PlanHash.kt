package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * A fixed random number for an integer and a salt, on the CPU, in Long
 * arithmetic — the same on every device and in every run, so the canvas and
 * the file see the same randomness. SplitMix64's mix.
 *
 * For effects whose randomness is the same for every pixel of a frame — a
 * camera's pose, a glitch's torn blocks — and so belongs here rather than in a
 * shader hash, which `mediump` can ruin (see [CameraShake]).
 */
internal object PlanHash {

    /** In 0..1 (1 excluded). */
    fun unit(i: Long, salt: Int): Double {
        var z = i * -0x61C8864680B583EBL + salt.toLong() * 0x632BE59BD9B4E019L
        z = (z xor (z ushr 30)) * -0x40A7B892E31B1A47L
        z = (z xor (z ushr 27)) * -0x6B2FB644ECCEEE15L
        z = z xor (z ushr 31)
        return (z ushr 11).toDouble() / (1L shl 53).toDouble()
    }

    /** In -1..1. */
    fun signed(i: Long, salt: Int): Double = unit(i, salt) * 2.0 - 1.0
}
