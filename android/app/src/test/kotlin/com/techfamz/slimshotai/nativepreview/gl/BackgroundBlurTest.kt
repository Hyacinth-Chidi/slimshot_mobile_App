package com.techfamz.slimshotai.nativepreview.gl

import com.techfamz.slimshotai.nativepreview.gl.effects.BlurPass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The blurred background's strength (the owner's ask, 2026-11-10: "the blur
 * is okay but it's so clear that it looks like a mirror, so a slider to
 * control how clear or blurry it will be").
 */
class BackgroundBlurTest {

    @Test
    fun `the slider runs from light to heavy, and nowhere back`() {
        var previous = -1.0
        for (step in 0..10) {
            val radius = BackgroundBlur.radiusFractionFor(step / 10f)
            assertTrue("strength ${step / 10f}", radius > previous)
            previous = radius
        }
        assertEquals(BackgroundBlur.MIN_RADIUS_FRACTION, BackgroundBlur.radiusFractionFor(0f), 1e-9)
        assertEquals(BackgroundBlur.MAX_RADIUS_FRACTION, BackgroundBlur.radiusFractionFor(1f), 1e-9)
    }

    @Test
    fun `a strength off the slider is held to its ends`() {
        assertEquals(BackgroundBlur.radiusFractionFor(0f), BackgroundBlur.radiusFractionFor(-3f), 0.0)
        assertEquals(BackgroundBlur.radiusFractionFor(1f), BackgroundBlur.radiusFractionFor(7f), 0.0)
    }

    @Test
    fun `the default is far past the blur that looked like a mirror`() {
        // The old background blurred by BlurPass's full-resolution cap, twice.
        val before = BlurPass.MAX_RADIUS_FRACTION
        assertTrue(BackgroundBlur.radiusFractionFor(BackgroundBlur.DEFAULT_STRENGTH) >= 4 * before)
        assertTrue("even the lightest is softer than before",
            BackgroundBlur.radiusFractionFor(0f) > before)
    }

    @Test
    fun `the copy is the same size in the preview and in any export`() {
        // One grid for the blur whatever the frame, so the preview's canvas
        // and a 1080 or 2K file blur alike.
        for ((width, height) in listOf(720 to 1280, 1080 to 1920, 1440 to 2560)) {
            assertEquals(180 to 320, BackgroundBlur.copySize(width, height))
        }
        assertEquals(320 to 180, BackgroundBlur.copySize(1920, 1080))
    }

    @Test
    fun `a frame smaller than the copy is not enlarged`() {
        assertEquals(100 to 200, BackgroundBlur.copySize(100, 200))
    }

    @Test
    fun `the strongest blur keeps its taps close enough not to band`() {
        // 16 taps a side over the radius: past ~1.5 texels apart a gaussian
        // starts to show steps.
        val radiusTexels = BackgroundBlur.MAX_RADIUS_FRACTION * BackgroundBlur.COPY_SHORT_SIDE
        assertTrue(radiusTexels / BlurPass.MAX_TAPS <= 1.5)
    }

    @Test
    fun `the strength is read from the canvas, held to the slider, default when absent`() {
        assertEquals(BackgroundBlur.DEFAULT_STRENGTH, BackgroundBlur.strengthOf(null), 0f)
        assertEquals(BackgroundBlur.DEFAULT_STRENGTH, BackgroundBlur.strengthOf(emptyMap<String, Any>()), 0f)
        assertEquals(0.2f, BackgroundBlur.strengthOf(mapOf("backgroundBlurStrength" to 0.2)), 1e-6f)
        assertEquals(1f, BackgroundBlur.strengthOf(mapOf("backgroundBlurStrength" to 7)), 0f)
        assertEquals(0f, BackgroundBlur.strengthOf(mapOf("backgroundBlurStrength" to -1.0)), 0f)
        assertEquals(
            BackgroundBlur.DEFAULT_STRENGTH,
            BackgroundBlur.strengthOf(mapOf("backgroundBlurStrength" to Double.NaN)),
            0f,
        )
    }
}
