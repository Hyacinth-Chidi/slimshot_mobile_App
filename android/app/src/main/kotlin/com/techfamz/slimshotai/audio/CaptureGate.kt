package com.techfamz.slimshotai.audio

/**
 * Which of the microphone's frames go into the take. Pure, JVM-tested.
 *
 * The recorder reads the microphone continuously from the moment it opens, so
 * by the time the video starts the microphone is already delivering; frames
 * heard while not capturing — before the video moves, during a pause — are
 * dropped. A take therefore has no microphone start-up delay inside it.
 *
 * Capture starts once the video is *seen* moving, a moment after it did, so
 * each start is aligned first ([alignTo]): silence fills the take up to the
 * picture's own position, and frame `n` of the file is always timeline time
 * `takeStart + n / rate`, through every pause.
 */
internal class CaptureGate {

    @Volatile
    var capturedFrames: Long = 0L
        private set

    /** How many of [frames] just read are kept. */
    fun accept(frames: Int, capturing: Boolean): Int {
        if (!capturing || frames <= 0) return 0
        capturedFrames += frames
        return frames
    }

    /**
     * The silence to write so the take reaches [targetFrames], counted as
     * captured. Never negative: what was captured cannot be taken back.
     */
    fun alignTo(targetFrames: Long): Long {
        val pad = (targetFrames - capturedFrames).coerceAtLeast(0L)
        capturedFrames += pad
        return pad
    }

    fun capturedMs(sampleRate: Int): Long = capturedFrames * 1000L / sampleRate

    companion object {
        fun framesFor(alignMs: Long, sampleRate: Int): Long =
            (alignMs * sampleRate / 1000L).coerceAtLeast(0L)

        fun framesFor(alignMs: Int, sampleRate: Int): Long =
            framesFor(alignMs.toLong(), sampleRate)
    }
}
