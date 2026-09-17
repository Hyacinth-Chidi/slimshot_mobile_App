package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * What the preview hands ExoPlayer for a clip's rate and pitch.
 *
 * Device-reported: a speed-curved clip sounded different in the preview than in
 * the exported file, with small glitches, and the file was the one that sounded
 * right. Two causes, both pinned here:
 *
 * - The preview time-stretched (pitch held at 1) while the export resamples
 *   (pitch follows speed). With pitch equal to speed Media3's Sonic skips its
 *   time-stretcher and only resamples — the export's own operation.
 * - The rate moved in fixed steps of 0.05, which is 2.5% at 2x but 12.5% at
 *   0.4x: over a semitone per step, exactly where a slow-motion ramp lives.
 *   Steps are now a fixed *ratio*, so they sound the same size at any speed.
 */
class PlaybackRateTest {

    @Test
    fun `natural speed stays exactly natural`() {
        assertEquals(1.0, PlaybackRate.quantise(1.0), 0.0)
    }

    @Test
    fun `quantising twice changes nothing`() {
        var v = 0.1
        while (v <= 10.0) {
            val once = PlaybackRate.quantise(v)
            assertEquals("at $v", once, PlaybackRate.quantise(once), 1e-12)
            v *= 1.013
        }
    }

    @Test
    fun `the result is never more than half a step from the exact rate`() {
        val half = sqrt(PlaybackRate.STEP_RATIO)
        var v = 0.1
        while (v <= 10.0) {
            val ratio = PlaybackRate.quantise(v) / v
            assertTrue("at $v ratio $ratio", ratio <= half + 1e-9 && ratio >= 1.0 / half - 1e-9)
            v *= 1.007
        }
    }

    @Test
    fun `neighbouring steps differ by the same ratio at every speed`() {
        val seen = sortedSetOf<Double>()
        var v = 0.1
        while (v <= 10.0) {
            seen.add(PlaybackRate.quantise(v))
            v *= 1.002
        }
        val steps = seen.toList()
        assertTrue("expected a ladder of steps", steps.size > 20)
        for (i in 1 until steps.size) {
            // The ends are clamped to the speed range, so they may be a short step.
            if (i == 1 || i == steps.size - 1) continue
            val ratio = steps[i] / steps[i - 1]
            assertTrue(
                "step ${steps[i - 1]} -> ${steps[i]} is ratio $ratio",
                abs(ratio - PlaybackRate.STEP_RATIO) < 1e-6,
            )
        }
    }

    @Test
    fun `a slow-motion step is no bigger than a fast one`() {
        // The old fixed 0.05 step was a 12.5% jump at 0.4x. Walk the slow end
        // and check no two neighbouring outputs are further apart than a step.
        var last = PlaybackRate.quantise(0.3)
        var v = 0.3
        while (v <= 0.6) {
            val q = PlaybackRate.quantise(v)
            assertTrue("jump $last -> $q", q / last <= PlaybackRate.STEP_RATIO + 1e-9)
            last = q
            v += 0.0005
        }
    }

    @Test
    fun `it never runs backwards and stays inside the speed range`() {
        var last = 0.0
        var v = 0.01
        while (v <= 20.0) {
            val q = PlaybackRate.quantise(v)
            assertTrue("at $v", q >= last)
            assertTrue("at $v", q >= SpeedCurve.MIN_SPEED - 1e-12 && q <= SpeedCurve.MAX_SPEED + 1e-12)
            last = q
            v *= 1.01
        }
    }

    @Test
    fun `junk is natural speed, never a crash or a zero rate`() {
        assertEquals(1.0, PlaybackRate.quantise(Double.NaN), 0.0)
        assertEquals(1.0, PlaybackRate.quantise(0.0), 0.0)
        assertEquals(1.0, PlaybackRate.quantise(-2.0), 0.0)
        assertEquals(1.0, PlaybackRate.quantise(Double.POSITIVE_INFINITY), 0.0)
    }

    @Test
    fun `pitch follows speed on a curved clip, so the player resamples like the export`() {
        assertEquals(0.4f, PlaybackRate.pitchFor(0.4, curved = true), 1e-6f)
        assertEquals(2.5f, PlaybackRate.pitchFor(2.5, curved = true), 1e-6f)
        assertEquals(1f, PlaybackRate.pitchFor(1.0, curved = true), 0f)
    }

    @Test
    fun `a flat-speed clip follows the one scope rule`() {
        val expected = if (PlaybackRate.FLAT_SPEED_SHIFTS_PITCH) 1.5f else 1f
        assertEquals(expected, PlaybackRate.pitchFor(1.5, curved = false), 1e-6f)
        // Natural speed is natural pitch under either rule.
        assertEquals(1f, PlaybackRate.pitchFor(1.0, curved = false), 0f)
    }

    @Test
    fun `pitch stays inside what the audio sink accepts`() {
        assertEquals(PlaybackRate.MAX_PITCH, PlaybackRate.pitchFor(10.0, curved = true), 0f)
        assertEquals(PlaybackRate.MIN_PITCH, PlaybackRate.pitchFor(0.01, curved = true), 0f)
        assertEquals(1f, PlaybackRate.pitchFor(Double.NaN, curved = true), 0f)
    }
}
