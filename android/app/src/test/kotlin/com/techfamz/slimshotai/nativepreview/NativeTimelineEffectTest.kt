package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Reading an effect bar as the composer sends it (`EditorTimelineEffect`). */
class NativeTimelineEffectTest {

    @Test
    fun `reads the composer's map, a keyframed intensity included`() {
        val bar = NativeTimelineEffect.fromMap(
            mapOf(
                "id" to "z",
                "effectId" to "cinema_zoom",
                "start" to 1.0,
                "end" to 3.0,
                "lane" to 2,
                "intensity" to mapOf(
                    "baseValue" to 0.5,
                    "keyframes" to listOf(
                        mapOf("progress" to 0.0, "value" to 0.0, "interpolation" to "linear"),
                        mapOf("progress" to 1.0, "value" to 1.0, "interpolation" to "linear"),
                    ),
                ),
                "introSeconds" to 1.2,
            ),
        )!!
        assertEquals("z", bar.id)
        assertEquals("cinema_zoom", bar.effectId)
        assertEquals(1.0, bar.start, 0.0)
        assertEquals(3.0, bar.end, 0.0)
        assertEquals(2, bar.lane)
        assertEquals(1.2, bar.introSeconds!!, 0.0)
        assertEquals(0.5, bar.intensity.resolveAt(0.5), 1e-9)
    }

    @Test
    fun `a flat intensity is a bare number and the window may be absent`() {
        val bar = NativeTimelineEffect.fromMap(
            mapOf("id" to "v", "effectId" to "vignette", "start" to 0, "end" to 2, "lane" to 0, "intensity" to 0.8),
        )!!
        assertNull(bar.introSeconds)
        assertEquals(0.8, bar.intensity.resolveAt(0.3), 1e-9)
    }

    @Test
    fun `a map without an effect is not a bar`() {
        assertNull(NativeTimelineEffect.fromMap(mapOf("id" to "x", "start" to 0, "end" to 2)))
        assertNull(NativeTimelineEffect.fromMap(mapOf("effectId" to "blur", "start" to 0, "end" to 2)))
    }

    @Test
    fun `an end before the start is held to the minimum, never dropped`() {
        val bar = NativeTimelineEffect.fromMap(
            mapOf("id" to "e", "effectId" to "blur", "start" to 4.0, "end" to 2.0),
        )!!
        assertTrue(bar.end - bar.start >= NativeTimelineEffect.MIN_SECONDS - 1e-9)
    }

    @Test
    fun `the timeline's effects array reads in order`() {
        val bars = NativeTimelineEffect.listFrom(
            mapOf(
                "effects" to listOf(
                    mapOf("id" to "a", "effectId" to "grain", "start" to 0, "end" to 1, "lane" to 0, "intensity" to 1),
                    "junk",
                    mapOf("id" to "b", "effectId" to "blur", "start" to 1, "end" to 2, "lane" to 1, "intensity" to 1),
                ),
            ),
        )
        assertEquals(listOf("a", "b"), bars.map { it.id })
        assertEquals(emptyList<NativeTimelineEffect>(), NativeTimelineEffect.listFrom(emptyMap()))
    }
}
