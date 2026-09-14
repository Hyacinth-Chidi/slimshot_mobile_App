package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pins the effect clock.
 *
 * `effectProgressAt` is the only place a clip's position through its effect is
 * computed, and both engines call it with their own timeline position — the
 * preview's ticker at whatever rate the device manages, the export loop as fast
 * as the codecs allow. Because it is a pure function of a *position*, the two
 * reach the same value at the same instant of a clip whatever rate either runs
 * at. A frame counter or `System.nanoTime` in its place would draw a different
 * picture in the file than on the canvas.
 *
 * These are the cases that decide whether a timed effect is right: where the
 * window comes from, what happens after it ends, and the degenerate durations
 * that would otherwise divide by zero.
 */
class ClipEffectProgressTest {

    private fun clip(
        timelineStart: Double,
        timelineEnd: Double,
        introSeconds: Double? = null,
    ) = NativeTimelineClip(
        id = "c",
        sourceVideoPath = "/v.mp4",
        playbackVideoPath = "/v.mp4",
        sourceStart = 0.0,
        sourceEnd = timelineEnd - timelineStart,
        timelineStart = timelineStart,
        timelineEnd = timelineEnd,
        speed = 1.0,
        volume = 1.0,
        isReversed = false,
        hasPreparedProxy = false,
        needsReverseProxy = false,
        laneIndex = 0,
        isImage = false,
        sourceWidth = 1080.0,
        sourceHeight = 1920.0,
        colorMatrix = null,
        canvasScale = 1.0,
        canvasOffsetX = 0.0,
        canvasOffsetY = 0.0,
        effectId = "fade_in",
        effectIntensity = 1.0,
        effectIntroSeconds = introSeconds,
    )

    @Test
    fun `an intro measures progress across its own window`() {
        // The window is the catalog's, not the clip's: a 0.8s fade is 0.8s on a
        // 10s clip, so at 0.4s in it is exactly half played.
        val c = clip(timelineStart = 0.0, timelineEnd = 10.0, introSeconds = 0.8)
        assertEquals(0.0, c.effectProgressAt(0.0), 1e-9)
        assertEquals(0.5, c.effectProgressAt(0.4), 1e-9)
        assertEquals(1.0, c.effectProgressAt(0.8), 1e-9)
    }

    @Test
    fun `an intro settles at 1 and stays there`() {
        // "Plays once and settles": `p == 1` is the shader's resting state, so
        // the clip is left untouched without the effect being removed. If this
        // wrapped or fell back to 0 the fade would replay for the whole clip.
        val c = clip(timelineStart = 0.0, timelineEnd = 10.0, introSeconds = 0.8)
        assertEquals(1.0, c.effectProgressAt(0.9), 1e-9)
        assertEquals(1.0, c.effectProgressAt(9.99), 1e-9)
    }

    @Test
    fun `an intro is measured from the clip's own start, not the timeline's`() {
        // The clip that matters most is the one that is not first: measuring
        // from timeline zero would leave every later clip's intro already over
        // before its first frame.
        val c = clip(timelineStart = 12.0, timelineEnd = 20.0, introSeconds = 2.0)
        assertEquals(0.0, c.effectProgressAt(12.0), 1e-9)
        assertEquals(0.5, c.effectProgressAt(13.0), 1e-9)
        assertEquals(1.0, c.effectProgressAt(14.0), 1e-9)
    }

    @Test
    fun `a clip shorter than the window is cut off, never compressed`() {
        // The intro runs at its declared speed and the clip ends mid-animation.
        // Compressing it to fit would play the same effect at a different speed
        // depending on the clip it landed on.
        val c = clip(timelineStart = 0.0, timelineEnd = 0.4, introSeconds = 0.8)
        assertEquals(0.5, c.effectProgressAt(0.4), 1e-9)
    }

    @Test
    fun `a static look measures progress across the whole clip`() {
        // No window means the whole clip. The value is unused — a static
        // shader declares no `uProgress` — but it must be well-defined, and
        // spanning the clip is what a future non-intro timed effect will want.
        val c = clip(timelineStart = 0.0, timelineEnd = 4.0, introSeconds = null)
        assertEquals(0.0, c.effectProgressAt(0.0), 1e-9)
        assertEquals(0.5, c.effectProgressAt(2.0), 1e-9)
        assertEquals(1.0, c.effectProgressAt(4.0), 1e-9)
    }

    @Test
    fun `progress is clamped outside the clip`() {
        // Both engines can ask about a position just off the clip — the lane
        // resolver hands back the upcoming clip before it starts and the last
        // one after it ends — and an unclamped value would drive a shader past
        // its own animation.
        val c = clip(timelineStart = 5.0, timelineEnd = 9.0, introSeconds = 1.0)
        assertEquals(0.0, c.effectProgressAt(0.0), 1e-9)
        assertEquals(1.0, c.effectProgressAt(100.0), 1e-9)
    }

    @Test
    fun `a zero-length clip is finished, not divided by zero`() {
        // A clip can arrive mid-edit with no length at all. Returning 0 would
        // park a fade on black for as long as it was on screen; 1 is the
        // settled picture, which is what an animation with no time to run has
        // already finished doing.
        val c = clip(timelineStart = 3.0, timelineEnd = 3.0, introSeconds = null)
        assertEquals(1.0, c.effectProgressAt(3.0), 1e-9)
    }

    @Test
    fun `a clip composed before the clock existed has no window`() {
        // Every saved project is this case, and it must parse as "measure
        // across the clip" rather than as a zero-length window.
        val parsed = NativeTimelineClip.fromMap(
            mapOf(
                "id" to "c",
                "sourceVideoPath" to "/v.mp4",
                "sourceStart" to 0.0,
                "sourceEnd" to 4.0,
                "timelineStart" to 0.0,
                "timelineEnd" to 4.0,
            ),
            "/v.mp4",
        )
        assertNull(parsed!!.effectIntroSeconds)
        assertEquals(0.5, parsed.effectProgressAt(2.0), 1e-9)
    }

    @Test
    fun `a non-positive window is dropped rather than trusted`() {
        // A window that ends before it starts is not a window. Dropping it
        // falls back to the whole clip, which is defined; keeping it would
        // make `effectProgressAt` guess.
        val parsed = NativeTimelineClip.fromMap(
            mapOf(
                "id" to "c",
                "sourceVideoPath" to "/v.mp4",
                "sourceStart" to 0.0,
                "sourceEnd" to 4.0,
                "timelineStart" to 0.0,
                "timelineEnd" to 4.0,
                "effectIntroSeconds" to 0.0,
            ),
            "/v.mp4",
        )
        assertNull(parsed!!.effectIntroSeconds)
    }

    @Test
    fun `the window survives the wire`() {
        val parsed = NativeTimelineClip.fromMap(
            mapOf(
                "id" to "c",
                "sourceVideoPath" to "/v.mp4",
                "sourceStart" to 0.0,
                "sourceEnd" to 10.0,
                "timelineStart" to 0.0,
                "timelineEnd" to 10.0,
                "effectId" to "fade_in",
                "effectIntroSeconds" to 0.8,
            ),
            "/v.mp4",
        )
        assertEquals(0.8, parsed!!.effectIntroSeconds!!, 1e-9)
        assertEquals(0.5, parsed.effectProgressAt(0.4), 1e-9)
    }
}
