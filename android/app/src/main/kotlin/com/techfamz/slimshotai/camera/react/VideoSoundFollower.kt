package com.techfamz.slimshotai.camera.react

import kotlin.math.abs

/**
 * The video's sound in a live reaction follows the moment of the video on
 * screen, and stays one continuous stream while it does.
 *
 * The decoder is sought only when the player really jumped — the first
 * moment, a restart — never for the drift between two clocks: re-aiming at
 * every 40 ms of drift was heard as glitches, since the player's reported
 * position jitters. Drift past that jitter is taken up a sample per block,
 * which the decoder's resampler spreads over the block: no step anywhere in
 * the wave. Pure, JVM-tested.
 */
internal object VideoSoundFollower {

    sealed class Step {
        /** Nothing playing — held, ended, not started: no sound. */
        object Silence : Step()

        /** The player jumped: seek the decoder to [ms] first. */
        data class Seek(val ms: Long) : Step()

        /** Read on, consuming [adjust] source frames more (or fewer) than the block. */
        data class Read(val adjust: Int) : Step()
    }

    /** Within this the player's position is jitter, left alone. */
    const val TOLERANCE_MS = 15.0

    /** Beyond this the player jumped. */
    const val JUMP_MS = 200.0

    /** What to do for a block that starts while [showingMs] is on screen and the decoder stands at [readerMs]. */
    fun step(showingMs: Long?, readerMs: Double?): Step {
        if (showingMs == null) return Step.Silence
        if (readerMs == null) return Step.Seek(showingMs)
        val behind = showingMs - readerMs
        return when {
            abs(behind) > JUMP_MS -> Step.Seek(showingMs)
            behind > TOLERANCE_MS -> Step.Read(1)
            behind < -TOLERANCE_MS -> Step.Read(-1)
            else -> Step.Read(0)
        }
    }
}
