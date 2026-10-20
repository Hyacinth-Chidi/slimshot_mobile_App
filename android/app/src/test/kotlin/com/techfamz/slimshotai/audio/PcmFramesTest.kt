package com.techfamz.slimshotai.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The arithmetic every extracted or recorded file is written with. */
class PcmFramesTest {

    @Test
    fun `float samples clamp to the 16-bit range`() {
        val out = ShortArray(4)
        PcmFrames.floatToShort(floatArrayOf(2f, -2f, 0.5f, 0f), 4, out)
        assertEquals(Short.MAX_VALUE, out[0])
        assertEquals(Short.MIN_VALUE, out[1])
        assertTrue(kotlin.math.abs(out[2] - 16383) <= 1)
        assertEquals(0.toShort(), out[3])
    }

    @Test
    fun `only the requested count is converted`() {
        val out = ShortArray(2) { 7 }
        PcmFrames.floatToShort(floatArrayOf(1f, 1f), 1, out)
        assertEquals(7.toShort(), out[1])
    }

    @Test
    fun `frames convert to microseconds exactly`() {
        assertEquals(1_000_000L, PcmFrames.usForFrames(44_100, 44_100))
        assertEquals(20L, PcmFrames.usForFrames(1, 48_000))
        assertEquals(0L, PcmFrames.usForFrames(0, 48_000))
    }
}
