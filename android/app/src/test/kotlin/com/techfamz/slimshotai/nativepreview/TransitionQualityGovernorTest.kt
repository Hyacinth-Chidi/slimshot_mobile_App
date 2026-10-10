package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.TransitionQualityGovernor
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When the preview drops a heavy transition to its lighter version.
 *
 * Decided from the device's own frames, never from a list of phones: the
 * median of the last [TransitionQualityGovernor.WINDOW] layered frames against
 * a budget. The export never asks — it is not realtime.
 */
class TransitionQualityGovernorTest {

    @Test
    fun `a phone that keeps up stays on the full version`() {
        val governor = TransitionQualityGovernor()
        repeat(100) { assertFalse(governor.record(20)) }
        assertFalse(governor.light)
    }

    @Test
    fun `a phone that cannot keep up drops to the light version once`() {
        val governor = TransitionQualityGovernor()
        val tipped = (1..TransitionQualityGovernor.WINDOW).map { governor.record(80) }
        // It decides on the frame that fills the window, and only then.
        assertTrue(tipped.last())
        assertFalse(tipped.dropLast(1).any { it })
        assertTrue(governor.light)
        // Already light: never reported again.
        assertFalse(governor.record(200))
    }

    @Test
    fun `a few slow frames do not decide it`() {
        // The first frame of a window pays for allocations and a shader link;
        // the median looks past a handful of those.
        val governor = TransitionQualityGovernor()
        repeat(3) { governor.record(300) }
        repeat(TransitionQualityGovernor.WINDOW) { governor.record(20) }
        assertFalse(governor.light)
    }

    @Test
    fun `nothing is decided before the window is full`() {
        val governor = TransitionQualityGovernor()
        repeat(TransitionQualityGovernor.WINDOW - 1) { assertFalse(governor.record(500)) }
        assertFalse(governor.light)
    }
}
