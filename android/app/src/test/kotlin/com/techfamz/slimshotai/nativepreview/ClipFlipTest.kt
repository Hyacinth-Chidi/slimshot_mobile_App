package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A clip's mirror flags, and the mask the shader receives for them.
 *
 * `uFlip*` is a `vec2` of 0/1 the sampling helpers feed to
 * `mix(fitted, 1.0 - fitted, uFlip)` — 1 on an axis mirrors it. Encoding the
 * two booleans as that mask in one place keeps the two engines from each
 * translating them and one of them getting an axis backwards.
 */
class ClipFlipTest {

    private fun clip(h: Boolean, v: Boolean) = NativeTimelineClip(
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
        contentRect = floatArrayOf(0f, 0f, 1f, 1f),
        flipHorizontal = h,
        flipVertical = v,
        effectId = null,
        effectIntensity = AnimatableDouble(baseValue = 1.0),
        effectIntroSeconds = null,
    )

    @Test
    fun `unflipped is a zero mask`() {
        assertArrayEquals(floatArrayOf(0f, 0f), clip(h = false, v = false).flipMask(), 0f)
    }

    @Test
    fun `each axis sets its own component`() {
        assertArrayEquals(floatArrayOf(1f, 0f), clip(h = true, v = false).flipMask(), 0f)
        assertArrayEquals(floatArrayOf(0f, 1f), clip(h = false, v = true).flipMask(), 0f)
        assertArrayEquals(floatArrayOf(1f, 1f), clip(h = true, v = true).flipMask(), 0f)
    }

    @Test
    fun `the wire reads flags, and reads their absence as unflipped`() {
        val base = mapOf<String, Any?>(
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
        val plain = NativeTimelineClip.fromMap(base, "/v.mp4")
        assertNotNull(plain)
        assertFalse(plain!!.flipHorizontal)
        assertFalse(plain.flipVertical)

        val flipped = NativeTimelineClip.fromMap(base + mapOf("flipVertical" to true), "/v.mp4")
        assertNotNull(flipped)
        assertFalse(flipped!!.flipHorizontal)
        assertTrue(flipped.flipVertical)
    }
}
