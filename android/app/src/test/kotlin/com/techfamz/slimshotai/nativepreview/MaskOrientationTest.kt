package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.OverlayRenderer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which way up a mask is by the time the shader reads it.
 *
 * The mask arrives y-DOWN, like every canvas coordinate in the contract — its
 * outline on the canvas is drawn at `frame.top + centerY * frame.height` — but
 * the clip shader reads it against `fitted`, a coordinate in the y-UP space
 * the lanes sample in (texcoord (0,0) is the bottom-left vertex). Nothing
 * converted it, so a window dragged toward the top of the picture was drawn
 * toward the bottom: the crop's bug (`ContentRectOrientationTest`) again, on
 * the mask. Found reading the code, before anyone had dragged a mask on a
 * device.
 *
 * Overlays are split. A photo overlay's quad carries top-down texcoords, so
 * its mask was right; a video overlay's carries bottom-up ones and had the
 * clip's bug. So the conversion is applied where the space is known: a clip
 * lane always, an overlay only when it is drawn from a video.
 */
class MaskOrientationTest {

    private val base = mapOf<String, Any?>(
        "id" to "c",
        "sourceVideoPath" to "/v.mp4",
        "sourceStart" to 0.0,
        "sourceEnd" to 4.0,
        "timelineStart" to 0.0,
        "timelineEnd" to 4.0,
    )

    /** A window 20% down from the top of the picture, as Dart sends it. */
    private val nearTheTop = mapOf(
        "shape" to "rectangle",
        "centerX" to 0.3,
        "centerY" to 0.2,
        "width" to 0.4,
        "height" to 0.2,
        "feather" to 0.05,
        "inverted" to true,
    )

    private fun clip(mask: Map<String, Any?>?): NativeTimelineClip {
        val map = if (mask == null) base else base + ("mask" to mask)
        return NativeTimelineClip.fromMap(map, "/v.mp4")!!
    }

    private fun overlayDraw(isExternal: Boolean, mask: FloatArray) = OverlayRenderer.Draw(
        textureId = 1,
        isExternal = isExternal,
        contentAspect = 1.0,
        centerX = 0.5,
        centerY = 0.5,
        boxWidth = 0.3,
        boxHeight = 0.2,
        scale = 1.0,
        rotation = 0.0,
        opacity = 1.0,
        texMatrix = null,
        mask = mask,
    )

    @Test
    fun `the wire is read as it was sent, in Dart's order`() {
        // The parse stays the twin of Dart's `maskUniforms`; the turn-over
        // happens after it, where the sampling space is known.
        val parsed = NativeTimelineClip.parseMask(nearTheTop)
        assertArrayEquals(
            floatArrayOf(1f, 0.3f, 0.2f, 0.05f, 0.4f, 0.2f, 1f, 0f, 1f, 0f, 0f, 0f),
            parsed,
            1e-6f,
        )
    }

    @Test
    fun `a window near the TOP of a clip is near the top of its y-up lane`() {
        // 20% down from the top is 80% up from the bottom.
        assertEquals(0.8f, clip(nearTheTop).maskUniforms()[2], 1e-6f)
    }

    @Test
    fun `only the vertical centre moves`() {
        val wire = NativeTimelineClip.parseMask(nearTheTop)
        val lane = clip(nearTheTop).maskUniforms()
        for (i in wire.indices) {
            if (i == 2) continue
            assertEquals("slot $i", wire[i], lane[i], 0f)
        }
    }

    @Test
    fun `a clip with no mask is untouched`() {
        // Every project that never used the mask must send exactly what it
        // always sent.
        assertArrayEquals(NativeTimelineClip.NO_MASK, clip(null).maskUniforms(), 0f)
        assertArrayEquals(
            NativeTimelineClip.NO_MASK,
            NativeTimelineClip.toSamplingMask(NativeTimelineClip.NO_MASK),
            0f,
        )
    }

    @Test
    fun `turning over twice is the original`() {
        for (y in listOf(0.0, 0.1, 0.25, 0.5, 0.75, 1.0)) {
            val wire = NativeTimelineClip.parseMask(nearTheTop + ("centerY" to y))
            val twice = NativeTimelineClip.toSamplingMask(
                NativeTimelineClip.toSamplingMask(wire),
            )
            assertArrayEquals("centerY $y", wire, twice, 1e-6f)
        }
    }

    @Test
    fun `a photo overlay samples top-down, so its mask is used as sent`() {
        val wire = NativeTimelineClip.parseMask(nearTheTop)
        assertArrayEquals(wire, overlayDraw(isExternal = false, mask = wire).samplingMask(), 0f)
    }

    @Test
    fun `a video overlay samples bottom-up, so its mask is turned over`() {
        val wire = NativeTimelineClip.parseMask(nearTheTop)
        val drawn = overlayDraw(isExternal = true, mask = wire).samplingMask()
        assertEquals(0.8f, drawn[2], 1e-6f)
    }
}
