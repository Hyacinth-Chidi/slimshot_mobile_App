package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When the preview has to redraw because of an overlay, and which clock an
 * overlay reads.
 *
 * The engine ticks sixty times a second. Redrawing on every tick merely
 * because an overlay *exists* would double the GL work for a sticker sitting
 * still over 30fps video, and keep the GPU awake over a paused photo. A redraw
 * is owed only when the picture can actually differ: an overlay appears,
 * disappears, or is inside an animation window.
 */
class OverlayClockTest {

    private fun overlay(
        start: Double = 2.0,
        end: Double = 8.0,
        animationIn: String? = null,
        animationOut: String? = null,
        inSeconds: Double = 0.5,
        outSeconds: Double = 0.5,
    ): NativeTimelineOverlay = NativeTimelineOverlay.fromMap(
        mapOf(
            "id" to "o",
            "kind" to "image",
            "path" to "/p.png",
            "startSeconds" to start,
            "endSeconds" to end,
            "animationIn" to animationIn,
            "animationOut" to animationOut,
            "animationInSeconds" to inSeconds,
            "animationOutSeconds" to outSeconds,
        ),
    )!!

    @Test
    fun `no overlays never asks for a redraw`() {
        assertFalse(OverlayClock.needsRedraw(emptyList(), 0.0, 5.0))
    }

    @Test
    fun `a still overlay in the middle of its window asks for nothing`() {
        val list = listOf(overlay())
        assertFalse(OverlayClock.needsRedraw(list, 4.0, 4.016))
        assertFalse(OverlayClock.needsRedraw(list, 4.0, 6.0))
    }

    @Test
    fun `appearing and disappearing both ask for a redraw`() {
        val list = listOf(overlay())
        assertTrue("appears", OverlayClock.needsRedraw(list, 1.99, 2.01))
        assertTrue("disappears", OverlayClock.needsRedraw(list, 7.99, 8.01))
        // A scrub backwards is the same crossing.
        assertTrue("scrubbed back out", OverlayClock.needsRedraw(list, 2.5, 1.0))
    }

    @Test
    fun `entirely outside the window asks for nothing`() {
        val list = listOf(overlay())
        assertFalse(OverlayClock.needsRedraw(list, 0.0, 1.0))
        assertFalse(OverlayClock.needsRedraw(list, 9.0, 12.0))
    }

    @Test
    fun `inside an in-animation every step is a redraw, and so is the step that ends it`() {
        val list = listOf(overlay(animationIn = "fade_in", inSeconds = 0.5))
        assertTrue(OverlayClock.needsRedraw(list, 2.1, 2.116))
        // The frame that lands on rest must still be drawn, or the overlay
        // parks one step short of full opacity.
        assertTrue(OverlayClock.needsRedraw(list, 2.49, 2.51))
        assertFalse(OverlayClock.needsRedraw(list, 2.6, 2.616))
    }

    @Test
    fun `inside an out-animation every step is a redraw`() {
        val list = listOf(overlay(animationOut = "fade_out", outSeconds = 0.5))
        assertFalse(OverlayClock.needsRedraw(list, 7.0, 7.016))
        assertTrue(OverlayClock.needsRedraw(list, 7.6, 7.616))
    }

    @Test
    fun `an animation name with no window asks for nothing extra`() {
        val list = listOf(overlay(animationIn = "fade_in", inSeconds = 0.0))
        assertFalse(OverlayClock.needsRedraw(list, 2.1, 2.116))
    }

    @Test
    fun `one animating overlay among still ones is enough`() {
        val list = listOf(
            overlay(start = 0.0, end = 20.0),
            overlay(start = 5.0, end = 9.0, animationIn = "zoom_in"),
        )
        assertFalse(OverlayClock.needsRedraw(list, 3.0, 3.016))
        assertTrue(OverlayClock.needsRedraw(list, 5.1, 5.116))
    }

    @Test
    fun `the override is honoured only past the engine's own end`() {
        // Flutter walks the playhead through the tail, where the engine's clock
        // is parked. Inside the video the engine's clock is the authority and a
        // stale override must never fight it.
        assertNull(OverlayClock.override(requested = 3.0, engineDuration = 10.0))
        assertNull(OverlayClock.override(requested = 10.0, engineDuration = 10.0))
        assertEquals(12.5, OverlayClock.override(requested = 12.5, engineDuration = 10.0)!!, 0.0)
    }

    @Test
    fun `junk never becomes an override`() {
        assertNull(OverlayClock.override(requested = Double.NaN, engineDuration = 10.0))
        assertNull(OverlayClock.override(requested = Double.POSITIVE_INFINITY, engineDuration = 10.0))
    }
}
