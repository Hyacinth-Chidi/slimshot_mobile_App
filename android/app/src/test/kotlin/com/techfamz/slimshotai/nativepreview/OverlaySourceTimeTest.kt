package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which frame of a video overlay is due at a timeline instant, and whether its
 * sound belongs in the file.
 *
 * `speed` was on the overlay model and honoured by **nothing**: the preview
 * plugin ignored it and `sourceAt` walked the source at 1x, so a slowed
 * overlay played at normal speed on the canvas and in the file alike. It is
 * fixed here rather than in either engine, so both read one mapping — the same
 * rule that keeps a clip's speed curve honest.
 */
class OverlaySourceTimeTest {

    private fun overlay(
        start: Double = 2.0,
        end: Double = 10.0,
        sourceStart: Double = 0.0,
        sourceEnd: Double = 0.0,
        speed: Double = 1.0,
        volume: Double = 1.0,
        muted: Boolean = false,
        kind: String = "video",
    ): NativeTimelineOverlay = NativeTimelineOverlay.fromMap(
        mapOf(
            "id" to "o",
            "kind" to kind,
            "path" to "/v.mp4",
            "startSeconds" to start,
            "endSeconds" to end,
            "sourceStart" to sourceStart,
            "sourceEnd" to sourceEnd,
            "speed" to speed,
            "volume" to volume,
            "isMuted" to muted,
        ),
    )!!

    @Test
    fun `at natural speed the source walks with the timeline, as it always did`() {
        val o = overlay(sourceStart = 4.0)
        assertEquals(4.0, o.sourceAt(2.0), 1e-9)
        assertEquals(7.0, o.sourceAt(5.0), 1e-9)
    }

    @Test
    fun `at half speed the source walks half as fast`() {
        val o = overlay(sourceStart = 0.0, speed = 0.5)
        assertEquals(0.0, o.sourceAt(2.0), 1e-9)
        assertEquals(2.0, o.sourceAt(6.0), 1e-9)
    }

    @Test
    fun `at double speed it walks twice as fast`() {
        val o = overlay(sourceStart = 1.0, speed = 2.0)
        assertEquals(1.0, o.sourceAt(2.0), 1e-9)
        assertEquals(7.0, o.sourceAt(5.0), 1e-9)
    }

    @Test
    fun `the source end still clamps, whatever the speed`() {
        val o = overlay(sourceStart = 0.0, sourceEnd = 3.0, speed = 2.0)
        assertEquals(3.0, o.sourceAt(9.0), 1e-9)
    }

    @Test
    fun `before its window it sits at its first frame`() {
        val o = overlay(sourceStart = 2.0, speed = 2.0)
        assertEquals(2.0, o.sourceAt(0.0), 1e-9)
    }

    @Test
    fun `a junk speed falls back to natural rather than freezing the overlay`() {
        // A zero or negative speed would park the overlay on one frame for
        // ever; a draft can hold anything.
        assertEquals(5.0, overlay(sourceStart = 2.0, speed = 0.0).sourceAt(5.0), 1e-9)
        assertEquals(5.0, overlay(sourceStart = 2.0, speed = -2.0).sourceAt(5.0), 1e-9)
    }

    @Test
    fun `a video overlay with sound is audible, and the export should mix it`() {
        assertTrue(overlay().hasAudibleSound)
        assertEquals(1.0, overlay().effectiveVolume, 1e-9)
        assertEquals(0.4, overlay(volume = 0.4).effectiveVolume, 1e-9)
    }

    @Test
    fun `muted, silent and non-video overlays contribute nothing`() {
        assertFalse("muted", overlay(muted = true).hasAudibleSound)
        assertFalse("volume 0", overlay(volume = 0.0).hasAudibleSound)
        assertFalse("an image has no sound", overlay(kind = "image").hasAudibleSound)
        assertFalse("nor does text", overlay(kind = "text").hasAudibleSound)
        assertEquals(0.0, overlay(muted = true).effectiveVolume, 1e-9)
    }
}
