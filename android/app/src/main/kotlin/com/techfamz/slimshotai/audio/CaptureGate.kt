package com.techfamz.slimshotai.audio

/**
 * Which of the microphone's frames go into the take. Pure, JVM-tested.
 *
 * The recorder reads the microphone continuously from the moment it opens, so
 * by the time the video starts the microphone is already delivering; frames
 * heard while not capturing — before the countdown ends, during a pause — are
 * dropped. A take therefore starts on the frame recording began, with no
 * microphone start-up delay inside it, and a pause leaves no gap in the file.
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

    fun capturedMs(sampleRate: Int): Long = capturedFrames * 1000L / sampleRate
}
