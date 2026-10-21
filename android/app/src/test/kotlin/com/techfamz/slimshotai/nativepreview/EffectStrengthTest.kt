package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.effects.BlurPass
import com.techfamz.slimshotai.nativepreview.gl.effects.ChromaticPass
import com.techfamz.slimshotai.nativepreview.gl.effects.SharpenPass
import com.techfamz.slimshotai.nativepreview.gl.effects.StandaloneBlurPass
import java.io.File
import kotlin.math.min
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Sharpen, Soft Blur and Fringe were reported from the device as too faint —
 * Sharpen invisible even at 100%, Soft Blur barely there, Fringe only at 100%.
 * Each had a reason in its arithmetic, and these pin the arithmetic that
 * replaced it. The shaders themselves only run on a device; the two that
 * changed are also written out for `glslangValidator -S frag`.
 */
class EffectStrengthTest {

    /** The catalog's default for Sharpen and Fringe (`effect_catalog.dart`). */
    private val catalogDefault = 0.5f

    // -- Sharpen ---------------------------------------------------------------

    @Test
    fun `sharpen reaches the same fraction of the frame at every resolution`() {
        // It reached one texel, whatever the frame: on the 720-wide preview,
        // shown smaller than its texture, a one-texel halo is averaged away.
        for ((w, h) in listOf(720 to 1280, 1080 to 1920, 1440 to 2560, 1920 to 1080)) {
            val (stepX, stepY) = SharpenPass.sampleStep(w, h)
            val short = min(w, h).toFloat()
            assertEquals("$w x $h", SharpenPass.SAMPLE_RADIUS, stepX * w / short, 1e-6f)
            assertEquals("$w x $h", SharpenPass.SAMPLE_RADIUS, stepY * h / short, 1e-6f)
        }
    }

    @Test
    fun `on the preview canvas sharpen reaches past two texels`() {
        val (stepX, _) = SharpenPass.sampleStep(720, 1280)
        assertTrue("${stepX * 720} texels", stepX * 720 >= 2f)
    }

    @Test
    fun `a frame too small for the radius still samples its neighbours`() {
        // A tile cell: the radius is half a texel there, and half a texel out
        // samples the pixel itself, sharpening nothing.
        val (stepX, stepY) = SharpenPass.sampleStep(160, 144)
        assertEquals(1f / 160f, stepX, 1e-9f)
        assertEquals(1f / 144f, stepY, 1e-9f)
    }

    @Test
    fun `sharpen works on brightness alone, past a noise floor, with its halo limited`() {
        val source = SharpenPass.FRAGMENT
        assertTrue("luma-only", source.contains("dot(") && source.contains("LUMA"))
        assertTrue("noise floor", source.contains("NOISE_FLOOR"))
        assertTrue("halo limit", source.contains("HALO_LIMIT"))
        assertTrue("eight-tap ring", source.split("texture2D(").size - 1 == 9)
    }

    // -- Soft Blur -------------------------------------------------------------

    @Test
    fun `soft blur at its default blurs more than it used to at full strength`() {
        // The old ceiling was the full-resolution kernel's cap.
        assertTrue(StandaloneBlurPass.radiusFractionFor(0.4f) > BlurPass.MAX_RADIUS_FRACTION)
    }

    @Test
    fun `soft blur at full strength reaches four times the kernel's cap`() {
        assertEquals(
            BlurPass.MAX_RADIUS_FRACTION * 4,
            StandaloneBlurPass.radiusFractionFor(1f),
            1e-9,
        )
        assertEquals(StandaloneBlurPass.MAX_RADIUS_FRACTION, StandaloneBlurPass.radiusFractionFor(1f), 1e-9)
    }

    @Test
    fun `soft blur keeps a floor at zero and grows with the slider`() {
        assertEquals(StandaloneBlurPass.MIN_RADIUS_FRACTION, StandaloneBlurPass.radiusFractionFor(0f), 1e-9)
        var last = -1.0
        for (i in 0..20) {
            val r = StandaloneBlurPass.radiusFractionFor(i / 20f)
            assertTrue("$i", r > last)
            last = r
        }
        // Out-of-range intensities clamp rather than overshoot the kernel.
        assertEquals(StandaloneBlurPass.radiusFractionFor(1f), StandaloneBlurPass.radiusFractionFor(3f), 1e-9)
        assertEquals(StandaloneBlurPass.radiusFractionFor(0f), StandaloneBlurPass.radiusFractionFor(-1f), 1e-9)
    }

    @Test
    fun `a radius the kernel covers at full resolution is drawn at full resolution`() {
        assertEquals(1, StandaloneBlurPass.downscaleFor(0.0))
        assertEquals(1, StandaloneBlurPass.downscaleFor(3.0))
        assertEquals(1, StandaloneBlurPass.downscaleFor(BlurPass.MAX_TAPS.toDouble()))
    }

    @Test
    fun `a larger radius is drawn smaller, by the least that fits the taps`() {
        assertEquals(2, StandaloneBlurPass.downscaleFor(16.5))
        assertEquals(2, StandaloneBlurPass.downscaleFor(32.0))
        assertEquals(4, StandaloneBlurPass.downscaleFor(32.5))
        assertEquals(4, StandaloneBlurPass.downscaleFor(64.0))
        assertEquals(8, StandaloneBlurPass.downscaleFor(64.5))
    }

    @Test
    fun `the strongest blur fits the tap budget at every size the app draws`() {
        // The preview canvas, 1080 and 2K exports, and a tile cell.
        for (short in listOf(144, 720, 1080, 1440)) {
            val radiusPx = StandaloneBlurPass.radiusFractionFor(1f) * short
            val scale = StandaloneBlurPass.downscaleFor(radiusPx)
            assertTrue("$short: ${radiusPx / scale} taps", radiusPx / scale <= BlurPass.MAX_TAPS)
        }
    }

    @Test
    fun `a blur is drawn small only once it is wide enough to hide it`() {
        // Below about two and a half texels of sigma at the reduced size, the
        // upsample and the cheap downsample would show; the switch happens
        // only past that, at every step.
        for (radiusPx in listOf(16.5, 32.5, 64.5, 100.0)) {
            val scale = StandaloneBlurPass.downscaleFor(radiusPx)
            val sigmaSmall = radiusPx / scale * BlurPass.SIGMA_SCALE
            assertTrue("$radiusPx px at 1/$scale: sigma $sigmaSmall", sigmaSmall >= 2.5)
        }
    }

    // -- Fringe ----------------------------------------------------------------

    @Test
    fun `fringe grows in proportion to the distance from the centre`() {
        // It grew with the cube of the distance, so the middle of the frame —
        // where everything is — stayed registered and only the corners showed.
        val edge = ChromaticPass.shiftAt(0.5f, 1f)
        assertEquals(edge / 2f, ChromaticPass.shiftAt(0.25f, 1f), 1e-7f)
        assertEquals(0f, ChromaticPass.shiftAt(0f, 1f), 0f)
        assertEquals(0f, ChromaticPass.shiftAt(0.5f, 0f), 0f)
    }

    @Test
    fun `at its default the fringe shows halfway out from the centre`() {
        // Halfway to the side edge of a 1080-wide frame: at least three pixels.
        val pixels = ChromaticPass.shiftAt(0.25f, catalogDefault) * 1080
        assertTrue("$pixels px", pixels >= 3f)
    }

    @Test
    fun `the shader scales red out and blue in about the centre`() {
        val source = ChromaticPass.FRAGMENT
        assertTrue(source.contains("(1.0 + spread)"))
        assertTrue(source.contains("(1.0 - spread)"))
        assertFalse("no cubic falloff", Regex("""\br2\b""").containsMatchIn(source))
    }

    @Test
    fun `the two shaders are written out for glslang`() {
        val dir = File(System.getProperty("java.io.tmpdir"), "slimshot-shader-dump").apply { mkdirs() }
        File(dir, "sharpen.frag").writeText("#version 100\n" + SharpenPass.FRAGMENT)
        File(dir, "chromatic.frag").writeText("#version 100\n" + ChromaticPass.FRAGMENT)
        assertTrue(File(dir, "sharpen.frag").exists() && File(dir, "chromatic.frag").exists())
    }
}
