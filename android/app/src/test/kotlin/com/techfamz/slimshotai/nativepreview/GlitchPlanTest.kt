package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.effects.GlitchPlan
import kotlin.math.abs
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Glitch was reported from the device as invisible even at 100%. Its shader
 * decided each band's tear from a hash that, at `mediump`, came back as zero —
 * so the gate never opened. The damage is now planned on the CPU from the bar's
 * own seconds and handed to the shader as a few torn blocks, and these pin how
 * often and how hard it strikes.
 */
class GlitchPlanTest {

    private val step = 1.0 / GlitchPlan.TICKS_PER_SECOND
    private val catalogDefault = 0.4f // effect_catalog.dart

    private fun ticks(intensity: Float, seconds: Double) =
        (0 until (seconds * GlitchPlan.TICKS_PER_SECOND).toInt()).map {
            GlitchPlan.at((it + 0.5) * step, intensity)
        }

    @Test
    fun `at zero intensity every frame is clean`() {
        assertTrue(ticks(0f, 30.0).none { it.torn })
        val clean = GlitchPlan.at(1.3, 0f)
        assertEquals(0f, clean.frameSplit, 0f)
        assertEquals(-1f, clean.swapFrom, 0f)
    }

    @Test
    fun `at full strength it glitches almost all the time`() {
        val torn = ticks(1f, 60.0).count { it.torn } / (60.0 * GlitchPlan.TICKS_PER_SECOND)
        assertTrue("$torn", torn >= 0.8)
    }

    @Test
    fun `at the default it comes in bursts - torn about half the time, never gone long`() {
        val all = ticks(catalogDefault, 60.0)
        val torn = all.count { it.torn }.toDouble() / all.size
        assertTrue("$torn", torn in 0.25..0.6)
        var run = 0
        var longest = 0
        for (frame in all) {
            run = if (frame.torn) 0 else run + 1
            longest = maxOf(longest, run)
        }
        assertTrue("longest clean run ${longest * step}s", longest * step <= 3.0)
    }

    @Test
    fun `a bar opens on a glitch`() {
        // The first window always strikes, so a bar dropped on the timeline —
        // and the sheet's tile, which plays a bar's first 1.6s — shows it.
        for (intensity in listOf(0.1f, catalogDefault, 1f)) {
            assertTrue("$intensity", ticks(intensity, 0.5).any { it.torn })
        }
    }

    @Test
    fun `a glitch holds for its whole tick`() {
        val a = GlitchPlan.at(2.0 * step + 0.001, 0.8f)
        val b = GlitchPlan.at(3.0 * step - 0.001, 0.8f)
        assertArrayEquals(a.blocks, b.blocks, 0f)
        assertEquals(a.frameSplit, b.frameSplit, 0f)
    }

    @Test
    fun `blocks lie inside the frame and tear by a bounded amount`() {
        for (frame in ticks(1f, 60.0)) {
            assertEquals(GlitchPlan.MAX_BLOCKS * 4, frame.blocks.size)
            for (j in 0 until GlitchPlan.MAX_BLOCKS) {
                val y0 = frame.blocks[j * 4]
                val y1 = frame.blocks[j * 4 + 1]
                val tear = frame.blocks[j * 4 + 2]
                val split = frame.blocks[j * 4 + 3]
                if (y0 < 0f) {
                    // An unused block is empty and moves nothing.
                    assertEquals(0f, tear, 0f)
                    assertEquals(0f, split, 0f)
                    continue
                }
                assertTrue(y0 >= 0f && y1 <= 1f && y1 > y0)
                assertTrue(abs(tear) <= GlitchPlan.MAX_TEAR && abs(tear) > 0f)
                assertTrue(split in 0f..GlitchPlan.MAX_SPLIT)
            }
        }
    }

    @Test
    fun `a full-strength tear is wide enough to see`() {
        val widest = ticks(1f, 60.0).flatMap { f ->
            (0 until GlitchPlan.MAX_BLOCKS).map { abs(f.blocks[it * 4 + 2]) }
        }.max()
        // Over a tenth of the frame's width somewhere in a minute.
        assertTrue("$widest", widest >= 0.1f)
    }

    @Test
    fun `the same instant always plans the same damage`() {
        val a = GlitchPlan.at(7.77, 0.6f)
        val b = GlitchPlan.at(7.77, 0.6f)
        assertArrayEquals(a.blocks, b.blocks, 0f)
        assertFalse(a.blocks.any { it.isNaN() })
    }
}
