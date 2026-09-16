package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The fit is of the **content**, not of the frame.
 *
 * A lane samples through its content rect, so what reaches the canvas is the
 * frame narrowed by that rect — and its shape is the frame's shape times the
 * rect's own proportions. Fitting by the frame's shape while sampling through
 * a differently shaped rect squeezes the picture into a box of the wrong
 * shape; that was the per-clip crop's first device-visible bug, and the same
 * arithmetic is what makes a custom project crop export as the preview shows
 * it. Both engines and the renderer's photo path read this one function.
 */
class LaneFitTest {

    private val full = floatArrayOf(0f, 0f, 1f, 1f)

    @Test
    fun `a full-frame rect keeps the frame's shape`() {
        assertEquals(16.0 / 9.0, LaneFit.contentAspect(16.0 / 9.0, full), 1e-9)
    }

    @Test
    fun `a crop narrows the shape by its own proportions`() {
        // The left half of a 16:9 frame is 8:9.
        val leftHalf = floatArrayOf(0f, 0f, 0.5f, 1f)
        assertEquals(8.0 / 9.0, LaneFit.contentAspect(16.0 / 9.0, leftHalf), 1e-6)
    }

    @Test
    fun `a square crop of a landscape frame is square`() {
        val square = floatArrayOf(0.2f, 0f, 0.5625f, 1f)
        assertEquals(1.0, LaneFit.contentAspect(16.0 / 9.0, square), 1e-6)
    }

    @Test
    fun `an unprobed frame stays unprobed`() {
        // `LaneFit.of` fills the frame for an aspect of zero; a crop on an
        // unprobed clip must not invent a shape.
        assertEquals(0.0, LaneFit.contentAspect(0.0, floatArrayOf(0f, 0f, 0.5f, 1f)), 0.0)
    }

    @Test
    fun `a junk rect falls back to the frame's shape`() {
        assertEquals(16.0 / 9.0, LaneFit.contentAspect(16.0 / 9.0, floatArrayOf(0f, 0f, 0.5f, 0f)), 1e-9)
        assertEquals(16.0 / 9.0, LaneFit.contentAspect(16.0 / 9.0, floatArrayOf(0f, 0f)), 1e-9)
    }

    @Test
    fun `the fit is of the content, not the frame`() {
        // A 16:9 clip cropped to its left half (8:9) on a 9:16 canvas is still
        // wider than the canvas: full width, bars above and below sized by 8:9.
        val content = LaneFit.contentAspect(16.0 / 9.0, floatArrayOf(0f, 0f, 0.5f, 1f))
        val (fitX, fitY) = LaneFit.of(content, 9.0 / 16.0)
        assertEquals(1f, fitX, 1e-6f)
        assertEquals((9.0 / 16.0) / (8.0 / 9.0), fitY.toDouble(), 1e-6)
    }

    @Test
    fun `a clip reports the shape of what it shows`() {
        val clip = NativeTimelineClip(
            id = "c",
            sourceVideoPath = "/v.mp4",
            playbackVideoPath = "/v.mp4",
            sourceStart = 0.0,
            sourceEnd = 4.0,
            timelineStart = 0.0,
            timelineEnd = 4.0,
            speed = 1.0,
            volume = AnimatableDouble(baseValue = 1.0),
            isReversed = false,
            hasPreparedProxy = false,
            needsReverseProxy = false,
            laneIndex = 0,
            isImage = false,
            sourceWidth = 1920.0,
            sourceHeight = 1080.0,
            colorMatrix = null,
            canvasScale = AnimatableDouble(baseValue = 1.0),
            canvasOffsetX = AnimatableDouble(baseValue = 0.0),
            canvasOffsetY = AnimatableDouble(baseValue = 0.0),
            canvasRotation = AnimatableDouble(baseValue = 0.0),
            contentRect = floatArrayOf(0f, 0f, 0.5f, 1f),
            effectId = null,
            effectIntensity = AnimatableDouble(baseValue = 1.0),
            effectIntroSeconds = null,
        )
        assertEquals(16.0 / 9.0, clip.sourceAspect, 1e-9)
        assertEquals(8.0 / 9.0, clip.contentAspect, 1e-6)
    }
}
