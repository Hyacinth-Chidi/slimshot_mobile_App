package com.techfamz.slimshotai.camera.react

import kotlin.math.abs

/**
 * Where each block of the microphone goes in the file: one continuous stream.
 *
 * A block is anchored where it was heard (its timestamp, in file time) at the
 * start, after a pause, and after a real gap — frames the microphone lost —
 * and laid end to end otherwise. Placing every block by its own timestamp
 * left gaps and overlaps of a few samples between blocks, since timestamps
 * jitter, and each was heard as a click. Timestamps that drift past that
 * jitter — the microphone's clock against the system's — are followed a
 * sample at a time, so the voice stays on its picture through a long take
 * without a jump. Pure, JVM-tested.
 */
internal class MicPlacer(private val sampleRate: Int) {

    private val toleranceFrames = sampleRate * TOLERANCE_MS / 1000
    private val gapFrames = sampleRate * GAP_MS / 1000
    private var next: Long? = null

    /**
     * The file frame a block of [frames] heard at [heardFileNanos] starts at;
     * null — the block dropped — while the take is paused (no file time).
     */
    fun place(heardFileNanos: Long?, frames: Int): Long? {
        if (heardFileNanos == null) {
            next = null
            return null
        }
        val measured = heardFileNanos * sampleRate / NANOS
        val expected = next
        val start = when {
            expected == null || abs(measured - expected) > gapFrames -> measured
            measured - expected > toleranceFrames -> expected + 1
            expected - measured > toleranceFrames -> expected - 1
            else -> expected
        }
        next = start + frames
        return start
    }

    private companion object {
        const val NANOS = 1_000_000_000L

        /** How far timestamps may wander before the stream follows them. */
        const val TOLERANCE_MS = 20L

        /** Beyond this the stream is anchored again: frames were lost. */
        const val GAP_MS = 60L
    }
}
