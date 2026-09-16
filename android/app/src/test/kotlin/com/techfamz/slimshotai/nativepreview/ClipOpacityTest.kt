package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * A clip's opacity on the engine side: read like every other animated
 * parameter, clamped where it is resolved, present at 1.0 for every timeline
 * composed before clips could fade.
 */
class ClipOpacityTest {

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
    fun `absent from the wire reads as fully present`() {
        val clip = NativeTimelineClip.fromMap(base, "/v.mp4")
        assertNotNull(clip)
        assertEquals(1.0, clip!!.opacityAt(0.0), 0.0)
        assertEquals(1.0, clip.opacityAt(1.0), 0.0)
    }

    @Test
    fun `a flat number is a flat opacity`() {
        val clip = NativeTimelineClip.fromMap(base + mapOf("opacity" to 0.4), "/v.mp4")
        assertEquals(0.4, clip!!.opacityAt(0.5), 1e-9)
    }

    @Test
    fun `keyframes fade across the clip and resolve clamped`() {
        val clip = NativeTimelineClip.fromMap(
            base + mapOf(
                "opacity" to mapOf(
                    "baseValue" to 1.0,
                    "keyframes" to listOf(
                        mapOf("progress" to 0.0, "value" to 1.5),
                        mapOf("progress" to 1.0, "value" to -0.5),
                    ),
                ),
            ),
            "/v.mp4",
        )!!
        assertEquals(1.0, clip.opacityAt(0.0), 1e-9)
        assertEquals(0.5, clip.opacityAt(0.5), 1e-9)
        assertEquals(0.0, clip.opacityAt(1.0), 1e-9)
    }
}
