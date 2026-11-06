package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertEquals
import org.junit.Test

/** Camera frames that never made it into the file, told from timestamp gaps. */
class MissedFramesTest {

    private fun run(frames: MissedFrames, count: Int, intervalNanos: Long, from: Long = 0L): Long {
        var t = from
        repeat(count) {
            frames.onFrame(t)
            t += intervalNanos
        }
        return t - intervalNanos
    }

    @Test
    fun `a steady 30 fps camera misses nothing`() {
        val frames = MissedFrames()
        run(frames, 300, 33_333_333L)
        assertEquals(300, frames.frames)
        assertEquals(0, frames.missed)
    }

    @Test
    fun `a 100 ms gap at 30 fps is two frames missed`() {
        val frames = MissedFrames()
        val last = run(frames, 60, 33_333_333L)
        run(frames, 30, 33_333_333L, from = last + 100_000_000L)
        assertEquals(2, frames.missed)
    }

    @Test
    fun `a camera that drops to 15 fps in low light is not choppy`() {
        val frames = MissedFrames()
        run(frames, 300, 66_666_666L)
        assertEquals(0, frames.missed)
    }

    @Test
    fun `30 fps falling to 15 fps settles once the camera's own rate is learned`() {
        val frames = MissedFrames()
        val last = run(frames, 90, 33_333_333L)
        run(frames, 300, 66_666_666L, from = last + 66_666_666L)
        assert(frames.missed <= 20) { "missed ${frames.missed}" }
    }
}
