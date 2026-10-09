package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

/**
 * A mask's tilt on the wire, and the third vec4 the shader turns the window by.
 *
 * Dart's `maskUniforms` writes `(cos, sin, 0, 0)` of the angle — degrees,
 * clockwise — after the two vec4s the mask always had, and `parseMask` reads
 * the same order. A y-up sampling space turns the other way round, so
 * `toSamplingMask` negates the sine along with turning the centre over.
 */
class MaskTiltTest {

    private fun wire(angle: Any?) = mapOf(
        "shape" to "rectangle",
        "centerX" to 0.4,
        "centerY" to 0.3,
        "width" to 0.2,
        "height" to 0.6,
        "feather" to 0.05,
        "angle" to angle,
    )

    private fun radians(degrees: Double) = degrees * Math.PI / 180.0

    @Test
    fun `an untilted mask carries the identity turn`() {
        val m = NativeTimelineClip.parseMask(wire(null))
        assertEquals(12, m.size)
        assertArrayEquals(floatArrayOf(1f, 0f, 0f, 0f), m.copyOfRange(8, 12), 0f)
    }

    @Test
    fun `no mask carries the identity turn too`() {
        assertEquals(12, NativeTimelineClip.NO_MASK.size)
        assertArrayEquals(
            floatArrayOf(1f, 0f, 0f, 0f),
            NativeTimelineClip.NO_MASK.copyOfRange(8, 12),
            0f,
        )
    }

    @Test
    fun `a tilt reads as its cosine and sine, as Dart writes them`() {
        val m = NativeTimelineClip.parseMask(wire(-59.0))
        assertEquals(cos(radians(-59.0)).toFloat(), m[8], 1e-6f)
        assertEquals(sin(radians(-59.0)).toFloat(), m[9], 1e-6f)
        assertEquals(0f, m[10], 0f)
        assertEquals(0f, m[11], 0f)
    }

    @Test
    fun `the first two vec4s are what they always were`() {
        val tilted = NativeTimelineClip.parseMask(wire(30.0))
        val flat = NativeTimelineClip.parseMask(wire(null))
        assertArrayEquals(flat.copyOfRange(0, 8), tilted.copyOfRange(0, 8), 0f)
    }

    @Test
    fun `a whole turn is no turn, and junk is untilted`() {
        val around = NativeTimelineClip.parseMask(wire(450.0))
        assertEquals(0f, around[8], 1e-6f)
        assertEquals(1f, around[9], 1e-6f)
        val junk = NativeTimelineClip.parseMask(wire("left"))
        assertArrayEquals(floatArrayOf(1f, 0f, 0f, 0f), junk.copyOfRange(8, 12), 0f)
    }

    @Test
    fun `in a y-up lane the tilt turns the other way`() {
        // Clockwise on a y-down picture is anticlockwise in y-up coordinates:
        // the sine changes sign, the cosine does not.
        val wire = NativeTimelineClip.parseMask(wire(30.0))
        val lane = NativeTimelineClip.toSamplingMask(wire)
        assertEquals(wire[8], lane[8], 0f)
        assertEquals(-wire[9], lane[9], 0f)
        assertEquals(1f - wire[2], lane[2], 1e-6f)
    }

    @Test
    fun `an overlay's window turns on the shape of the picture it is drawn as`() {
        // A tilt is rigid on the picture, so the shader needs the box's real
        // shape: an image or video overlay is drawn contain-fitted, which is
        // its content's own aspect. A glyph never carries a mask.
        fun draw(contentAspect: Double, boxRect: FloatArray? = null) =
            com.techfamz.slimshotai.nativepreview.gl.OverlayRenderer.Draw(
                textureId = 1,
                isExternal = false,
                contentAspect = contentAspect,
                centerX = 0.5,
                centerY = 0.5,
                boxWidth = 0.4,
                boxHeight = 0.225,
                scale = 1.0,
                rotation = 0.0,
                opacity = 1.0,
                texMatrix = null,
                boxRect = boxRect,
            )
        assertEquals(16f / 9f, draw(16.0 / 9.0).maskAspect(), 1e-6f)
        assertEquals(0.5625f, draw(0.5625).maskAspect(), 1e-6f)
        assertEquals(1f, draw(0.0).maskAspect(), 0f)
        assertEquals(1f, draw(2.0, boxRect = floatArrayOf(0f, 0f, 0.5f, 1f)).maskAspect(), 0f)
    }

    @Test
    fun `turning a tilted mask over twice is the original`() {
        for (angle in listOf(-120.0, -59.0, 0.0, 17.0, 90.0, 180.0)) {
            val wire = NativeTimelineClip.parseMask(wire(angle))
            val twice = NativeTimelineClip.toSamplingMask(NativeTimelineClip.toSamplingMask(wire))
            assertArrayEquals("$angle°", wire, twice, 1e-6f)
        }
    }
}
