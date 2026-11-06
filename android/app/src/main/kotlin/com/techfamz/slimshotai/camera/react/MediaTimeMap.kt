package com.techfamz.slimshotai.camera.react

/**
 * Which moment of the video was on screen at each instant of the take, from
 * the player's position sampled with `nanoTime` on every engine tick and at
 * every play, pause and end. The video's sound in the file is read at these
 * moments, so it matches the picture that was drawn: moving while it played,
 * nothing while it was held.
 */
internal class MediaTimeMap {

    private class Sample(val nanos: Long, val positionMs: Long, val playing: Boolean)

    private val samples = ArrayList<Sample>()

    @Synchronized
    fun sample(nanos: Long, positionMs: Long, playing: Boolean) {
        // A sample at the same instant as the last replaces it: the newer
        // word on the player's state wins.
        if (samples.isNotEmpty() && samples.last().nanos >= nanos) {
            if (samples.last().nanos == nanos) samples[samples.size - 1] = Sample(nanos, positionMs, playing)
            return
        }
        samples += Sample(nanos, positionMs, playing)
    }

    /** The moment on screen at [nanos] while the video played; null while held, or before the first sample. */
    @Synchronized
    fun mediaMsAt(nanos: Long): Long? {
        val index = samples.indexOfLast { it.nanos <= nanos }
        if (index < 0) return null
        val at = samples[index]
        if (!at.playing) return null
        val carried = at.positionMs + (nanos - at.nanos) / 1_000_000L
        val next = samples.getOrNull(index + 1) ?: return carried
        return minOf(carried, next.positionMs)
    }

    /** Drops samples before [beforeNanos], keeping the one standing at it. */
    @Synchronized
    fun prune(beforeNanos: Long) {
        val keep = samples.indexOfLast { it.nanos <= beforeNanos }
        if (keep > 0) samples.subList(0, keep).clear()
    }
}
