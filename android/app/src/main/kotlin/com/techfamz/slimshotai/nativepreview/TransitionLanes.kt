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
}
