package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The voice and the video's sound are both at full, so their sum can pass
 * full scale; clamped, every such peak is a crackle. The limiter takes the
 * level down for the over and gives it back gently, and leaves a mix inside
 * full scale exactly as it was.
 */
class MixLimiterTest {

    @Test
    fun `a mix inside full scale passes untouched`() {
        val limiter = MixLimiter(48_000)
        val block = floatArrayOf(0.5f, -0.5f, 0.97f, -0.97f, 0.1f, 0.2f)
        val before = block.copyOf()
        limiter.process(block, 3)
        assertArrayEquals(before, block, 0f)
    }

    @Test
    fun `an over is brought to the ceiling, then the level comes back gently`() {
        val limiter = MixLimiter(48_000)
        val frames = 4801
        val block = FloatArray(2 * frames) { 0.5f }
        block[0] = 1.6f
        block[1] = -1.6f
        limiter.process(block, frames)
        assertEquals(MixLimiter.CEILING, block[0], 1e-6f)
        assertEquals(-MixLimiter.CEILING, block[1], 1e-6f)
        var last = block[2]
        assertTrue(last < 0.5f)
        for (f in 2 until frames) {
            assertTrue("never a step down", block[2 * f] >= last)
            assertTrue("never above what came in", block[2 * f] <= 0.5f)
            last = block[2 * f]
        }
        assertTrue("most of the way back after 100 ms", last > 0.42f)
    }
}
