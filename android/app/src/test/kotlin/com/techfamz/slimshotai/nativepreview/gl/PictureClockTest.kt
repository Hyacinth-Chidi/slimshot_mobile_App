package com.techfamz.slimshotai.nativepreview.gl

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The instant overlays are drawn at: the picture's own.
 *
 * Measured on a phone, video frames reach the renderer ~42 ms before they are
 * shown, while the overlays were timed by the clock as the engine read it —
 * so a caption drawn by the engine trailed the picture beside it by just as
 * much. Over video an overlay is now drawn at the instant of the frame it is
 * composited with; over a photo, where no frame says, at the clock carried to
 * now plus the lead video frames have shown.
 */
class PictureClockTest {

    private fun ms(value: Long): Long = value * 1_000_000L

    @Test
    fun `paused draws at the clock`() {
        val clock = PictureClock()
        clock.onClock(3.5, ms(0), advancing = false)
        clock.onVideoFrame(dueNs = ms(40), latchedNs = ms(1))
        assertEquals(3.5, clock.overlayTime(ms(2)), 0.0)
    }

    @Test
    fun `over video it draws at the frame's own time`() {
        val clock = PictureClock()
        clock.onClock(10.0, ms(1_000), advancing = true)
        clock.onVideoFrame(dueNs = ms(1_042), latchedNs = ms(1_002))
        assertEquals(10.042, clock.overlayTime(ms(1_003)), 1e-9)
    }

    @Test
    fun `a due time out of reach is not the picture`() {
        val clock = PictureClock()
        clock.onClock(10.0, ms(1_000), advancing = true)
        // A timestamp a second away is not a frame about to be shown — and
        // not a lead worth learning either.
        clock.onVideoFrame(dueNs = ms(2_003), latchedNs = ms(1_002))
        assertEquals(10.003, clock.overlayTime(ms(1_003)), 1e-9)
    }

    @Test
    fun `over a photo it runs on from the last change of the clock`() {
        // ExoPlayer can hold one position for most of a second on an image
        // period; carried from the read, the text would stand still with it.
        val clock = PictureClock()
        clock.onClock(5.0, ms(0), advancing = true)
        clock.onClock(5.0, ms(200), advancing = true)
        assertEquals(5.4, clock.overlayTime(ms(400)), 1e-9)
    }

    @Test
    fun `over a photo it adds the lead video taught it`() {
        val clock = PictureClock()
        clock.onClock(1.0, ms(0), advancing = true)
        for (i in 0 until 10) {
            clock.onVideoFrame(dueNs = ms(i * 33L + 40), latchedNs = ms(i * 33L))
        }
        // The last frame is long gone: a photo is on screen.
        assertEquals(2.04, clock.overlayTime(ms(1_000)), 0.002)
    }

    @Test
    fun `frames latched while paused teach nothing`() {
        val clock = PictureClock()
        clock.onClock(1.0, ms(0), advancing = true)
        for (i in 0 until 5) {
            clock.onVideoFrame(dueNs = ms(i * 33L + 40), latchedNs = ms(i * 33L))
        }
        clock.onClock(1.0, ms(150), advancing = false)
        // A seek's frame is shown at once: a lead of nothing.
        clock.onVideoFrame(dueNs = ms(200), latchedNs = ms(200))
        clock.onClock(1.0, ms(300), advancing = true)
        assertEquals(1.0 + 0.7 + 0.04, clock.overlayTime(ms(1_000)), 1e-6)
    }

    @Test
    fun `a photo on screen ends what the last video frame said`() {
        // At a cut to a photo the video's last frame is still recent, but it
        // is no longer the picture: nothing would ask for a draw over the
        // photo until it aged out.
        val clock = PictureClock()
        clock.onClock(1.0, ms(0), advancing = true)
        clock.onVideoFrame(dueNs = ms(40), latchedNs = ms(0))
        clock.onNoVideo()
        assertFalse(clock.framesDriveDraws(ms(1)))
        assertEquals(1.0 + 0.001 + 0.04, clock.overlayTime(ms(1)), 1e-9)
    }

    @Test
    fun `video frames drive the draws only while fresh and playing`() {
        val clock = PictureClock()
        clock.onClock(1.0, ms(0), advancing = true)
        clock.onVideoFrame(dueNs = ms(40), latchedNs = ms(0))
        assertTrue(clock.framesDriveDraws(ms(1)))
        assertFalse(clock.framesDriveDraws(PictureClock.FRESH_FRAME_NS + 1))

        clock.onClock(1.0, ms(2), advancing = false)
        assertFalse(clock.framesDriveDraws(ms(3)))
    }
}
