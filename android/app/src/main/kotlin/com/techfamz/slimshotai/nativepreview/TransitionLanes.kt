package com.techfamz.slimshotai.nativepreview

/**
 * The two decisions a transition makes about the lanes, outside the engine
 * so they can be tested: the engine itself only runs on a device.
 *
 * Both were found in one emulator log, of a split clip with a transition at
 * its cut that stopped playback there for good (`LaneClockTest` has the
 * rounding that set it off). Each kept the loop going once it started.
 */
internal object TransitionLanes {

    /**
     * Whether a window that no longer contains [position] closed by the clock
     * passing it — the incoming lane, playing in step, takes over — rather
     * than by the clock jumping back before it.
     *
     * A lane moved under the clock (a seek, a rewind) can leave it before the
     * window with the window still open. Handing the clock to the incoming
     * lane then, parked at its first frame, put it back inside the window,
     * whose opening handed it to the outgoing lane, back before the window:
     * the two lanes traded it on every tick and nothing played. Before the
     * window the clip at the clock keeps it.
     */
    fun closeHandsOver(position: Double, window: NativeTimelineTransitionIntent): Boolean =
        position >= window.timelineStartSeconds

    /**
     * Whether the timeline's first incoming lane may be parked on its clip's
     * first frame after a rebuild's seek — only while nothing is using it.
     *
     * Not when the seek landed inside a window: both lanes are already where
     * the playhead needs them. And never the lane the clock is read from: past
     * the first window the playhead is in its incoming clip, and rewinding
     * that lane moved the clock to the window's start.
     */
    fun mayPrewarm(windowActive: Boolean, incomingLane: Int, masterLane: Int): Boolean =
        !windowActive && incomingLane != masterLane

    /**
     * The clock after a window has closed into its incoming lane: held at
     * the window's end ([holdEnd]) until that lane's own reading ([raw])
     * gets there, then the lane's. NaN [holdEnd]: no hold.
     *
     * The incoming lane starts late — tens of milliseconds on a phone, two
     * seconds on the emulator's decoder — so at the window's end it can still
     * stand before it. Read as it was, the clock went back inside the window,
     * whose opening handed it to the outgoing lane at the window's end, whose
     * close handed it back: the playhead swung between the two until the
     * lane got going, the stop-and-restart device-reported at a transition.
     * Held, the playhead waits at the cut while the lane catches up.
     */
    fun heldClock(raw: Double, holdEnd: Double): Double =
        if (!holdEnd.isNaN() && raw < holdEnd) holdEnd else raw

    /**
     * Whether an incoming lane taking the clock is too far behind the
     * window's end to be waited for, and is moved there instead. Within the
     * drift tolerance it is left to catch up, as drift is: a seek flushes the
     * decoder, which shows far more than a moment's hold.
     */
    fun handOverNeedsSeek(incomingClock: Double, windowEnd: Double): Boolean =
        windowEnd - incomingClock > HAND_OVER_SEEK_SECONDS

    /** The engine's drift tolerance: below it a lane is never seeked. */
    private const val HAND_OVER_SEEK_SECONDS = 0.25
}
