package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The engine's clock against ExoPlayer's whole milliseconds.
 *
 * Device-reported: a clip split and given a transition at the cut stopped
 * playback there for good, and an overlay added over the second half did not
 * show until the playhead was moved and played. Reproduced on the emulator
 * with the engine logging its clock. A split leaves the cut between two
 * milliseconds (here 4.99279 s); the player seeks and reports in whole ones,
 * and both conversions rounded *down*, so the clock read back up to a
 * millisecond before where it had been put:
 *
 * - parked on the cut, it read 4.9918 — inside the transition, whose end is
 *   the cut — so the engine handed the clock to the outgoing lane parked
 *   elsewhere, then back, and the two lanes traded it for ever;
 * - the outgoing clip ended at 4.992, short of the window's end, so a
 *   transition played up to never closed;
 * - paused on the second half at 6.62827, it read 6.62779 — before an overlay
 *   added at the playhead (6.628), which was therefore not yet live.
 */
class LaneClockTest {

    private fun clip(
        timelineStart: Double,
        timelineEnd: Double,
        sourceStart: Double,
        sourceEnd: Double,
        speed: Double = 1.0,
        speedCurve: SpeedCurve? = null,
        lane: Int = 0,
    ) = NativeTimelineClip(
        id = "c$lane",
        sourceVideoPath = "/v.mp4",
        playbackVideoPath = "/v.mp4",
        sourceStart = sourceStart,
        sourceEnd = sourceEnd,
        timelineStart = timelineStart,
        timelineEnd = timelineEnd,
        speed = speed,
        speedCurve = speedCurve,
        volume = AnimatableDouble(baseValue = 1.0),
        isReversed = false,
        hasPreparedProxy = false,
        needsReverseProxy = false,
        laneIndex = lane,
        isImage = false,
        sourceWidth = 1080.0,
        sourceHeight = 1920.0,
        colorMatrix = null,
        canvasScale = AnimatableDouble(baseValue = 1.0),
        canvasOffsetX = AnimatableDouble(baseValue = 0.0),
        canvasOffsetY = AnimatableDouble(baseValue = 0.0),
        canvasRotation = AnimatableDouble(baseValue = 0.0),
        contentRect = floatArrayOf(0f, 0f, 1f, 1f),
        flipHorizontal = false,
        flipVertical = false,
    )

    // The emulator's project, as the engine logged it: one 8 s clip split at
    // 4.99279 s and dissolved over 0.8 s.
    private val cut = 4.992793330439818
    private val first = clip(0.0, cut, 0.0, cut, lane = 0)
    private val second = clip(cut - 0.8, cut - 0.8 + (8.0 - cut), cut, 8.0, lane = 1)
    private val window = NativeTimelineTransitionIntent(
        leftClipId = first.id,
        rightClipId = second.id,
        leftClipIndex = 0,
        rightClipIndex = 1,
        type = "dissolve",
        durationSeconds = 0.8,
        timelineStartSeconds = cut - 0.8,
        timelineEndSeconds = cut,
    )

    private fun readBack(clip: NativeTimelineClip, target: Double) =
        LaneClock.timelineSeconds(clip, LaneClock.seekMs(clip, target), ended = false)

    @Test
    fun `parked on the cut, the clock is not back inside the transition`() {
        // `seek` puts the incoming clip in charge at the cut: the window has
        // closed there.
        val clock = readBack(second, cut)
        assertFalse("read $clock", window.contains(clock))
        assertTrue(clock >= cut)
    }

    @Test
    fun `an outgoing clip that has ended stands at its end`() {
        // The player ends on a whole millisecond, short of the cut.
        val endedMs = (cut * 1000.0).toLong()
        val clock = LaneClock.timelineSeconds(first, endedMs, ended = true)
        assertEquals(cut, clock, 0.0)
        assertFalse(window.contains(clock))
    }

    @Test
    fun `an overlay added at the playhead is live where the clock stands`() {
        val playhead = 6.628270182291671
        val overlayStart = (playhead * 1000.0).toLong() / 1000.0 // the editor's whole ms
        assertTrue(readBack(second, playhead) >= overlayStart)
    }

    @Test
    fun `a seek never reads back before its target, at any speed`() {
        for (speed in listOf(0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 10.0)) {
            val start = 1.2345678
            val span = 4.3210987
            val c = clip(start, start + span / speed, 0.7777777, 0.7777777 + span, speed = speed)
            var t = start
            while (t < c.timelineEnd) {
                val back = readBack(c, t)
                assertTrue("speed $speed: $t read back as $back", back >= t - 1e-9)
                // Ahead by less than a millisecond of source.
                assertTrue("speed $speed: $t read back as $back", back - t < 0.001 / speed + 1e-9)
                t += 0.0013579
            }
        }
    }

    @Test
    fun `nor under a speed curve`() {
        val curve = SpeedCurve(listOf(0.0, 0.5, 1.0), listOf(0.5, 3.0, 0.5))
        val start = 2.3456789
        val span = 4.0
        // The clip's length is the curve's own: the timeline the ramp takes.
        val c = clip(
            start,
            start + curve.durationFactor * span,
            1.111111,
            1.111111 + span,
            speedCurve = curve,
        )
        var t = start
        while (t < c.timelineEnd) {
            val back = readBack(c, t)
            assertTrue("$t read back as $back", back >= t - 1e-9)
            t += 0.0021
        }
    }

    @Test
    fun `a whole-millisecond target reads back exactly`() {
        // Unsplit clips end on whole milliseconds; nothing moves for them.
        val c = clip(0.0, 8.0, 0.0, 8.0)
        for (ms in listOf(0L, 1L, 799L, 800L, 4000L, 7999L)) {
            assertEquals(ms, LaneClock.seekMs(c, ms / 1000.0))
        }
    }

    @Test
    fun `a seek never asks for a negative position`() {
        assertEquals(0L, LaneClock.seekMs(second, second.timelineStart - 0.5))
    }
}
