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
        kind: String = "image",
    ): NativeTimelineOverlay = NativeTimelineOverlay.fromMap(
        mapOf(
            "id" to "o",
            "kind" to kind,
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
    fun `a live video overlay is a new picture every step, animation or not`() {
        // Device-found by reasoning from the first report: a photo overlay at
        // rest needs no redraw, but a video overlay's frame changes with the
        // clock. Over a photo clip nothing else asks for a draw, so without
        // this rule the overlay's footage would freeze.
        val list = listOf(overlay(kind = "video"))
        assertTrue(OverlayClock.needsRedraw(list, 4.0, 4.016))
        // A scrub backwards is a new frame too.
        assertTrue(OverlayClock.needsRedraw(list, 5.0, 3.0))
        // A clock that has not moved owes nothing.
        assertFalse(OverlayClock.needsRedraw(list, 4.0, 4.0))
        // Outside its window it is not on screen.
        assertFalse(OverlayClock.needsRedraw(list, 9.0, 9.5))
    }

    @Test
    fun `a keyframed overlay is a new picture whenever the clock moves inside it`() {
        // Its placement is a function of the playhead, so every step of the
        // clock inside its span moves it — at rest or not, over a still photo
        // clip where nothing else would ask for a draw.
        val keyframed = NativeTimelineOverlay.fromMap(
            mapOf(
                "id" to "k",
                "kind" to "image",
                "path" to "/p.png",
                "startSeconds" to 2.0,
                "endSeconds" to 8.0,
                "centerX" to mapOf(
                    "baseValue" to 0.5,
                    "keyframes" to listOf(
                        mapOf("progress" to 0.0, "value" to 0.2),
                        mapOf("progress" to 1.0, "value" to 0.8),
                    ),
                ),
            ),
        )!!
        val list = listOf(keyframed)
        assertTrue(OverlayClock.needsRedraw(list, 4.0, 4.016))
        assertTrue("a scrub backwards", OverlayClock.needsRedraw(list, 5.0, 3.0))
        assertFalse("a clock that has not moved", OverlayClock.needsRedraw(list, 4.0, 4.0))
        assertFalse("off screen", OverlayClock.needsRedraw(list, 9.0, 9.5))
        // An overlay with no keyframes still asks for nothing mid-span.
        assertFalse(OverlayClock.needsRedraw(listOf(overlay()), 4.0, 4.016))
    }

    @Test
    fun `stepping forward a frame never seeks the overlay's decoder`() {
        // A seek flushes the codec; doing it on ordinary playback would be the
        // decoder-flush storm of dead-ends entry 11 in a third place.
        assertFalse(OverlayClock.shouldSeek(lastRenderedUs = 1_000_000, targetUs = 1_033_000))
        assertFalse(OverlayClock.shouldSeek(lastRenderedUs = 1_000_000, targetUs = 1_400_000))
    }

    @Test
    fun `a playhead that went backwards seeks, because the decoder only walks forward`() {
        assertTrue(OverlayClock.shouldSeek(lastRenderedUs = 5_000_000, targetUs = 2_000_000))
        // A hair behind is the same frame, not a jump.
        assertFalse(OverlayClock.shouldSeek(lastRenderedUs = 5_000_000, targetUs = 4_990_000))
    }

    @Test
    fun `a long jump forward seeks rather than decoding every frame between`() {
        assertTrue(OverlayClock.shouldSeek(lastRenderedUs = 1_000_000, targetUs = 9_000_000))
    }

    @Test
    fun `a decoder that has shown nothing yet is never seeked`() {
        // It was opened at its start position; a seek before its first output
        // is the flush-after-start that loses the codec's config data.
        assertFalse(OverlayClock.shouldSeek(lastRenderedUs = -1, targetUs = 3_000_000))
    }

    @Test
    fun `a first draw is owed whenever there is no previous instant`() {
        // The engine has no last position after a new list, a seek, or a
        // timeline push. Whatever the clock says, that draw has to happen, or
        // the overlays sit unpainted until the playhead happens to move.
        val list = listOf(overlay())
        assertTrue(OverlayClock.needsFirstDraw(Double.NaN))
        assertFalse(OverlayClock.needsFirstDraw(4.0))
        // And it is independent of whether the clock moved.
        assertFalse(OverlayClock.needsRedraw(list, 4.0, 4.0))
    }

    @Test
    fun `the override is honoured only past the engine's own end`() {
        // Flutter walks the playhead through the tail, where the engine's clock
        // is parked. Inside the video the engine's clock is the authority and a
        // stale override must never fight it.
        assertNull(OverlayClock.override(requested = 3.0, enginePosition = 10.0, engineDuration = 10.0))
        assertNull(OverlayClock.override(requested = 10.0, enginePosition = 10.0, engineDuration = 10.0))
        assertEquals(
            12.5,
            OverlayClock.override(requested = 12.5, enginePosition = 10.0, engineDuration = 10.0)!!,
            0.0,
        )
    }

    @Test
    fun `a tail position left over from earlier never outlives the tail`() {
        // Device-reported: after one playback through the tail, a video overlay
        // showed a frozen frame from 0:00 on, before its own start, and never
        // moved again. The override was written during the tail and never
        // cleared, so the overlays' clock stayed pinned past the end while the
        // real playhead was back inside the video. It is honoured only while
        // the engine itself is parked at its end.
        assertNull(OverlayClock.override(requested = 18.0, enginePosition = 0.0, engineDuration = 10.0))
        assertNull(OverlayClock.override(requested = 18.0, enginePosition = 6.0, engineDuration = 10.0))
        assertEquals(
            18.0,
            OverlayClock.override(requested = 18.0, enginePosition = 9.99, engineDuration = 10.0)!!,
            0.0,
        )
    }

    @Test
    fun `junk never becomes an override`() {
        assertNull(OverlayClock.override(requested = Double.NaN, enginePosition = 10.0, engineDuration = 10.0))
        assertNull(
            OverlayClock.override(
                requested = Double.POSITIVE_INFINITY,
                enginePosition = 10.0,
                engineDuration = 10.0,
            ),
        )
    }
}
