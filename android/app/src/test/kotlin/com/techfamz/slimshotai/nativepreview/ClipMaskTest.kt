package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * The mask on the wire, and the two vec4s the shader reads for it.
 *
 * Order is `(shape, centerX, centerY, feather)` then `(width, height,
 * inverted, 0)` — the same order `maskUniforms` in Dart writes, so the two
 * sides cannot drift into reading a feather as a width.
 */
class ClipMaskTest {

    private val base = mapOf<String, Any?>(
        "id" to "c",
        "sourceVideoPath" to "/v.mp4",
        "playbackVideoPath" to "/v.mp4",
        "sourceStart" to 0.0,
        "sourceEnd" to 4.0,
        "timelineStart" to 0.0,
        "timelineEnd" to 4.0,
        "speed" to 1.0,
        "volume" to 1.0,
    )

    @Test
    fun `absent from the wire is no mask, shape zero`() {
        val clip = NativeTimelineClip.fromMap(base, "/v.mp4")
        assertNotNull(clip)
        assertArrayEquals(floatArrayOf(0f, 0.5f, 0.5f, 0f, 0f, 0f, 0f, 0f), clip!!.maskUniforms(), 0f)
    }

    @Test
    fun `a mask encodes in the shader's order`() {
        val clip = NativeTimelineClip.fromMap(
            base + mapOf(
                "mask" to mapOf(
                    "shape" to "linear",
                    "centerX" to 0.3,
                    "centerY" to 0.6,
                    "width" to 0.4,
                    "height" to 0.5,
                    "feather" to 0.02,
                    "inverted" to true,
                ),
            ),
            "/v.mp4",
        )!!
        assertArrayEquals(
            floatArrayOf(3f, 0.3f, 0.6f, 0.02f, 0.4f, 0.5f, 1f, 0f),
            clip.maskUniforms(),
            1e-6f,
        )
    }

    @Test
    fun `an unknown shape is no mask`() {
        val clip = NativeTimelineClip.fromMap(base + mapOf("mask" to mapOf("shape" to "hexagon")), "/v.mp4")!!
        assertArrayEquals(floatArrayOf(0f, 0.5f, 0.5f, 0f, 0f, 0f, 0f, 0f), clip.maskUniforms(), 0f)
    }
}
