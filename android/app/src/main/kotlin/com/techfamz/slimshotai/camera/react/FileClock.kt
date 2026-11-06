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

    /**
     * The moment [fileNanos] was recorded at — the inverse of [fileNanos]. A
     * file time at a pause's seam is the moment recording resumed. Null
     * before the start.
     */
    @Synchronized
    fun realNanos(fileNanos: Long): Long? {
        val start = startNanos ?: return null
        var real = start + fileNanos
        for (pause in pauses) {
            if (real >= pause[0]) real += pause[1] - pause[0] else break
        }
        return real
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
        /** A camera timestamp is at most this far behind its arrival on its own clock. */
        const val BASE_TOLERANCE_NANOS = 1_000_000_000L

        /** Clock jitter a timestamp may sit ahead of its arrival by. */
        private const val AHEAD_NANOS = 5_000_000L

        /**
         * A camera frame's moment on `nanoTime`'s clock. Cameras stamp with
         * either that clock or boot time (`elapsedRealtimeNanos`), and the two
         * differ by however long the phone has slept — often well under a
         * second, so "close to the arrival" cannot tell them apart. The
         * timestamp is matched to whichever clock read nearest **after** it
         * at [arrival] / [arrivalBoot]; a boot-clock stamp is moved onto the
         * monotonic clock. On neither, the arrival stands in.
         */
        fun frameNanos(timestamp: Long, arrival: Long, arrivalBoot: Long): Long {
            val behindMono = arrival - timestamp
            val behindBoot = arrivalBoot - timestamp
            val mono = behindMono in -AHEAD_NANOS until BASE_TOLERANCE_NANOS
            val boot = behindBoot in -AHEAD_NANOS until BASE_TOLERANCE_NANOS
            return when {
                mono && (!boot || abs(behindMono) <= abs(behindBoot)) -> timestamp
                boot -> timestamp - (arrivalBoot - arrival)
                else -> arrival
            }
        }
    }
}
