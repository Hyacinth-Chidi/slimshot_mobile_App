package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two lane hand-offs a transition makes, as logged on the emulator when
 * a split clip with a transition at its cut stopped playback for good: the
 * prewarm moved a lane the playhead was using, and a window "closed" by the
 * clock jumping back before it handed the clock to the incoming lane, which
 * put it back inside the window — and round again, for ever.
 */
class TransitionLanesTest {

    private val window = NativeTimelineTransitionIntent(
        leftClipId = "a",
        rightClipId = "b",
        leftClipIndex = 0,
        rightClipIndex = 1,
        type = "dissolve",
        durationSeconds = 0.8,
        timelineStartSeconds = 4.192793330439818,
        timelineEndSeconds = 4.992793330439818,
    )

    @Test
    fun `a window closes into the incoming lane once the clock is past it`() {
        assertTrue(TransitionLanes.closeHandsOver(window.timelineEndSeconds, window))
        assertTrue(TransitionLanes.closeHandsOver(window.timelineEndSeconds + 0.5, window))
    }

    @Test
    fun `a clock that jumped back before the window keeps its own clip`() {
        // The logged loop: the outgoing lane read 3.592 with the window open.
        assertFalse(TransitionLanes.closeHandsOver(3.592, window))
        assertFalse(TransitionLanes.closeHandsOver(0.0, window))
    }

    @Test
    fun `the incoming lane is prewarmed only while nothing is using it`() {
        assertTrue(
            TransitionLanes.mayPrewarm(windowActive = false, incomingLane = 1, masterLane = 0),
        )
    }

    @Test
    fun `not when a seek has already placed both lanes for a window`() {
        // Logged: the playhead on the split's cut, the seek inside the window,
        // then the prewarm sent the incoming lane back to its first frame.
        assertFalse(
            TransitionLanes.mayPrewarm(windowActive = true, incomingLane = 1, masterLane = 0),
        )
    }

    @Test
    fun `never the lane the clock is read from`() {
        // The playhead past the first window, in its incoming clip: that lane
        // is the master, and rewinding it to the clip's start moved the clock.
        assertFalse(
            TransitionLanes.mayPrewarm(windowActive = false, incomingLane = 1, masterLane = 1),
        )
    }

    // Run 1 on the emulator, after the clock fix: the incoming lane had not
    // started by the window's end (still buffering at its first frame,
    // 3.369), and handing it the clock put the clock back inside the window;
    // it swung between 4.765 and 3.369 for two seconds.

    @Test
    fun `after a hand-over the clock holds at the window's end until the incoming lane gets there`() {
        assertEquals(4.765, TransitionLanes.heldClock(raw = 3.369, holdEnd = 4.765), 0.0)
        assertEquals(4.765, TransitionLanes.heldClock(raw = 4.74, holdEnd = 4.765), 0.0)
    }

    @Test
    fun `and runs on from the incoming lane once it is past`() {
        assertEquals(4.9, TransitionLanes.heldClock(raw = 4.9, holdEnd = 4.765), 0.0)
        assertEquals(2.0, TransitionLanes.heldClock(raw = 2.0, holdEnd = Double.NaN), 0.0)
    }

    @Test
    fun `the hold lasts as long as the lane is behind, however far`() {
        // A lane that barely started is never moved: a seek restarts its
        // decoder from the last keyframe, which froze the picture for seconds
        // on the emulator. It plays on from the frame it shows, and the clock
        // waits for it.
        assertEquals(4.765, TransitionLanes.heldClock(raw = 3.369, holdEnd = 4.765), 0.0)
        assertEquals(4.765, TransitionLanes.heldClock(raw = 3.9, holdEnd = 4.765), 0.0)
        assertEquals(4.8, TransitionLanes.heldClock(raw = 4.8, holdEnd = 4.765), 0.0)
    }
}
