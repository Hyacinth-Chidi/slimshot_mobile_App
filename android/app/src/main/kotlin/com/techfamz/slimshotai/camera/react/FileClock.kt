package com.techfamz.slimshotai.camera.react

import kotlin.math.abs

/**
 * The file's clock: the recording's time with every pause of the take taken
 * out, in `System.nanoTime()` terms. The picture's frames and the sound's
 * samples are both placed by it, which is what keeps them together across
 * pauses.
 */
internal class FileClock {

    private var startNanos: Long? = null
    private val pauses = mutableListOf<LongArray>()
    private var pausedAt: Long? = null

    val isPaused: Boolean @Synchronized get() = pausedAt != null

    @Synchronized
    fun start(nanos: Long) {
        startNanos = nanos
        pauses.clear()
        pausedAt = null
    }

    @Synchronized
    fun pause(nanos: Long) {
        if (startNanos == null || pausedAt != null) return
        pausedAt = nanos
    }

    @Synchronized
    fun resume(nanos: Long) {
        val from = pausedAt ?: return
        pauses += longArrayOf(from, maxOf(from, nanos))
        pausedAt = null
    }

    /** [nanos] in file time; null before the start or inside a pause. */
    @Synchronized
    fun fileNanos(nanos: Long): Long? {
        val start = startNanos ?: return null
        if (nanos < start) return null
        val open = pausedAt
        if (open != null && nanos >= open) return null
        var paused = 0L
        for ((from, to) in pauses.map { it[0] to it[1] }) {
            if (nanos >= to) {
                paused += to - from
            } else if (nanos >= from) {
                return null
            }
        }
        return nanos - start - paused
    }

    /** How much the file holds at [nanos]: held still through a pause. */
    @Synchronized
    fun durationNanos(nanos: Long): Long {
        val start = startNanos ?: return 0L
        val open = pausedAt
        val at = if (open != null && nanos >= open) open else nanos
        if (at < start) return 0L
        var paused = 0L
        for (pause in pauses) {
            if (at >= pause[1]) paused += pause[1] - pause[0] else if (at > pause[0]) paused += at - pause[0]
        }
        return at - start - paused
    }

    companion object {
        /** A camera timestamp within this of its arrival is on the same clock. */
        const val BASE_TOLERANCE_NANOS = 200_000_000L

        /**
         * A camera frame's moment: its own timestamp where it is on
         * `nanoTime`'s clock — some cameras stamp with boot time — else when it
         * arrived.
         */
        fun frameNanos(timestamp: Long, arrival: Long): Long =
            if (abs(arrival - timestamp) < BASE_TOLERANCE_NANOS) timestamp else arrival
    }
}
