package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Easing on a transition shapes the picture's travel through the window and
 * nothing else: the sound's crossfade keeps the window's even clock.
 */
class TransitionEasingTest {

    private fun window(easing: String? = null): Map<String, Any?> = buildMap {
        put("leftClipId", "a")
        put("rightClipId", "b")
        put("leftClipIndex", 0)
        put("rightClipIndex", 1)
        put("type", "dissolve")
        put("durationSeconds", 1.0)
        put("timelineStartSeconds", 4.0)
        put("timelineEndSeconds", 5.0)
        if (easing != null) put("easing", easing)
    }

    private fun parse(vararg transitions: Map<String, Any?>) =
        NativeTimelineTransitionIntents.fromTimeline(mapOf("transitions" to transitions.toList()))

    @Test
    fun `a transition without easing travels in a straight line`() {
        val w = parse(window()).single()
        assertEquals(KeyframeInterpolation.LINEAR, w.easing)
        assertEquals(0.25f, w.pictureProgressAt(4.25), 1e-6f)
    }

    @Test
    fun `the picture follows the curve and the sound does not`() {
        val w = parse(window("cubicInOut")).single()
        assertEquals(KeyframeInterpolation.CUBIC_IN_OUT, w.easing)
        val expected = applyKeyframeEasing(KeyframeInterpolation.CUBIC_IN_OUT, 0.25).toFloat()
        assertEquals(expected, w.pictureProgressAt(4.25), 1e-6f)
        // Slow out of the cut: a quarter of the way in, well under a quarter done.
        assertTrue(w.pictureProgressAt(4.25) < 0.1f)
        // The audio crossfade reads the plain clock.
        assertEquals(0.25f, w.progressAt(4.25), 1e-6f)
    }

    @Test
    fun `the curve still opens and closes the window exactly`() {
        for (name in listOf("sineIn", "quadOut", "cubicInOut", "bounceOut")) {
            val w = parse(window(name)).single()
            assertEquals(name, 0f, w.pictureProgressAt(4.0), 1e-6f)
            assertEquals(name, 1f, w.pictureProgressAt(5.0), 1e-6f)
        }
    }

    @Test
    fun `an easing this build does not know is a straight line`() {
        assertEquals(KeyframeInterpolation.LINEAR, parse(window("warp9")).single().easing)
    }

    @Test
    fun `an easing change alone is the same structure, a type change is not`() {
        val plain = parse(window())
        val eased = parse(window("quadOut"))
        assertTrue(NativeTimelineTransitionIntents.sameWindows(plain, eased))
        val other = parse(window() + ("type" to "wipe"))
        assertFalse(NativeTimelineTransitionIntents.sameWindows(plain, other))
        assertFalse(NativeTimelineTransitionIntents.sameWindows(plain, emptyList()))
    }
}
