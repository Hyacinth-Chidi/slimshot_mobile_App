package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which way up the crop rectangle is by the time the shader samples through it.
 *
 * **Device-reported:** "if I crop from the top, it crops from the bottom; if I
 * crop from the bottom, it crops from the top" — on both the project crop and
 * the per-clip crop.
 *
 * The whole Dart side is y-DOWN, like every canvas coordinate in the contract:
 * `Rect.top` is the distance from the top edge, the crop handles hit-test in
 * screen pixels, and the painter draws `frame.top + top * frame.height`. All
 * of that is self-consistent, which is why the handles *look* right while the
 * picture disagrees.
 *
 * The shader's sampling space is y-UP — texcoord (0,0) is the bottom-left
 * vertex. `TransitionShaders` already documents this for the pan, which is
 * negated at the one place the two frames meet, with the note that skipping it
 * makes a downward drag move the clip up ("which shipped once"). The content
 * rect crossed the same boundary and was **not** converted, so `top` became
 * `bottom` in the sample.
 *
 * The conversion belongs at the parse boundary: both engines push the parsed
 * rect straight to `setLaneContentRect`, so converting once here fixes the
 * preview and the export together and keeps a single definition.
 */
class ContentRectOrientationTest {

    /** The composer's own payload shape: left/top/width/height, y-DOWN. */
    private fun clip(
        left: Double? = null,
        top: Double? = null,
        width: Double? = null,
        height: Double? = null,
    ): NativeTimelineClip {
        val map = mutableMapOf<String, Any>(
            "id" to "c",
            "sourceStart" to 0.0,
            "sourceEnd" to 5.0,
            "timelineStart" to 0.0,
        )
        if (width != null && height != null) {
            map["contentRect"] = mapOf(
                "left" to (left ?: 0.0),
                "top" to (top ?: 0.0),
                "width" to width,
                "height" to height,
            )
        }
        return NativeTimelineClip.fromMap(map, fallbackSource = "/v.mp4")!!
    }

    @Test
    fun `an uncropped clip samples the whole frame`() {
        // The identity rect has to survive the flip untouched, or every
        // project that never used the crop tool would change.
        val r = clip().contentRect
        assertEquals(0f, r[0], 0f)
        assertEquals(0f, r[1], 0f)
        assertEquals(1f, r[2], 0f)
        assertEquals(1f, r[3], 0f)
    }

    @Test
    fun `cropping the TOP half in the UI samples the top half of the picture`() {
        // Dart sends y-down: "the top half" is top=0, height=0.5.
        // In the shader's y-up space that same region starts at 0.5.
        val r = clip(top = 0.0, width = 1.0, height = 0.5).contentRect
        assertEquals("x is unchanged", 0f, r[0], 0f)
        assertEquals("width is unchanged", 1f, r[2], 0f)
        assertEquals("height is unchanged", 0.5f, r[3], 0f)
        assertEquals("y is measured from the bottom", 0.5f, r[1], 1e-6f)
    }

    @Test
    fun `cropping the BOTTOM half in the UI samples the bottom half`() {
        // y-down: top=0.5, height=0.5. y-up: starts at 0.
        val r = clip(top = 0.5, width = 1.0, height = 0.5).contentRect
        assertEquals(0f, r[1], 1e-6f)
        assertEquals(0.5f, r[3], 0f)
    }

    @Test
    fun `the horizontal axis is never touched`() {
        // Only y differs between the two spaces. A left crop that moved would
        // be the same bug mirrored.
        val r = clip(left = 0.25, width = 0.5, height = 1.0).contentRect
        assertEquals(0.25f, r[0], 0f)
        assertEquals(0.5f, r[2], 0f)
    }

    @Test
    fun `flipping twice is the original, for any rect`() {
        // The conversion is its own inverse, which is what makes it safe to
        // reason about: nothing accumulates and no draft drifts.
        for (top in listOf(0.0, 0.1, 0.33, 0.5, 0.9)) {
            for (height in listOf(0.05, 0.25, 0.5, 1.0)) {
                if (top + height > 1.0) continue
                val once = NativeTimelineClip.toSamplingRect(
                    floatArrayOf(0f, top.toFloat(), 1f, height.toFloat()),
                )
                val twice = NativeTimelineClip.toSamplingRect(once)
                assertEquals(top.toFloat(), twice[1], 1e-6f)
                assertEquals(height.toFloat(), twice[3], 1e-6f)
            }
        }
    }

    @Test
    fun `a full-height rect is unmoved whatever its width`() {
        // The common case for a project cropped only left-to-right; if this
        // moved, an existing 16:9 crop would jump vertically.
        val r = clip(left = 0.2, width = 0.6, height = 1.0).contentRect
        assertEquals(0f, r[1], 1e-6f)
        assertEquals(1f, r[3], 0f)
    }

    @Test
    fun `a rect stays inside the frame after conversion`() {
        // Junk from a hand-edited draft must not sample outside the texture.
        val r = clip(top = 0.8, width = 1.0, height = 0.2).contentRect
        assertTrue("y >= 0", r[1] >= 0f)
        assertTrue("y + height <= 1", r[1] + r[3] <= 1f + 1e-6f)
    }
}
