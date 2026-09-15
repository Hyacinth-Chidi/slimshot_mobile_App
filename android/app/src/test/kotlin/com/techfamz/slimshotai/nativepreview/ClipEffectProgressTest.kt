package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        volume = AnimatableDouble(baseValue = 1.0),
        isReversed = false,
        hasPreparedProxy = false,
        needsReverseProxy = false,
        laneIndex = 0,
        isImage = false,
        sourceWidth = 1080.0,
        sourceHeight = 1920.0,
        colorMatrix = null,
        canvasScale = AnimatableDouble(baseValue = 1.0),
        canvasOffsetX = AnimatableDouble(baseValue = 0.0),
        canvasOffsetY = AnimatableDouble(baseValue = 0.0),
        effectId = "fade_in",
        effectIntensity = AnimatableDouble(baseValue = 1.0),
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

    // -----------------------------------------------------------------------
    // The intensity's wire shape
    // -----------------------------------------------------------------------
    //
    // **These maps are copied from what the Dart composer actually emits**, not
    // from what `fromWire` happens to accept — the two are only the same thing
    // if someone checks, and a wrong key here is silent: `fromWire` falls back
    // rather than throwing, so a rename on either side would export a flat
    // effect with nothing on screen explaining why. The Dart half of the pin is
    // `video_segment_effect_test.dart`'s "the animated intensity reaches the
    // wire" group, which asserts the composer writes exactly these keys.

    private fun clipMap(intensity: Any?) = mapOf(
        "id" to "c",
        "sourceVideoPath" to "/v.mp4",
        "sourceStart" to 0.0,
        "sourceEnd" to 10.0,
        "timelineStart" to 0.0,
        "timelineEnd" to 10.0,
        "effectId" to "vhs",
        "effectIntensity" to intensity,
    )

    @Test
    fun `a flat intensity arrives as a bare number and resolves flat`() {
        // **The compatibility gate.** This is the shape every timeline composed
        // before the animatable model sent, and the shape an unanimated clip
        // still sends. It must resolve to the same value at every progress —
        // which is byte for byte what the scalar did.
        val parsed = NativeTimelineClip.fromMap(clipMap(0.6), "/v.mp4")!!
        assertFalse(parsed.effectIntensity.isAnimated)
        for (p in listOf(0.0, 0.25, 0.5, 0.75, 1.0)) {
            assertEquals("at p=$p", 0.6, parsed.effectIntensityAt(p), 1e-9)
        }
    }

    @Test
    fun `an envelope arrives and shapes the strength`() {
        val parsed = NativeTimelineClip.fromMap(
            clipMap(mapOf("baseValue" to 0.8, "envelope" to "ramp_in")),
            "/v.mp4",
        )!!
        assertTrue(parsed.effectIntensity.isAnimated)
        assertEquals("ramp_in", parsed.effectIntensity.envelope)
        // `ramp_in` opens at nothing and rests at full — the base value.
        assertEquals(0.0, parsed.effectIntensityAt(0.0), 1e-9)
        assertEquals(0.8, parsed.effectIntensityAt(1.0), 1e-9)
    }

    @Test
    fun `keyframes arrive with the interpolation name the Dart enum writes`() {
        // `interpolation` is the Dart enum's `.name`, lower case — not the
        // Kotlin constant's name. An unknown one degrades to the default rather
        // than throwing.
        val parsed = NativeTimelineClip.fromMap(
            clipMap(
                mapOf(
                    "baseValue" to 0.5,
                    "keyframes" to listOf(
                        mapOf(
                            "progress" to 0.0,
                            "value" to 0.2,
                            "interpolation" to "linear",
                        ),
                        mapOf(
                            "progress" to 1.0,
                            "value" to 0.8,
                            "interpolation" to "ease",
                        ),
                    ),
                ),
            ),
            "/v.mp4",
        )!!
        assertEquals(2, parsed.effectIntensity.keyframes.size)
        assertEquals(
            KeyframeInterpolation.LINEAR,
            parsed.effectIntensity.keyframes[0].interpolation,
        )
        assertEquals(0.2, parsed.effectIntensityAt(0.0), 1e-9)
        assertEquals(0.5, parsed.effectIntensityAt(0.5), 1e-9)
        assertEquals(0.8, parsed.effectIntensityAt(1.0), 1e-9)
    }

    @Test
    fun `a missing intensity still shows the effect at full strength`() {
        // A clip carrying an id but no intensity — the catalog's neutral full
        // strength, not zero, or the effect would draw nothing and read as
        // broken.
        val parsed = NativeTimelineClip.fromMap(clipMap(null), "/v.mp4")!!
        assertEquals(1.0, parsed.effectIntensityAt(0.5), 1e-9)
    }

    @Test
    fun `the resolved intensity is clamped for the shader`() {
        // Keyframe values are deliberately unclamped in the model — a general
        // parameter's range is its consumer's business — so the clamp has to be
        // on the value a frame is actually drawn with. A shader turning an
        // out-of-range fraction into a sampling offset would read off the frame.
        val parsed = NativeTimelineClip.fromMap(
            clipMap(
                mapOf(
                    "baseValue" to 0.5,
                    "keyframes" to listOf(
                        mapOf("progress" to 0.0, "value" to -3.0),
                        mapOf("progress" to 1.0, "value" to 40.0),
                    ),
                ),
            ),
            "/v.mp4",
        )!!
        assertEquals(0.0, parsed.effectIntensityAt(0.0), 1e-9)
        assertEquals(1.0, parsed.effectIntensityAt(1.0), 1e-9)
    }

    @Test
    fun `a junk intensity costs the clip its strength, never the timeline`() {
        // A malformed field must not drop the clip: the engine would then play
        // a shorter timeline than the editor is drawing.
        for (junk in listOf<Any?>("loud", emptyList<Any>(), true)) {
            val parsed = NativeTimelineClip.fromMap(clipMap(junk), "/v.mp4")
            assertNotNull("junk: $junk", parsed)
            assertEquals("junk: $junk", 1.0, parsed!!.effectIntensityAt(0.5), 1e-9)
        }
    }
}
