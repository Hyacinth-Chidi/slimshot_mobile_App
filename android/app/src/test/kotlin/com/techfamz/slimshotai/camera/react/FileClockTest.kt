package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The file's own clock: recording time, with every pause taken out. */
class FileClockTest {

    @Test
    fun `file time runs from the start`() {
        val clock = FileClock()
        assertNull("before the start", clock.fileNanos(500))
        clock.start(1_000)
        assertEquals(2_000L, clock.fileNanos(3_000))
    }

    @Test
    fun `a pause is taken out, and nothing inside it has a file time`() {
        val clock = FileClock()
        clock.start(1_000)
        clock.pause(3_000)
        assertTrue(clock.isPaused)
        assertNull(clock.fileNanos(5_000))
        assertEquals(2_000L, clock.durationNanos(5_000))
        clock.resume(7_000)
        assertFalse(clock.isPaused)
        assertEquals(3_000L, clock.fileNanos(8_000))
        assertEquals(3_000L, clock.durationNanos(8_000))
        assertEquals(1_500L, clock.fileNanos(2_500), "before the pause is untouched by it")
    }

    @Test
    fun `two pauses add up`() {
        val clock = FileClock()
        clock.start(0)
        clock.pause(1_000)
        clock.resume(2_000)
        clock.pause(3_000)
        clock.resume(5_000)
        assertEquals(3_000L, clock.fileNanos(6_000))
    }

    @Test
    fun `a file time maps back to the moment it was recorded`() {
        val clock = FileClock()
        clock.start(1_000)
        clock.pause(3_000)
        clock.resume(7_000)
        org.junit.Assert.assertEquals(2_500L, clock.realNanos(1_500))
        org.junit.Assert.assertEquals(7_000L, clock.realNanos(2_000))
        org.junit.Assert.assertEquals(8_000L, clock.realNanos(3_000))
        assertNull(FileClock().realNanos(0))
    }

    @Test
    fun `a camera timestamp is trusted only on the clock it is compared with`() {
        assertEquals(1_000_000_000L, FileClock.frameNanos(1_000_000_000L, 1_010_000_000L))
        assertEquals(1_010_000_000L, FileClock.frameNanos(5L, 1_010_000_000L))
    }

    private fun assertEquals(expected: Long, actual: Long?, message: String) =
        org.junit.Assert.assertEquals(message, expected, actual)
}
